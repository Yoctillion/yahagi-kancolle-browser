import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/fleet/construction_summary_card.dart';
import 'package:yahagi_kancolle_browser/src/fleet/operation_progress.dart';
import 'package:yahagi_kancolle_browser/src/fleet/operation_status_views.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/performance/second_tick_scope.dart';

import 'fixtures/kcsapi_fixtures.dart';

void main() {
  testWidgets(
    'server-completed construction summary needs no completion timestamp',
    (tester) async {
      final now = DateTime.now().toUtc();
      final controller = GameStateController(
        initialState: _state(null, dockState: 3),
      );
      await controller.idle;

      try {
        await tester.pumpWidget(_host(() => now, _summary(controller)));
        expect(_dotColor(tester), const Color(0xff4caf50));
        expect(find.text('已完成'), findsOneWidget);
        expect(find.byType(OperationCountdownText), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    },
  );

  testWidgets(
    'server-completed construction summary ignores a future timestamp',
    (tester) async {
      var now = DateTime.now().toUtc();
      final controller = GameStateController(
        initialState: _state(now.add(const Duration(hours: 1)), dockState: 3),
      );
      await controller.idle;

      try {
        await tester.pumpWidget(_host(() => now, _summary(controller)));
        expect(_dotColor(tester), const Color(0xff4caf50));
        expect(find.text('已完成'), findsOneWidget);
        expect(find.byType(OperationCountdownText), findsNothing);

        now = now.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('已完成'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    },
  );

  testWidgets(
    'construction summary dot completes without a captured API event',
    (tester) async {
      final completion = DateTime.now().toUtc().add(const Duration(hours: 1));
      var now = completion.subtract(const Duration(seconds: 2));
      final controller = GameStateController(initialState: _state(completion));
      await controller.idle;

      try {
        await tester.pumpWidget(_host(() => now, _summary(controller)));
        expect(_dotColor(tester), const Color(0xffffc940));

        now = completion;
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('已完成'), findsOneWidget);
        expect(_dotColor(tester), const Color(0xff4caf50));
        expect(controller.state.constructionDocks.single.state, 2);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    },
  );

  testWidgets('construction details complete without a captured API event', (
    tester,
  ) async {
    final completion = DateTime.now().toUtc().add(const Duration(hours: 1));
    var now = completion.subtract(const Duration(seconds: 2));
    final state = _state(completion);

    try {
      await tester.pumpWidget(
        _host(() => now, ConstructionDockStatusView(state: state)),
      );
      expect(find.byType(OperationCountdownText), findsOneWidget);

      now = completion;
      await tester.pump(const Duration(seconds: 1));
      expect(_progress(tester), 1);
      expect(find.text('建造完成'), findsOneWidget);
      expect(find.byType(OperationCountdownText), findsNothing);
      expect(state.constructionDocks.single.state, 2);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
    'unknown construction duration becomes complete on its deadline',
    (tester) async {
      final completion = DateTime.now().toUtc().add(const Duration(hours: 1));
      var now = completion.subtract(const Duration(seconds: 2));
      final state = _state(completion, hasDuration: false);

      try {
        await tester.pumpWidget(
          _host(() => now, ConstructionDockStatusView(state: state)),
        );
        expect(find.text('进度未知'), findsOneWidget);

        now = completion;
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('建造完成'), findsOneWidget);
        expect(find.text('进度未知'), findsNothing);
        expect(_progress(tester), 1);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets('construction summary catches up after the app was hidden', (
    tester,
  ) async {
    final previousLifecycle = tester.binding.lifecycleState;
    final completion = DateTime.now().toUtc().add(const Duration(hours: 1));
    var now = completion.subtract(const Duration(seconds: 2));
    final controller = GameStateController(initialState: _state(completion));
    await controller.idle;

    try {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(_host(() => now, _summary(controller)));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      now = completion.add(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('已完成'), findsOneWidget);
      expect(_dotColor(tester), const Color(0xff4caf50));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.handleAppLifecycleStateChanged(
        previousLifecycle ?? AppLifecycleState.resumed,
      );
      controller.dispose();
    }
  });

  testWidgets('construction details catch up after the app was hidden', (
    tester,
  ) async {
    final previousLifecycle = tester.binding.lifecycleState;
    final completion = DateTime.now().toUtc().add(const Duration(hours: 1));
    var now = completion.subtract(const Duration(seconds: 2));

    try {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        _host(() => now, ConstructionDockStatusView(state: _state(completion))),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      now = completion.add(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(_progress(tester), 1);
      expect(find.text('建造完成'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.handleAppLifecycleStateChanged(
        previousLifecycle ?? AppLifecycleState.resumed,
      );
    }
  });

  testWidgets(
    'a reused construction dock resumes countdown and progress ticks',
    (tester) async {
      var now = DateTime.fromMillisecondsSinceEpoch(
        DateTime.now().millisecondsSinceEpoch,
        isUtc: true,
      ).add(const Duration(hours: 1));
      final previousCompletion = now.subtract(const Duration(minutes: 1));
      final controller = GameStateController(
        initialState: _state(previousCompletion, dockState: 3),
      );
      await controller.idle;

      try {
        await tester.pumpWidget(
          _host(
            () => now,
            Column(
              children: [
                _summary(controller),
                Expanded(
                  child: AnimatedBuilder(
                    animation: controller,
                    builder: (context, _) =>
                        ConstructionDockStatusView(state: controller.state),
                  ),
                ),
              ],
            ),
          ),
        );
        expect(_dotColor(tester), const Color(0xff4caf50));
        expect(find.text('建造完成'), findsOneWidget);

        final nextCompletion = now.add(const Duration(minutes: 1));
        controller.accept(
          kcsapiEvent('/kcsapi/api_get_member/kdock', [
            {
              'api_id': 1,
              'api_state': 2,
              'api_created_ship_id': 101,
              'api_complete_time': nextCompletion.millisecondsSinceEpoch,
            },
          ]),
        );
        await controller.idle;
        await tester.pump();
        await tester.pump();
        expect(_dotColor(tester), const Color(0xffffc940));
        expect(find.text('建造完成'), findsNothing);
        expect(find.text('00:01:00'), findsNWidgets(2));

        final progressBeforeTick = _progress(tester)!;
        now = now.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('00:00:59'), findsNWidgets(2));
        expect(_progress(tester), greaterThan(progressBeforeTick));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    },
  );
}

GameState _state(
  DateTime? completion, {
  int dockState = 2,
  bool hasDuration = true,
}) {
  return GameState(
    masterShips: {
      101: MasterShip(
        id: 101,
        name: '测试建造舰',
        shipTypeId: 2,
        buildTimeMinutes: hasDuration ? 2 : 0,
      ),
    },
    constructionDocks: [
      ConstructionDock(
        id: 1,
        state: dockState,
        createdShipMasterId: 101,
        completionTime: completion,
      ),
    ],
  );
}

Widget _summary(GameStateController controller) {
  return ConstructionSummaryCard(
    controller: controller,
    collapsed: false,
    visible: const {'empty'},
    onToggleCollapse: () {},
    onOpenConstruction: () {},
  );
}

Widget _host(DateTime Function() now, Widget child) {
  return MaterialApp(
    home: SecondTickScope(
      now: now,
      child: Scaffold(body: child),
    ),
  );
}

Color? _dotColor(WidgetTester tester) {
  final dot = tester.widget<Container>(
    find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          (widget.decoration as BoxDecoration?)?.shape == BoxShape.circle,
    ),
  );
  return (dot.decoration! as BoxDecoration).color;
}

double? _progress(WidgetTester tester) {
  return tester
      .widget<LinearProgressIndicator>(
        find.descendant(
          of: find.byKey(const Key('construction-progress-1')),
          matching: find.byType(LinearProgressIndicator),
        ),
      )
      .value;
}
