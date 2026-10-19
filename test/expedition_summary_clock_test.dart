import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/fleet/expedition_summary_card.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/performance/second_tick_scope.dart';

import 'fixtures/kcsapi_fixtures.dart';

Future<GameStateController> _controllerWithExpedition(DateTime end) async {
  final port =
      (jsonDecode(portEvent.responseBody) as Map)['api_data']
          as Map<String, dynamic>;
  final fleets = port['api_deck_port'] as List;
  (fleets[1]['api_mission'] as List)[2] = end.millisecondsSinceEpoch;
  final controller = GameStateController();
  addTearDown(controller.dispose);
  controller
    ..accept(start2Event)
    ..accept(kcsapiEvent('/kcsapi/api_port/port', port));
  await controller.idle;
  return controller;
}

Widget _summary(GameStateController controller) => Scaffold(
  body: ExpeditionSummaryCard(
    controller: controller,
    collapsed: false,
    onToggleCollapse: () {},
    onOpenExpedition: () {},
    onOpenExpeditionCheck: (_) {},
  ),
);

Finder _countdown(String text) => find.descendant(
  of: find.byKey(const Key('expedition-summary-time-2')),
  matching: find.text(text),
);

void _resetLifecycleAfterTest(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  addTearDown(() {
    tester.binding.resetInternalState();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
}

void main() {
  testWidgets('visible inactive expedition brief keeps counting down', (
    tester,
  ) async {
    _resetLifecycleAfterTest(tester);
    var now = DateTime.utc(2030);
    final controller = await _controllerWithExpedition(
      now.add(const Duration(minutes: 10)),
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SecondTickScope(now: () => now, child: _summary(controller)),
        ),
      );
      expect(_countdown('00:10:00'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(_countdown('00:09:59'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('hidden expedition brief catches up when visible but inactive', (
    tester,
  ) async {
    _resetLifecycleAfterTest(tester);
    var now = DateTime.utc(2030);
    final controller = await _controllerWithExpedition(
      now.add(const Duration(minutes: 10)),
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SecondTickScope(now: () => now, child: _summary(controller)),
        ),
      );
      expect(_countdown('00:10:00'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      now = now.add(const Duration(minutes: 2));
      await tester.pump(const Duration(minutes: 2));
      expect(_countdown('00:10:00'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(_countdown('00:08:00'), findsOneWidget);
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(_countdown('00:07:59'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('expedition brief catches up after ticker mode is reenabled', (
    tester,
  ) async {
    _resetLifecycleAfterTest(tester);
    var now = DateTime.utc(2030);
    final visible = ValueNotifier<bool>(true);
    addTearDown(visible.dispose);
    final controller = await _controllerWithExpedition(
      now.add(const Duration(minutes: 10)),
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SecondTickScope(
            now: () => now,
            child: ValueListenableBuilder<bool>(
              valueListenable: visible,
              child: _summary(controller),
              builder: (context, enabled, child) =>
                  TickerMode(enabled: enabled, child: child!),
            ),
          ),
        ),
      );
      expect(_countdown('00:10:00'), findsOneWidget);

      visible.value = false;
      await tester.pump();
      now = now.add(const Duration(minutes: 2));
      await tester.pump(const Duration(minutes: 2));
      expect(_countdown('00:10:00'), findsOneWidget);

      visible.value = true;
      await tester.pump();
      expect(_countdown('00:08:00'), findsOneWidget);
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(_countdown('00:07:59'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('expedition brief completion uses the shared countdown clock', (
    tester,
  ) async {
    _resetLifecycleAfterTest(tester);
    // A scope can retain an older time while paused. Its time must also decide
    // whether to subscribe, instead of disabling ticks using DateTime.now().
    var now = DateTime.utc(2000);
    final controller = await _controllerWithExpedition(
      now.add(const Duration(seconds: 1)),
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SecondTickScope(now: () => now, child: _summary(controller)),
        ),
      );
      expect(_countdown('00:00:01'), findsOneWidget);

      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(_countdown('已返母港'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
