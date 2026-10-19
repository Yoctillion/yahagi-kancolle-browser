import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_catalog.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_catalog_controller.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_catalog_store.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_update_service.dart';

String fixture([String version = '2026101805']) => jsonEncode({
  'version': version,
  '1': {'1': '我是睦月！', '141': '联合舰队，出击！'},
});

void main() {
  group('catalog validation', () {
    test('reads the upstream shape and makes quote maps immutable', () {
      final data = ShipSubtitleCatalog.fromJsonString(fixture());
      expect(data.version, '2026101805');
      expect(data.quoteCount, 2);
      expect(data.isEmpty, isFalse);
      expect(data.quotes['1']?['141'], '联合舰队，出击！');
      expect(() => data.quotes['1']!['1'] = 'changed', throwsUnsupportedError);
      expect(() => data.quotes.clear(), throwsUnsupportedError);
    });

    test(
      'rejects malformed versions, nonnumeric ids, and partial payloads',
      () {
        for (final body in [
          {
            'version': 'latest',
            '1': {'1': '台词'},
          },
          {
            'version': '2026101805',
            'garbage': {'1': '台词'},
          },
          {
            'version': '2026101805',
            '1': {'x': '台词'},
          },
          {
            'version': '2026101805',
            '1': {'1': 7},
          },
          {
            'version': '2026101805',
            '1': {'1': '   '},
          },
          {'version': '2026101805'},
          {'version': '2026101805', '1': {}},
        ]) {
          expect(
            () => ShipSubtitleCatalog.fromJson(body),
            throwsFormatException,
          );
        }
      },
    );

    test(
      'bundled snapshot is current complete simplified Chinese data',
      () async {
        final data = ShipSubtitleCatalog.fromJsonString(
          await File('assets/data/subtitles/zh-cn.json').readAsString(),
        );
        expect(data.version.compareTo('2026101805'), greaterThanOrEqualTo(0));
        expect(data.quotes.length, greaterThanOrEqualTo(860));
        expect(data.quoteCount, greaterThan(33000));
        expect(data.quotes['1']?['1'], contains('睦月'));
      },
    );
  });

  group('cache and update', () {
    late Directory directory;
    late FileShipSubtitleCatalogStore store;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('ship-subtitles-');
      store = FileShipSubtitleCatalogStore(
        cacheFile: File('${directory.path}/catalog.json'),
        bundledReader: () async => fixture(),
      );
    });
    tearDown(() async => directory.delete(recursive: true));

    test(
      'ignores older or corrupt caches and recovers a torn replacement',
      () async {
        await store.cacheFile.writeAsString(fixture('2026101705'));
        expect((await store.loadBestAvailable()).version, '2026101805');
        await store.cacheFile.writeAsString('{broken');
        await File(
          '${store.cacheFile.path}.bak',
        ).writeAsString(fixture('2026101905'));
        expect((await store.loadBestAvailable()).version, '2026101905');
        expect(
          ShipSubtitleCatalog.fromJsonString(
            await store.cacheFile.readAsString(),
          ).version,
          '2026101905',
        );
      },
    );

    test('persists the last check and replaces a valid catalog', () async {
      final checkedAt = DateTime.utc(2026, 10, 18, 9);
      await store.saveLastCheckedAt(checkedAt);
      await store.save(
        ShipSubtitleCatalog.fromJsonString(fixture('2026101905')),
      );
      expect(await store.loadLastCheckedAt(), checkedAt);
      expect((await store.loadBestAvailable()).version, '2026101905');
      expect(await File('${store.cacheFile.path}.tmp').exists(), isFalse);
      expect(await File('${store.cacheFile.path}.bak').exists(), isFalse);
    });

    test(
      'uses downloaded body version when version endpoint is ahead',
      () async {
        final result = await ShipSubtitleUpdateService(
          client: MockClient(
            (request) async => http.Response(
              request.url.path.endsWith('/version')
                  ? '{"version":"2026102005"}'
                  : fixture('2026101905'),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
          store: store,
        ).checkAndUpdate(current: await store.loadBestAvailable());
        expect(result, isA<ShipSubtitleUpdated>());
        expect((await store.loadBestAvailable()).version, '2026101905');
      },
    );

    test('does not downgrade when a CDN serves older full data', () async {
      final result = await ShipSubtitleUpdateService(
        client: MockClient(
          (request) async => http.Response(
            request.url.path.endsWith('/version')
                ? '{"version":"2026102005"}'
                : fixture('2026101705'),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
        store: store,
      ).checkAndUpdate(current: await store.loadBestAvailable());
      expect(result, isA<ShipSubtitleUpdateFailed>());
      expect((await store.loadBestAvailable()).version, '2026101805');
    });

    test('skips full download when the version is unchanged', () async {
      final paths = <String>[];
      final result = await ShipSubtitleUpdateService(
        client: MockClient((request) async {
          paths.add(request.url.path);
          return http.Response('{"version":"2026101805"}', 200);
        }),
        store: store,
      ).checkAndUpdate(current: await store.loadBestAvailable());
      expect(result, isA<ShipSubtitleUpToDate>());
      expect(paths, ['/subtitles/version']);
    });

    test(
      'falls back to the second trusted source after a primary failure',
      () async {
        final hosts = <String>[];
        final result = await ShipSubtitleUpdateService(
          client: MockClient((request) async {
            hosts.add(request.url.host);
            if (request.url.host == 'acc.kcwiki.cn') {
              return http.Response('', 503);
            }
            return http.Response(
              request.url.path.endsWith('/version')
                  ? '{"version":"2026101905"}'
                  : fixture('2026101905'),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
          store: store,
        ).checkAndUpdate(current: await store.loadBestAvailable());
        expect(result, isA<ShipSubtitleUpdated>());
        expect(hosts, contains('api.kcwiki.moe'));
        expect(result.sourceHost, 'api.kcwiki.moe');
      },
    );

    test(
      'rejects cross-host and insecure redirects before fetching them',
      () async {
        final hosts = <String>[];
        final result = await ShipSubtitleUpdateService(
          client: MockClient((request) async {
            hosts.add(request.url.host);
            return http.Response(
              '',
              302,
              headers: {
                'location': request.url.host == 'acc.kcwiki.cn'
                    ? 'https://untrusted.example/subtitles/version'
                    : 'http://api.kcwiki.moe/subtitles/version',
              },
            );
          }),
          store: store,
        ).checkAndUpdate(current: await store.loadBestAvailable());
        expect(result, isA<ShipSubtitleUpdateFailed>());
        expect(hosts.toSet(), {'acc.kcwiki.cn', 'api.kcwiki.moe'});
      },
    );

    test('rejects oversized payloads without replacing cached data', () async {
      await store.save(ShipSubtitleCatalog.fromJsonString(fixture()));
      final result = await ShipSubtitleUpdateService(
        client: MockClient(
          (request) async => http.Response(
            request.url.path.endsWith('/version')
                ? '{"version":"2026101905"}'
                : fixture('2026101905'),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
        store: store,
        maximumDataBytes: 10,
      ).checkAndUpdate(current: await store.loadBestAvailable());
      expect(result, isA<ShipSubtitleUpdateFailed>());
      expect((await store.loadBestAvailable()).version, '2026101805');
    });

    test('bounds a stalled network request', () async {
      final result = await ShipSubtitleUpdateService(
        client: MockClient((_) => Completer<http.Response>().future),
        store: store,
        timeout: const Duration(milliseconds: 10),
      ).checkAndUpdate(current: await store.loadBestAvailable());
      expect(result, isA<ShipSubtitleUpdateFailed>());
      expect((await store.loadBestAvailable()).version, '2026101805');
    });

    test(
      'rejects malformed downloaded full data and preserves cached data',
      () async {
        final result = await ShipSubtitleUpdateService(
          client: MockClient(
            (request) async => http.Response(
              request.url.path.endsWith('/version')
                  ? '{"version":"2026101905"}'
                  : '{"version":"2026101905","1":{"1":12}}',
              200,
            ),
          ),
          store: store,
        ).checkAndUpdate(current: await store.loadBestAvailable());
        expect(result, isA<ShipSubtitleUpdateFailed>());
        expect(
          (result as ShipSubtitleUpdateFailed).kind,
          ShipSubtitleUpdateFailure.validation,
        );
        expect((await store.loadBestAvailable()).version, '2026101805');
      },
    );

    test('limits streamed bytes without trusting Content-Length', () async {
      final result = await ShipSubtitleUpdateService(
        client: _BodyClient(() => Stream.value(List.filled(40, 65))),
        store: store,
        maximumDataBytes: 20,
      ).checkAndUpdate(current: await store.loadBestAvailable());
      expect(result, isA<ShipSubtitleUpdateFailed>());
      expect((await store.loadBestAvailable()).version, '2026101805');
    });

    test(
      'cancels continuously streaming responses at the overall deadline',
      () async {
        var cancelled = 0;
        final client = _BodyClient(() {
          Timer? timer;
          late StreamController<List<int>> stream;
          stream = StreamController<List<int>>(
            onListen: () => timer = Timer.periodic(
              const Duration(milliseconds: 2),
              (_) => stream.add([32]),
            ),
            onCancel: () {
              timer?.cancel();
              cancelled++;
            },
          );
          return stream.stream;
        });
        final result = await ShipSubtitleUpdateService(
          client: client,
          store: store,
          timeout: const Duration(seconds: 1),
          maximumDownloadDuration: const Duration(milliseconds: 20),
        ).checkAndUpdate(current: await store.loadBestAvailable());
        expect(result, isA<ShipSubtitleUpdateFailed>());
        expect(cancelled, 2);
      },
    );

    test(
      'automatic checks persist daily limit while manual checks bypass it',
      () async {
        var now = DateTime.utc(2026, 10, 18, 9);
        final updater = _CountingUpdater();
        final controller = await ShipSubtitleCatalogController.load(
          store: store,
          updater: updater,
          now: () => now,
        );
        await controller.checkIfDue();
        await controller.checkIfDue();
        expect(updater.calls, 1);
        expect(await store.loadLastCheckedAt(), now);
        controller.dispose();
        final reloaded = await ShipSubtitleCatalogController.load(
          store: store,
          updater: updater,
          now: () => now,
        );
        addTearDown(reloaded.dispose);
        await reloaded.checkIfDue();
        expect(updater.calls, 1);
        await reloaded.checkForUpdates();
        expect(updater.calls, 2);
        now = now.add(const Duration(hours: 24));
        await reloaded.checkIfDue();
        expect(updater.calls, 3);
      },
    );

    test(
      'failed checks preserve data and still rate limit automatic retries',
      () async {
        final updater = _CountingUpdater(fail: true);
        final controller = await ShipSubtitleCatalogController.load(
          store: store,
          updater: updater,
        );
        addTearDown(controller.dispose);
        await controller.checkIfDue();
        await controller.checkIfDue();
        expect(updater.calls, 1);
        expect(controller.data.version, '2026101805');
        expect(controller.lastError, isNotNull);
        expect(controller.isChecking, isFalse);
      },
    );
  });
}

final class _BodyClient extends http.BaseClient {
  _BodyClient(this.body);
  final Stream<List<int>> Function() body;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        request.url.path.endsWith('/version')
            ? Stream.value(utf8.encode('{"version":"2026101905"}'))
            : body(),
        200,
      );
}

final class _CountingUpdater implements ShipSubtitleUpdateClient {
  _CountingUpdater({this.fail = false});
  final bool fail;
  int calls = 0;
  @override
  Future<ShipSubtitleUpdateResult> checkAndUpdate({
    required ShipSubtitleCatalog current,
  }) async {
    calls++;
    return fail
        ? ShipSubtitleUpdateFailed(
            ShipSubtitleUpdateFailure.network,
            StateError('offline'),
            sourceHost: 'test',
          )
        : ShipSubtitleUpToDate(current, sourceHost: 'test');
  }
}
