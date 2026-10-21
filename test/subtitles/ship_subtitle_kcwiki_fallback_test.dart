import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_catalog.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_catalog_controller.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_catalog_store.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_language.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_resource_state.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_update_service.dart';

const oldVersion = '2026101705';
const middleVersion = '2026101805';
const latestVersion = '2026101905';
final checkedAt = DateTime.utc(2026, 10, 20, 9);

ShipSubtitleCatalog catalog(String text, String version) => ShipSubtitleCatalog(
  version: version,
  quotes: {
    '1': {'1': text},
  },
);

void main() {
  test(
    'a mixed primary retries the complete fallback group and restores it offline',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'subtitle-fallback-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = FileShipSubtitleResourceStateStore.inDirectory(directory);
      final requests = <Uri>[];
      var offline = false;
      final fixture = HttpFixture(
        resourceStore: store,
        respond: (request) {
          if (offline) throw StateError('An offline load must not fetch data.');
          requests.add(request.url);
          if (request.url.path.endsWith('/version')) {
            return http.Response('{"version":"$latestVersion"}', 200);
          }
          final primary = request.url.host == 'acc.kcwiki.cn';
          return http.Response(
            catalog(
              '${request.url.host}${request.url.path}',
              primary && request.url.path != '/subtitles/zh-cn'
                  ? middleVersion
                  : latestVersion,
            ).toJsonString(),
            200,
          );
        },
      );
      addTearDown(fixture.client.close);
      var controller = await fixture.load();
      final publishedVersions = <String>[];
      controller.addListener(
        () => publishedVersions.add(controller.kcwikiVersion),
      );
      expect(await controller.checkForUpdates(), isA<ShipSubtitleUpdated>());
      expect(
        requests
            .where((uri) => uri.host == 'api.kcwiki.moe')
            .map((uri) => uri.path),
        containsAll(['/subtitles/zh-cn', '/subtitles/zh-tw', '/subtitles/jp']),
      );
      expect(publishedVersions.toSet(), {oldVersion, latestVersion});
      expect(
        fixture.languageStores.values.every((value) => value.saves == 0),
        isTrue,
      );
      for (final language in kcwikiSubtitleLanguages) {
        await controller.selectLanguage(language);
        expect(controller.data.version, latestVersion);
        expect(controller.data.quotes['1']?['1'], startsWith('api.kcwiki.moe'));
      }
      controller.dispose();
      offline = true;
      final requestCount = requests.length;
      controller = await fixture.load();
      addTearDown(controller.dispose);
      expect(controller.kcwikiVersion, latestVersion);
      expect(controller.kcwikiLastCheckedAt, checkedAt);
      for (final language in kcwikiSubtitleLanguages) {
        await controller.selectLanguage(language);
        expect(controller.data.version, latestVersion);
        expect(controller.data.quotes['1']?['1'], startsWith('api.kcwiki.moe'));
      }
      expect(requests, hasLength(requestCount));
    },
  );

  test('no consistent source leaves every cached language untouched', () async {
    final store = MemoryResourceStore();
    final requests = <Uri>[];
    final fixture = HttpFixture(
      resourceStore: store,
      respond: (request) {
        requests.add(request.url);
        if (request.url.path.endsWith('/version')) {
          return http.Response('{"version":"$latestVersion"}', 200);
        }
        return http.Response(
          catalog(
            request.url.host,
            request.url.path == '/subtitles/zh-cn'
                ? latestVersion
                : middleVersion,
          ).toJsonString(),
          200,
        );
      },
    );
    addTearDown(fixture.client.close);
    final controller = await fixture.load();
    addTearDown(controller.dispose);
    expect(await controller.checkForUpdates(), isA<ShipSubtitleUpdateFailed>());
    expect(requests.any((uri) => uri.host == 'api.kcwiki.moe'), isTrue);
    expect(controller.kcwikiVersion, oldVersion);
    expect(controller.kcwikiLastCheckedAt, isNull);
    expect(store.state.catalogs, isEmpty);
    expect(
      fixture.languageStores.values.every((value) => value.saves == 0),
      isTrue,
    );
    for (final language in kcwikiSubtitleLanguages) {
      await controller.selectLanguage(language);
      expect(controller.data.version, oldVersion);
      expect(controller.data.quotes['1']?['1'], 'offline ${language.code}');
    }
  });

  test('an older fallback cannot replace a newer cached group', () async {
    final fixture = HttpFixture(
      initialVersion: middleVersion,
      respond: (request) {
        if (request.url.path.endsWith('/version')) {
          return http.Response('{"version":"$latestVersion"}', 200);
        }
        return http.Response(
          catalog(
            request.url.host,
            request.url.host == 'acc.kcwiki.cn' &&
                    request.url.path == '/subtitles/zh-cn'
                ? latestVersion
                : oldVersion,
          ).toJsonString(),
          200,
        );
      },
    );
    addTearDown(fixture.client.close);
    final controller = await fixture.load();
    addTearDown(controller.dispose);
    expect(await controller.checkForUpdates(), isA<ShipSubtitleUpdateFailed>());
    expect(controller.kcwikiVersion, middleVersion);
    expect(controller.kcwikiLastCheckedAt, isNull);
    expect(
      fixture.languageStores.values.every((value) => value.saves == 0),
      isTrue,
    );
  });

  test('unchanged source versions skip full downloads and fallback', () async {
    final requests = <Uri>[];
    final fixture = HttpFixture(
      respond: (request) {
        requests.add(request.url);
        return http.Response('{"version":"$oldVersion"}', 200);
      },
    );
    addTearDown(fixture.client.close);
    final controller = await fixture.load();
    addTearDown(controller.dispose);
    expect(await controller.checkForUpdates(), isA<ShipSubtitleUpToDate>());
    expect(requests, hasLength(3));
    expect(requests.every((uri) => uri.host == 'acc.kcwiki.cn'), isTrue);
    expect(requests.every((uri) => uri.path == '/subtitles/version'), isTrue);
    expect(controller.kcwikiVersion, oldVersion);
  });
}

final class HttpFixture {
  HttpFixture({
    required http.Response Function(http.Request) respond,
    this.initialVersion = oldVersion,
    ShipSubtitleResourceStateStore? resourceStore,
  }) : client = MockClient((request) async => respond(request)),
       resourceStore = resourceStore ?? MemoryResourceStore();

  final String initialVersion;
  final MockClient client;
  final ShipSubtitleResourceStateStore resourceStore;
  final languageStores = <ShipSubtitleLanguage, MemoryCatalogStore>{};

  Future<ShipSubtitleCatalogController> load() =>
      ShipSubtitleCatalogController.load(
        updateAllLanguages: true,
        resourceStore: resourceStore,
        now: () => checkedAt,
        languageLoader: (language) async {
          final data = catalog('offline ${language.code}', initialVersion);
          final store = languageStores[language] = MemoryCatalogStore(data);
          return ShipSubtitleCatalogSource(
            data: data,
            store: store,
            updater: ShipSubtitleUpdateService(
              client: client,
              store: store,
              language: language,
            ),
          );
        },
      );
}

final class MemoryCatalogStore implements ShipSubtitleCatalogStore {
  MemoryCatalogStore(this.data);
  final ShipSubtitleCatalog data;
  int saves = 0;
  @override
  Future<ShipSubtitleCatalog> loadBestAvailable() async => data;
  @override
  Future<DateTime?> loadLastCheckedAt() async => null;
  @override
  Future<void> save(ShipSubtitleCatalog value) async => saves++;
  @override
  Future<void> saveLastCheckedAt(DateTime value) async {}
}

final class MemoryResourceStore implements ShipSubtitleResourceStateStore {
  ShipSubtitleResourceState state = const ShipSubtitleResourceState();
  @override
  Future<ShipSubtitleResourceState> load() async => state;
  @override
  Future<void> save(ShipSubtitleResourceState value) async => state = value;
}
