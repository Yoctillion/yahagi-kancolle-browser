import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ship_subtitle_kc3_bundle.dart';
import 'ship_subtitle_kc3_store.dart';
import 'ship_subtitle_update_service.dart' show ShipSubtitleUpdateFailure;

sealed class ShipSubtitleKc3UpdateResult {
  const ShipSubtitleKc3UpdateResult({required this.sourceHost});
  final String sourceHost;
}

final class ShipSubtitleKc3UpToDate extends ShipSubtitleKc3UpdateResult {
  const ShipSubtitleKc3UpToDate(this.bundle, {required super.sourceHost});
  final ShipSubtitleKc3Bundle bundle;
}

final class ShipSubtitleKc3Updated extends ShipSubtitleKc3UpdateResult {
  const ShipSubtitleKc3Updated(this.bundle, {required super.sourceHost});
  final ShipSubtitleKc3Bundle bundle;
}

final class ShipSubtitleKc3UpdateFailed extends ShipSubtitleKc3UpdateResult {
  const ShipSubtitleKc3UpdateFailed(
    this.kind,
    this.error, {
    required super.sourceHost,
  });
  final ShipSubtitleUpdateFailure kind;
  final Object error;
}

abstract interface class ShipSubtitleKc3UpdateClient {
  Future<ShipSubtitleKc3UpdateResult> checkAndUpdate({
    required ShipSubtitleKc3Bundle current,
  });
}

/// Repository HEAD is resolved once; all 22 members use that immutable SHA.
final class ShipSubtitleKc3UpdateService
    implements ShipSubtitleKc3UpdateClient {
  const ShipSubtitleKc3UpdateService({
    required this.client,
    required this.store,
    this.timeout = const Duration(seconds: 20),
    this.maximumDownloadDuration = const Duration(minutes: 2),
    this.maximumDataBytes = 16 * 1024 * 1024,
    this.maximumMetadataBytes = 128 * 1024,
  });

  final http.Client client;
  final ShipSubtitleKc3Store store;
  final Duration timeout;
  final Duration maximumDownloadDuration;
  final int maximumDataBytes;
  final int maximumMetadataBytes;

  @override
  Future<ShipSubtitleKc3UpdateResult> checkAndUpdate({
    required ShipSubtitleKc3Bundle current,
  }) async {
    var sourceHost = 'api.github.com';
    final deadline = DateTime.now().add(maximumDownloadDuration);
    try {
      final metadata = jsonDecode(
        utf8.decode(
          await _get(
            Uri.https(
              sourceHost,
              '/repos/KC3Kai/kc3-translations/commits/master',
            ),
            maximumMetadataBytes,
            deadline,
          ),
        ),
      );
      if (metadata is! Map<String, dynamic>) {
        throw const FormatException('KC3 repository HEAD is invalid.');
      }
      final sha = ShipSubtitleKc3Bundle.validateCommit(metadata['sha']);
      final details = metadata['commit'];
      final committer = details is Map ? details['committer'] : null;
      final version = ShipSubtitleKc3Bundle.versionFromCommitDate(
        committer is Map ? committer['date'] : null,
      );
      if (sha == current.commit) {
        if (version != current.version) {
          throw const FormatException(
            'KC3 existing commit has inconsistent date.',
          );
        }
        return ShipSubtitleKc3UpToDate(current, sourceHost: sourceHost);
      }
      if (version.compareTo(current.version) < 0) {
        throw const FormatException('KC3 repository returned an older HEAD.');
      }
      sourceHost = 'raw.githubusercontent.com';
      final files = <String, Uint8List>{};
      var totalBytes = 0;
      for (final path in ShipSubtitleKc3Bundle.sourcePaths) {
        final bytes = await _get(
          Uri.https(sourceHost, '/KC3Kai/kc3-translations/$sha/$path'),
          maximumDataBytes - totalBytes,
          deadline,
        );
        totalBytes += bytes.length;
        files[path] = bytes;
      }
      final candidate = await compute(_decodeBundle, (
        version: version,
        commit: sha,
        files: files,
      ));
      try {
        await store.save(candidate);
      } on Object catch (error) {
        return ShipSubtitleKc3UpdateFailed(
          ShipSubtitleUpdateFailure.storage,
          error,
          sourceHost: sourceHost,
        );
      }
      return ShipSubtitleKc3Updated(candidate, sourceHost: sourceHost);
    } on Object catch (error) {
      return ShipSubtitleKc3UpdateFailed(
        error is FormatException
            ? ShipSubtitleUpdateFailure.validation
            : ShipSubtitleUpdateFailure.network,
        error,
        sourceHost: sourceHost,
      );
    }
  }

  Future<Uint8List> _get(Uri uri, int maximumBytes, DateTime deadline) async {
    Completer<void>? activeAbort;
    Duration nextTimeout() {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw TimeoutException('KC3 download exceeded its time limit.');
      }
      return remaining < timeout ? remaining : timeout;
    }

    try {
      var requestUri = uri;
      for (var redirects = 0; redirects <= 5; redirects++) {
        if (!_allowedUri(requestUri, uri)) {
          throw const FormatException('KC3 download URL is not allowed.');
        }
        final abort = Completer<void>();
        activeAbort = abort;
        final request =
            http.AbortableRequest('GET', requestUri, abortTrigger: abort.future)
              ..followRedirects = false
              ..headers['User-Agent'] = 'Yahagi-Kancolle-Browser'
              ..headers['Accept'] = 'application/vnd.github+json';
        final response = await client.send(request).timeout(nextTimeout());
        if (const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
          final location = response.headers['location'];
          await response.stream.listen((_) {}, onError: (Object _) {}).cancel();
          if (!abort.isCompleted) abort.complete();
          if (location == null || redirects == 5) {
            throw const FormatException('KC3 redirect limit exceeded.');
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
              'KC3 request failed: ${response.statusCode}',
              requestUri,
            );
          }
          throw const FormatException('KC3 response exceeds size limit.');
        }
        final bytes = BytesBuilder(copy: false);
        final chunks = StreamIterator(response.stream);
        try {
          while (await chunks.moveNext().timeout(nextTimeout())) {
            final chunk = chunks.current;
            if (bytes.length + chunk.length > maximumBytes) {
              throw const FormatException('KC3 response exceeds size limit.');
            }
            bytes.add(chunk);
          }
        } finally {
          if (!abort.isCompleted) abort.complete();
          await chunks.cancel();
        }
        return bytes.takeBytes();
      }
      throw const FormatException('KC3 redirect limit exceeded.');
    } finally {
      final abort = activeAbort;
      if (abort != null && !abort.isCompleted) abort.complete();
    }
  }
}

ShipSubtitleKc3Bundle _decodeBundle(
  ({String version, String commit, Map<String, Uint8List> files}) input,
) {
  final files = <String, dynamic>{};
  for (final entry in input.files.entries) {
    final decoded = jsonDecode(utf8.decode(entry.value));
    if (decoded is! Map<String, dynamic> && decoded is! List) {
      throw const FormatException('KC3 resource must be an object or array.');
    }
    files[entry.key] = decoded;
  }
  return ShipSubtitleKc3Bundle.fromKc3Files(
    version: input.version,
    commit: input.commit,
    files: files,
  );
}

bool _allowedUri(Uri uri, Uri original) =>
    uri.scheme == 'https' &&
    uri.userInfo.isEmpty &&
    uri.port == 443 &&
    !uri.hasFragment &&
    !uri.hasQuery &&
    uri.host == original.host &&
    uri.path == original.path &&
    ((uri.host == 'api.github.com' &&
            uri.path == '/repos/KC3Kai/kc3-translations/commits/master') ||
        (uri.host == 'raw.githubusercontent.com' &&
            RegExp(
              r'^/KC3Kai/kc3-translations/[0-9a-f]{40}/data/(en|scn|tcn|kr)/(quotes|ships|ship_affix|items|stype|equiptype)\.json$',
            ).hasMatch(uri.path) &&
            ShipSubtitleKc3Bundle.sourcePaths.any(
              (path) => uri.path.endsWith('/$path'),
            )));
