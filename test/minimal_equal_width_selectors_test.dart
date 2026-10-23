import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/fleet/repair_summary_card.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/layout/flat_style.dart';
import 'package:yahagi_kancolle_browser/src/layout/flat_underline_tabs.dart';
import 'package:yahagi_kancolle_browser/src/layout/panel_style.dart';

Future<void> _pumpRepair(
  WidgetTester tester, {
  required double width,
  String languageCode = 'zh',
  PanelStyle style = PanelStyle.flat,
}) async {
  final controller = GameStateController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(languageCode),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(
              child: PanelStyleScope(
                style: style,
                child: RepairSummaryCard(
                  controller: controller,
                  collapsed: false,
                  onToggleCollapse: () {},
                  onOpenRepair: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Color _lineColor(WidgetTester tester, String mode) =>
    ((tester
                        .widget<DecoratedBox>(
                          find.descendant(
                            of: find.byKey(Key('repair-summary-mode-$mode')),
                            matching: find.byType(DecoratedBox),
                          ),
                        )
                        .decoration
                    as BoxDecoration)
                .border!
            as Border)
        .bottom
        .color;

void main() {
  for (final width in [300.0, 190.0]) {
    for (final language in ['zh', 'en']) {
      testWidgets('极简维修三模式等分整行，点击迁移选中底线 ($width, $language)', (tester) async {
        await _pumpRepair(tester, width: width, languageCode: language);
        final selector = find.byKey(const Key('repair-summary-mode-selector'));
        expect(tester.widget(selector), isA<FlatUnderlineTabs>());
        final selectorRect = tester.getRect(selector);
        final content = tester.getRect(
          find.byKey(const Key('repair-summary-dock-grid')),
        );
        expect(selectorRect.width, width - 12);
        expect(selectorRect.left, content.left);
        expect(selectorRect.right, content.right);
        expect(selectorRect.height, 22);
        const modes = ['dock', 'anchorage', 'nosaki'];
        for (final (index, mode) in modes.indexed) {
          final rect = tester.getRect(
            find.byKey(Key('repair-summary-mode-$mode')),
          );
          expect(rect.width, closeTo(selectorRect.width / 3, 0.01));
          expect(
            rect.left,
            closeTo(selectorRect.left + index * selectorRect.width / 3, 0.01),
          );
          expect(rect.top, selectorRect.top);
          expect(
            _lineColor(tester, mode),
            mode == 'dock' ? flatAccentColor : Colors.transparent,
          );
        }
        for (final mode in ['anchorage', 'nosaki', 'dock']) {
          await tester.tap(find.byKey(Key('repair-summary-mode-$mode')));
          await tester.pumpAndSettle();
          for (final option in modes) {
            expect(
              _lineColor(tester, option),
              option == mode ? flatAccentColor : Colors.transparent,
            );
          }
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('卡片维修模式保留原26dp带底色选择器', (tester) async {
    await _pumpRepair(tester, width: 300, style: PanelStyle.card);
    final selector = find.byKey(const Key('repair-summary-mode-selector'));
    final box = tester.widget<Container>(selector);
    expect(tester.getSize(selector).height, 26);
    expect((box.decoration! as BoxDecoration).color, isNotNull);
    expect(find.byType(FlatUnderlineTabs), findsNothing);
    await tester.tap(find.byKey(const Key('repair-summary-mode-anchorage')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('repair-summary-dock-grid')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
