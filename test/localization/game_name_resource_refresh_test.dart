import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/localization/game_name_catalog.dart';
import 'package:yahagi_kancolle_browser/src/localization/game_name_localizations.dart';
import 'package:yahagi_kancolle_browser/src/notification/game_notification_coordinator.dart';
import 'package:yahagi_kancolle_browser/src/notification/notification_models.dart';
import 'package:yahagi_kancolle_browser/src/settings/notification_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/notification_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_catalog.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_catalog_controller.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_kc3_bundle.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_kc3_update_service.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_update_service.dart';

import '../notification/game_notification_coordinator_test.dart'
    show FakeNotificationPort;

const _rawShip = MasterShip(id: 1, name: '睦月', shipTypeId: 2);
const _pageNamesKey = Key('page-entity-names');
const _dialogNamesKey = Key('dialog-entity-names');
const _updatedNames = {'en': 'Updated English Ship', 'ko': '갱신 함선'};
const _updatedAkashiNames = {'en': 'Updated Repair Ship', 'ko': '갱신 공작함'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ShipSubtitleKc3Bundle bundled;
  late ShipSubtitleKc3Bundle updated;
  setUpAll(() async {
    bundled = ShipSubtitleKc3Bundle.fromJsonString(
      await File(ShipSubtitleKc3Bundle.bundledAsset).readAsString(),
    );
    final source = jsonDecode(bundled.toJsonString()) as Map<String, dynamic>;
    const version = '20990101000000';
    source['version'] = version;
    source['commit'] = 'f' * 40;
    for (final quoteKey in ['english', 'korean']) {
      (source[quoteKey] as Map<String, dynamic>)['version'] = version;
    }
    final names = source['names'] as Map<String, dynamic>;
    for (final code in _updatedNames.keys) {
      final language = code == 'en' ? 'en-us' : 'ko-kr';
      final ships = names[language]['ships'] as Map<String, dynamic>;
      ships[_rawShip.name] = _updatedNames[code]!;
      ships['明石'] = _updatedAkashiNames[code]!;
    }
    updated = ShipSubtitleKc3Bundle.fromJson(source);
  });

  for (final locale in [
    const Locale('zh'),
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    const Locale('ja'),
  ]) {
    testWidgets(
      '$locale name widgets ignore translated resource replacements',
      (tester) async {
        final resources = _resources(bundled, _BundleUpdater(updated));
        addTearDown(resources.dispose);
        var builds = 0;
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            builder: (context, child) =>
                GameNameLocalizationScope(controller: resources, child: child!),
            home: Builder(
              builder: (context) {
                builds++;
                return Text(gameNames(context).shipName(_rawShip.name));
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final before = builds;
        await resources.checkForUpdates();
        await tester.pump();
        expect(resources.kc3Bundle, same(updated));
        expect(find.text(_rawShip.name), findsOneWidget);
        expect(builds, before);
      },
    );
  }

  for (final code in _updatedNames.keys) {
    testWidgets('$code unchanged resource checks keep name widgets idle', (
      tester,
    ) async {
      final resources = _resources(bundled, _BundleUpdater(bundled));
      addTearDown(resources.dispose);
      var builds = 0;
      GameNameCatalog? observed;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(code),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) =>
              GameNameLocalizationScope(controller: resources, child: child!),
          home: Builder(
            builder: (context) {
              builds++;
              observed = gameNames(context);
              return Text(observed!.shipName(_rawShip.name));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final initialBuilds = builds;
      final initialNames = observed;

      await resources.checkForUpdates();
      await tester.pump();
      expect(builds, initialBuilds);
      expect(observed, same(initialNames));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(builds, initialBuilds);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    test(
      '$code metadata-only checks do not resend notification snapshots',
      () async {
        GameStateController.disableTimerForTest = true;
        addTearDown(() => GameStateController.disableTimerForTest = false);
        final resources = _resources(bundled, _BundleUpdater(bundled));
        addTearDown(resources.dispose);
        final gameState = GameStateController(initialState: _anchorageState());
        addTearDown(gameState.dispose);
        await gameState.initialize();
        final settings = NotificationSettingsController(
          initialSettings: const NotificationSettings(),
        );
        addTearDown(settings.dispose);
        final notificationLocale = ValueNotifier(code);
        addTearDown(notificationLocale.dispose);
        final port = FakeNotificationPort();
        final coordinator = GameNotificationCoordinator(
          gameStateController: gameState,
          settingsController: settings,
          notificationPort: port,
          localeCodeProvider: () => notificationLocale.value,
          localeListenable: notificationLocale,
          namesProvider: () => GameNameCatalog(
            bundle: resources.kc3Bundle,
            locale: Locale(notificationLocale.value),
          ),
          namesListenable: resources,
        );
        addTearDown(coordinator.dispose);
        coordinator.start();
        await Future<void>.delayed(Duration.zero);
        final before = port.applyCount;
        expect(before, greaterThan(0));

        await resources.checkForUpdates();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(resources.kc3Bundle, same(bundled));
        expect(port.applyCount, before);
        for (final next in ['en', 'ko', 'zh']) {
          notificationLocale.value = next;
          await Future<void>.delayed(Duration.zero);
          final afterLocaleChange = port.applyCount;
          await resources.checkForUpdates();
          await Future<void>.delayed(Duration.zero);
          await Future<void>.delayed(Duration.zero);
          expect(port.applyCount, afterLocaleChange, reason: next);
        }
      },
    );

    testWidgets(
      '$code resource update refreshes an open dialog and its existing page',
      (tester) async {
        final updater = _BundleUpdater(updated);
        final resources = _resources(bundled, updater);
        addTearDown(resources.dispose);
        final locale = Locale(code);
        final originalName = GameNameCatalog(
          bundle: bundled,
          locale: locale,
        ).shipName(_rawShip.name, shipId: _rawShip.id);
        final state = GameState.empty.copyWith(
          masterShips: const {1: _rawShip},
        );
        final originalMaster = state.masterShips[1];

        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) =>
                GameNameLocalizationScope(controller: resources, child: child!),
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    _ShipName(key: _pageNamesKey, ship: state.masterShips[1]!),
                    TextButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          content: _ShipName(
                            key: _dialogNamesKey,
                            ship: state.masterShips[1]!,
                          ),
                        ),
                      ),
                      child: const Text('Open names'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open names'));
        await tester.pumpAndSettle();
        final dialogElement = tester.element(find.byType(AlertDialog));
        final pageElement = tester.element(
          find.byKey(_pageNamesKey, skipOffstage: false),
        );
        expect(_displayedName(tester, _pageNamesKey), originalName);
        expect(_displayedName(tester, _dialogNamesKey), originalName);
        expect(updater.calls, 0);

        expect(await resources.checkForUpdates(), isA<ShipSubtitleUpdated>());
        await tester.pumpAndSettle();

        expect(resources.kc3Bundle, same(updated));
        expect(updater.calls, 1);
        expect(_displayedName(tester, _pageNamesKey), _updatedNames[code]);
        expect(_displayedName(tester, _dialogNamesKey), _updatedNames[code]);
        expect(tester.element(find.byType(AlertDialog)), same(dialogElement));
        expect(
          tester.element(find.byKey(_pageNamesKey, skipOffstage: false)),
          same(pageElement),
        );
        expect(state.masterShips[1], same(originalMaster));
        expect(state.masterShips[1]!.name, '睦月');
      },
    );

    test(
      '$code resource update refreshes alarm and ongoing names without moving deadlines',
      () async {
        GameStateController.disableTimerForTest = true;
        addTearDown(() => GameStateController.disableTimerForTest = false);
        final updater = _BundleUpdater(updated);
        final resources = _resources(bundled, updater);
        addTearDown(resources.dispose);
        final now = DateTime.utc(2026, 10, 19, 12);
        final deadline = now.add(const Duration(minutes: 30));
        final rawState = GameState.empty.copyWith(
          masterShips: const {1: _rawShip},
          ships: const {
            10: OwnedShip(
              id: 10,
              masterId: 1,
              level: 1,
              currentHp: 5,
              maxHp: 13,
              repairDurationMilliseconds: 3600000,
            ),
          },
          constructionDocks: [
            ConstructionDock(
              id: 1,
              state: 1,
              createdShipMasterId: 1,
              startedAt: now.subtract(const Duration(minutes: 30)),
              completionTime: deadline,
            ),
          ],
          repairDocks: [
            RepairDock(id: 1, state: 1, shipId: 10, completionTime: deadline),
          ],
        );
        final gameState = GameStateController(initialState: rawState);
        addTearDown(gameState.dispose);
        await gameState.initialize();
        final settings = NotificationSettingsController(
          initialSettings: const NotificationSettings(
            expedition: false,
            anchorage: false,
            morale: false,
            constructionPreemptSeconds: 30,
            repairPreemptSeconds: 30,
          ),
        );
        addTearDown(settings.dispose);
        final port = FakeNotificationPort();
        final coordinator = GameNotificationCoordinator(
          gameStateController: gameState,
          settingsController: settings,
          notificationPort: port,
          nowProvider: () => now,
          localeCodeProvider: () => code,
          namesProvider: () => GameNameCatalog(
            bundle: resources.kc3Bundle,
            locale: Locale(code),
          ),
          namesListenable: resources,
        );
        addTearDown(coordinator.dispose);
        coordinator.start();
        await Future<void>.delayed(Duration.zero);

        final originalName = GameNameCatalog(
          bundle: bundled,
          locale: Locale(code),
        ).shipName(_rawShip.name, shipId: _rawShip.id);
        final before = port.latestSnapshot!;
        final beforeApplies = port.applyCount;
        expect(before.alarms, hasLength(4));
        expect(before.ongoingItems, hasLength(2));
        for (final alarm in before.alarms) {
          expect(alarm.body, contains(originalName));
        }
        for (final task in before.ongoingItems) {
          expect(task.title, contains(originalName));
        }
        expect(updater.calls, 0);

        expect(await resources.checkForUpdates(), isA<ShipSubtitleUpdated>());
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        final after = port.latestSnapshot!;
        expect(updater.calls, 1);
        expect(port.applyCount, greaterThan(beforeApplies));
        expect(after.alarms, hasLength(before.alarms.length));
        for (final alarm in after.alarms) {
          final previous = before.alarms.singleWhere(
            (item) => item.key == alarm.key,
          );
          expect(alarm.body, contains(_updatedNames[code]));
          expect(alarm.body, isNot(contains(originalName)));
          expect(alarm.taskId, previous.taskId);
          expect(alarm.triggerTime, previous.triggerTime);
          expect(alarm.stage, previous.stage);
          expect(alarm.type, previous.type);
        }
        expect(after.ongoingItems, hasLength(before.ongoingItems.length));
        for (final task in after.ongoingItems) {
          final previous = before.ongoingItems.singleWhere(
            (item) => item.id == task.id,
          );
          expect(task.title, contains(_updatedNames[code]));
          expect(task.title, isNot(contains(originalName)));
          expect(task.targetEpochMs, previous.targetEpochMs);
          expect(task.anchorEpochMs, previous.anchorEpochMs);
          expect(task.remainingSeconds, previous.remainingSeconds);
          expect(task.totalDurationSec, previous.totalDurationSec);
          expect(task.progress, previous.progress);
          expect(task.state, previous.state);
        }
        expect(port.deliveredImmediateAlerts, isEmpty);
        expect(gameState.state, same(rawState));
        expect(gameState.state.masterShips[1], same(_rawShip));
        expect(gameState.state.masterShips[1]!.name, '睦月');
      },
    );

    test(
      '$code anchorage milestone translates Akashi and refreshes her name from resources',
      () async {
        GameStateController.disableTimerForTest = true;
        addTearDown(() => GameStateController.disableTimerForTest = false);
        final resources = _resources(bundled, _BundleUpdater(updated));
        addTearDown(resources.dispose);
        final now = DateTime.utc(2026, 10, 19, 12);
        final startedAt = now.subtract(const Duration(minutes: 5));
        final deadline = startedAt.add(const Duration(minutes: 20));
        final rawState = _anchorageState();
        final gameState = GameStateController(initialState: rawState);
        addTearDown(gameState.dispose);
        await gameState.initialize();
        final settings = NotificationSettingsController(
          initialSettings: const NotificationSettings(
            expedition: false,
            construction: false,
            repair: false,
            morale: false,
          ),
        );
        addTearDown(settings.dispose);
        final port = FakeNotificationPort();
        final coordinator = GameNotificationCoordinator(
          gameStateController: gameState,
          settingsController: settings,
          notificationPort: port,
          nowProvider: () => now,
          anchorageRepairStartedAtProvider: () => startedAt,
          localeCodeProvider: () => code,
          namesProvider: () => GameNameCatalog(
            bundle: resources.kc3Bundle,
            locale: Locale(code),
          ),
          namesListenable: resources,
        );
        addTearDown(coordinator.dispose);
        coordinator.start();
        await Future<void>.delayed(Duration.zero);

        final before = port.scheduledAlarms['anchorage_1_20m']!;
        expect(before.body, contains(code == 'en' ? 'Akashi' : '아카시'));
        expect(before.body, isNot(contains('明石')));
        expect(before.taskId, 'anchorage:1');
        expect(before.stage, NotificationAlarmStage.milestone);
        expect(before.triggerTime, deadline);

        expect(await resources.checkForUpdates(), isA<ShipSubtitleUpdated>());
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        final after = port.scheduledAlarms['anchorage_1_20m']!;
        expect(after.body, contains(_updatedAkashiNames[code]));
        expect(after.body, isNot(contains('明石')));
        expect(after.taskId, before.taskId);
        expect(after.triggerTime, before.triggerTime);
        expect(after.stage, before.stage);
        expect(port.deliveredImmediateAlerts, isEmpty);
        expect(gameState.state, same(rawState));
        expect(gameState.state.masterShips[182]!.name, '明石');
      },
    );
  }
}

GameState _anchorageState() => GameState.empty.copyWith(
  masterShips: const {
    182: MasterShip(id: 182, name: '明石', shipTypeId: 19),
    1: _rawShip,
  },
  ships: const {
    1: OwnedShip(
      id: 1,
      masterId: 182,
      level: 35,
      currentHp: 39,
      maxHp: 39,
      condition: 49,
      currentFuel: 50,
      currentAmmo: 10,
      slotIds: [],
    ),
    2: OwnedShip(
      id: 2,
      masterId: 1,
      level: 50,
      currentHp: 20,
      maxHp: 30,
      condition: 49,
      currentFuel: 15,
      currentAmmo: 20,
      slotIds: [],
      repairDurationMilliseconds: 3600000,
    ),
  },
  fleets: const [
    Fleet(id: 1, name: 'Fleet 1', shipIds: [1, 2]),
  ],
);

class _ShipName extends StatelessWidget {
  const _ShipName({super.key, required this.ship});
  final MasterShip ship;

  @override
  Widget build(BuildContext context) =>
      Text(gameNames(context).shipName(ship.name, shipId: ship.id));
}

String? _displayedName(WidgetTester tester, Key key) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(key, skipOffstage: false),
        matching: find.byType(Text, skipOffstage: false),
        skipOffstage: false,
      ),
    )
    .data;

ShipSubtitleCatalogController _resources(
  ShipSubtitleKc3Bundle bundled,
  _BundleUpdater updater,
) {
  final data = ShipSubtitleCatalog(
    version: '2026101805',
    quotes: {
      '1': {'1': '离线台词'},
    },
  );
  return ShipSubtitleCatalogController(
    data: data,
    updater: const _UnchangedQuotes(),
    now: () => DateTime.utc(2026, 10, 19),
    languageLoader: (_) async => ShipSubtitleCatalogSource(
      data: data,
      updater: const _UnchangedQuotes(),
    ),
    kc3Source: ShipSubtitleKc3Source(bundle: bundled, updater: updater),
  );
}

final class _UnchangedQuotes implements ShipSubtitleUpdateClient {
  const _UnchangedQuotes();
  @override
  Future<ShipSubtitleUpdateResult> checkAndUpdate({
    required ShipSubtitleCatalog current,
  }) async => ShipSubtitleUpToDate(current, sourceHost: 'memory');
}

final class _BundleUpdater implements ShipSubtitleKc3UpdateClient {
  _BundleUpdater(this.updated);
  final ShipSubtitleKc3Bundle updated;
  int calls = 0;

  @override
  Future<ShipSubtitleKc3UpdateResult> checkAndUpdate({
    required ShipSubtitleKc3Bundle current,
  }) async {
    calls++;
    return ShipSubtitleKc3Updated(updated, sourceHost: 'memory');
  }
}
