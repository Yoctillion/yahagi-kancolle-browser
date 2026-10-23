import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_serializer.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_catalog.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_catalog_controller.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_kc3_bundle.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_kc3_update_service.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_language.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_port.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_runtime_controller.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_settings.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_update_service.dart';

import '../fixtures/kcsapi_fixtures.dart' show kcsapiEvent;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GameStateController.disableTimerForTest = true;
  });
  tearDown(() => GameStateController.disableTimerForTest = false);

  test(
    'unsupported subtitles expose status and retry without losing opt-in',
    () async {
      final f = await _Fixture.create(supported: false);
      addTearDown(f.dispose);
      await f.settings.setEnabled(true);
      await f.runtime.idle;
      expect(f.runtime.status, ShipSubtitleRuntimeStatus.unsupported);
      expect(f.settings.enabled, isTrue);
      expect(f.port.configs, isEmpty);

      f.port.supported = true;
      await f.runtime.retry();
      expect(f.runtime.status, ShipSubtitleRuntimeStatus.ready);
      expect(f.port.ships.single.single['fileName'], 'voice-file');
      expect(f.port.catalogs, hasLength(1));
      expect(f.port.configs.last['enabled'], isTrue);
    },
  );

  test(
    'support channel errors stay distinguishable and recover on enable',
    () async {
      final port = _Port()
        ..supportError = PlatformException(code: 'temporarily_unavailable');
      final f = await _Fixture.create(port: port);
      addTearDown(f.dispose);
      expect(f.runtime.status, ShipSubtitleRuntimeStatus.failed);
      expect(f.runtime.lastError, isA<PlatformException>());
      port.supportError = null;
      await f.settings.setEnabled(true);
      await f.runtime.idle;
      expect(port.supportChecks, 2);
      expect(f.runtime.status, ShipSubtitleRuntimeStatus.ready);
      expect(port.configs.last['enabled'], isTrue);
      expect(f.runtime.lastError, isNull);
    },
  );

  test(
    'unsupported rendering rechecks on a later foreground session',
    () async {
      final f = await _Fixture.create(supported: false);
      addTearDown(f.dispose);
      await f.settings.setEnabled(true);
      await f.runtime.idle;
      f.runtime.didChangeAppLifecycleState(AppLifecycleState.paused);
      f.port.supported = true;
      f.runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await f.runtime.idle;
      expect(f.runtime.status, ShipSubtitleRuntimeStatus.ready);
      expect(f.port.configs.last['enabled'], isTrue);
    },
  );

  for (final recovery in ['retry', 'reenable']) {
    test(
      'failed language loads stay visible and recover on $recovery',
      () async {
        var loads = 0;
        var failLoad = true;
        final loadError = StateError('Temporary language read failure');
        final f = await _Fixture.create(
          languageLoader: (_) async {
            loads++;
            if (failLoad) throw loadError;
            return _languageSource('日本語の台詞', _Updater());
          },
        );
        addTearDown(f.dispose);
        await f.settings.setEnabled(true);
        await f.runtime.idle;
        await f.settings.setLanguage(ShipSubtitleLanguage.japanese);
        await Future<void>.delayed(Duration.zero);
        await f.runtime.idle;
        expect(loads, 1);
        expect(f.catalog.isLanguageReady, isFalse);
        expect(f.port.configs.last['enabled'], isFalse);
        expect(f.runtime.status, ShipSubtitleRuntimeStatus.failed);
        expect(f.runtime.lastError, same(loadError));

        failLoad = false;
        if (recovery == 'retry') {
          await f.runtime.retry();
        } else {
          await f.settings.setEnabled(false);
          await f.runtime.idle;
          await f.settings.setEnabled(true);
        }
        await f.runtime.idle;
        expect(loads, 2);
        expect(f.catalog.isLanguageReady, isTrue);
        expect(f.port.catalogs.last.quotes['1']?['1'], '日本語の台詞');
        expect(f.port.configs.last['enabled'], isTrue);
        expect(f.runtime.status, ShipSubtitleRuntimeStatus.ready);
        expect(f.runtime.lastError, isNull);
      },
    );
  }

  test(
    'failed support rechecks still allow an active renderer to stop',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.settings.setEnabled(true);
      await f.runtime.idle;
      expect(f.port.configs.last['enabled'], isTrue);
      final catalogsSent = f.port.catalogs.length;
      f.port.supportError = PlatformException(code: 'temporarily_unavailable');
      await f.runtime.retry();
      expect(f.runtime.status, ShipSubtitleRuntimeStatus.failed);

      await f.settings.setEnabled(false);
      await f.runtime.idle;
      expect(f.port.configs.last['enabled'], isFalse);
      expect(f.port.catalogs.length, catalogsSent);
      expect(f.runtime.status, ShipSubtitleRuntimeStatus.failed);
      expect(f.runtime.lastError, isA<PlatformException>());
    },
  );

  test('an active renderer stops while a support recheck is pending', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    await f.settings.setEnabled(true);
    await f.runtime.idle;
    final gate = Completer<bool>();
    f.port.supportGate = gate.future;
    final retry = f.runtime.retry();
    await Future<void>.delayed(Duration.zero);
    await f.settings.setEnabled(false);
    await Future<void>.delayed(Duration.zero);
    final stoppedBeforeReply = f.port.configs.last['enabled'] == false;
    gate.completeError(PlatformException(code: 'temporarily_unavailable'));
    await retry;
    expect(stoppedBeforeReply, isTrue);
    expect(f.port.configs.last['enabled'], isFalse);
    expect(f.runtime.status, ShipSubtitleRuntimeStatus.failed);
  });

  test('a failed support recheck cannot leave a late enable running', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    await f.settings.setEnabled(true);
    await f.runtime.idle;
    final gate = Completer<void>();
    f.port.configureGate = gate.future;
    await f.settings.setFontSize(ShipSubtitleFontSize.large);
    await Future<void>.delayed(Duration.zero);
    f.port.supportError = PlatformException(code: 'temporarily_unavailable');
    final retry = f.runtime.retry();
    await f.settings.setEnabled(false);
    gate.complete();
    await retry;
    await f.runtime.idle;
    expect(f.port.configs.last['enabled'], isFalse);
    expect(f.runtime.status, ShipSubtitleRuntimeStatus.failed);
  });

  test(
    'a renderer stops on background after a failed support recheck',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.settings.setEnabled(true);
      await f.runtime.idle;
      f.port.supportError = PlatformException(code: 'temporarily_unavailable');
      await f.runtime.retry();
      f.runtime.didChangeAppLifecycleState(AppLifecycleState.paused);
      await f.runtime.idle;
      expect(f.port.configs.last['enabled'], isFalse);
      expect(f.settings.enabled, isTrue);
      expect(f.runtime.status, ShipSubtitleRuntimeStatus.failed);
    },
  );

  test(
    'concurrent support retries share one check and disposal ignores its reply',
    () async {
      final f = await _Fixture.create();
      final gate = Completer<bool>();
      f.port.supportGate = gate.future;
      final checks = f.port.supportChecks;
      var notifications = 0;
      f.runtime.addListener(() => notifications++);
      final first = f.runtime.retry();
      final second = f.runtime.retry();
      await Future<void>.delayed(Duration.zero);
      expect(f.runtime.status, ShipSubtitleRuntimeStatus.checking);
      expect(f.port.supportChecks, checks + 1);
      f.dispose();
      final beforeReply = notifications;
      gate.complete(true);
      await Future.wait([first, second]);
      expect(notifications, beforeReply);
      expect(f.port.configs, hasLength(1));
    },
  );

  test(
    'retry waits for an old catalog send before resending the complete state',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final gate = Completer<void>();
      f.port.catalogGate = gate.future;
      await f.settings.setEnabled(true);
      await f.port.catalogStarted.future;
      final retry = f.runtime.retry();
      gate.complete();
      await retry;
      expect(f.port.ships, hasLength(2));
      expect(f.port.catalogs, hasLength(2));
      expect(f.port.configs.last['enabled'], isTrue);
      expect(f.runtime.status, ShipSubtitleRuntimeStatus.ready);
    },
  );

  testWidgets(
    'missing voice filenames are visible and arriving master data clears the wait',
    (tester) async {
      final f = await _Fixture.create(
        masterShips: const {1: MasterShip(id: 1, name: '睦月', shipTypeId: 2)},
      );
      addTearDown(f.dispose);
      await f.settings.setEnabled(true);
      await f.runtime.idle;
      expect(f.runtime.status, ShipSubtitleRuntimeStatus.waitingForGameData);
      expect(f.port.ships.single, isEmpty);

      f.game.accept(
        kcsapiEvent('/kcsapi/api_start2/getData', {
          'api_mst_ship': [
            {'api_id': 1, 'api_name': '睦月', 'api_stype': 2},
          ],
          'api_mst_shipgraph': [
            {
              'api_id': 1,
              'api_filename': 'arriving-voice',
              'api_version': ['1'],
            },
          ],
        }),
      );
      await f.game.idle;
      await tester.pump();
      await f.runtime.idle;
      expect(f.port.ships.last.single['fileName'], 'arriving-voice');
      expect(f.runtime.status, ShipSubtitleRuntimeStatus.ready);
      f.runtime.dispose();
    },
  );

  test(
    'cached voice mappings reach subtitles before any live startup response',
    () async {
      final cached = GameStateSerializer.deserialize(
        GameStateSerializer.serialize(
          const GameState(
            masterShips: {
              1: MasterShip(
                id: 1,
                name: '睦月',
                shipTypeId: 2,
                portraitFileName: 'cached-voice',
                portraitVersion: '1',
              ),
            },
          ),
        ),
      );
      final f = await _Fixture.create(masterShips: cached.masterShips);
      addTearDown(f.dispose);
      await f.settings.setEnabled(true);
      await f.runtime.idle;
      expect(f.port.ships.single.single['fileName'], 'cached-voice');
      expect(f.runtime.status, ShipSubtitleRuntimeStatus.ready);
    },
  );

  for (final stage in ['catalog', 'configure']) {
    test(
      '$stage delivery errors remain visible and retry resends current state',
      () async {
        final f = await _Fixture.create();
        addTearDown(f.dispose);
        if (stage == 'catalog') {
          f.port.catalogError = PlatformException(code: 'send_failed');
        } else {
          f.port.configureError = PlatformException(code: 'send_failed');
        }
        await f.settings.setEnabled(true);
        await f.runtime.idle;
        expect(f.runtime.status, ShipSubtitleRuntimeStatus.failed);
        expect(f.runtime.lastError, isA<PlatformException>());
        f.port.catalogError = null;
        f.port.configureError = null;
        await f.runtime.retry();
        expect(f.runtime.status, ShipSubtitleRuntimeStatus.ready);
        expect(f.port.configs.last['enabled'], isTrue);
        expect(f.port.ships.last.single['fileName'], 'voice-file');
        expect(f.port.catalogs.last.quotes['1']?['1'], '台词');
      },
    );
  }

  test(
    'disabling during a support retry never enables the old request',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.settings.setEnabled(true);
      await f.runtime.idle;
      final gate = Completer<bool>();
      f.port.supportGate = gate.future;
      final retry = f.runtime.retry();
      final previousCount = f.port.configs.length;
      await f.settings.setEnabled(false);
      gate.complete(true);
      await retry;
      expect(f.port.configs.skip(previousCount).map((c) => c['enabled']), [
        false,
      ]);
    },
  );

  test(
    'default off sends no full catalog and performs no update check',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      expect(f.port.configs.last['enabled'], isFalse);
      expect(f.port.catalogs, isEmpty);
      expect(f.updater.checks, 0);
    },
  );

  test(
    'background work waits for resume and unchanged resumes do not resend data',
    () async {
      final englishUpdater = _Updater();
      final f = await _Fixture.create(
        languageLoader: (_) async =>
            _languageSource('English line', englishUpdater),
      );
      addTearDown(f.dispose);
      f.runtime.didChangeAppLifecycleState(AppLifecycleState.paused);
      await f.settings.setEnabled(true);
      await f.runtime.idle;
      expect(f.updater.checks, 0);
      expect(f.port.catalogs, isEmpty);
      expect(f.port.ships, isEmpty);
      expect(f.port.configs.last['enabled'], isFalse);

      f.runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await f.runtime.idle;
      expect(f.updater.checks, 1);
      expect(f.port.catalogs.length, 1);
      expect(f.port.ships.length, 1);
      expect(f.port.configs.last['enabled'], isTrue);

      f.runtime.didChangeAppLifecycleState(AppLifecycleState.paused);
      await f.settings.setLanguage(ShipSubtitleLanguage.english);
      await f.catalog.selectLanguage(ShipSubtitleLanguage.english);
      await f.runtime.idle;
      expect(englishUpdater.checks, 0);
      expect(f.port.catalogs.length, 1);
      expect(f.port.ships.length, 1);

      f.runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await f.runtime.idle;
      expect(englishUpdater.checks, 1);
      expect(f.port.catalogs.last.quotes['1']?['1'], 'English line');
      final catalogsSent = f.port.catalogs.length;
      final shipsSent = f.port.ships.length;
      f.runtime.didChangeAppLifecycleState(AppLifecycleState.paused);
      await f.runtime.idle;
      f.runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await f.runtime.idle;
      expect(f.port.catalogs.length, catalogsSent);
      expect(f.port.ships.length, shipsSent);
    },
  );

  test('a background transition cannot apply an in-flight enable', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    final gate = Completer<void>();
    f.port.catalogGate = gate.future;
    await f.settings.setEnabled(true);
    await f.port.catalogStarted.future;
    f.runtime.didChangeAppLifecycleState(AppLifecycleState.paused);
    gate.complete();
    await f.runtime.idle;
    expect(
      f.port.configs.every((config) => config['enabled'] == false),
      isTrue,
    );
    f.runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await f.runtime.idle;
    expect(f.port.configs.last['enabled'], isTrue);
  });

  test(
    'enable sends mappings once; lock and size use only light config',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.settings.setEnabled(true);
      await f.runtime.idle;
      expect(f.port.catalogs.length, 1);
      expect(f.port.ships.single.single['fileName'], 'voice-file');
      expect(f.updater.checks, 1);
      await f.layout.setUiLocked(true);
      await f.settings.setFontSize(ShipSubtitleFontSize.large);
      await f.runtime.idle;
      expect(f.port.configs.last, containsPair('locked', true));
      expect(f.port.configs.last, containsPair('fontSize', 'large'));
      expect(f.port.catalogs.length, 1);
      expect(f.port.ships.length, 1);
      await f.settings.setEnabled(false);
      await f.runtime.idle;
      expect(f.port.configs.last['enabled'], isFalse);
    },
  );

  test(
    'drag callback persists position and cannot move while locked',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.settings.setEnabled(true);
      await f.runtime.idle;
      f.port.onPositionChanged!(.2, .3);
      await f.runtime.positionIdle;
      expect(f.settings.x, .2);
      expect(f.settings.y, .3);
      await f.layout.setUiLocked(true);
      await f.runtime.idle;
      f.port.onPositionChanged!(.7, .8);
      await f.runtime.positionIdle;
      expect(f.settings.x, .2);
    },
  );
  test(
    'disable during full data delivery cannot apply a stale enable',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final gate = Completer<void>();
      f.port.catalogGate = gate.future;
      await f.settings.setEnabled(true);
      await f.port.catalogStarted.future;
      await f.settings.setEnabled(false);
      gate.complete();
      await f.runtime.idle;
      expect(
        f.port.configs.every((config) => config['enabled'] == false),
        isTrue,
      );
    },
  );

  test('dispose during data delivery contains late configuration', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    final gate = Completer<void>();
    f.port.catalogGate = gate.future;
    await f.settings.setEnabled(true);
    await f.port.catalogStarted.future;
    f.runtime.dispose();
    gate.complete();
    await f.runtime.idle;
    expect(
      f.port.configs.every((config) => config['enabled'] == false),
      isTrue,
    );
    expect(f.port.onPositionChanged, isNull);
  });

  test(
    'language change clears the old renderer until new data is ready',
    () async {
      final gate = Completer<ShipSubtitleCatalogSource>();
      final started = Completer<void>();
      final englishUpdater = _Updater();
      final f = await _Fixture.create(
        languageLoader: (language) {
          expect(language, ShipSubtitleLanguage.english);
          if (!started.isCompleted) started.complete();
          return gate.future;
        },
      );
      addTearDown(f.dispose);
      await f.settings.setEnabled(true);
      await f.runtime.idle;
      await f.settings.setLanguage(ShipSubtitleLanguage.english);
      await Future<void>.delayed(Duration.zero);
      expect(f.catalog.language, ShipSubtitleLanguage.english);
      await started.future;
      await f.runtime.idle;
      expect(f.port.configs.last['enabled'], isFalse);
      expect(f.port.catalogs.length, 1);
      expect(englishUpdater.checks, 0);
      gate.complete(_languageSource('English line', englishUpdater));
      await f.catalog.selectLanguage(ShipSubtitleLanguage.english);
      await f.runtime.idle;
      expect(f.port.catalogs.last.quotes['1']?['1'], 'English line');
      expect(f.port.configs.last['enabled'], isTrue);
      expect(englishUpdater.checks, 1);
      expect(f.port.ships.length, 2);
    },
  );

  test(
    'language can prepare offline while disabled without checking updates',
    () async {
      final updater = _Updater();
      final f = await _Fixture.create(
        languageLoader: (_) async => _languageSource('English line', updater),
      );
      addTearDown(f.dispose);
      await f.settings.setLanguage(ShipSubtitleLanguage.english);
      await Future<void>.delayed(Duration.zero);
      expect(f.catalog.language, ShipSubtitleLanguage.english);
      await f.catalog.selectLanguage(ShipSubtitleLanguage.english);
      await f.runtime.idle;
      expect(f.catalog.dataLanguage, ShipSubtitleLanguage.english);
      expect(updater.checks, 0);
      expect(f.port.catalogs, isEmpty);
      expect(f.port.configs.last['enabled'], isFalse);
    },
  );

  test(
    'speaker names follow subtitle language including remodel suffixes',
    () async {
      final bundle = _nameBundle();
      final f = await _Fixture.create(
        kc3Source: ShipSubtitleKc3Source(
          bundle: bundle,
          updater: _Kc3Updater(),
        ),
        languageLoader: (_) async => _languageSource('台词', _Updater()),
        masterShips: const {
          1: MasterShip(
            id: 1,
            name: '霧島改二',
            shipTypeId: 2,
            portraitFileName: 'voice-file',
          ),
        },
      );
      addTearDown(f.dispose);
      await f.settings.setEnabled(true);
      await f.catalog.checkForUpdates();
      await f.runtime.idle;
      expect(f.port.ships.last.single['name'], '雾岛改二');
      for (final entry in {
        ShipSubtitleLanguage.traditionalChinese: '霧島改二',
        ShipSubtitleLanguage.japanese: '霧島改二',
        ShipSubtitleLanguage.english: 'Kirishima Kai Ni',
        ShipSubtitleLanguage.korean: '키리시마 개2',
      }.entries) {
        await f.settings.setLanguage(entry.key);
        await f.catalog.selectLanguage(entry.key);
        await f.runtime.idle;
        expect(f.port.ships.last.single['name'], entry.value);
      }
    },
  );

  test(
    'speaker names include KC3 master-ID variants for identically named ships',
    () async {
      final f = await _Fixture.create(
        kc3Source: ShipSubtitleKc3Source(
          bundle: _nameBundle(),
          updater: _Kc3Updater(),
        ),
        languageLoader: (_) async => _languageSource('台词', _Updater()),
        masterShips: const {
          650: MasterShip(
            id: 650,
            name: '宗谷',
            shipTypeId: 2,
            portraitFileName: 'voice-file',
          ),
        },
      );
      addTearDown(f.dispose);
      await f.settings.setLanguage(ShipSubtitleLanguage.english);
      await f.catalog.selectLanguage(ShipSubtitleLanguage.english);
      await f.settings.setEnabled(true);
      await f.catalog.checkForUpdates();
      await f.runtime.idle;
      expect(f.port.ships.last.single['name'], 'Souya (AGB)');
    },
  );

  test(
    'name-only bundle updates resend names without resending Chinese quotes',
    () async {
      final updater = _Kc3Updater();
      final f = await _Fixture.create(
        kc3Source: ShipSubtitleKc3Source(
          bundle: _nameBundle(),
          updater: updater,
        ),
        languageLoader: (_) async => _languageSource('台词', _Updater()),
        masterShips: const {
          1: MasterShip(
            id: 1,
            name: '霧島改二',
            shipTypeId: 2,
            portraitFileName: 'voice-file',
          ),
        },
      );
      addTearDown(f.dispose);
      await f.settings.setEnabled(true);
      await f.catalog.checkForUpdates();
      await f.runtime.idle;
      final catalogsSent = f.port.catalogs.length;
      final shipsSent = f.port.ships.length;
      updater.next = _nameBundle(simplifiedName: '雾岛新译名');
      await f.catalog.checkForUpdates();
      await f.runtime.idle;
      expect(f.port.ships.length, shipsSent + 1);
      expect(f.port.ships.last.single['name'], '雾岛新译名改二');
      expect(f.port.catalogs.length, catalogsSent);
    },
  );

  test(
    'language changes resend speaker mappings without a master reload',
    () async {
      final f = await _Fixture.create(
        languageLoader: (_) async =>
            _languageSource('English line', _Updater()),
      );
      addTearDown(f.dispose);
      await f.settings.setEnabled(true);
      await f.runtime.idle;
      final originalMaster = f.game.state.masterShips;
      expect(f.port.ships.length, 1);
      await f.settings.setLanguage(ShipSubtitleLanguage.english);
      await f.catalog.selectLanguage(ShipSubtitleLanguage.english);
      await f.runtime.idle;
      expect(identical(originalMaster, f.game.state.masterShips), isTrue);
      expect(f.port.ships.length, 2);
      await f.settings.setFontSize(ShipSubtitleFontSize.large);
      await f.layout.setUiLocked(true);
      await f.runtime.idle;
      expect(f.port.ships.length, 2);
    },
  );

  test(
    'a late language load never replaces newer selected subtitles',
    () async {
      final english = Completer<ShipSubtitleCatalogSource>();
      final japanese = Completer<ShipSubtitleCatalogSource>();
      final englishStarted = Completer<void>();
      final f = await _Fixture.create(
        languageLoader: (language) {
          if (language == ShipSubtitleLanguage.english) {
            if (!englishStarted.isCompleted) englishStarted.complete();
            return english.future;
          }
          return japanese.future;
        },
      );
      addTearDown(f.dispose);
      await f.settings.setEnabled(true);
      await f.runtime.idle;
      await f.settings.setLanguage(ShipSubtitleLanguage.english);
      await Future<void>.delayed(Duration.zero);
      expect(f.catalog.language, ShipSubtitleLanguage.english);
      await englishStarted.future;
      await f.settings.setLanguage(ShipSubtitleLanguage.japanese);
      japanese.complete(_languageSource('日本語の台詞', _Updater()));
      await f.catalog.selectLanguage(ShipSubtitleLanguage.japanese);
      await f.runtime.idle;
      expect(f.port.catalogs.last.quotes['1']?['1'], '日本語の台詞');
      english.complete(_languageSource('English line', _Updater()));
      await Future<void>.delayed(Duration.zero);
      await f.runtime.idle;
      expect(f.catalog.dataLanguage, ShipSubtitleLanguage.japanese);
      expect(f.port.catalogs.last.quotes['1']?['1'], '日本語の台詞');
      expect(
        f.port.catalogs.any((data) => data.quotes['1']?['1'] == 'English line'),
        isFalse,
      );
    },
  );

  test(
    'language selection still works when native rendering is unsupported',
    () async {
      final f = await _Fixture.create(
        supported: false,
        languageLoader: (_) async => _languageSource('日本語の台詞', _Updater()),
      );
      addTearDown(f.dispose);
      await f.settings.setLanguage(ShipSubtitleLanguage.japanese);
      await Future<void>.delayed(Duration.zero);
      expect(f.catalog.language, ShipSubtitleLanguage.japanese);
      await f.catalog.selectLanguage(ShipSubtitleLanguage.japanese);
      expect(f.catalog.dataLanguage, ShipSubtitleLanguage.japanese);
      expect(f.port.catalogs, isEmpty);
      expect(f.port.configs, isEmpty);
    },
  );

  for (final language in [
    ShipSubtitleLanguage.english,
    ShipSubtitleLanguage.korean,
  ]) {
    test(
      '${language.label} remodels inherit missing lines and retain their own lines',
      () async {
        final f = await _Fixture.create(
          masterShips: const {
            1: MasterShip(
              id: 1,
              name: '睦月',
              shipTypeId: 2,
              afterShipId: 2001,
              portraitFileName: 'base-voice',
            ),
            2001: MasterShip(
              id: 2001,
              name: '睦月改',
              shipTypeId: 2,
              afterShipId: 1,
              portraitFileName: 'remodel-voice',
            ),
          },
          languageLoader: (_) async => ShipSubtitleCatalogSource(
            data: ShipSubtitleCatalog(
              version: '20260804124356',
              quotes: {
                '1': {'1': 'Introduction', '2': 'Base line'},
                '2001': {'2': 'Remodel line'},
              },
            ),
            updater: _Updater(),
          ),
        );
        addTearDown(f.dispose);
        await f.settings.setEnabled(true);
        await f.runtime.idle;
        await f.settings.setLanguage(language);
        await f.catalog.selectLanguage(language);
        await f.runtime.idle;
        expect(f.port.catalogs.last.quotes['2001'], {
          '1': 'Introduction',
          '2': 'Remodel line',
        });
        expect(f.port.catalogs.last.quotes['1']?['2'], 'Base line');
      },
    );
  }
}

ShipSubtitleCatalogSource _languageSource(String line, _Updater updater) =>
    ShipSubtitleCatalogSource(
      data: ShipSubtitleCatalog(
        version: '2026101805',
        quotes: {
          '1': {'1': line},
        },
      ),
      updater: updater,
    );

final class _Fixture {
  _Fixture(
    this.settings,
    this.catalog,
    this.layout,
    this.game,
    this.port,
    this.updater,
    this.runtime,
  );
  final ShipSubtitleSettingsController settings;
  final ShipSubtitleCatalogController catalog;
  final LayoutSettingsController layout;
  final GameStateController game;
  final _Port port;
  final _Updater updater;
  final ShipSubtitleRuntimeController runtime;
  static Future<_Fixture> create({
    ShipSubtitleCatalogSourceLoader? languageLoader,
    ShipSubtitleKc3Source? kc3Source,
    bool supported = true,
    _Port? port,
    Map<int, MasterShip>? masterShips,
  }) async {
    final settings = await ShipSubtitleSettingsController.load();
    final updater = _Updater();
    final catalog = ShipSubtitleCatalogController(
      data: ShipSubtitleCatalog(
        version: '2026101805',
        quotes: {
          '1': {'1': '台词'},
        },
      ),
      updater: updater,
      languageLoader: languageLoader,
      kc3Source: kc3Source,
    );
    final layout = await LayoutSettingsController.load(
      SharedPreferencesLayoutSettingsStore(),
    );
    final game = GameStateController(
      initialState: GameState(
        masterShips:
            masterShips ??
            const {
              1: MasterShip(
                id: 1,
                name: '睦月',
                shipTypeId: 2,
                portraitFileName: 'voice-file',
              ),
            },
      ),
    );
    port ??= _Port()..supported = supported;
    final runtime = ShipSubtitleRuntimeController(
      settings: settings,
      catalog: catalog,
      layout: layout,
      gameState: game,
      port: port,
    );
    await runtime.initialize();
    return _Fixture(settings, catalog, layout, game, port, updater, runtime);
  }

  void dispose() {
    runtime.dispose();
    settings.dispose();
    catalog.dispose();
    layout.dispose();
    game.dispose();
  }
}

ShipSubtitleKc3Bundle _nameBundle({String simplifiedName = '雾岛'}) =>
    ShipSubtitleKc3Bundle(
      version: '20261017023118',
      commit: '6fed2aac44a1ca95f2892bb1af93a6bc0e60b667',
      entityNames: {
        for (final language in ShipSubtitleLanguage.values.where(
          (language) => language != ShipSubtitleLanguage.japanese,
        ))
          language: GameNameDictionary.fromJson({
            'items': {'12cm単装砲': '12cm Single Gun Mount'},
            'stype': List.filled(23, 'Ship type'),
            'equiptype': List.generate(5, (_) => ['', 'Type']),
          }),
      },
      english: ShipSubtitleCatalog(
        version: '20261017023118',
        quotes: {
          '1': {'1': 'English line'},
        },
      ),
      korean: ShipSubtitleCatalog(
        version: '20261017023118',
        quotes: {
          '1': {'1': '한국어 대사'},
        },
      ),
      names: {
        for (final entry in {
          ShipSubtitleLanguage.simplifiedChinese: simplifiedName,
          ShipSubtitleLanguage.traditionalChinese: '霧島',
          ShipSubtitleLanguage.english: 'Kirishima',
          ShipSubtitleLanguage.korean: '키리시마',
        }.entries)
          entry.key: ShipSubtitleNameCatalog.fromJson({
            'ships': {'霧島': entry.value},
            'affix': {
              'prefixes': <String, String>{},
              'byId': {'650': 'Souya (AGB)'},
              'suffixes': {
                '改二': switch (entry.key) {
                  ShipSubtitleLanguage.english => ' Kai Ni',
                  ShipSubtitleLanguage.korean => ' 개2',
                  _ => '改二',
                },
              },
            },
          }),
      },
    );

final class _Kc3Updater implements ShipSubtitleKc3UpdateClient {
  ShipSubtitleKc3Bundle? next;
  @override
  Future<ShipSubtitleKc3UpdateResult> checkAndUpdate({
    required ShipSubtitleKc3Bundle current,
  }) async {
    final updated = next;
    next = null;
    return updated == null
        ? ShipSubtitleKc3UpToDate(current, sourceHost: 'test')
        : ShipSubtitleKc3Updated(updated, sourceHost: 'test');
  }
}

final class _Updater implements ShipSubtitleUpdateClient {
  int checks = 0;
  @override
  Future<ShipSubtitleUpdateResult> checkAndUpdate({
    required ShipSubtitleCatalog current,
  }) async {
    checks++;
    return ShipSubtitleUpToDate(current, sourceHost: 'test');
  }
}

final class _Port implements ShipSubtitlePort {
  bool supported = true;
  int supportChecks = 0;
  Object? supportError;
  Object? catalogError;
  Object? configureError;
  Future<bool>? supportGate;
  Future<void>? configureGate;
  Future<void>? catalogGate;
  final catalogStarted = Completer<void>();
  @override
  void Function(double, double)? onPositionChanged;
  final configs = <Map<String, Object?>>[];
  final catalogs = <ShipSubtitleCatalog>[];
  final ships = <List<Map<String, Object?>>>[];
  @override
  Future<bool> isSupported() async {
    supportChecks++;
    if (supportError != null) throw supportError!;
    return supportGate == null ? supported : await supportGate!;
  }

  @override
  Future<void> configure({
    required bool enabled,
    required ShipSubtitleFontSize fontSize,
    required bool locked,
    required double x,
    required double y,
  }) async {
    await configureGate;
    if (configureError != null) throw configureError!;
    configs.add({
      'enabled': enabled,
      'fontSize': fontSize.wireName,
      'locked': locked,
      'x': x,
      'y': y,
    });
  }

  @override
  Future<void> setCatalog(ShipSubtitleCatalog data) async {
    if (catalogError != null) throw catalogError!;
    if (!catalogStarted.isCompleted) catalogStarted.complete();
    await catalogGate;
    catalogs.add(data);
  }

  @override
  Future<void> setShips(List<Map<String, Object?>> values) async {
    ships.add(values);
  }

  @override
  void dispose() {
    onPositionChanged = null;
  }
}
