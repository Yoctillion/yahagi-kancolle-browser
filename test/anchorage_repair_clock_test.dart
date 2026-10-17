import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/fleet/anchorage_repair_view.dart';
import 'package:yahagi_kancolle_browser/src/fleet/repair_summary_card.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/performance/second_tick_scope.dart';

import 'anchorage_repair_calculator_test.dart' show buildAnchorageTestState;

void _resetLifecycleAfterTest(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  addTearDown(() {
    tester.binding.resetInternalState();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
}

GameStateController _controller(DateTime anchor) {
  final state = buildAnchorageTestState(facilities: 3);
  final controller = GameStateController(
    initialState: state.copyWith(
      fleets: [
        ...state.fleets,
        const Fleet(id: 2, name: '第二舰队'),
      ],
    ),
  );
  controller.akashiTimer.reset(anchor);
  addTearDown(controller.dispose);
  return controller;
}

Finder _remaining(bool summary, String text) => find.descendant(
  of: find.byKey(
    Key(summary ? 'repair-summary-anchorage-slot-1' : 'anchorage-repair-row-2'),
  ),
  matching: find.text(text),
);

Widget _summary(GameStateController controller, {bool collapsed = false}) =>
    RepairSummaryCard(
      controller: controller,
      collapsed: collapsed,
      visible: const {'empty'},
      onToggleCollapse: () {},
      onOpenRepair: (_) {},
    );

void main() {
  for (final summary in [false, true]) {
    testWidgets(
      'anchorage ${summary ? 'summary' : 'detail'} ticks while inactive and catches up without resetting anchor',
      (tester) async {
        _resetLifecycleAfterTest(tester);
        final anchor = DateTime.utc(2030);
        var now = anchor.add(const Duration(minutes: 10));
        final controller = _controller(anchor);
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: SecondTickScope(
                now: () => now,
                child: Scaffold(
                  body: summary
                      ? _summary(controller)
                      : RepairCenterView(
                          controller: controller,
                          mode: RepairCenterMode.anchorage,
                        ),
                ),
              ),
            ),
          );
          if (summary) {
            await tester.tap(
              find.byKey(const Key('repair-summary-mode-anchorage')),
            );
            await tester.pump();
          }
          expect(_remaining(summary, '00:50:00'), findsOneWidget);

          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          now = now.add(const Duration(seconds: 1));
          await tester.pump(const Duration(seconds: 1));
          expect(_remaining(summary, '00:49:59'), findsOneWidget);

          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          now = now.add(const Duration(minutes: 5));
          await tester.pump(const Duration(minutes: 5));
          expect(_remaining(summary, '00:49:59'), findsOneWidget);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await tester.pump();
          expect(_remaining(summary, '00:44:59'), findsOneWidget);
          expect(controller.anchorageRepairStartedAt, anchor);

          await tester.tap(
            find.byKey(
              Key(summary ? 'repair-summary-fleet-2' : 'fleet-button-2'),
            ),
          );
          await tester.pump();
          await tester.tap(
            find.byKey(
              Key(summary ? 'repair-summary-fleet-1' : 'fleet-button-1'),
            ),
          );
          await tester.pump();
          expect(_remaining(summary, '00:44:59'), findsOneWidget);
          expect(controller.anchorageRepairStartedAt, anchor);

          now = anchor.add(const Duration(hours: 1));
          await tester.pump(const Duration(seconds: 1));
          expect(_remaining(summary, '00:00:00'), findsOneWidget);
          now = now.add(const Duration(seconds: 1));
          await tester.pump(const Duration(seconds: 1));
          expect(_remaining(summary, '00:00:00'), findsOneWidget);
          if (!summary) {
            expect(
              find.descendant(
                of: find.byKey(const Key('anchorage-summary-elapsed')),
                matching: find.text('01:00:01'),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: find.byKey(const Key('anchorage-repair-row-2')),
                matching: find.text('正在修理中'),
              ),
              findsOneWidget,
            );
          }
          expect(controller.anchorageRepairStartedAt, anchor);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );
  }

  testWidgets(
    'collapsed anchorage summary resumes at the current elapsed time',
    (tester) async {
      _resetLifecycleAfterTest(tester);
      final anchor = DateTime.utc(2030);
      var now = anchor.add(const Duration(minutes: 10));
      final collapsed = ValueNotifier<bool>(false);
      addTearDown(collapsed.dispose);
      final controller = _controller(anchor);
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: SecondTickScope(
              now: () => now,
              child: Scaffold(
                body: ValueListenableBuilder<bool>(
                  valueListenable: collapsed,
                  builder: (context, value, child) =>
                      _summary(controller, collapsed: value),
                ),
              ),
            ),
          ),
        );
        await tester.tap(
          find.byKey(const Key('repair-summary-mode-anchorage')),
        );
        await tester.pump();
        expect(_remaining(true, '00:50:00'), findsOneWidget);

        collapsed.value = true;
        await tester.pump();
        now = now.add(const Duration(minutes: 5));
        await tester.pump(const Duration(minutes: 5));
        expect(
          find.byKey(const Key('repair-summary-anchorage-slot-1')),
          findsNothing,
        );

        collapsed.value = false;
        await tester.pump();
        expect(_remaining(true, '00:45:00'), findsOneWidget);
        expect(controller.anchorageRepairStartedAt, anchor);
        now = now.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        expect(_remaining(true, '00:44:59'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets('changing repair modes preserves the anchorage timer', (
    tester,
  ) async {
    _resetLifecycleAfterTest(tester);
    final anchor = DateTime.utc(2030);
    var now = anchor.add(const Duration(minutes: 10));
    final controller = _controller(anchor);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: SecondTickScope(
            now: () => now,
            child: Scaffold(body: RepairCenterView(controller: controller)),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('repair-mode-anchorage')));
      await tester.pump();
      expect(_remaining(false, '00:50:00'), findsOneWidget);

      await tester.tap(find.byKey(const Key('repair-mode-dock')));
      await tester.pump();
      now = now.add(const Duration(minutes: 5));
      await tester.pump(const Duration(minutes: 5));
      await tester.tap(find.byKey(const Key('repair-mode-anchorage')));
      await tester.pump();
      expect(_remaining(false, '00:45:00'), findsOneWidget);
      expect(controller.anchorageRepairStartedAt, anchor);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
