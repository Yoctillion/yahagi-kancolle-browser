import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/fleet/expedition_summary_card.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/layout/panel_style.dart';
import 'package:yahagi_kancolle_browser/src/performance/second_tick_scope.dart';

import 'fixtures/kcsapi_fixtures.dart';

void main() {
  testWidgets('扁平折叠的远征简报在时钟刷新后也不显示摘要', (tester) async {
    var now = DateTime.utc(2030);
    final port =
        (jsonDecode(portEvent.responseBody) as Map)['api_data']
            as Map<String, dynamic>;
    ((port['api_deck_port'] as List)[1]['api_mission'] as List)[2] = now
        .add(const Duration(minutes: 10))
        .millisecondsSinceEpoch;
    final controller = GameStateController();
    addTearDown(controller.dispose);
    controller
      ..accept(start2Event)
      ..accept(kcsapiEvent('/kcsapi/api_port/port', port));
    await controller.idle;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SecondTickScope(
          now: () => now,
          child: PanelStyleScope(
            style: PanelStyle.flat,
            child: Scaffold(
              body: ExpeditionSummaryCard(
                controller: controller,
                collapsed: true,
                onToggleCollapse: () {},
                onOpenExpedition: () {},
                onOpenExpeditionCheck: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('dashboard-card-summary')), findsNothing);

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('dashboard-card-summary')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
