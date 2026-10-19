import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_catalog.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_catalog_controller.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_catalog_store.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_language.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_update_service.dart';

ShipSubtitleCatalog catalog(String text, [String version = '2026101805']) =>
    ShipSubtitleCatalog(
      version: version,
      quotes: {
        '1': {'1': text},
      },
    );

void main() {
  test(
    'one resource check updates all kcwiki languages without switching',
    () async {
      final checked = <ShipSubtitleLanguage>[];
      final controller = await ShipSubtitleCatalogController.load(
        languageLoader: (language) async => ShipSubtitleCatalogSource(
          data: catalog(language.label),
          updater: RecordingUpdater(language, checked),
        ),
      );
      addTearDown(controller.dispose);
      await controller.checkForUpdates();
      expect(checked.toSet(), {
        ShipSubtitleLanguage.simplifiedChinese,
        ShipSubtitleLanguage.traditionalChinese,
        ShipSubtitleLanguage.japanese,
      });
      expect(controller.language, ShipSubtitleLanguage.simplifiedChinese);
      await controller.selectLanguage(ShipSubtitleLanguage.japanese);
      expect(controller.data.quotes['1']?['1'], 'updated 日本語');
      expect(checked, hasLength(3));
    },
  );
  test('a synchronously failed language load can be retried', () async {
    var calls = 0;
    final controller = ShipSubtitleCatalogController(
      data: catalog('简中'),
      updater: PendingUpdater(),
      languageLoader: (_) {
        if (++calls == 1) throw const FormatException('temporary read failure');
        return Future.value(
          ShipSubtitleCatalogSource(
            data: catalog('English'),
            updater: PendingUpdater(),
          ),
        );
      },
    );
    addTearDown(controller.dispose);
    await controller.selectLanguage(ShipSubtitleLanguage.english);
    expect(controller.lastError, isNotNull);
    await controller.selectLanguage(ShipSubtitleLanguage.english);
    expect(controller.isLanguageReady, isTrue);
    expect(controller.data.quotes['1']?['1'], 'English');
    expect(calls, 2);
  });

  test('KC3 English labels and timed plain text map to numeric voice IDs', () {
    final data = ShipSubtitleCatalog.fromKc3Json({
      'timing': {'Intro': 2000},
      '1': {
        'Intro': "I'm Mutsuki. <i>Ready</i> &amp; waiting!",
        'Poke(1)': 'Hello<br />Admiral&#33;',
        'H2300': {'1500,2500': 'Second.', '0': 'First.', '3000': ''},
        '141': 'Combined fleet!',
        '2@Xmas': 'Seasonal line must not overwrite the base voice.',
        'Friend44(1)': 'Unsupported extra category.',
      },
      '2': {'2@Xmas': 'Only seasonal.'},
    }, version: '20260804124356');
    expect(data.version, '20260804124356');
    expect(data.quotes, {
      '1': {
        '1': "I'm Mutsuki. Ready & waiting!",
        '2': 'Hello\nAdmiral!',
        '53': 'First.\nSecond.',
        '141': 'Combined fleet!',
      },
    });
    expect(
      ShipSubtitleCatalog.fromJsonString(data.toJsonString()).version,
      data.version,
    );
  });

  test(
    'English checks its own file commit then fetches pinned quote data',
    () async {
      final directory = await Directory.systemTemp.createTemp('subtitle-en-');
      addTearDown(() => directory.delete(recursive: true));
      final store = FileShipSubtitleCatalogStore(
        cacheFile: File('${directory.path}/en-us.json'),
        bundledReader: () async =>
            catalog('offline', '20260701000000').toJsonString(),
      );
      final urls = <Uri>[];
      const sha = 'dfa489f91a2a15120037d174e76771330d4c3582';
      final result = await ShipSubtitleUpdateService(
        language: ShipSubtitleLanguage.english,
        store: store,
        client: MockClient((request) async {
          urls.add(request.url);
          return http.Response(
            jsonEncode(
              request.url.host == 'api.github.com'
                  ? [
                      {
                        'sha': sha,
                        'commit': {
                          'committer': {'date': '2026-08-04T12:43:56Z'},
                        },
                      },
                    ]
                  : {
                      '1': {
                        'Intro': 'English update',
                        'Poke(1)': 'Hello<br>Admiral',
                      },
                    },
            ),
            200,
          );
        }),
      ).checkAndUpdate(current: await store.loadBestAvailable());
      expect(result, isA<ShipSubtitleUpdated>());
      expect(urls.length, 2);
      expect(urls.first.host, 'api.github.com');
      expect(urls.first.queryParameters, {
        'path': 'data/en/quotes.json',
        'per_page': '1',
      });
      expect(
        urls.last.toString(),
        'https://raw.githubusercontent.com/KC3Kai/kc3-translations/$sha/data/en/quotes.json',
      );
      final saved = await store.loadBestAvailable();
      expect(saved.version, '20260804124356');
      expect(saved.quotes['1']?['1'], 'English update');
    },
  );

  test('English skips full download when its own commit is unchanged', () async {
    final directory = await Directory.systemTemp.createTemp('subtitle-en-');
    addTearDown(() => directory.delete(recursive: true));
    final store = FileShipSubtitleCatalogStore(
      cacheFile: File('${directory.path}/en-us.json'),
      bundledReader: () async =>
          catalog('English', '20260804124356').toJsonString(),
    );
    var calls = 0;
    final result = await ShipSubtitleUpdateService(
      language: ShipSubtitleLanguage.english,
      store: store,
      client: MockClient((request) async {
        calls++;
        return http.Response(
          '[{"sha":"dfa489f91a2a15120037d174e76771330d4c3582","commit":{"committer":{"date":"2026-08-04T12:43:56Z"}}}]',
          200,
        );
      }),
    ).checkAndUpdate(current: await store.loadBestAvailable());
    expect(result, isA<ShipSubtitleUpToDate>());
    expect(calls, 1);
  });

  test(
    'English rejects malformed commits and unsafe redirects without writes',
    () async {
      final directory = await Directory.systemTemp.createTemp('subtitle-en-');
      addTearDown(() => directory.delete(recursive: true));
      final store = FileShipSubtitleCatalogStore(
        cacheFile: File('${directory.path}/en-us.json'),
        bundledReader: () async =>
            catalog('English', '20260804124356').toJsonString(),
      );
      for (final body in [
        '[{"sha":"../../evil","commit":{"committer":{"date":"2026-09-04T12:43:56Z"}}}]',
        '[{"sha":"dfa489f91a2a15120037d174e76771330d4c3582","commit":{"committer":{"date":"not-a-date"}}}]',
        '{"message":"API rate limit exceeded"}',
      ]) {
        final result = await ShipSubtitleUpdateService(
          language: ShipSubtitleLanguage.english,
          store: store,
          client: MockClient((_) async => http.Response(body, 200)),
        ).checkAndUpdate(current: await store.loadBestAvailable());
        expect(result, isA<ShipSubtitleUpdateFailed>());
        expect(await store.cacheFile.exists(), isFalse);
      }
      final fetched = <Uri>[];
      final result = await ShipSubtitleUpdateService(
        language: ShipSubtitleLanguage.english,
        store: store,
        client: MockClient((request) async {
          fetched.add(request.url);
          return http.Response(
            '',
            302,
            headers: {'location': 'https://untrusted.example/quotes.json'},
          );
        }),
      ).checkAndUpdate(current: await store.loadBestAvailable());
      expect(result, isA<ShipSubtitleUpdateFailed>());
      expect(fetched.length, 1);
      expect(await store.cacheFile.exists(), isFalse);
    },
  );

  test('every language has an offline snapshot of real voice lines', () async {
    final expected = {
      ShipSubtitleLanguage.simplifiedChinese: '睦月',
      ShipSubtitleLanguage.traditionalChinese: '睦月',
      ShipSubtitleLanguage.japanese: '睦月です',
      ShipSubtitleLanguage.english: "I'm Mutsuki",
    };
    for (final entry in expected.entries) {
      final file = File(entry.key.bundledAsset);
      expect(await file.exists(), isTrue, reason: entry.key.code);
      final data = ShipSubtitleCatalog.fromJsonString(
        await file.readAsString(),
      );
      expect(data.quotes['1']?['1'], contains(entry.value));
      expect(data.quotes.length, greaterThan(500));
      expect(
        data.quoteCount,
        greaterThan(entry.key == ShipSubtitleLanguage.english ? 15000 : 33000),
      );
    }
  });

  test('selected language uses its own full-data path', () async {
    final directory = await Directory.systemTemp.createTemp(
      'subtitle-language-',
    );
    addTearDown(() => directory.delete(recursive: true));
    for (final entry in {
      ShipSubtitleLanguage.traditionalChinese: '/subtitles/zh-tw',
      ShipSubtitleLanguage.japanese: '/subtitles/jp',
    }.entries) {
      final paths = <String>[];
      final store = FileShipSubtitleCatalogStore(
        cacheFile: File('${directory.path}/${entry.key.code}.json'),
        bundledReader: () async => catalog('offline').toJsonString(),
      );
      final result = await ShipSubtitleUpdateService(
        language: entry.key,
        store: store,
        client: MockClient((request) async {
          paths.add(request.url.path);
          return http.Response(
            request.url.path.endsWith('/version')
                ? '{"version":"2026101905"}'
                : catalog(entry.key.label, '2026101905').toJsonString(),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ).checkAndUpdate(current: catalog('offline'));
      expect(result, isA<ShipSubtitleUpdated>());
      expect(paths, ['/subtitles/version', entry.value]);
      expect(
        (await store.loadBestAvailable()).quotes['1']?['1'],
        entry.key.label,
      );
    }
  });

  test(
    'file stores keep original simplified path and isolate language state',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'subtitle-language-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final stores = <FileShipSubtitleCatalogStore>[];
      for (final language in ShipSubtitleLanguage.values) {
        final store = FileShipSubtitleCatalogStore.inDirectory(
          directory,
          language: language,
          bundledReader: () async => catalog(language.label).toJsonString(),
        );
        stores.add(store);
        expect(
          store.cacheFile.path,
          endsWith('ship-subtitles-${language.code}.json'),
        );
        await store.save(catalog(language.label, '2026101905'));
        await store.saveLastCheckedAt(
          DateTime.utc(2026, 10, 18, language.index),
        );
      }
      for (final language in ShipSubtitleLanguage.values) {
        expect(
          (await stores[language.index].loadBestAvailable()).quotes['1']?['1'],
          language.label,
        );
        expect(
          await stores[language.index].loadLastCheckedAt(),
          DateTime.utc(2026, 10, 18, language.index),
        );
      }
    },
  );

  test(
    'late old-language updates only change their own data and check time',
    () async {
      final oldUpdater = PendingUpdater();
      final englishUpdater = PendingUpdater();
      final controller = ShipSubtitleCatalogController(
        data: catalog('简中'),
        updater: oldUpdater,
        now: () => DateTime.utc(2026, 10, 18),
        languageLoader: (_) async => ShipSubtitleCatalogSource(
          data: catalog('English', '2018082511'),
          updater: englishUpdater,
        ),
      );
      addTearDown(controller.dispose);
      final oldCheck = controller.checkForUpdates();
      await controller.selectLanguage(ShipSubtitleLanguage.english);
      expect(controller.language, ShipSubtitleLanguage.english);
      expect(controller.dataLanguage, ShipSubtitleLanguage.english);
      expect(controller.isChecking, isFalse);
      expect(controller.lastCheckedAt, isNull);
      oldUpdater.pending.complete(
        ShipSubtitleUpdated(catalog('新简中', '2026101905'), sourceHost: 'test'),
      );
      await oldCheck;
      expect(controller.data.quotes['1']?['1'], 'English');
      expect(controller.lastCheckedAt, isNull);
      await controller.selectLanguage(ShipSubtitleLanguage.simplifiedChinese);
      expect(controller.data.quotes['1']?['1'], '新简中');
      expect(controller.lastCheckedAt, DateTime.utc(2026, 10, 18));
      await controller.checkIfDue();
      expect(oldUpdater.calls, 1);
    },
  );

  test(
    'rapid switches ignore the older load and preserve the latest target',
    () async {
      final pending = Completer<ShipSubtitleCatalogSource>();
      final controller = ShipSubtitleCatalogController(
        data: catalog('简中'),
        updater: PendingUpdater(),
        languageLoader: (language) => language == ShipSubtitleLanguage.english
            ? pending.future
            : Future.value(
                ShipSubtitleCatalogSource(
                  data: catalog('日本語'),
                  updater: PendingUpdater(),
                ),
              ),
      );
      addTearDown(controller.dispose);
      final first = controller.selectLanguage(ShipSubtitleLanguage.english);
      expect(controller.language, ShipSubtitleLanguage.english);
      expect(controller.dataLanguage, ShipSubtitleLanguage.simplifiedChinese);
      expect(controller.isLoadingLanguage, isTrue);
      await controller.selectLanguage(ShipSubtitleLanguage.japanese);
      pending.complete(
        ShipSubtitleCatalogSource(
          data: catalog('English'),
          updater: PendingUpdater(),
        ),
      );
      await first;
      expect(controller.language, ShipSubtitleLanguage.japanese);
      expect(controller.dataLanguage, ShipSubtitleLanguage.japanese);
      expect(controller.data.quotes['1']?['1'], '日本語');
      expect(controller.isLoadingLanguage, isFalse);
    },
  );

  test(
    'failed language loads expose failure and never claim old data is selected',
    () async {
      final controller = ShipSubtitleCatalogController(
        data: catalog('简中'),
        updater: PendingUpdater(),
        languageLoader: (_) async =>
            throw const FormatException('broken asset'),
      );
      addTearDown(controller.dispose);
      await controller.selectLanguage(ShipSubtitleLanguage.english);
      expect(controller.language, ShipSubtitleLanguage.english);
      expect(controller.dataLanguage, ShipSubtitleLanguage.simplifiedChinese);
      expect(controller.isLoadingLanguage, isFalse);
      expect(controller.lastError, isA<FormatException>());
      expect(controller.lastCheckedAt, isNull);
    },
  );
}

final class RecordingUpdater implements ShipSubtitleUpdateClient {
  RecordingUpdater(this.language, this.calls);
  final ShipSubtitleLanguage language;
  final List<ShipSubtitleLanguage> calls;
  @override
  Future<ShipSubtitleUpdateResult> checkAndUpdate({
    required ShipSubtitleCatalog current,
  }) async {
    calls.add(language);
    return ShipSubtitleUpdated(
      catalog('updated ${language.label}', '2026101905'),
      sourceHost: 'test',
    );
  }
}

final class PendingUpdater implements ShipSubtitleUpdateClient {
  final pending = Completer<ShipSubtitleUpdateResult>();
  int calls = 0;
  @override
  Future<ShipSubtitleUpdateResult> checkAndUpdate({
    required ShipSubtitleCatalog current,
  }) {
    calls++;
    return pending.future;
  }
}
