import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ship_subtitle_catalog.dart';
import 'ship_subtitle_catalog_store.dart';
import 'ship_subtitle_language.dart';

sealed class ShipSubtitleUpdateResult {
  const ShipSubtitleUpdateResult({required this.sourceHost});
  final String sourceHost;
}

final class ShipSubtitleUpToDate extends ShipSubtitleUpdateResult {
  const ShipSubtitleUpToDate(this.catalog, {required super.sourceHost});
  final ShipSubtitleCatalog catalog;
}

final class ShipSubtitleUpdated extends ShipSubtitleUpdateResult {
  const ShipSubtitleUpdated(this.catalog, {required super.sourceHost});
  final ShipSubtitleCatalog catalog;
}

enum ShipSubtitleUpdateFailure { network, validation, storage }

final class ShipSubtitleUpdateFailed extends ShipSubtitleUpdateResult {
  const ShipSubtitleUpdateFailed(
    this.kind,
    this.error, {
    required super.sourceHost,
  });
  final ShipSubtitleUpdateFailure kind;
  final Object error;
}

abstract interface class ShipSubtitleUpdateClient {
  Future<ShipSubtitleUpdateResult> checkAndUpdate({
    required ShipSubtitleCatalog current,
  });
}

/// kcwiki's version and full-data endpoints can have different CDN cache ages.
/// The full body's version is authoritative; older data is never installed.
final class ShipSubtitleUpdateService implements ShipSubtitleUpdateClient {
  const ShipSubtitleUpdateService({
    required this.client,
    required this.store,
    this.language = ShipSubtitleLanguage.simplifiedChinese,
    this.timeout = const Duration(seconds: 20),
    this.maximumDownloadDuration = const Duration(minutes: 2),
    this.maximumDataBytes = 16 * 1024 * 1024,
  });

  static const sourceHosts = ['acc.kcwiki.cn', 'api.kcwiki.moe'];
  final http.Client client;
  final ShipSubtitleCatalogStore store;
  final ShipSubtitleLanguage language;
  final Duration timeout;
  final Duration maximumDownloadDuration;
  final int maximumDataBytes;

  @override
  Future<ShipSubtitleUpdateResult> checkAndUpdate({
    required ShipSubtitleCatalog current,
  }) async {
    if (language.usesKc3Quotes) return _checkKc3(current);
    Object? lastError;
    var sourceHost = '';
    for (final host in sourceHosts) {
      sourceHost = host;
      final result = await checkKcwikiSource(
        current: current,
        sourceHost: host,
      );
      if (result is ShipSubtitleUpdateFailed) {
        lastError = result.error;
        continue;
      }
      if (result is ShipSubtitleUpToDate) return result;
      try {
        await store.save((result as ShipSubtitleUpdated).catalog);
      } on Object catch (error) {
        return ShipSubtitleUpdateFailed(
          ShipSubtitleUpdateFailure.storage,
          error,
          sourceHost: host,
        );
      }
      return result;
    }
    final error =
        lastError ?? const HttpException('Subtitle service is unavailable.');
    return ShipSubtitleUpdateFailed(
      error is FormatException
          ? ShipSubtitleUpdateFailure.validation
          : ShipSubtitleUpdateFailure.network,
      error,
      sourceHost: sourceHost,
    );
  }

  /// Download one trusted source without saving or falling back independently.
  /// The group controller validates all three files before publishing any file.
  Future<ShipSubtitleUpdateResult> checkKcwikiSource({
    required ShipSubtitleCatalog current,
    required String sourceHost,
  }) async {
    try {
      if (!sourceHosts.contains(sourceHost) || language.usesKc3Quotes) {
        throw const FormatException('Invalid kcwiki subtitle source.');
      }
      final versionBody = jsonDecode(
        utf8.decode(
          await _get(Uri.https(sourceHost, '/subtitles/version'), 4096),
        ),
      );
      if (versionBody is! Map<String, dynamic>) {
        throw const FormatException('Subtitle version response is invalid.');
      }
      final advertisedVersion = ShipSubtitleCatalog.validateVersion(
        versionBody['version'],
      );
      if (advertisedVersion.compareTo(current.version) <= 0) {
        return ShipSubtitleUpToDate(current, sourceHost: sourceHost);
      }
      final bytes = await _get(
        Uri.https(sourceHost, switch (language) {
          ShipSubtitleLanguage.simplifiedChinese => '/subtitles/zh-cn',
          ShipSubtitleLanguage.traditionalChinese => '/subtitles/zh-tw',
          ShipSubtitleLanguage.japanese => '/subtitles/jp',
          ShipSubtitleLanguage.english || ShipSubtitleLanguage.korean =>
            throw StateError('This subtitle language uses KC3.'),
        }),
        maximumDataBytes,
      );
      final catalog = await compute(_decodeCatalog, bytes);
      if (catalog.version.compareTo(current.version) <= 0) {
        throw const FormatException('Subtitle CDN returned stale full data.');
      }
      return ShipSubtitleUpdated(catalog, sourceHost: sourceHost);
    } on Object catch (error) {
      return ShipSubtitleUpdateFailed(
        error is FormatException
            ? ShipSubtitleUpdateFailure.validation
            : ShipSubtitleUpdateFailure.network,
        error,
        sourceHost: sourceHost,
      );
    }
  }

  Future<ShipSubtitleUpdateResult> _checkKc3(
    ShipSubtitleCatalog current,
  ) async {
    var sourceHost = 'api.github.com';
    final directory = language == ShipSubtitleLanguage.korean ? 'kr' : 'en';
    try {
      final uri = Uri.https(
        'api.github.com',
        '/repos/KC3Kai/kc3-translations/commits',
        {'path': 'data/$directory/quotes.json', 'per_page': '1'},
      );
      final commits = jsonDecode(utf8.decode(await _get(uri, 128 * 1024)));
      if (commits is! List || commits.length != 1 || commits.first is! Map) {
        throw const FormatException('KC3 subtitle commit response is invalid.');
      }
      final commit = commits.first as Map;
      final sha = commit['sha'];
      final details = commit['commit'];
      final committer = details is Map ? details['committer'] : null;
      final date = committer is Map ? committer['date'] : null;
      if (sha is! String ||
          !RegExp(r'^[0-9a-f]{40}$').hasMatch(sha) ||
          date is! String ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$').hasMatch(date)) {
        throw const FormatException('KC3 subtitle commit metadata is invalid.');
      }
      final parsed = DateTime.tryParse(date);
      if (parsed == null ||
          parsed.toUtc().toIso8601String().replaceFirst('.000Z', 'Z') != date) {
        throw const FormatException('KC3 subtitle date is invalid.');
      }
      final version = date.replaceAll(RegExp(r'[^0-9]'), '');
      ShipSubtitleCatalog.validateVersion(version);
      if (version.compareTo(current.version) <= 0) {
        return ShipSubtitleUpToDate(current, sourceHost: sourceHost);
      }
      sourceHost = 'raw.githubusercontent.com';
      final bytes = await _get(
        Uri.https(
          sourceHost,
          '/KC3Kai/kc3-translations/$sha/data/$directory/quotes.json',
        ),
        maximumDataBytes,
      );
      final catalog = await compute(_decodeKc3Catalog, (
        bytes: bytes,
        version: version,
      ));
      try {
        await store.save(catalog);
      } on Object catch (error) {
        return ShipSubtitleUpdateFailed(
          ShipSubtitleUpdateFailure.storage,
          error,
          sourceHost: sourceHost,
        );
      }
      return ShipSubtitleUpdated(catalog, sourceHost: sourceHost);
    } on Object catch (error) {
      return ShipSubtitleUpdateFailed(
        error is FormatException
            ? ShipSubtitleUpdateFailure.validation
            : ShipSubtitleUpdateFailure.network,
        error,
        sourceHost: sourceHost,
      );
    }
  }

  Future<Uint8List> _get(Uri uri, int maximumBytes) async {
    Completer<void>? activeAbort;
    final deadline = DateTime.now().add(maximumDownloadDuration);
    Duration nextTimeout() {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw TimeoutException('Subtitle download exceeded its time limit.');
      }
      return remaining < timeout ? remaining : timeout;
    }

    Future<Uint8List> download() async {
      var requestUri = uri;
      for (var redirectCount = 0; redirectCount <= 5; redirectCount++) {
        if (!_allowedUri(requestUri, uri)) {
          throw const FormatException('Subtitle download URL is not allowed.');
        }
        final abort = Completer<void>();
        activeAbort = abort;
        final request =
            http.AbortableRequest('GET', requestUri, abortTrigger: abort.future)
              ..followRedirects = false
              ..headers['User-Agent'] = 'Yahagi-Kancolle-Browser';
        final response = await client.send(request).timeout(nextTimeout());
        if (_redirectStatus(response.statusCode)) {
          final location = response.headers['location'];
          await response.stream.listen((_) {}, onError: (Object _) {}).cancel();
          if (!abort.isCompleted) abort.complete();
          if (location == null || redirectCount == 5) {
            throw const FormatException('Subtitle redirect is invalid.');
          }
          requestUri = requestUri.resolve(location);
          continue;
        }
        if (response.statusCode != 200 ||
            (response.contentLength != null &&
                response.contentLength! > maximumBytes)) {
          await response.stream.listen((_) {}, onError: (Object _) {}).cancel();
          if (!abort.isCompleted) abort.complete();
          if (response.statusCode != 200) {
            throw http.ClientException(
              'Subtitle request failed: ${response.statusCode}',
              requestUri,
            );
          }
          throw const FormatException('Subtitle response exceeds size limit.');
        }
        final bytes = BytesBuilder(copy: false);
        final chunks = StreamIterator(response.stream);
        try {
          while (await chunks.moveNext().timeout(nextTimeout())) {
            final chunk = chunks.current;
            if (bytes.length + chunk.length > maximumBytes) {
              throw const FormatException(
                'Subtitle response exceeds size limit.',
              );
            }
            bytes.add(chunk);
          }
        } finally {
          if (!abort.isCompleted) abort.complete();
          await chunks.cancel();
        }
        return bytes.takeBytes();
      }
      throw const FormatException('Subtitle redirect limit exceeded.');
    }

    try {
      return await download();
    } finally {
      final abort = activeAbort;
      if (abort != null && !abort.isCompleted) abort.complete();
    }
  }
}

ShipSubtitleCatalog _decodeCatalog(Uint8List bytes) =>
    ShipSubtitleCatalog.fromJsonString(utf8.decode(bytes));

ShipSubtitleCatalog _decodeKc3Catalog(
  ({Uint8List bytes, String version}) input,
) {
  final source = jsonDecode(utf8.decode(input.bytes));
  if (source is! Map<String, dynamic>) {
    throw const FormatException('KC3 subtitle catalog must be an object.');
  }
  return ShipSubtitleCatalog.fromKc3Json(source, version: input.version);
}

bool _allowedUri(Uri uri, Uri original) =>
    uri.scheme == 'https' &&
    uri.userInfo.isEmpty &&
    uri.port == 443 &&
    !uri.hasFragment &&
    uri.path == original.path &&
    uri.query == original.query &&
    ((ShipSubtitleUpdateService.sourceHosts.contains(uri.host) &&
            !uri.hasQuery &&
            const {
              '/subtitles/version',
              '/subtitles/zh-cn',
              '/subtitles/zh-tw',
              '/subtitles/jp',
            }.contains(uri.path)) ||
        (uri.host == 'api.github.com' &&
            original.host == uri.host &&
            uri.path == '/repos/KC3Kai/kc3-translations/commits' &&
            uri.queryParameters.length == 2 &&
            const {
              'data/en/quotes.json',
              'data/kr/quotes.json',
            }.contains(uri.queryParameters['path']) &&
            uri.queryParameters['per_page'] == '1') ||
        (uri.host == 'raw.githubusercontent.com' &&
            original.host == uri.host &&
            !uri.hasQuery &&
            RegExp(
              r'^/KC3Kai/kc3-translations/[0-9a-f]{40}/data/(?:en|kr)/quotes\.json$',
            ).hasMatch(uri.path)));

bool _redirectStatus(int code) =>
    const {301, 302, 303, 307, 308}.contains(code);
