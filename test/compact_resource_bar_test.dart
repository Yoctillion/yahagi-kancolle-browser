import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/src/settings/header_resource_settings.dart';
import 'package:yahagi_kancolle_browser/src/fleet/resource_grid.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/widgets/top_notice.dart';

void main() {
  testWidgets('furniture coin is hidden by default and can be enabled', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final controller = await LayoutSettingsController.load(
      SharedPreferencesLayoutSettingsStore(),
    );
    const state = GameState(furnitureCoins: 183854, hasFurnitureCoinData: true);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CompactResourceBar(
            state: state,
            settingsController: controller,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('header-resource-furniture-coin')),
      findsNothing,
    );

    await controller.toggleHeaderResourceVisible(headerFurnitureCoinId);
    await tester.pump();
    await tester.drag(
      find.byKey(const Key('header-resource-list')),
      const Offset(-2000, 0),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('header-resource-furniture-coin')),
      findsOneWidget,
    );
    expect(find.text('183854'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/images/material/useitem_44.png',
      ),
      findsOneWidget,
    );
    final coin = find.byKey(const Key('header-resource-furniture-coin'));
    final coinImage = tester.widget<Image>(
      find.descendant(of: coin, matching: find.byType(Image)),
    );
    final valueScaler = tester.widget<FittedBox>(
      find.descendant(of: coin, matching: find.byType(FittedBox)),
    );
    expect(coinImage.fit, BoxFit.contain);
    expect(valueScaler.fit, BoxFit.scaleDown);
    expect(valueScaler.clipBehavior, Clip.hardEdge);
    expect(tester.takeException(), isNull);
  });

  testWidgets('furniture coin uses a dash before api_fcoin is captured', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final controller = await LayoutSettingsController.load(
      SharedPreferencesLayoutSettingsStore(),
    );
    await controller.toggleHeaderResourceVisible(headerFurnitureCoinId);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CompactResourceBar(
            state: GameState.empty,
            settingsController: controller,
          ),
        ),
      ),
    );
    await tester.drag(
      find.byKey(const Key('header-resource-list')),
      const Offset(-2000, 0),
    );
    await tester.pumpAndSettle();

    final coin = find.byKey(const Key('header-resource-furniture-coin'));
    expect(coin, findsOneWidget);
    expect(find.descendant(of: coin, matching: find.text('—')), findsOneWidget);
  });

  testWidgets('furniture coin toggles the theoretical total from boxes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final controller = await LayoutSettingsController.load(
      SharedPreferencesLayoutSettingsStore(),
    );
    await controller.toggleHeaderResourceVisible(headerFurnitureCoinId);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CompactResourceBar(
            state: const GameState(
              furnitureCoins: 183854,
              hasFurnitureCoinData: true,
              useItems: <int, int>{10: 12, 11: 7, 12: 3},
              hasUseItemData: true,
            ),
            settingsController: controller,
          ),
        ),
      ),
    );
    await tester.drag(
      find.byKey(const Key('header-resource-list')),
      const Offset(-2000, 0),
    );
    await tester.pumpAndSettle();

    final coin = find.byKey(const Key('header-resource-furniture-coin'));
    expect(
      find.descendant(of: coin, matching: find.text('183854')),
      findsOneWidget,
    );

    await tester.tap(coin);
    await tester.pump();

    expect(
      find.descendant(of: coin, matching: find.text('≈191154')),
      findsOneWidget,
    );
    final coinIcon = tester.widget<Image>(
      find.descendant(of: coin, matching: find.byType(Image)),
    );
    expect(
      (coinIcon.image as AssetImage).assetName,
      'assets/images/material/useitem_44.png',
    );

    await tester.tap(coin);
    await tester.pump();

    expect(
      find.descendant(of: coin, matching: find.text('183854')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('theoretical furniture coin total waits for box data', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final controller = await LayoutSettingsController.load(
      SharedPreferencesLayoutSettingsStore(),
    );
    await controller.toggleHeaderResourceVisible(headerFurnitureCoinId);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CompactResourceBar(
            state: const GameState(
              furnitureCoins: 183854,
              hasFurnitureCoinData: true,
            ),
            settingsController: controller,
          ),
        ),
      ),
    );
    await tester.drag(
      find.byKey(const Key('header-resource-list')),
      const Offset(-2000, 0),
    );
    await tester.pumpAndSettle();

    final coin = find.byKey(const Key('header-resource-furniture-coin'));
    await tester.tap(coin);
    await tester.pump();

    expect(find.descendant(of: coin, matching: find.text('—')), findsOneWidget);
    expect(find.textContaining('≈'), findsNothing);
  });

  testWidgets('furniture boxes independently toggle coin equivalents', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final controller = await LayoutSettingsController.load(
      SharedPreferencesLayoutSettingsStore(),
    );
    for (final id in <String>['useitem-10', 'useitem-11', 'useitem-12']) {
      await controller.toggleHeaderResourceVisible(id);
    }

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CompactResourceBar(
            state: const GameState(
              useItems: <int, int>{10: 999, 11: 7, 12: 3},
              hasUseItemData: true,
            ),
            settingsController: controller,
          ),
        ),
      ),
    );
    await tester.drag(
      find.byKey(const Key('header-resource-list')),
      const Offset(-2000, 0),
    );
    await tester.pumpAndSettle();

    final small = find.byKey(const Key('header-resource-useitem-10'));
    final medium = find.byKey(const Key('header-resource-useitem-11'));
    final large = find.byKey(const Key('header-resource-useitem-12'));
    expect(
      find.descendant(of: small, matching: find.text('999')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: medium, matching: find.text('7')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: large, matching: find.text('3')),
      findsOneWidget,
    );

    await tester.tap(small);
    await tester.tap(medium);
    await tester.tap(large);
    await tester.pump();

    expect(
      find.descendant(of: small, matching: find.text('199800币')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: medium, matching: find.text('2800币')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: large, matching: find.text('2100币')),
      findsOneWidget,
    );
    final smallIcon = tester.widget<Image>(
      find.descendant(of: small, matching: find.byType(Image)),
    );
    expect(
      (smallIcon.image as AssetImage).assetName,
      'assets/images/material/10.png',
    );

    await tester.tap(small);
    await tester.pump();

    expect(
      find.descendant(of: small, matching: find.text('999')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: medium, matching: find.text('2800币')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: large, matching: find.text('2100币')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('furniture box coin mode keeps a dash before data is captured', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final controller = await LayoutSettingsController.load(
      SharedPreferencesLayoutSettingsStore(),
    );
    await controller.toggleHeaderResourceVisible('useitem-10');

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CompactResourceBar(
            state: GameState.empty,
            settingsController: controller,
          ),
        ),
      ),
    );
    await tester.drag(
      find.byKey(const Key('header-resource-list')),
      const Offset(-2000, 0),
    );
    await tester.pumpAndSettle();

    final small = find.byKey(const Key('header-resource-useitem-10'));
    await tester.tap(small);
    await tester.pump();

    expect(
      find.descendant(of: small, matching: find.text('—')),
      findsOneWidget,
    );
    expect(find.textContaining('币'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('frame refresh capsule defaults hidden and becomes actionable', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final controller = await LayoutSettingsController.load(
      SharedPreferencesLayoutSettingsStore(),
    );
    var refreshCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CompactResourceBar(
            state: const GameState(),
            settingsController: controller,
            onFrameRefreshTap: () => refreshCalls += 1,
          ),
        ),
      ),
    );

    expect(
      defaultVisibleHeaderResourceIds,
      isNot(contains(headerFrameRefreshId)),
    );
    expect(
      find.byKey(const Key('header-resource-frame-refresh')),
      findsNothing,
    );
    await controller.toggleHeaderResourceVisible(headerFrameRefreshId);
    await tester.pump();
    final refresh = find.byKey(const Key('header-resource-frame-refresh'));
    expect(refresh, findsOneWidget);
    expect(find.text('框架刷新'), findsOneWidget);
    expect(tester.getSize(refresh).width, 98);
    await tester.tap(refresh);
    expect(refreshCalls, 1);
  });

  test('formats anchorage repair elapsed time for the header capsule', () {
    final startedAt = DateTime.utc(2026, 8, 11, 1, 2, 3);

    expect(
      formatAnchorageRepairElapsed(
        startedAt,
        DateTime.utc(2026, 8, 11, 14, 7, 9),
      ),
      '13:05:06',
    );
    expect(
      formatAnchorageRepairElapsed(null, DateTime.utc(2026, 8, 11)),
      '--:--:--',
    );
    expect(
      formatAnchorageRepairElapsed(
        startedAt,
        DateTime.utc(2026, 8, 11, 1, 2, 2),
      ),
      '00:00:00',
    );
  });

  test('formats nosaki sparkle elapsed time for the header capsule', () {
    final startedAt = DateTime.utc(2026, 8, 11, 1, 2, 3);

    expect(
      formatNosakiSparkleElapsed(
        startedAt,
        DateTime.utc(2026, 8, 11, 14, 7, 9),
      ),
      '13:05:06',
    );
    expect(
      formatNosakiSparkleElapsed(null, DateTime.utc(2026, 8, 11)),
      '--:--:--',
    );
    expect(
      formatNosakiSparkleElapsed(startedAt, DateTime.utc(2026, 8, 11, 1, 2, 2)),
      '00:00:00',
    );
  });

  testWidgets('narrow header keeps the empty senka capsule visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 200,
              child: CompactResourceBar(state: GameState()),
            ),
          ),
        ),
      ),
    );

    expect(find.text('战果：--（#--）'), findsOneWidget);
    expect(find.text('泊地：--:--:--'), findsOneWidget);
    expect(
      find.byKey(const Key('header-anchorage-timer-summary')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('header renders nosaki capsule with empty timer', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 500,
              child: CompactResourceBar(state: GameState()),
            ),
          ),
        ),
      ),
    );

    expect(find.text('野埼：--:--:--'), findsOneWidget);
    expect(
      find.byKey(const Key('header-nosaki-timer-summary')),
      findsOneWidget,
    );
  });

  testWidgets('anchorage capsule invokes tap without breaking long press', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CompactResourceBar(
            state: const GameState(),
            onAnchorageTimerTap: () => taps++,
          ),
        ),
      ),
    );

    final timer = find.byKey(const Key('header-resource-anchorage-timer'));
    await tester.tap(timer);
    await tester.pump();
    expect(taps, 1);

    await tester.longPress(timer);
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(find.byKey(const Key('header-resource-edit-mode')), findsOneWidget);
  });

  testWidgets('nosaki capsule invokes tap without breaking long press', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CompactResourceBar(
            state: const GameState(),
            onNosakiTimerTap: () => taps++,
          ),
        ),
      ),
    );

    final timer = find.byKey(const Key('header-resource-nosaki-timer'));
    await tester.tap(timer);
    await tester.pump();
    expect(taps, 1);

    await tester.longPress(timer);
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(find.byKey(const Key('header-resource-edit-mode')), findsOneWidget);
  });

  testWidgets('starts at the leading edge and long press enters edit mode', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final controller = await LayoutSettingsController.load(
      SharedPreferencesLayoutSettingsStore(),
    );
    const state = GameState(
      resources: <GameResourceType, int>{GameResourceType.fuel: 12345},
    );
    var senkaTapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(padding: EdgeInsets.only(left: 48)),
            child: Padding(
              padding: const EdgeInsets.only(top: 100),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 600,
                  child: CompactResourceBar(
                    state: state,
                    senka: 1120,
                    rank: 370,
                    settingsController: controller,
                    onSenkaTap: () => senkaTapCount += 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final senka = find.byKey(const Key('header-senka-summary'));
    expect(senka, findsOneWidget);
    expect(find.text('战果：1120（#370）'), findsOneWidget);
    expect(tester.getTopLeft(senka).dx, 0);
    final senkaDecoration =
        tester.widget<Container>(senka).decoration! as BoxDecoration;
    final senkaBorder = senkaDecoration.border! as Border;
    expect(senkaBorder.top.color, const Color(0xff315064));

    final first = find.byKey(const Key('header-resource-ship-capacity'));
    expect(first, findsOneWidget);
    expect(
      find.byKey(const Key('header-resource-anchorage-timer')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(first).dx,
      greaterThan(tester.getRect(senka).right),
    );
    expect(find.byKey(const Key('header-resource-useitem-68')), findsNothing);

    await tester.tap(find.byKey(const Key('header-resource-senka')));
    await tester.pump();
    expect(senkaTapCount, 1);
    await tester.tap(first);
    await tester.pump();
    expect(senkaTapCount, 1);

    await tester.longPress(senka);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('header-resource-edit-mode')), findsOneWidget);
    expect(find.byKey(const Key('header-resource-filter')), findsOneWidget);
    final resetX = tester
        .getTopLeft(find.byKey(const Key('header-resource-reset')))
        .dx;
    final doneX = tester
        .getTopLeft(find.byKey(const Key('header-resource-edit-done')))
        .dx;
    final filterX = tester
        .getTopLeft(find.byKey(const Key('header-resource-filter')))
        .dx;
    expect(resetX, lessThan(doneX));
    expect(doneX, lessThan(filterX));
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byIcon(Icons.drag_indicator_rounded), findsNothing);

    await tester.tap(find.byKey(const Key('header-resource-filter')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('header-resource-filter-list')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('header-resource-filter-row-senka')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('header-resource-visible-senka')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('header-resource-filter-row-anchorage-timer')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('header-resource-visible-anchorage-timer')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('header-resource-filter-row-ship-capacity')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('header-resource-visible-ship-capacity')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('header-resource-filter-row-equipment-capacity')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('header-resource-visible-equipment-capacity')),
      findsOneWidget,
    );
    final firstFilterRow = find.byKey(
      const Key('header-resource-filter-row-material-1'),
    );
    final secondFilterRow = find.byKey(
      const Key('header-resource-filter-row-material-2'),
    );
    expect(
      tester.getTopLeft(firstFilterRow).dx,
      tester.getTopLeft(secondFilterRow).dx,
    );
    expect(
      tester.getTopLeft(secondFilterRow).dy,
      greaterThan(tester.getTopLeft(firstFilterRow).dy),
    );
    expect(
      find.byKey(const Key('header-resource-visible-material-1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('header-resource-visible-senka')));
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('header-resource-visible-ship-capacity')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('header-resource-filter-done')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('header-resource-edit-done')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('header-senka-summary')), findsNothing);
    expect(find.byKey(const Key('header-ship-capacity')), findsNothing);
    expect(find.byKey(const Key('header-resource-material-1')), findsOneWidget);
    expect(find.byKey(const Key('header-resource-material-2')), findsOneWidget);
  });

  testWidgets(
    'header shows --:--:-- for anchorage when damaged, while nosaki shows continuous timer when started',
    (tester) async {
      final startedAt = DateTime.utc(2026, 8, 20, 10);
      // Damaged Akashi (hp 10/45 <= 50%) and damaged Nozaki (hp 30/48 < max)
      const damagedState = GameState(
        fleets: <Fleet>[
          Fleet(id: 1, name: '第一舰队', shipIds: <int>[1, 2]),
        ],
        ships: <int, OwnedShip>{
          1: OwnedShip(
            id: 1,
            masterId: 187,
            level: 80,
            currentHp: 10,
            maxHp: 45,
          ), // Akashi heavy damage
          2: OwnedShip(
            id: 2,
            masterId: 1002,
            level: 80,
            currentHp: 30,
            maxHp: 48,
            currentFuel: 100,
            currentAmmo: 100,
          ), // Nozaki damaged
        },
        masterShips: <int, MasterShip>{
          187: MasterShip(id: 187, name: '明石改', shipTypeId: 19),
          1002: MasterShip(
            id: 1002,
            name: '野埼改',
            shipTypeId: 22,
            maxFuel: 100,
            maxAmmo: 100,
          ),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: CompactResourceBar(
              state: damagedState,
              anchorageRepairStartedAt: startedAt,
              nosakiSparkleStartedAt: startedAt,
            ),
          ),
        ),
      );

      expect(find.text('泊地：--:--:--'), findsOneWidget);
      expect(find.text('野埼：--:--:--'), findsNothing);
    },
  );

  testWidgets(
    'header shows active elapsed time when Akashi and Nozaki are ready',
    (tester) async {
      final startedAt = DateTime.now().toUtc().subtract(
        const Duration(minutes: 10),
      );
      const readyState = GameState(
        fleets: <Fleet>[
          Fleet(id: 1, name: '第一舰队', shipIds: <int>[1, 2]),
        ],
        ships: <int, OwnedShip>{
          1: OwnedShip(
            id: 1,
            masterId: 187,
            level: 80,
            currentHp: 45,
            maxHp: 45,
          ),
          2: OwnedShip(
            id: 2,
            masterId: 1002,
            level: 80,
            currentHp: 48,
            maxHp: 48,
            currentFuel: 100,
            currentAmmo: 100,
            condition: 49,
          ),
        },
        masterShips: <int, MasterShip>{
          187: MasterShip(id: 187, name: '明石改', shipTypeId: 19),
          1002: MasterShip(
            id: 1002,
            name: '野埼改',
            shipTypeId: 22,
            maxFuel: 100,
            maxAmmo: 100,
          ),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: CompactResourceBar(
              state: readyState,
              anchorageRepairStartedAt: startedAt,
              nosakiSparkleStartedAt: startedAt,
            ),
          ),
        ),
      );

      expect(find.text('泊地：--:--:--'), findsNothing);
      expect(find.text('野埼：--:--:--'), findsNothing);
      expect(find.textContaining('泊地：00:10:'), findsOneWidget);
      expect(find.textContaining('野埼：00:10:'), findsOneWidget);
    },
  );

  testWidgets('compact header UI size adjusts bar height and pill sizes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final controller = await LayoutSettingsController.load(
      SharedPreferencesLayoutSettingsStore(),
    );
    await controller.setHeaderUiSize(HeaderUiSize.compact);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CompactResourceBar(
            state: const GameState(),
            settingsController: controller,
          ),
        ),
      ),
    );

    // Verify fuel capsule width is 74 and height is 26 in compact mode
    final fuelPill = find.byKey(const Key('header-resource-material-1'));
    expect(fuelPill, findsOneWidget);
    expect(tester.getSize(fuelPill).height, 26);
    expect(tester.getSize(fuelPill).width, 74);
  });

  testWidgets('minimal resource items have no capsule border', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final controller = await LayoutSettingsController.load(
      SharedPreferencesLayoutSettingsStore(),
    );
    await controller.setUiDisplaySize(UiDisplaySize.minimal);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CompactResourceBar(
            state: const GameState(),
            settingsController: controller,
          ),
        ),
      ),
    );

    final item = find.byKey(const Key('header-resource-material-1'));
    expect(item, findsOneWidget);
    expect(tester.getSize(item).width, 74);
    final decorations = <Decoration?>[
      for (final box in tester.widgetList<Container>(
        find.descendant(of: item, matching: find.byType(Container)),
      ))
        box.decoration,
      for (final box in tester.widgetList<DecoratedBox>(
        find.descendant(of: item, matching: find.byType(DecoratedBox)),
      ))
        box.decoration,
    ];
    for (final decoration in decorations) {
      expect(decoration is BoxDecoration ? decoration.border : null, isNull);
      expect(decoration is BoxDecoration ? decoration.color : null, isNull);
    }
  });

  Future<LayoutSettingsController> loadGridController() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    return LayoutSettingsController.load(
      SharedPreferencesLayoutSettingsStore(),
    );
  }

  Widget gridHarness(
    LayoutSettingsController controller, {
    double width = 200,
    double? senka,
    GameState state = const GameState(),
    Locale locale = const Locale('zh'),
  }) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TopNoticeHost(
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: CompactResourceBar(
                state: state,
                senka: senka,
                rank: senka == null ? null : 123,
                settingsController: controller,
                layout: ResourceBarLayout.grid,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('grid layout wraps visible resources into 4 columns', (
    tester,
  ) async {
    final controller = await loadGridController();
    await tester.pumpWidget(gridHarness(controller));

    expect(
      find.byKey(const Key('information-panel-resources')),
      findsOneWidget,
    );
    final first = tester.getTopLeft(
      find.byKey(const Key('header-resource-material-1')),
    );
    final fourth = tester.getTopLeft(
      find.byKey(const Key('header-resource-material-4')),
    );
    final fifth = tester.getTopLeft(
      find.byKey(const Key('header-resource-material-5')),
    );
    expect(fourth.dy, first.dy);
    expect(fourth.dx, greaterThan(first.dx));
    expect(fifth.dx, first.dx);
    expect(fifth.dy, greaterThan(first.dy));
    expect(tester.takeException(), isNull);
  });

  const richState = GameState(
    resources: <GameResourceType, int>{
      GameResourceType.fuel: 146449,
      GameResourceType.ammunition: 159378,
      GameResourceType.steel: 157012,
      GameResourceType.bauxite: 143589,
      GameResourceType.instantBuild: 771,
      GameResourceType.instantRepair: 889,
      GameResourceType.developmentMaterial: 501,
      GameResourceType.improvementMaterial: 11,
    },
    maxShipCount: 750,
    maxEquipmentCount: 3431,
    hasPortData: true,
  );

  testWidgets('grid puts wide items two per row and plain items four per row', (
    tester,
  ) async {
    final controller = await loadGridController();
    await controller.setUiDisplaySize(UiDisplaySize.minimal);
    await tester.pumpWidget(
      gridHarness(controller, width: 250, senka: 3128, state: richState),
    );

    expect(tester.takeException(), isNull);
    Offset topLeft(String key) => tester.getTopLeft(find.byKey(Key(key)));
    final senka = topLeft('header-senka-summary');
    final anchorage = topLeft('header-anchorage-timer-summary');
    final nosaki = topLeft('header-nosaki-timer-summary');
    final ships = topLeft('header-ship-capacity');
    final equipment = topLeft('header-equipment-capacity');
    expect(anchorage.dy, senka.dy);
    expect(anchorage.dx, greaterThan(senka.dx));
    expect(nosaki.dy, greaterThan(senka.dy));
    expect(ships.dy, nosaki.dy);
    expect(ships.dx, anchorage.dx);
    expect(equipment.dy, greaterThan(nosaki.dy));
    expect(equipment.dx, senka.dx);
    // 落单的宽项只占半格，不拉满整行。
    expect(
      tester.getSize(find.byKey(const Key('header-equipment-capacity'))).width,
      lessThan(125),
    );

    final m1 = topLeft('header-resource-material-1');
    expect(m1.dy, greaterThan(equipment.dy));
    for (final id in [2, 3, 4]) {
      expect(topLeft('header-resource-material-$id').dy, m1.dy);
    }
    final m5 = topLeft('header-resource-material-5');
    expect(m5.dx, m1.dx);
    expect(m5.dy, greaterThan(m1.dy));
    for (final id in [6, 7, 8]) {
      expect(topLeft('header-resource-material-$id').dy, m5.dy);
    }
    expect(
      tester.getSize(find.byKey(const Key('information-panel-resources'))),
      isA<Size>().having((s) => s.height, 'height', lessThanOrEqualTo(5 * 22)),
    );
  });

  testWidgets('grid wide items show an icon instead of the text label', (
    tester,
  ) async {
    final controller = await loadGridController();
    await controller.setUiDisplaySize(UiDisplaySize.minimal);
    await tester.pumpWidget(
      gridHarness(controller, width: 250, senka: 3128, state: richState),
    );

    final grid = find.byKey(const Key('information-panel-resources'));
    for (final label in ['战果', '泊地', '野埼', '舰娘', '装备']) {
      expect(
        find.descendant(of: grid, matching: find.textContaining(label)),
        findsNothing,
        reason: label,
      );
    }
    for (final (key, icon, label) in const [
      ('header-senka-summary', Icons.emoji_events_rounded, '战果'),
      ('header-anchorage-timer-summary', Icons.anchor, '泊地'),
      ('header-nosaki-timer-summary', Icons.auto_awesome, '野埼'),
      ('header-ship-capacity', Icons.directions_boat_filled_rounded, '舰娘'),
      ('header-equipment-capacity', Icons.build_rounded, '装备'),
    ]) {
      final item = find.byKey(Key(key));
      expect(
        find.descendant(of: item, matching: find.byIcon(icon)),
        findsOneWidget,
        reason: key,
      );
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(of: item, matching: find.byType(Tooltip)).first,
      );
      expect(tooltip.message, contains(label), reason: key);
    }
    expect(find.text('3128(#123)'), findsOneWidget);
    expect(find.text('0/750'), findsOneWidget);
    expect(find.byIcon(Icons.anchor).evaluate().length, 1);
  });

  testWidgets('grid collapses to the first four plain resources and persists', (
    tester,
  ) async {
    final controller = await loadGridController();
    await controller.setUiDisplaySize(UiDisplaySize.minimal);
    await tester.pumpWidget(
      gridHarness(controller, width: 250, senka: 3128, state: richState),
    );
    final toggle = find.byKey(const Key('information-panel-resources-toggle'));
    expect(
      find.descendant(
        of: toggle,
        matching: find.byIcon(Icons.keyboard_arrow_up_rounded),
      ),
      findsOneWidget,
    );
    expect(tester.getSize(toggle), const Size(24, 24));
    final lastItem = tester.getRect(
      find.byKey(const Key('header-resource-material-8')),
    );
    final toggleRect = tester.getRect(toggle);
    expect(toggleRect.left, greaterThanOrEqualTo(lastItem.right));
    expect(toggleRect.center.dy, closeTo(lastItem.center.dy, 2.01));

    await tester.tap(toggle);
    await tester.pumpAndSettle();

    void expectCollapsed() {
      for (final id in [1, 2, 3, 4]) {
        expect(
          find.byKey(Key('header-resource-material-$id')),
          findsOneWidget,
          reason: 'material-$id',
        );
      }
      for (final key in [
        'header-resource-material-5',
        'header-resource-material-8',
        'header-senka-summary',
        'header-equipment-capacity',
      ]) {
        expect(find.byKey(Key(key)), findsNothing, reason: key);
      }
      expect(
        find.descendant(
          of: find.byKey(const Key('information-panel-resources-toggle')),
          matching: find.byIcon(Icons.keyboard_arrow_down_rounded),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }

    expectCollapsed();
    expect(
      controller.dashboardCardCollapsed,
      contains(panelResourcesCollapseId),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList('layout_dashboard_card_collapsed'),
      contains('panel-resources'),
    );

    final restored = await LayoutSettingsController.load(
      SharedPreferencesLayoutSettingsStore(),
    );
    await tester.pumpWidget(
      gridHarness(restored, width: 250, senka: 3128, state: richState),
    );
    await tester.pumpAndSettle();
    expectCollapsed();

    await tester.tap(
      find.byKey(const Key('information-panel-resources-toggle')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('header-senka-summary')), findsOneWidget);
    expect(
      restored.dashboardCardCollapsed,
      isNot(contains(panelResourcesCollapseId)),
    );
  });

  testWidgets('grid collapse still toggles while the UI is locked', (
    tester,
  ) async {
    final controller = await loadGridController();
    await controller.setUiLocked(true);
    await tester.pumpWidget(gridHarness(controller, width: 250));

    await tester.tap(
      find.byKey(const Key('information-panel-resources-toggle')),
    );
    await tester.pumpAndSettle();

    expect(
      controller.dashboardCardCollapsed,
      contains(panelResourcesCollapseId),
    );
    expect(find.byKey(const Key('header-resource-material-5')), findsNothing);
  });

  for (final locale in const [Locale('zh'), Locale('en')]) {
    testWidgets('grid fits 190dp without clipping numbers in $locale', (
      tester,
    ) async {
      final controller = await loadGridController();
      await controller.setUiDisplaySize(UiDisplaySize.minimal);
      await controller.toggleHeaderResourceVisible(headerFrameRefreshId);
      await tester.pumpWidget(
        gridHarness(
          controller,
          width: 190,
          senka: 31280.5,
          state: richState,
          locale: locale,
        ),
      );

      expect(tester.takeException(), isNull);
      for (final (key, value) in const [
        ('header-senka-summary', '31280.5(#123)'),
        ('header-ship-capacity', '0/750'),
        ('header-equipment-capacity', '0/3431'),
        ('header-anchorage-timer-summary', '--:--:--'),
        ('header-resource-material-1', '146449'),
        ('header-resource-material-2', '159378'),
        ('header-resource-material-4', '143589'),
      ]) {
        final item = find.byKey(Key(key));
        final text = find.descendant(of: item, matching: find.text(value));
        expect(text, findsOneWidget, reason: key);
        final itemRect = tester.getRect(item);
        final textRect = tester.getRect(text);
        expect(textRect.left, greaterThanOrEqualTo(itemRect.left), reason: key);
        expect(
          textRect.right,
          lessThanOrEqualTo(itemRect.right + 0.01),
          reason: key,
        );
      }
    });
  }

  testWidgets('grid layout keeps senka item numbers unclipped at 200dp width', (
    tester,
  ) async {
    final controller = await loadGridController();
    await controller.setUiDisplaySize(UiDisplaySize.minimal);
    await tester.pumpWidget(gridHarness(controller, senka: 1234.5));

    expect(tester.takeException(), isNull);
    final summary = find.byKey(const Key('header-senka-summary'));
    expect(tester.getSize(summary).width, lessThan(100));
    final value = find.textContaining('1234.5');
    expect(value, findsOneWidget);
    expect(tester.widget<Text>(value).style?.fontSize, 11);
    // 半格放不下时整体缩小而不是裁掉，数值仍完整落在格子里。
    final cell = tester.getRect(summary);
    expect(tester.getRect(value).left, greaterThanOrEqualTo(cell.left));
    expect(tester.getRect(value).right, lessThanOrEqualTo(cell.right + 0.01));
  });

  testWidgets('grid layout rows are 20dp tall with numbers unclipped', (
    tester,
  ) async {
    final controller = await loadGridController();
    await controller.setUiDisplaySize(UiDisplaySize.minimal);
    await controller.toggleHeaderResourceVisible(headerFrameRefreshId);
    await tester.pumpWidget(
      gridHarness(
        controller,
        senka: 1234.5,
        state: const GameState(
          resources: <GameResourceType, int>{GameResourceType.fuel: 123456},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    for (final key in const [
      'header-resource-material-1',
      'header-senka-summary',
      'header-anchorage-timer-summary',
      'header-nosaki-timer-summary',
      'header-ship-capacity',
      'header-equipment-capacity',
      'header-frame-refresh',
    ]) {
      expect(tester.getSize(find.byKey(Key(key))).height, 20, reason: key);
    }
    final first = tester.getTopLeft(
      find.byKey(const Key('header-resource-material-1')),
    );
    final seventh = tester.getTopLeft(
      find.byKey(const Key('header-resource-material-7')),
    );
    expect(seventh.dy - first.dy, 20 + 2);
    for (final (key, value) in const [
      ('header-resource-material-1', '123456'),
      ('header-senka-summary', '1234.5'),
    ]) {
      final item = tester.getRect(find.byKey(Key(key)));
      final text = tester.getRect(find.textContaining(value));
      expect(text.left, greaterThanOrEqualTo(item.left), reason: value);
      expect(text.top, greaterThanOrEqualTo(item.top), reason: value);
      expect(text.right, lessThanOrEqualTo(item.right), reason: value);
      expect(text.bottom, lessThanOrEqualTo(item.bottom), reason: value);
    }
  });

  for (final size in [UiDisplaySize.normal, UiDisplaySize.minimal]) {
    testWidgets('grid layout items have no capsule decoration at $size', (
      tester,
    ) async {
      final controller = await loadGridController();
      await controller.setUiDisplaySize(size);
      await tester.pumpWidget(gridHarness(controller, senka: 1234.5));

      for (final key in const [
        'header-resource-material-1',
        'header-senka-summary',
        'header-ship-capacity',
      ]) {
        final item = find.byKey(Key(key));
        expect(item, findsOneWidget);
        final boxes = <Decoration?>[
          for (final box in tester.widgetList<Container>(
            find.descendant(of: item, matching: find.byType(Container)),
          ))
            box.decoration,
          if (tester.widget(item) is Container)
            (tester.widget(item) as Container).decoration,
          for (final box in tester.widgetList<DecoratedBox>(
            find.descendant(of: item, matching: find.byType(DecoratedBox)),
          ))
            box.decoration,
        ];
        for (final d in boxes) {
          expect(d is BoxDecoration ? d.border : null, isNull, reason: key);
          expect(d is BoxDecoration ? d.color : null, isNull, reason: key);
        }
      }
    });
  }

  testWidgets('grid layout long-press respects ui lock', (tester) async {
    final controller = await loadGridController();
    await controller.setUiLocked(true);
    await tester.pumpWidget(gridHarness(controller));

    await tester.longPress(find.byKey(const Key('header-resource-material-1')));
    await tester.pump();

    expect(find.byKey(const Key('header-resource-edit-mode')), findsNothing);
    expect(find.text('界面已锁定，布局自定义已禁用，功能切换不受影响'), findsOneWidget);
  });

  testWidgets('grid layout long-press enters edit mode when unlocked', (
    tester,
  ) async {
    final controller = await loadGridController();
    await tester.pumpWidget(gridHarness(controller));

    await tester.longPress(find.byKey(const Key('header-resource-material-1')));
    await tester.pump();

    expect(find.byKey(const Key('header-resource-edit-mode')), findsOneWidget);
  });
}
