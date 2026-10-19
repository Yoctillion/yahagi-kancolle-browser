import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/fleet/fleet_switcher_bar.dart';
import 'package:yahagi_kancolle_browser/src/fleet/repair_summary_card.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';

import 'nosaki_sparkle_calculator_test.dart' show buildNosakiTestState;

void main() {
  for (final scenario in <(Locale, List<String>, String)>[
    (const Locale('zh'), ['入渠修理', '泊地修理', '野埼刷闪'], '野埼刷闪中'),
    (
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      ['入渠修理', '泊地修理', '野埼刷閃'],
      '野埼刷閃中',
    ),
    (const Locale('ja'), ['入渠修理', '泊地修理', '野埼キラ付け'], '野埼キラ付け中'),
    (const Locale('ko'), ['입거 수리', '정박지 수리', '노사키 반짝이 작업'], '노사키 반짝이 작업 중'),
    (
      const Locale('en'),
      ['Dock repair', 'Anchorage repair', 'Nosaki sparkling'],
      'Nosaki sparkling',
    ),
  ]) {
    testWidgets('narrow repair modes and sparkle status use ${scenario.$1}', (
      tester,
    ) async {
      final controller = GameStateController(initialState: GameState.empty);
      addTearDown(controller.dispose);
      final state = buildNosakiTestState(companionConds: [49, 54]);
      await tester.pumpWidget(
        MaterialApp(
          locale: scenario.$1,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 180,
                    child: RepairSummaryCard(
                      controller: controller,
                      collapsed: false,
                      visible: const {},
                      showLogo: false,
                      showTitle: false,
                      onToggleCollapse: () {},
                      onOpenRepair: (_) {},
                    ),
                  ),
                  SizedBox(
                    width: 360,
                    child: FleetSwitcherBar(
                      fleets: state.fleets,
                      selectedFleetId: 1,
                      state: state,
                      nosakiSparkleStartedAt: DateTime.now().toUtc(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      for (var index = 0; index < 3; index++) {
        final mode = ['dock', 'anchorage', 'nosaki'][index];
        final button = find.byKey(Key('repair-summary-mode-$mode'));
        expect(button, findsOneWidget);
        final tooltip = tester.widget<Tooltip>(
          find.descendant(of: button, matching: find.byType(Tooltip)),
        );
        expect(tooltip.message, scenario.$2[index]);
        expect(tester.getSize(button).height, 20);
      }
      expect(find.text(scenario.$3), findsOneWidget);
      expect(find.text('野崎'), findsNothing);
      expect(find.text('野崎刷闪中'), findsNothing);
      if (scenario.$1.languageCode == 'en' ||
          scenario.$1.languageCode == 'ko') {
        final modes = find.byKey(const Key('repair-summary-mode-selector'));
        for (final untranslated in ['入渠', '泊地', '泊地修理', '野埼']) {
          expect(
            find.descendant(of: modes, matching: find.text(untranslated)),
            findsNothing,
          );
        }
      }
      expect(tester.takeException(), isNull);
    });
  }
}
