import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/fleet/operation_status_views.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/performance/second_tick_scope.dart';

GameState _expedition(DateTime end) => GameState(
  masterMissions: const {
    1: MasterMission(id: 1, name: '测试远征', duration: Duration(seconds: 4)),
  },
  fleets: [
    Fleet(
      id: 2,
      name: '第二舰队',
      mission: FleetMission(state: 1, missionId: 1, completionTime: end),
    ),
  ],
);

double? _progress(WidgetTester tester) => tester
    .widget<LinearProgressIndicator>(
      find.descendant(
        of: find.byKey(const Key('expedition-progress-2')),
        matching: find.byType(LinearProgressIndicator),
      ),
    )
    .value;

void main() {
  testWidgets('expedition progress completes from an old shared tick', (
    tester,
  ) async {
    final end = DateTime.now().toUtc().subtract(const Duration(minutes: 1));
    var now = end.subtract(const Duration(seconds: 2));
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: SecondTickScope(
            now: () => now,
            child: Scaffold(
              body: ExpeditionStatusView(state: _expedition(end)),
            ),
          ),
        ),
      );
      expect(_progress(tester), 0.5);

      now = end;
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('已完成'), findsOneWidget);
      expect(_progress(tester), 1);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('progress catches up after hidden completion and restarts', (
    tester,
  ) async {
    var now = DateTime.utc(2030);
    final end = now.add(const Duration(seconds: 4));
    final state = ValueNotifier(_expedition(end));
    final previousLifecycle = tester.binding.lifecycleState;
    try {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        MaterialApp(
          home: SecondTickScope(
            now: () => now,
            child: Scaffold(
              body: ValueListenableBuilder<GameState>(
                valueListenable: state,
                builder: (context, value, child) =>
                    ExpeditionStatusView(state: value),
              ),
            ),
          ),
        ),
      );
      expect(_progress(tester), 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      now = end.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(_progress(tester), 1);

      final nextEnd = now.add(const Duration(seconds: 4));
      state.value = _expedition(nextEnd);
      await tester.pump();
      expect(_progress(tester), 0);
      now = now.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      expect(_progress(tester), 0.5);
      now = nextEnd;
      await tester.pump(const Duration(seconds: 1));
      expect(_progress(tester), 1);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.handleAppLifecycleStateChanged(
        previousLifecycle ?? AppLifecycleState.resumed,
      );
      state.dispose();
    }
  });
}
