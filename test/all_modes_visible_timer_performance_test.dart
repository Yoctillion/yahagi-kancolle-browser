import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/fleet/dashboard_card.dart';
import 'package:yahagi_kancolle_browser/src/fleet/fleet_summary_card.dart';
import 'package:yahagi_kancolle_browser/src/fleet/global_game_timer.dart';
import 'package:yahagi_kancolle_browser/src/fleet/morale_recovery_timer_controller.dart';
import 'package:yahagi_kancolle_browser/src/fleet/resource_grid.dart';
import 'package:yahagi_kancolle_browser/src/fleet/timer_mechanics_service.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/layout/panel_style.dart';
import 'package:yahagi_kancolle_browser/src/notification/notification_timer_anchor_store.dart';
import 'package:yahagi_kancolle_browser/src/performance/second_tick_scope.dart';
import 'package:yahagi_kancolle_browser/src/settings/battle_status_effect_settings.dart';
import 'package:yahagi_kancolle_browser/src/settings/header_resource_settings.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_store.dart';

import 'fixtures/fleet_display_sample.dart';
import 'fixtures/kcsapi_fixtures.dart';

class _Clock {
  var value = DateTime.utc(2030);
  DateTime now() => value;

  Future<void> advance(WidgetTester tester, [int seconds = 1]) async {
    for (var second = 0; second < seconds; second++) {
      value = value.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }
  }
}

class _BuildCounter {
  _BuildCounter(this.matches) {
    _previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = _record;
  }
  final bool Function(Widget) matches;
  late final void Function(Element, bool)? _previous;
  var builds = 0;

  void _record(Element element, bool builtOnce) {
    _previous?.call(element, builtOnce);
    if (matches(element.widget)) builds++;
  }

  void dispose() => debugOnRebuildDirtyWidget = _previous;
}

Widget _host(
  _Clock clock,
  Widget child, {
  UiDisplaySize mode = UiDisplaySize.normal,
}) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: SecondTickScope(
    now: clock.now,
    child: Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(
          width: mode == UiDisplaySize.normal ? 640 : 360,
          child: PanelStyleScope(
            style: mode.isMinimal ? PanelStyle.flat : PanelStyle.card,
            child: child,
          ),
        ),
      ),
    ),
  ),
);

Future<LayoutSettingsController> _settings(UiDisplaySize mode) async {
  SharedPreferences.setMockInitialValues({});
  final settings = await LayoutSettingsController.load(
    SharedPreferencesLayoutSettingsStore(),
  );
  await settings.setUiDisplaySize(mode);
  for (final id in settings.visibleHeaderResourceIds) {
    if (id != 'material-1') await settings.toggleHeaderResourceVisible(id);
  }
  return settings;
}

const _resources = GameState(resources: {GameResourceType.fuel: 12345});

String _timerText(WidgetTester tester, String key) => tester
    .widgetList<Text>(
      find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)),
    )
    .map((text) => text.data ?? text.textSpan!.toPlainText())
    .join(' ');

FleetSummaryCard _fleet(
  GameStateController controller, {
  MoraleRecoveryTimerController? recovery,
  Set<String> visible = const {'minimum-condition'},
}) => FleetSummaryCard(
  controller: controller,
  moraleRecoveryTimerController: recovery,
  visible: visible,
  collapsed: false,
  damagePulseFilter: DamagePulseFilter.off,
  moraleSparkleMode: MoraleSparkleMode.off,
  onToggleCollapse: () {},
  onOpenFleet: (_) {},
);

MoraleNotificationTimerAnchor _anchor(GameState state, DateTime deadline) =>
    MoraleNotificationTimerAnchor(
      fleetSignature: NotificationTimerSignature.morale(state.fleets.first),
      observedAt: deadline.subtract(const Duration(seconds: 2)),
      observedCondition: 15,
      targetAt: deadline,
    );

void main() {
  for (final mode in UiDisplaySize.values) {
    testWidgets('$mode hidden header timers rest and resume through settings', (
      tester,
    ) async {
      final clock = _Clock();
      final settings = await _settings(mode);
      addTearDown(settings.dispose);
      final counter = _BuildCounter(
        (widget) => widget is Text && widget.data == '12345',
      );
      addTearDown(counter.dispose);
      await tester.pumpWidget(
        _host(
          clock,
          CompactResourceBar(
            state: _resources,
            settingsController: settings,
            nosakiSparkleStartedAt: clock.value.subtract(
              const Duration(minutes: 1),
            ),
            layout: mode.isMinimal
                ? ResourceBarLayout.grid
                : mode == UiDisplaySize.compact
                ? ResourceBarLayout.staticStrip
                : ResourceBarLayout.strip,
          ),
          mode: mode,
        ),
      );
      final originalState = tester.state(find.byType(CompactResourceBar));
      expect(counter.builds, greaterThan(0));
      counter.builds = 0;
      await clock.advance(tester, 3);
      expect(counter.builds, 0, reason: 'neither running timer is shown');

      await settings.toggleHeaderResourceVisible(headerNosakiTimerId);
      await tester.pump();
      expect(
        _timerText(tester, 'header-nosaki-timer-summary'),
        contains('00:01:03'),
        reason: 'showing a timer reads absolute time immediately',
      );
      await settings.setUiDisplaySize(
        mode == UiDisplaySize.normal
            ? UiDisplaySize.compact
            : UiDisplaySize.normal,
      );
      await tester.pump();
      await clock.advance(tester);
      expect(
        _timerText(tester, 'header-nosaki-timer-summary'),
        contains('00:01:04'),
      );
      expect(
        tester.state(find.byType(CompactResourceBar)),
        same(originalState),
      );

      await settings.toggleHeaderResourceVisible(headerNosakiTimerId);
      await tester.pump();
      counter.builds = 0;
      await clock.advance(tester, 3);
      expect(counter.builds, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$mode fleet rests when idle and after a recovery deadline', (
      tester,
    ) async {
      final clock = _Clock();
      final state = demoState();
      final controller = GameStateController(initialState: state);
      await controller.initialize();
      addTearDown(controller.dispose);
      final counter = _BuildCounter((widget) => widget is DashboardCard);
      addTearDown(counter.dispose);
      await tester.pumpWidget(_host(clock, _fleet(controller), mode: mode));
      await tester.pumpAndSettle();
      final originalState = tester.state(find.byType(FleetSummaryCard));
      counter.builds = 0;
      await clock.advance(tester, 3);
      expect(counter.builds, 0);

      controller.accept(
        kcsapiEvent('/kcsapi/api_get_member/ship2', [
          {'api_id': 4, 'api_ship_id': 4, 'api_cond': 10},
        ], capturedAt: clock.value),
      );
      await controller.idle;
      await tester.pump();
      expect(
        tester
            .widget<Text>(
              find.byKey(
                const Key('fleet-summary-metric-minimum-condition-value'),
              ),
            )
            .data,
        '10',
      );

      final recovery = MoraleRecoveryTimerController(
        initialAnchors: {
          1: _anchor(state, clock.value.add(const Duration(seconds: 2))),
        },
      );
      addTearDown(recovery.dispose);
      await tester.pumpWidget(
        _host(
          clock,
          _fleet(
            controller,
            recovery: recovery,
            visible: const {'recovery-countdown'},
          ),
          mode: mode,
        ),
      );
      expect(tester.state(find.byType(FleetSummaryCard)), same(originalState));
      expect(find.text('00:02'), findsOneWidget);
      await clock.advance(tester);
      expect(find.text('00:01'), findsOneWidget);
      await clock.advance(tester);
      final recovered = lookupAppLocalizations(
        const Locale('zh'),
      ).moraleRecovered;
      expect(find.text(recovered), findsOneWidget);
      counter.builds = 0;
      await clock.advance(tester, 3);
      expect(counter.builds, 0, reason: 'deadline completion ends UI ticks');

      recovery.replaceAnchors({
        1: _anchor(state, clock.value.add(const Duration(seconds: 2))),
      });
      await tester.pump();
      expect(find.text('00:02'), findsOneWidget);
      await clock.advance(tester);
      expect(find.text('00:01'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('collapsed resource grid follows its customized visible timers', (
    tester,
  ) async {
    final clock = _Clock();
    final settings = await _settings(UiDisplaySize.minimal);
    addTearDown(settings.dispose);
    await settings.toggleHeaderResourceVisible(headerNosakiTimerId);
    final counter = _BuildCounter(
      (widget) => widget is Text && widget.data == '12345',
    );
    addTearDown(counter.dispose);
    await tester.pumpWidget(
      _host(
        clock,
        CompactResourceBar(
          state: _resources,
          settingsController: settings,
          layout: ResourceBarLayout.grid,
          nosakiSparkleStartedAt: clock.value.subtract(
            const Duration(minutes: 1),
          ),
        ),
        mode: UiDisplaySize.minimal,
      ),
    );
    expect(
      _timerText(tester, 'header-nosaki-timer-summary'),
      contains('00:01:00'),
    );
    await tester.tap(
      find.byKey(const Key('information-panel-resources-toggle')),
    );
    await tester.pump();
    expect(find.byKey(const Key('header-nosaki-timer-summary')), findsNothing);
    counter.builds = 0;
    await clock.advance(tester, 3);
    expect(counter.builds, 0);

    await settings.setCollapsedPanelResourceIds([
      'material-1',
      headerNosakiTimerId,
    ]);
    await tester.pump();
    expect(
      _timerText(tester, 'header-nosaki-timer-summary'),
      contains('00:01:03'),
    );
    await clock.advance(tester);
    expect(
      _timerText(tester, 'header-nosaki-timer-summary'),
      contains('00:01:04'),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'header editor keeps hidden running timers live until editing ends',
    (tester) async {
      final clock = _Clock();
      final settings = await _settings(UiDisplaySize.normal);
      addTearDown(settings.dispose);
      final counter = _BuildCounter(
        (widget) => widget is Text && widget.data == '12345',
      );
      addTearDown(counter.dispose);
      await tester.pumpWidget(
        _host(
          clock,
          CompactResourceBar(
            state: _resources,
            settingsController: settings,
            nosakiSparkleStartedAt: clock.value.subtract(
              const Duration(minutes: 1),
            ),
          ),
        ),
      );
      await tester.longPress(
        find.byKey(const Key('header-resource-material-1')),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('header-resource-edit-mode')),
        findsOneWidget,
      );
      await clock.advance(tester);
      expect(
        _timerText(tester, 'header-nosaki-timer-summary'),
        contains('00:01:01'),
      );
      await tester.tap(find.byKey(const Key('header-resource-edit-done')));
      await tester.pump();
      counter.builds = 0;
      await clock.advance(tester, 3);
      expect(counter.builds, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'anchorage placeholder rests and resumes when capture makes it ready',
    (tester) async {
      final clock = _Clock();
      final settings = await _settings(UiDisplaySize.compact);
      await settings.toggleHeaderResourceVisible(headerAnchorageTimerId);
      addTearDown(settings.dispose);
      final counter = _BuildCounter(
        (widget) => widget is Text && widget.data == '12345',
      );
      addTearDown(counter.dispose);
      final startedAt = clock.value.subtract(const Duration(minutes: 1));
      Widget bar(GameState state) => CompactResourceBar(
        state: state,
        settingsController: settings,
        anchorageRepairStartedAt: startedAt,
        layout: ResourceBarLayout.staticStrip,
      );
      await tester.pumpWidget(_host(clock, bar(_resources)));
      expect(
        _timerText(tester, 'header-anchorage-timer-summary'),
        contains('--:--:--'),
      );
      counter.builds = 0;
      await clock.advance(tester, 3);
      expect(counter.builds, 0);

      final base = demoState();
      final ready = base.copyWith(
        resources: _resources.resources,
        masterShips: {
          ...base.masterShips,
          1: const MasterShip(id: 182, name: '明石', shipTypeId: 19),
        },
        fleets: const [
          Fleet(id: 1, name: '第一舰队', shipIds: [1, 2]),
        ],
      );
      await tester.pumpWidget(_host(clock, bar(ready)));
      expect(
        _timerText(tester, 'header-anchorage-timer-summary'),
        contains('00:01:03'),
      );
      await clock.advance(tester);
      expect(
        _timerText(tester, 'header-anchorage-timer-summary'),
        contains('00:01:04'),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'every fleet layout retains the original active anchorage clock',
    (tester) async {
      final clock = _Clock();
      final base = demoState();
      final state = base.copyWith(
        masterShips: {
          ...base.masterShips,
          1: const MasterShip(id: 182, name: '明石', shipTypeId: 19),
        },
        fleets: const [
          Fleet(id: 1, name: '第一舰队', shipIds: [1, 2]),
        ],
      );
      final controller = GameStateController(
        initialState: state,
        timerService: TimerMechanicsService(
          akashiTimer: GlobalGameTimer(anchorAt: clock.value),
        ),
      );
      await controller.initialize();
      addTearDown(controller.dispose);
      final counter = _BuildCounter((widget) => widget is DashboardCard);
      addTearDown(counter.dispose);
      for (final mode in UiDisplaySize.values) {
        await tester.pumpWidget(_host(clock, _fleet(controller), mode: mode));
        await tester.pumpAndSettle();
        counter.builds = 0;
        await clock.advance(tester, 2);
        expect(
          counter.builds,
          greaterThan(0),
          reason: '$mode repair badges stay live',
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
