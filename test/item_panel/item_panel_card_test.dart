import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/item_panel/item_panel_card.dart';
import 'package:yahagi_kancolle_browser/src/settings/item_panel_settings.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_store.dart';

import '../fixtures/kcsapi_fixtures.dart';

void main() {
  late bool previousTimerSetting;

  setUp(() {
    previousTimerSetting = GameStateController.disableTimerForTest;
    GameStateController.disableTimerForTest = true;
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });
  tearDown(() {
    GameStateController.disableTimerForTest = previousTimerSetting;
  });

  Future<GameStateController> seededController(WidgetTester tester) async {
    final controller = GameStateController();
    addTearDown(controller.dispose);
    await tester.runAsync(() async {
      await controller.initialize();
      controller.accept(
        kcsapiEvent('/kcsapi/api_get_member/useitem', <Object?>[
          <String, Object?>{'api_id': 57, 'api_count': 43},
        ]),
      );
      await controller.idle;
    });
    return controller;
  }

  Widget app(
    GameStateController controller, {
    bool collapsed = false,
    VoidCallback? onOpenDisplaySettings,
  }) => MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: ItemPanelCard(
          controller: controller,
          mode: ItemPanelMode.compact,
          collapsed: collapsed,
          onToggleCollapse: () {},
          onOpenDisplaySettings: onOpenDisplaySettings,
        ),
      ),
    ),
  );

  testWidgets('shows the title and items', (tester) async {
    final controller = await seededController(tester);
    await tester.pumpWidget(app(controller));
    await tester.pump();

    expect(find.text('道具'), findsOneWidget);
    expect(find.byKey(const Key('item-cell-57')), findsOneWidget);
  });

  testWidgets('collapsed card hides the items', (tester) async {
    final controller = await seededController(tester);
    await tester.pumpWidget(app(controller, collapsed: true));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('item-cell-57')), findsNothing);
  });

  testWidgets('settings gear appears only while editing', (tester) async {
    final controller = await seededController(tester);
    await tester.pumpWidget(app(controller));
    await tester.pump();
    expect(
      find.byKey(const Key('items-display-settings-button')),
      findsNothing,
    );

    await tester.pumpWidget(app(controller, onOpenDisplaySettings: () {}));
    await tester.pump();
    expect(
      find.byKey(const Key('items-display-settings-button')),
      findsOneWidget,
    );
  });

  test('saved layouts gain the items card', () async {
    final store = SharedPreferencesLayoutSettingsStore();
    await store.saveDashboardCardOrder(['smart', 'fleet', 'battle']);

    final order = await store.loadDashboardCardOrder();

    expect(order, contains('items'));
    expect(order.indexOf('smart'), lessThan(order.indexOf('fleet')));
    expect(order.indexOf('fleet'), lessThan(order.indexOf('battle')));
  });
}
