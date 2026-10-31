import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/item_panel/item_panel_view.dart';
import 'package:yahagi_kancolle_browser/src/layout/panel_style.dart';
import 'package:yahagi_kancolle_browser/src/settings/item_panel_settings.dart';

import '../fixtures/kcsapi_fixtures.dart';

void main() {
  late bool previousTimerSetting;

  setUp(() {
    previousTimerSetting = GameStateController.disableTimerForTest;
    GameStateController.disableTimerForTest = true;
  });
  tearDown(() {
    GameStateController.disableTimerForTest = previousTimerSetting;
  });

  Future<GameStateController> controllerWith(
    WidgetTester tester,
    Map<int, int>? useItems,
  ) async {
    final controller = GameStateController();
    addTearDown(controller.dispose);
    await tester.runAsync(() async {
      await controller.initialize();
      if (useItems == null) return;
      controller.accept(
        kcsapiEvent('/kcsapi/api_get_member/useitem', <Object?>[
          for (final entry in useItems.entries)
            <String, Object?>{'api_id': entry.key, 'api_count': entry.value},
        ]),
      );
      await controller.idle;
    });
    return controller;
  }

  Widget app(
    GameStateController controller,
    ItemPanelMode mode, {
    Locale locale = const Locale('zh'),
    double width = 320,
    PanelStyle style = PanelStyle.card,
    VoidCallback? onLongPress,
  }) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: SizedBox(
            width: width,
            child: PanelStyleScope(
              style: style,
              child: GestureDetector(
                onLongPress: onLongPress,
                child: ItemPanelView(controller: controller, mode: mode),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('compact shows no item names until tapped', (tester) async {
    final controller = await controllerWith(tester, {57: 43});
    await tester.pumpWidget(app(controller, ItemPanelMode.compact));
    await tester.pump();

    expect(find.text('勋章'), findsNothing);
    expect(find.text('43'), findsOneWidget);

    await tester.tap(find.byKey(const Key('item-cell-57')));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('勋章'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('detailed shows names and counts', (tester) async {
    final controller = await controllerWith(tester, {57: 43});
    await tester.pumpWidget(app(controller, ItemPanelMode.detailed));
    await tester.pump();

    expect(find.text('勋章'), findsOneWidget);
    expect(find.text('43'), findsOneWidget);
  });

  testWidgets('zero items are dimmed', (tester) async {
    final controller = await controllerWith(tester, {57: 43});
    for (final mode in ItemPanelMode.values) {
      await tester.pumpWidget(app(controller, mode));
      await tester.pump();

      Finder opacityIn(int id) => find.descendant(
        of: find.byKey(Key('item-cell-$id')),
        matching: find.byType(Opacity),
      );
      expect(opacityIn(57), findsNothing, reason: mode.name);
      expect(opacityIn(61), findsOneWidget, reason: mode.name);
      expect(
        tester.widget<Opacity>(opacityIn(61)).opacity,
        lessThan(1),
        reason: mode.name,
      );
    }
  });

  testWidgets('seasonal group hides when all zero', (tester) async {
    final controller = await controllerWith(tester, {57: 43});
    await tester.pumpWidget(app(controller, ItemPanelMode.compact));
    await tester.pump();

    expect(find.byKey(const Key('item-group-seasonal')), findsNothing);
    expect(find.text('活动限定'), findsNothing);
    expect(find.byKey(const Key('item-group-reward')), findsOneWidget);
  });

  testWidgets('seasonal group shows owned items only', (tester) async {
    final controller = await controllerWith(tester, {96: 12});
    await tester.pumpWidget(app(controller, ItemPanelMode.compact));
    await tester.pump();

    expect(find.text('活动限定'), findsOneWidget);
    expect(find.byKey(const Key('item-cell-96')), findsOneWidget);
    expect(find.byKey(const Key('item-cell-68')), findsNothing);
  });

  testWidgets('shows waiting text without data', (tester) async {
    final controller = await controllerWith(tester, null);
    await tester.pumpWidget(app(controller, ItemPanelMode.compact));
    await tester.pump();

    expect(find.text('等待数据'), findsOneWidget);
    expect(find.byKey(const Key('item-cell-57')), findsNothing);
  });

  testWidgets('long press still reaches the parent', (tester) async {
    final controller = await controllerWith(tester, {57: 43});
    for (final mode in ItemPanelMode.values) {
      var longPresses = 0;
      await tester.pumpWidget(
        app(controller, mode, onLongPress: () => longPresses++),
      );
      await tester.pump();

      await tester.longPress(find.byKey(const Key('item-cell-57')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(longPresses, 1, reason: mode.name);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('narrow panel does not overflow', (tester) async {
    final controller = await controllerWith(tester, {10: 9999, 57: 9999});
    for (final mode in ItemPanelMode.values) {
      await tester.pumpWidget(app(controller, mode, width: 200));
      await tester.pump();

      expect(tester.takeException(), isNull, reason: mode.name);
      expect(find.text('9999'), findsNWidgets(2), reason: mode.name);
      final cell = tester.getRect(find.byKey(const Key('item-cell-57')));
      final count = tester.getRect(find.text('9999').first);
      expect(count.width, lessThanOrEqualTo(cell.width), reason: mode.name);
    }
  });

  testWidgets('flat style renders both views', (tester) async {
    final controller = await controllerWith(tester, {57: 43});
    for (final mode in ItemPanelMode.values) {
      await tester.pumpWidget(app(controller, mode, style: PanelStyle.flat));
      await tester.pump();

      expect(tester.takeException(), isNull, reason: mode.name);
      expect(find.byKey(const Key('item-cell-57')), findsOneWidget);
    }
  });

  testWidgets('names follow the locale', (tester) async {
    final controller = await controllerWith(tester, {57: 43});
    await tester.pumpWidget(app(controller, ItemPanelMode.detailed));
    await tester.pump();
    expect(find.text('勋章'), findsOneWidget);

    await tester.pumpWidget(
      app(controller, ItemPanelMode.detailed, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Medals'), findsOneWidget);
    expect(find.text('勋章'), findsNothing);
  });

  testWidgets('live useitem responses update the panel', (tester) async {
    final controller = await controllerWith(tester, {57: 43});
    await tester.pumpWidget(app(controller, ItemPanelMode.compact));
    await tester.pump();

    await tester.runAsync(() async {
      controller.accept(
        kcsapiEvent('/kcsapi/api_get_member/useitem', <Object?>[
          <String, Object?>{'api_id': 57, 'api_count': 44},
        ], sequence: 2),
      );
      await controller.idle;
    });
    await tester.pump();

    expect(find.text('44'), findsOneWidget);
  });
}
