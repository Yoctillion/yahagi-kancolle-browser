import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/detailed_battle_panel.dart';
import 'package:yahagi_kancolle_browser/src/battle/live_battle_card.dart';
import 'package:yahagi_kancolle_browser/src/battle/prediction/battle_prediction_executor.dart';
import 'package:yahagi_kancolle_browser/src/fleet/dashboard_card.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_reducer.dart';
import 'package:yahagi_kancolle_browser/src/layout/panel_style.dart';

import 'fixtures/kcsapi_fixtures.dart';

Widget _app(Widget child, {PageStorageBucket? bucket}) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: PageStorage(
    bucket: bucket ?? PageStorageBucket(),
    child: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

DashboardCard _card({bool collapsed = false}) => DashboardCard(
  title: '卡片标题',
  icon: const Icon(Icons.explore_outlined),
  collapsed: collapsed,
  onToggleCollapse: () {},
  titleBadge: const Text('徽章'),
  trailing: const Text('切换器'),
  headerAction: const Text('齿轮'),
  child: const Text('正文'),
);

void main() {
  for (final style in PanelStyle.values) {
    testWidgets('embedded card keeps only badge, trailing and body ($style)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          PanelStyleScope(
            style: style,
            child: DashboardCardEmbedScope(child: _card(collapsed: true)),
          ),
        ),
      );
      expect(find.text('卡片标题'), findsNothing);
      expect(find.text('齿轮'), findsNothing);
      expect(find.byKey(const Key('dashboard-card-header')), findsNothing);
      expect(find.byIcon(Icons.explore_outlined), findsNothing);
      expect(find.text('徽章'), findsOneWidget);
      expect(find.text('切换器'), findsOneWidget);
      expect(find.text('正文'), findsOneWidget);
    });
  }

  testWidgets('cards outside the embed scope keep their header', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_card()));
    expect(find.text('卡片标题'), findsOneWidget);
    expect(find.text('齿轮'), findsOneWidget);
  });

  group('embedded LiveBattleCard', () {
    final reducer = GameStateReducer();
    late GameState state;
    late BattleController controller;

    setUp(() async {
      state = reducer.reduce(GameState.empty, start2Event);
      state = reducer.reduce(state, portEvent);
      controller = BattleController(
        gameState: () => state,
        predictionExecutor: const ImmediateBattlePredictionExecutor(),
      );
      for (final event in [mapStartEvent, dayBattleEvent]) {
        state = reducer.reduce(state, event);
        controller.accept(event);
        await controller.idle;
      }
    });

    tearDown(() => controller.dispose());

    for (final style in PanelStyle.values) {
      testWidgets('keeps the compact/detailed switch ($style)', (tester) async {
        await tester.pumpWidget(
          _app(
            PanelStyleScope(
              style: style,
              child: DashboardCardEmbedScope(
                child: LiveBattleCard(
                  key: const PageStorageKey('embedded-battle'),
                  controller: controller,
                  collapsed: false,
                  onToggleCollapse: () {},
                ),
              ),
            ),
          ),
        );
        expect(find.byType(DetailedBattlePanel), findsOneWidget);
        await tester.tap(find.byKey(const Key('battle-mode-compact')));
        await tester.pump();
        expect(find.byType(DetailedBattlePanel), findsNothing);
        await tester.tap(find.byKey(const Key('battle-mode-detailed')));
        await tester.pump();
        expect(find.byType(DetailedBattlePanel), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
