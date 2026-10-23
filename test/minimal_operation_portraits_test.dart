import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/fleet/anchorage_repair_view.dart';
import 'package:yahagi_kancolle_browser/src/fleet/construction_summary_card.dart';
import 'package:yahagi_kancolle_browser/src/fleet/operation_progress.dart';
import 'package:yahagi_kancolle_browser/src/fleet/repair_summary_card.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_portrait.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_store.dart';
import 'package:yahagi_kancolle_browser/src/layout/panel_style.dart';
import 'package:yahagi_kancolle_browser/src/layout/flat_list_row.dart';
import 'package:yahagi_kancolle_browser/src/layout/flat_portrait_backdrop.dart';
import 'package:yahagi_kancolle_browser/src/performance/second_tick_scope.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/module_display_settings.dart';

final _now = DateTime.utc(2030, 1, 1);
const _shipName = 'Portrait fixture';

class _Store extends GameStateStore {
  _Store(this.state);
  final GameState state;
  @override
  Future<GameState> load() async => state;
}

GameState _operationState() => GameState(
  hasPortData: true,
  hasMasterData: true,
  masterShips: const {
    999001: MasterShip(id: 999001, name: _shipName, shipTypeId: 2),
  },
  ships: const {9001: OwnedShip(id: 9001, masterId: 999001, level: 50)},
  repairDocks: [
    const RepairDock(id: 1),
    RepairDock(
      id: 2,
      state: 1,
      shipId: 9001,
      completionTime: _now.add(const Duration(hours: 1)),
    ),
    const RepairDock(id: 3, state: -1),
    RepairDock(
      id: 4,
      state: 1,
      shipId: 9999,
      completionTime: _now.add(const Duration(hours: 2)),
    ),
  ],
  constructionDocks: [
    const ConstructionDock(id: 1),
    ConstructionDock(
      id: 2,
      state: 2,
      createdShipMasterId: 999001,
      completionTime: _now.add(const Duration(hours: 1)),
    ),
    const ConstructionDock(id: 3, state: -1),
    ConstructionDock(
      id: 4,
      state: 2,
      createdShipMasterId: 999999,
      completionTime: _now.add(const Duration(hours: 2)),
    ),
  ],
);

Finder _slot(String module, int id) => find.byKey(
  Key(
    module == 'repair'
        ? 'repair-summary-dock-slot-$id'
        : 'construction-summary-slot-$id',
  ),
);

Finder _rowInSlot(WidgetTester tester, Finder slot) =>
    tester.widget(slot) is FlatListRow
    ? slot
    : find.descendant(of: slot, matching: find.byType(FlatListRow));

void _expectPortraitBackdrop(WidgetTester tester, Finder slot) {
  final row = _rowInSlot(tester, slot);
  final rowRect = tester.getRect(row);
  final portrait = find.descendant(
    of: slot,
    matching: find.byType(ShipPortrait),
  );
  expect(portrait, findsOneWidget);
  final imageRect = tester.getRect(portrait);
  expect(imageRect.width, closeTo(rowRect.width * .6, .01));
  expect(imageRect.height, closeTo(rowRect.height, .01));
  expect(imageRect.topLeft, rowRect.topLeft);
  expect(tester.widget<FlatListRow>(row).tags, isEmpty);
  expect(
    find.ancestor(of: portrait, matching: find.byType(FlatPortraitBackdrop)),
    findsOneWidget,
  );
  final pointer = find
      .ancestor(of: portrait, matching: find.byType(IgnorePointer))
      .first;
  expect(tester.widget<IgnorePointer>(pointer).ignoring, isTrue);
}

Widget _app({
  required String module,
  required GameStateController game,
  required LayoutSettingsController settings,
  required VoidCallback onOpen,
  double width = 600,
  TextScaler textScaler = TextScaler.noScaling,
}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: textScaler),
    child: child!,
  ),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: SecondTickScope(
          now: () => _now,
          child: PanelStyleScope(
            style: PanelStyle.flat,
            child: AnimatedBuilder(
              animation: settings,
              builder: (context, _) => module == 'repair'
                  ? RepairSummaryCard(
                      controller: game,
                      collapsed: false,
                      visible: settings.moduleDisplayFields(module),
                      onOpenDisplaySettings: () =>
                          showModuleDisplaySettings(context, settings, module),
                      onToggleCollapse: () {},
                      onOpenRepair: (destination) {
                        expect(destination.mode, RepairCenterMode.dock);
                        onOpen();
                      },
                    )
                  : ConstructionSummaryCard(
                      controller: game,
                      collapsed: false,
                      visible: settings.moduleDisplayFields(module),
                      onOpenDisplaySettings: () =>
                          showModuleDisplaySettings(context, settings, module),
                      onToggleCollapse: () {},
                      onOpenConstruction: onOpen,
                    ),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  for (final module in ['repair', 'construction']) {
    testWidgets(
      '$module flat rows replace numbers with configurable portraits',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final settings = await LayoutSettingsController.load(
          SharedPreferencesLayoutSettingsStore(),
        );
        addTearDown(settings.dispose);
        final game = GameStateController(
          gameStateStore: _Store(_operationState()),
        );
        addTearDown(game.dispose);
        await game.initialize();
        var opened = false;
        await tester.pumpWidget(
          _app(
            module: module,
            game: game,
            settings: settings,
            onOpen: () => opened = true,
          ),
        );
        await tester.pumpAndSettle();

        final active = _slot(module, 2);
        expect(
          find.descendant(of: active, matching: find.text(_shipName)),
          findsOneWidget,
        );
        for (var id = 1; id <= 4; id++) {
          expect(
            find.descendant(of: _slot(module, id), matching: find.text('$id')),
            findsNothing,
          );
        }
        final portrait = find.descendant(
          of: active,
          matching: find.byType(ShipPortrait),
        );
        _expectPortraitBackdrop(tester, active);
        final originalRowSize = tester.getSize(_rowInSlot(tester, active));
        final originalNameRect = tester.getRect(
          find.descendant(of: active, matching: find.text(_shipName)),
        );
        expect(
          find.descendant(of: active, matching: find.text('01:00:00')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: active,
            matching: find.byType(OperationCountdownText),
          ),
          findsOneWidget,
        );
        await tester.tap(active);
        expect(opened, isTrue);

        await tester.tap(find.byKey(Key('$module-display-settings-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('$module-display-portrait')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('$module-display-close')));
        await tester.pumpAndSettle();
        expect(find.byType(ShipPortrait), findsNothing);
        expect(tester.getSize(_rowInSlot(tester, active)), originalRowSize);
        expect(
          tester.getRect(
            find.descendant(of: active, matching: find.text(_shipName)),
          ),
          originalNameRect,
        );
        expect(settings.moduleDisplayFields(module), {'empty'});
        final restored = await LayoutSettingsController.load(
          SharedPreferencesLayoutSettingsStore(),
        );
        addTearDown(restored.dispose);
        expect(restored.moduleDisplayFields(module), {'empty'});
        expect(
          find.descendant(of: active, matching: find.text(_shipName)),
          findsOneWidget,
        );
        await settings.setModuleDisplayFields(module, {'empty', 'portrait'});
        await tester.pump();
        expect(portrait, findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('$module empty and unknown slots preserve narrow layout', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final settings = await LayoutSettingsController.load(
        SharedPreferencesLayoutSettingsStore(),
      );
      addTearDown(settings.dispose);
      final game = GameStateController(
        gameStateStore: _Store(_operationState()),
      );
      addTearDown(game.dispose);
      await game.initialize();
      await tester.pumpWidget(
        _app(
          module: module,
          game: game,
          settings: settings,
          onOpen: () {},
          width: 190,
          textScaler: TextScaler.linear(1.5),
        ),
      );
      await tester.pumpAndSettle();

      for (final id in [1, 3, 4]) {
        final slot = _slot(module, id);
        expect(slot, findsOneWidget);
        expect(
          find.descendant(of: slot, matching: find.byType(ShipPortrait)),
          findsNothing,
        );
        if (id != 4) {
          final row = tester.widget<FlatListRow>(_rowInSlot(tester, slot));
          expect((row.name! as Text).data, isEmpty);
          expect(row.trailing, isNotNull);
        }
      }
      final active = _slot(module, 2);
      _expectPortraitBackdrop(tester, active);
      expect(
        find.descendant(of: active, matching: find.text(_shipName)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await settings.setModuleDisplayFields(module, {'portrait'});
      await tester.pumpAndSettle();
      expect(_slot(module, 1), findsNothing);
      expect(_slot(module, 3), findsNothing);
      expect(_slot(module, 2), findsOneWidget);
      expect(_slot(module, 4), findsOneWidget);
      expect(find.byType(ShipPortrait), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
