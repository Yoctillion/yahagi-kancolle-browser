import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/fleet/operation_progress.dart';
import 'package:yahagi_kancolle_browser/src/fleet/operation_status_views.dart';
import 'package:yahagi_kancolle_browser/src/fleet/repair_summary_card.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/performance/second_tick_scope.dart';

import 'fixtures/kcsapi_fixtures.dart';

void _prepare(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(() {
    tester.binding.resetInternalState();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
}

Future<GameStateController> _controllerWithRepair(DateTime end) async {
  final controller = GameStateController();
  addTearDown(controller.dispose);
  controller
    ..accept(start2Event)
    ..accept(portEvent)
    ..accept(
      kcsapiEvent('/kcsapi/api_get_member/ship2', [
        {
          'api_id': 9002,
          'api_ship_id': 102,
          'api_nowhp': 8,
          'api_ndock_time': 10000,
        },
      ]),
    )
    ..accept(
      kcsapiEvent('/kcsapi/api_get_member/ndock', [
        {
          'api_id': 1,
          'api_state': 1,
          'api_ship_id': 9002,
          'api_complete_time': end.millisecondsSinceEpoch,
        },
      ]),
    );
  await controller.idle;
  expect(controller.state.ships[9002]!.repairDurationMilliseconds, 10000);
  return controller;
}

Widget _views(GameStateController controller, {bool collapsed = false}) =>
    Scaffold(
      body: Column(
        children: [
          RepairSummaryCard(
            controller: controller,
            collapsed: collapsed,
            visible: const {'empty'},
            onToggleCollapse: () {},
            onOpenRepair: (_) {},
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) =>
                  RepairDockStatusView(state: controller.state),
            ),
          ),
        ],
      ),
    );

Finder get _summarySlot => find.byKey(const Key('repair-summary-dock-slot-1'));
Finder get _detailRow => find.byKey(const Key('repair-dock-row-1'));

void _expectCountdown(String text) {
  for (final parent in [_summarySlot, _detailRow]) {
    expect(
      find.descendant(of: parent, matching: find.text(text)),
      findsOneWidget,
    );
  }
}

void _expectExpired() {
  expect(find.byType(OperationCountdownText), findsNothing);
  expect(find.byKey(const Key('repair-portrait-1')), findsNothing);
  expect(
    find.descendant(of: _detailRow, matching: find.text('未入渠')),
    findsOneWidget,
  );
}

double _progress(WidgetTester tester) => tester
    .widget<LinearProgressIndicator>(
      find.descendant(
        of: find.byKey(const Key('repair-progress-1')),
        matching: find.byType(LinearProgressIndicator),
      ),
    )
    .value!;

void main() {
  testWidgets('inactive dock summary and detail advance without API events', (
    tester,
  ) async {
    _prepare(tester);
    // A deliberately different wall clock exposes mixed clock decisions.
    var now = DateTime.utc(2000);
    final end = now.add(const Duration(seconds: 10));
    final controller = await _controllerWithRepair(end);
    final capturedState = controller.state;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: SecondTickScope(now: () => now, child: _views(controller)),
        ),
      );
      _expectCountdown('00:00:10');
      expect(_progress(tester), 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      now = now.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      _expectCountdown('00:00:08');
      expect(_progress(tester), closeTo(0.2, 0.001));
      expect(controller.state, same(capturedState));

      now = end;
      await tester.pump(const Duration(seconds: 8));
      _expectExpired();
      expect(controller.state, same(capturedState));
      expect(controller.state.repairDocks.single.isRepairing, isTrue);
      expect(controller.state.ships[9002]!.currentHp, 8);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  for (final backgroundState in [
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  ]) {
    testWidgets('dock views catch up after $backgroundState crosses deadline', (
      tester,
    ) async {
      _prepare(tester);
      var now = DateTime.utc(2000);
      final end = now.add(const Duration(seconds: 5));
      final controller = await _controllerWithRepair(end);
      final capturedState = controller.state;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: SecondTickScope(now: () => now, child: _views(controller)),
          ),
        );
        _expectCountdown('00:00:05');

        tester.binding.handleAppLifecycleStateChanged(backgroundState);
        now = end.add(const Duration(seconds: 15));
        await tester.pump(const Duration(seconds: 20));
        _expectCountdown('00:00:05');

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        _expectExpired();
        expect(controller.state, same(capturedState));
        expect(controller.state.ships[9002]!.currentHp, 8);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }

  testWidgets('dock views catch up after ticker mode crosses deadline', (
    tester,
  ) async {
    _prepare(tester);
    var now = DateTime.utc(2000);
    final end = now.add(const Duration(seconds: 5));
    final controller = await _controllerWithRepair(end);
    final capturedState = controller.state;
    final visible = ValueNotifier<bool>(true);
    addTearDown(visible.dispose);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: SecondTickScope(
            now: () => now,
            child: ValueListenableBuilder<bool>(
              valueListenable: visible,
              child: _views(controller),
              builder: (context, enabled, child) =>
                  TickerMode(enabled: enabled, child: child!),
            ),
          ),
        ),
      );
      _expectCountdown('00:00:05');
      visible.value = false;
      await tester.pump();
      now = end.add(const Duration(seconds: 15));
      await tester.pump(const Duration(seconds: 20));
      _expectCountdown('00:00:05');

      visible.value = true;
      await tester.pump();
      _expectExpired();
      expect(controller.state, same(capturedState));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('collapsed dock summary clears its cached repair on expansion', (
    tester,
  ) async {
    _prepare(tester);
    var now = DateTime.utc(2000);
    final end = now.add(const Duration(seconds: 5));
    final controller = await _controllerWithRepair(end);
    final capturedState = controller.state;
    final collapsed = ValueNotifier<bool>(false);
    addTearDown(collapsed.dispose);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: SecondTickScope(
            now: () => now,
            child: ValueListenableBuilder<bool>(
              valueListenable: collapsed,
              builder: (context, value, _) =>
                  _views(controller, collapsed: value),
            ),
          ),
        ),
      );
      _expectCountdown('00:00:05');
      collapsed.value = true;
      await tester.pump();
      now = end;
      await tester.pump(const Duration(seconds: 5));
      collapsed.value = false;
      await tester.pump();
      _expectExpired();
      expect(controller.state, same(capturedState));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
    'same active dock refreshes its cache and accepts a later repair',
    (tester) async {
      _prepare(tester);
      var now = DateTime.utc(2000);
      final controller = await _controllerWithRepair(
        now.add(const Duration(seconds: 5)),
      );
      Future<void> replace(DateTime end) async {
        controller.accept(
          kcsapiEvent('/kcsapi/api_get_member/ndock', [
            {
              'api_id': 1,
              'api_state': 1,
              'api_ship_id': 9002,
              'api_complete_time': end.millisecondsSinceEpoch,
            },
          ]),
        );
        await controller.idle;
        await tester.pump();
      }

      try {
        await tester.pumpWidget(
          MaterialApp(
            home: SecondTickScope(now: () => now, child: _views(controller)),
          ),
        );
        _expectCountdown('00:00:05');
        final secondEnd = now.add(const Duration(seconds: 10));
        await replace(secondEnd);
        _expectCountdown('00:00:10');
        now = now.add(const Duration(seconds: 6));
        await tester.pump(const Duration(seconds: 6));
        _expectCountdown('00:00:04');
        expect(_progress(tester), closeTo(0.6, 0.001));

        now = secondEnd;
        await tester.pump(const Duration(seconds: 4));
        _expectExpired();

        final thirdEnd = now.add(const Duration(seconds: 10));
        await replace(thirdEnd);
        _expectCountdown('00:00:10');
        expect(_progress(tester), 0);
        now = thirdEnd;
        await tester.pump(const Duration(seconds: 10));
        _expectExpired();
        expect(controller.state.repairDocks.single.isRepairing, isTrue);
        expect(controller.state.ships[9002]!.currentHp, 8);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
