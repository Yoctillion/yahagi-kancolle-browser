import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_catalog.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_catalog_controller.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_kc3_bundle.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_kc3_store.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_kc3_update_service.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_language.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_resource_state.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_update_service.dart';

const oldVersion = '2026101705';
const newVersion = '2026101805';
final checkedAt = DateTime.utc(2026, 10, 18, 9);
ShipSubtitleCatalog data(String text, [String version = oldVersion]) =>
    ShipSubtitleCatalog(
      version: version,
      quotes: {
        '1': {'1': text},
      },
    );
ShipSubtitleKc3Bundle bundle([
  String version = '20261017000000',
  String text = 'Mutsuki',
]) => ShipSubtitleKc3Bundle.fromJson({
  'schema': 3,
  'version': version,
  'commit': (version == '20261017000000' ? 'a' : 'b') * 40,
  'english': data(text, version).toJson(),
  'entityNames': {
    for (final language in ['zh-cn', 'zh-tw', 'en-us', 'ko-kr'])
      language: {
        'items': {'12cm単装砲': '12cm Single Gun Mount'},
        'stype': List.filled(23, 'Ship type'),
        'equiptype': List.generate(5, (_) => ['', 'Type']),
      },
  },
  'korean': data(
    version == '20261017000000' ? '무츠키' : '새 무츠키',
    version,
  ).toJson(),
  'names': {
    for (final language in [
      ShipSubtitleLanguage.simplifiedChinese,
      ShipSubtitleLanguage.traditionalChinese,
      ShipSubtitleLanguage.english,
      ShipSubtitleLanguage.korean,
    ])
      language.code: {
        'ships': {
          '睦月': language == ShipSubtitleLanguage.korean
              ? (version == '20261017000000' ? '무츠키' : '새 무츠키')
              : text,
        },
        'affix': {
          'byId': {'699': '$text by ID'},
          'prefixes': <String, String>{},
          'suffixes': {'改': ' Kai'},
        },
      },
  },
});

void main() {
  test(
    'selecting Korean reads the loaded bundle without a language loader and keeps English separate',
    () async {
      final controller = ShipSubtitleCatalogController(
        data: data('简中'),
        updater: KcwikiUpdater(
          () async => ShipSubtitleUpToDate(data('简中'), sourceHost: 'test'),
        ),
        kc3Source: ShipSubtitleKc3Source(
          bundle: bundle(),
          updater: Kc3Updater(fail: false),
        ),
        languageLoader: (_) async =>
            throw StateError('Both KC3 quote catalogs are already loaded.'),
      );
      addTearDown(controller.dispose);
      await controller.selectLanguage(ShipSubtitleLanguage.korean);
      expect(controller.isLanguageReady, isTrue);
      expect(controller.data.quotes['1']?['1'], '무츠키');
      expect(controller.shipName(ShipSubtitleLanguage.korean, '睦月'), '무츠키');
      await controller.selectLanguage(ShipSubtitleLanguage.english);
      expect(controller.data.quotes['1']?['1'], 'Mutsuki');
      await controller.selectLanguage(ShipSubtitleLanguage.korean);
      expect(controller.data.quotes['1']?['1'], '무츠키');
    },
  );
  test(
    'one check while Korean is selected refreshes both KC3 catalogs and names plus all kcwiki languages',
    () async {
      final fixture = Fixture();
      final controller = await fixture.load(
        language: ShipSubtitleLanguage.korean,
      );
      addTearDown(controller.dispose);
      expect(controller.data.quotes['1']?['1'], '무츠키');
      expect(controller.kcwikiVersion, oldVersion);
      expect(await controller.checkForUpdates(), isA<ShipSubtitleUpdated>());
      expect(fixture.kcwikiCalls.toSet(), kcwikiSubtitleLanguages.toSet());
      expect(fixture.kc3.calls, 1);
      expect(controller.data.quotes['1']?['1'], '새 무츠키');
      expect(controller.shipName(ShipSubtitleLanguage.korean, '睦月'), '새 무츠키');
      expect(controller.lastCheckedAt, checkedAt);
      expect(controller.kcwikiVersion, newVersion);
      expect(controller.kc3Version, '20261018000000');
      await controller.selectLanguage(ShipSubtitleLanguage.english);
      expect(controller.data.quotes['1']?['1'], 'New Mutsuki');
      await controller.selectLanguage(ShipSubtitleLanguage.korean);
      expect(controller.data.quotes['1']?['1'], '새 무츠키');
    },
  );
  test(
    'failed KC3 update preserves Korean quotes and names independently of successful kcwiki data',
    () async {
      final fixture = Fixture(kc3Failure: true);
      final controller = await fixture.load(
        language: ShipSubtitleLanguage.korean,
      );
      addTearDown(controller.dispose);
      expect(
        await controller.checkForUpdates(),
        isA<ShipSubtitleUpdateFailed>(),
      );
      expect(controller.kcwikiVersion, newVersion);
      expect(controller.data.quotes['1']?['1'], '무츠키');
      expect(controller.shipName(ShipSubtitleLanguage.korean, '睦月'), '무츠키');
      expect(controller.kc3LastCheckedAt, isNull);
      expect(controller.lastCheckedAt, isNull);
    },
  );
  test(
    'pending batch can switch from English to Korean and publishes Korean without duplicate requests',
    () async {
      final gate = Completer<void>();
      final fixture = Fixture(gate: gate.future);
      final controller = await fixture.load(
        language: ShipSubtitleLanguage.english,
      );
      addTearDown(controller.dispose);
      final operation = controller.checkForUpdates();
      await Future<void>.delayed(Duration.zero);
      await controller.selectLanguage(ShipSubtitleLanguage.korean);
      expect(controller.checkForUpdates(), same(operation));
      gate.complete();
      await operation;
      expect(controller.language, ShipSubtitleLanguage.korean);
      expect(controller.data.quotes['1']?['1'], '새 무츠키');
      expect(fixture.kc3.calls, 1);
      expect(fixture.kcwikiCalls, hasLength(3));
    },
  );
  test(
    'newer bundled language group replaces old downloaded group and its stale metadata',
    () async {
      final oldChecked = checkedAt.subtract(const Duration(hours: 1));
      final store = MemoryResourceStore()
        ..state = ShipSubtitleResourceState(
          catalogs: {
            for (final language in kcwikiSubtitleLanguages)
              language: data('old ${language.label}'),
          },
          kcwikiLastCheckedAt: oldChecked,
          kcwikiLastAttemptAt: oldChecked,
          kc3LastAttemptAt: oldChecked,
        );
      final fixture = Fixture(resourceStore: store, initialVersion: newVersion);
      final controller = await fixture.load(
        language: ShipSubtitleLanguage.japanese,
      );
      addTearDown(controller.dispose);
      expect(controller.data.version, newVersion);
      expect(controller.kcwikiVersion, newVersion);
      expect(controller.kcwikiLastCheckedAt, isNull);
      for (final language in kcwikiSubtitleLanguages) {
        await controller.selectLanguage(language);
        expect(controller.data.version, newVersion);
      }
      await controller.checkIfDue();
      expect(fixture.kcwikiCalls, hasLength(3));
      expect(fixture.kc3.calls, 0);
    },
  );
  test(
    'a saved KC3 bundle stays active when only its check timestamp cannot be saved',
    () async {
      final fixture = Fixture(kc3Store: ThrowingTimestampStore());
      final controller = await fixture.load(
        language: ShipSubtitleLanguage.english,
      );
      addTearDown(controller.dispose);
      expect(
        await controller.checkForUpdates(),
        isA<ShipSubtitleUpdateFailed>(),
      );
      expect(controller.kc3Version, '20261018000000');
      expect(controller.kc3LastCheckedAt, isNull);
      expect(controller.data.quotes['1']?['1'], 'New Mutsuki');
      expect(
        controller.shipName(ShipSubtitleLanguage.english, '睦月', shipId: 699),
        'New Mutsuki by ID',
      );
      expect(
        controller.shipName(ShipSubtitleLanguage.english, '睦月'),
        'New Mutsuki',
      );
    },
  );
  test(
    'selecting English reads the in-memory KC3 bundle without a separate language loader',
    () async {
      final controller = ShipSubtitleCatalogController(
        data: data('简中'),
        updater: KcwikiUpdater(
          () async => ShipSubtitleUpToDate(data('简中'), sourceHost: 'test'),
        ),
        kc3Source: ShipSubtitleKc3Source(
          bundle: bundle(),
          updater: Kc3Updater(fail: false),
        ),
        languageLoader: (_) async =>
            throw StateError('The KC3 English catalog is already loaded.'),
      );
      addTearDown(controller.dispose);
      await controller.selectLanguage(ShipSubtitleLanguage.english);
      expect(controller.isLanguageReady, isTrue);
      expect(controller.data.quotes['1']?['1'], 'Mutsuki');
    },
  );
  test(
    'one check includes every kcwiki language and the KC3 bundle in English',
    () async {
      final fixture = Fixture();
      final controller = await fixture.load(
        language: ShipSubtitleLanguage.english,
      );
      addTearDown(controller.dispose);
      final result = await controller.checkForUpdates();
      expect(result, isA<ShipSubtitleUpdated>());
      expect(fixture.kcwikiCalls.toSet(), kcwikiSubtitleLanguages.toSet());
      expect(fixture.kc3.calls, 1);
      expect(controller.kcwikiVersion, newVersion);
      expect(controller.kc3Version, '20261018000000');
      expect(controller.data.quotes['1']?['1'], 'New Mutsuki');
      expect(
        controller.shipName(ShipSubtitleLanguage.english, '睦月'),
        'New Mutsuki',
      );
      expect(controller.kcwikiLastCheckedAt, checkedAt);
      expect(controller.kc3LastCheckedAt, checkedAt);
    },
  );

  test(
    'failed kcwiki member preserves the group while KC3 becomes available immediately',
    () async {
      final fixture = Fixture(
        failLanguage: ShipSubtitleLanguage.traditionalChinese,
      );
      final controller = await fixture.load(
        language: ShipSubtitleLanguage.english,
      );
      addTearDown(controller.dispose);
      final result = await controller.checkForUpdates();
      expect(result, isA<ShipSubtitleUpdateFailed>());
      expect(controller.lastError, isA<ShipSubtitleResourceUpdateError>());
      expect(controller.kcwikiVersion, oldVersion);
      expect(controller.kcwikiLastCheckedAt, isNull);
      expect(controller.kc3Version, '20261018000000');
      expect(controller.kc3LastCheckedAt, checkedAt);
      for (final language in kcwikiSubtitleLanguages) {
        await controller.selectLanguage(language);
        expect(controller.data.version, oldVersion);
      }
    },
  );

  test(
    'failed KC3 keeps the old English and names while kcwiki publishes',
    () async {
      final fixture = Fixture(kc3Failure: true);
      final controller = await fixture.load();
      addTearDown(controller.dispose);
      final oldBundle = controller.kc3Bundle;
      expect(
        await controller.checkForUpdates(),
        isA<ShipSubtitleUpdateFailed>(),
      );
      expect(controller.kcwikiVersion, newVersion);
      expect(controller.kcwikiLastCheckedAt, checkedAt);
      expect(controller.kc3Bundle, same(oldBundle));
      expect(controller.kc3LastCheckedAt, isNull);
      await controller.selectLanguage(ShipSubtitleLanguage.english);
      expect(controller.data.quotes['1']?['1'], 'Mutsuki');
      expect(
        controller.shipName(ShipSubtitleLanguage.english, '睦月'),
        'Mutsuki',
      );
    },
  );

  test(
    'a shared pending check survives switching and cannot start duplicate requests',
    () async {
      final gate = Completer<void>();
      final fixture = Fixture(gate: gate.future);
      final controller = await fixture.load();
      addTearDown(controller.dispose);
      final first = controller.checkForUpdates();
      await Future<void>.delayed(Duration.zero);
      await controller.selectLanguage(ShipSubtitleLanguage.english);
      expect(controller.isChecking, isTrue);
      final second = controller.checkForUpdates();
      expect(second, same(first));
      gate.complete();
      await first;
      expect(controller.language, ShipSubtitleLanguage.english);
      expect(controller.data.quotes['1']?['1'], 'New Mutsuki');
      expect(fixture.kcwikiCalls, hasLength(3));
      expect(fixture.kc3.calls, 1);
      expect(controller.isChecking, isFalse);
    },
  );

  test(
    'a failing group commit cannot advance metadata or its in-memory catalogs',
    () async {
      final store = MemoryResourceStore()..failCatalogSave = true;
      final fixture = Fixture(resourceStore: store);
      final controller = await fixture.load();
      addTearDown(controller.dispose);
      expect(
        await controller.checkForUpdates(),
        isA<ShipSubtitleUpdateFailed>(),
      );
      expect(controller.kcwikiVersion, oldVersion);
      expect(controller.kcwikiLastCheckedAt, isNull);
      expect(controller.data.version, oldVersion);
      expect(controller.kc3Version, '20261018000000');
      expect(controller.kc3LastCheckedAt, checkedAt);
    },
  );

  test(
    'different kcwiki versions do not publish a mixed-language group',
    () async {
      final fixture = Fixture(mismatchedVersion: true);
      final controller = await fixture.load();
      addTearDown(controller.dispose);
      expect(
        await controller.checkForUpdates(),
        isA<ShipSubtitleUpdateFailed>(),
      );
      expect(controller.kcwikiVersion, oldVersion);
      expect(controller.kcwikiLastCheckedAt, isNull);
      expect(controller.data.version, oldVersion);
    },
  );

  test(
    'attempt limits survive restart and manual checks bypass both group limits',
    () async {
      final directory = await Directory.systemTemp.createTemp('subtitle-all-');
      addTearDown(() => directory.delete(recursive: true));
      final store = FileShipSubtitleResourceStateStore.inDirectory(directory);
      final fixture = Fixture(
        resourceStore: store,
        failLanguage: ShipSubtitleLanguage.japanese,
        kc3Failure: true,
      );
      var controller = await fixture.load();
      await controller.checkIfDue();
      expect(fixture.kcwikiCalls, hasLength(3));
      expect(fixture.kc3.calls, 1);
      controller.dispose();
      controller = await fixture.load();
      addTearDown(controller.dispose);
      await controller.checkIfDue();
      expect(fixture.kcwikiCalls, hasLength(3));
      expect(fixture.kc3.calls, 1);
      expect(controller.kcwikiLastCheckedAt, isNull);
      expect(controller.kc3LastCheckedAt, isNull);
      await controller.checkForUpdates();
      expect(fixture.kcwikiCalls, hasLength(6));
      expect(fixture.kc3.calls, 2);
      fixture.time = checkedAt.add(const Duration(hours: 24));
      await controller.checkIfDue();
      expect(fixture.kcwikiCalls, hasLength(9));
      expect(fixture.kc3.calls, 3);
    },
  );

  test(
    'automatic checks use each source group timestamp independently',
    () async {
      final store = MemoryResourceStore()
        ..state = ShipSubtitleResourceState(kcwikiLastAttemptAt: checkedAt);
      final fixture = Fixture(resourceStore: store);
      final controller = await fixture.load();
      addTearDown(controller.dispose);
      await controller.checkIfDue();
      expect(fixture.kcwikiCalls, isEmpty);
      expect(fixture.kc3.calls, 1);
    },
  );

  test(
    'successful kcwiki group is restored offline without a network check',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'subtitle-group-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final fixture = Fixture(
        resourceStore: FileShipSubtitleResourceStateStore.inDirectory(
          directory,
        ),
      );
      final controller = await fixture.load();
      await controller.checkIfDue();
      controller.dispose();
      final restored = await fixture.load(
        language: ShipSubtitleLanguage.japanese,
      );
      addTearDown(restored.dispose);
      expect(restored.data.version, newVersion);
      expect(restored.kcwikiLastCheckedAt, checkedAt);
      await restored.checkIfDue();
      expect(fixture.kcwikiCalls, hasLength(3));
      expect(fixture.kc3.calls, 1);
    },
  );
}

final class Fixture {
  Fixture({
    this.failLanguage,
    bool kc3Failure = false,
    this.resourceStore,
    this.gate,
    this.mismatchedVersion = false,
    this.kc3Store,
    this.initialVersion = oldVersion,
  }) : kc3 = Kc3Updater(fail: kc3Failure);
  final ShipSubtitleLanguage? failLanguage;
  final bool mismatchedVersion;
  final Future<void>? gate;
  final ShipSubtitleResourceStateStore? resourceStore;
  final ShipSubtitleKc3Store? kc3Store;
  final String initialVersion;
  final Kc3Updater kc3;
  final kcwikiCalls = <ShipSubtitleLanguage>[];
  DateTime time = checkedAt;
  Future<ShipSubtitleCatalogController> load({
    ShipSubtitleLanguage language = ShipSubtitleLanguage.simplifiedChinese,
  }) => ShipSubtitleCatalogController.load(
    language: language,
    now: () => time,
    resourceStore: resourceStore,
    kc3Source: ShipSubtitleKc3Source(
      bundle: bundle(),
      updater: kc3,
      store: kc3Store,
    ),
    languageLoader: (target) async => ShipSubtitleCatalogSource(
      data: data(target.label, initialVersion),
      updater: KcwikiUpdater(() async {
        kcwikiCalls.add(target);
        await gate;
        if (target == failLanguage) {
          return ShipSubtitleUpdateFailed(
            ShipSubtitleUpdateFailure.network,
            StateError('offline'),
            sourceHost: 'test',
          );
        }
        return ShipSubtitleUpdated(
          data(
            'new ${target.label}',
            mismatchedVersion && target == ShipSubtitleLanguage.japanese
                ? '2026101905'
                : newVersion,
          ),
          sourceHost: 'test',
        );
      }),
    ),
  );
}

final class KcwikiUpdater implements ShipSubtitleUpdateClient {
  KcwikiUpdater(this.run);
  final Future<ShipSubtitleUpdateResult> Function() run;
  @override
  Future<ShipSubtitleUpdateResult> checkAndUpdate({
    required ShipSubtitleCatalog current,
  }) => run();
}

final class Kc3Updater implements ShipSubtitleKc3UpdateClient {
  Kc3Updater({required this.fail});
  final bool fail;
  int calls = 0;
  @override
  Future<ShipSubtitleKc3UpdateResult> checkAndUpdate({
    required ShipSubtitleKc3Bundle current,
  }) async {
    calls++;
    return fail
        ? ShipSubtitleKc3UpdateFailed(
            ShipSubtitleUpdateFailure.network,
            StateError('offline'),
            sourceHost: 'test',
          )
        : ShipSubtitleKc3Updated(
            bundle('20261018000000', 'New Mutsuki'),
            sourceHost: 'test',
          );
  }
}

final class MemoryResourceStore implements ShipSubtitleResourceStateStore {
  ShipSubtitleResourceState state = const ShipSubtitleResourceState();
  bool failCatalogSave = false;
  @override
  Future<ShipSubtitleResourceState> load() async => state;
  @override
  Future<void> save(ShipSubtitleResourceState value) async {
    if (failCatalogSave && value.catalogs.isNotEmpty) {
      throw const FileSystemException('disk full');
    }
    state = value;
  }
}

final class ThrowingTimestampStore implements ShipSubtitleKc3Store {
  @override
  Future<ShipSubtitleKc3Bundle> loadBestAvailable() async => bundle();
  @override
  Future<void> save(ShipSubtitleKc3Bundle value) async {}
  @override
  Future<DateTime?> loadLastCheckedAt() async => null;
  @override
  Future<void> saveLastCheckedAt(DateTime value) async =>
      throw const FileSystemException('timestamp disk full');
}
