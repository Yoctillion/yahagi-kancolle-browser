import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/fleet/construction_summary_card.dart';
import 'package:yahagi_kancolle_browser/src/fleet/dashboard_card.dart';
import 'package:yahagi_kancolle_browser/src/fleet/expedition_summary_card.dart';
import 'package:yahagi_kancolle_browser/src/fleet/fleet_summary_card.dart';
import 'package:yahagi_kancolle_browser/src/fleet/global_game_timer.dart';
import 'package:yahagi_kancolle_browser/src/fleet/morale_recovery_timer_controller.dart';
import 'package:yahagi_kancolle_browser/src/fleet/operation_progress.dart';
import 'package:yahagi_kancolle_browser/src/fleet/repair_summary_card.dart';
import 'package:yahagi_kancolle_browser/src/fleet/timer_mechanics_service.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/layout/panel_style.dart';
import 'package:yahagi_kancolle_browser/src/notification/notification_timer_anchor_store.dart';
import 'package:yahagi_kancolle_browser/src/performance/second_tick_scope.dart';
import 'package:yahagi_kancolle_browser/src/settings/battle_status_effect_settings.dart';

import 'fixtures/fleet_display_sample.dart';
import 'fixtures/kcsapi_fixtures.dart';

class _Clock {
  DateTime value = DateTime.utc(2030);

  DateTime now() => value;

  Future<void> advance(WidgetTester tester, [int seconds = 1]) async {
    for (var i = 0; i < seconds; i++) {
      value = value.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }
  }
}

class _DashboardBuildCounter {
  _DashboardBuildCounter() {
    _previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = _record;
  }

  late final void Function(Element, bool)? _previous;
  var builds = 0;

  void _record(Element element, bool builtOnce) {
    _previous?.call(element, builtOnce);
    if (element.widget is DashboardCard) builds++;
  }

  void dispose() => debugOnRebuildDirtyWidget = _previous;
}

Widget _host(
  _Clock clock,
  Widget child, {
  PanelStyle style = PanelStyle.flat,
}) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: SecondTickScope(
    now: clock.now,
    child: Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(
          width: 360,
          child: PanelStyleScope(style: style, child: child),
        ),
      ),
    ),
  ),
);

Future<GameStateController> _controller(GameState state) async {
  final controller = GameStateController(initialState: state);
  await controller.initialize();
  return controller;
}

FleetSummaryCard _fleet(
  GameStateController controller, {
  Set<String> visible = const {'minimum-condition'},
  MoraleRecoveryTimerController? recovery,
}) => FleetSummaryCard(
  controller: controller,
  collapsed: false,
  visible: visible,
  moraleRecoveryTimerController: recovery,
  damagePulseFilter: DamagePulseFilter.off,
  moraleSparkleMode: MoraleSparkleMode.off,
  onToggleCollapse: () {},
  onOpenFleet: (_) {},
);

GameState _nosakiState() {
  final state = demoState();
  return state.copyWith(
    masterShips: {
      ...state.masterShips,
      1002: const MasterShip(
        id: 1002,
        name: '野埼改',
        shipTypeId: 16,
        maxFuel: 40,
        maxAmmo: 45,
      ),
    },
    ships: {
      ...state.ships,
      1: const OwnedShip(
        id: 1,
        masterId: 1002,
        level: 85,
        currentHp: 49,
        maxHp: 49,
        currentFuel: 40,
        currentAmmo: 45,
        condition: 85,
      ),
    },
  );
}

void main() {
  for (final module in ['repair', 'expedition', 'construction']) {
    testWidgets('minimal collapsed $module has zero clock-driven card builds', (
      tester,
    ) async {
      final clock = _Clock();
      final controller = await _controller(demoState());
      addTearDown(controller.dispose);
      final card = switch (module) {
        'repair' => RepairSummaryCard(
          controller: controller,
          collapsed: true,
          onToggleCollapse: () {},
          onOpenRepair: (_) {},
        ),
        'expedition' => ExpeditionSummaryCard(
          controller: controller,
          collapsed: true,
          onToggleCollapse: () {},
          onOpenExpedition: () {},
          onOpenExpeditionCheck: (_) {},
        ),
        _ => ConstructionSummaryCard(
          controller: controller,
          collapsed: true,
          onToggleCollapse: () {},
          onOpenConstruction: () {},
        ),
      };
      final counter = _DashboardBuildCounter();
      addTearDown(counter.dispose);
      await tester.pumpWidget(_host(clock, card));
      await tester.pumpAndSettle();
      counter.builds = 0;
      await clock.advance(tester, 10);
      expect(counter.builds, 0);
      expect(find.byKey(const Key('dashboard-card-summary')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final style in PanelStyle.values) {
    testWidgets(
      '$style Nosaki keeps live data while minimal skips idle ticks',
      (tester) async {
        final clock = _Clock();
        final controller = await _controller(_nosakiState());
        addTearDown(controller.dispose);
        final counter = _DashboardBuildCounter();
        addTearDown(counter.dispose);
        await tester.pumpWidget(
          _host(
            clock,
            RepairSummaryCard(
              controller: controller,
              visible: const {'empty'},
              collapsed: false,
              onToggleCollapse: () {},
              onOpenRepair: (_) {},
            ),
            style: style,
          ),
        );
        await tester.tap(find.byKey(const Key('repair-summary-mode-nosaki')));
        await tester.pumpAndSettle();
        expect(find.textContaining('★49'), findsOneWidget);
        counter.builds = 0;
        await clock.advance(tester, 10);
        expect(counter.builds, style == PanelStyle.flat ? 0 : greaterThan(0));

        controller.accept(
          kcsapiEvent('/kcsapi/api_get_member/ship2', [
            {'api_id': 2, 'api_ship_id': 2, 'api_cond': 50},
          ], capturedAt: clock.value),
        );
        await controller.idle;
        await tester.pump();
        expect(find.textContaining('★49'), findsNothing);
        expect(find.textContaining('★50'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      '$style fleet keeps capture updates while skipping idle ticks',
      (tester) async {
        final clock = _Clock();
        final controller = await _controller(demoState());
        addTearDown(controller.dispose);
        final counter = _DashboardBuildCounter();
        addTearDown(counter.dispose);
        await tester.pumpWidget(_host(clock, _fleet(controller), style: style));
        await tester.pumpAndSettle();
        counter.builds = 0;
        await clock.advance(tester, 10);
        expect(counter.builds, 0);

        controller.accept(
          kcsapiEvent('/kcsapi/api_get_member/ship2', [
            {'api_id': 4, 'api_ship_id': 4, 'api_cond': 10},
          ], capturedAt: clock.value),
        );
        await controller.idle;
        await tester.pump();
        final value = find.byKey(
          const Key('fleet-summary-metric-minimum-condition-value'),
        );
        if (style == PanelStyle.flat) {
          expect(tester.widget<Text>(value).data, '10');
        } else {
          expect(find.text('10'), findsWidgets);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'minimal recovery timer ticks through its deadline and then rests',
    (tester) async {
      final clock = _Clock();
      final state = demoState();
      final controller = await _controller(state);
      addTearDown(controller.dispose);
      final recovery = MoraleRecoveryTimerController(
        initialAnchors: {
          1: MoraleNotificationTimerAnchor(
            fleetSignature: NotificationTimerSignature.morale(
              state.fleets.first,
            ),
            observedAt: clock.value,
            observedCondition: 15,
            targetAt: clock.value.add(const Duration(seconds: 2)),
          ),
        },
      );
      addTearDown(recovery.dispose);
      final counter = _DashboardBuildCounter();
      addTearDown(counter.dispose);
      await tester.pumpWidget(
        _host(
          clock,
          _fleet(
            controller,
            visible: const {'recovery-countdown'},
            recovery: recovery,
          ),
        ),
      );
      expect(find.text('00:02'), findsOneWidget);
      await clock.advance(tester);
      expect(find.text('00:01'), findsOneWidget);
      await clock.advance(tester);
      final recovered = lookupAppLocalizations(
        const Locale('zh'),
      ).moraleRecovered;
      expect(find.text(recovered), findsOneWidget);
      counter.builds = 0;
      await clock.advance(tester, 5);
      expect(counter.builds, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'minimal dock still removes its expired countdown at the deadline',
    (tester) async {
      final clock = _Clock();
      final controller = await _controller(
        demoState().copyWith(
          repairDocks: [
            RepairDock(
              id: 1,
              state: 1,
              shipId: 2,
              completionTime: clock.value.add(const Duration(seconds: 2)),
            ),
          ],
        ),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          clock,
          RepairSummaryCard(
            controller: controller,
            collapsed: false,
            visible: const {},
            onToggleCollapse: () {},
            onOpenRepair: (_) {},
          ),
        ),
      );
      expect(find.text('00:00:02'), findsOneWidget);
      await clock.advance(tester);
      expect(find.text('00:00:01'), findsOneWidget);
      await clock.advance(tester);
      expect(find.byType(OperationCountdownText), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'minimal fleet keeps anchorage badge until captured HP confirms repair',
    (tester) async {
      final clock = _Clock();
      final base = demoState();
      final state = base.copyWith(
        masterShips: {
          ...base.masterShips,
          1: const MasterShip(id: 182, name: '明石', shipTypeId: 19),
        },
        ships: {
          ...base.ships,
          2: const OwnedShip(
            id: 2,
            masterId: 2,
            level: 94,
            currentHp: 26,
            maxHp: 27,
          ),
        },
        fleets: const [
          Fleet(id: 1, name: '第一舰队', shipIds: [1, 2]),
        ],
      );
      final controller = GameStateController(
        initialState: state,
        timerService: TimerMechanicsService(
          akashiTimer: GlobalGameTimer(
            anchorAt: clock.value.subtract(
              const Duration(minutes: 19, seconds: 58),
            ),
          ),
        ),
      );
      await controller.initialize();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(clock, _fleet(controller)));
      final badge = find.byKey(const Key('minimal-repair-2'));
      expect(badge, findsOneWidget);
      await clock.advance(tester, 2);
      // Elapsed repair estimates do not acknowledge real HP gains themselves.
      expect(badge, findsOneWidget);
      controller.accept(
        kcsapiEvent('/kcsapi/api_get_member/ship2', [
          {'api_id': 2, 'api_ship_id': 2, 'api_nowhp': 27},
        ], capturedAt: clock.value),
      );
      await controller.idle;
      await tester.pump();
      expect(badge, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
