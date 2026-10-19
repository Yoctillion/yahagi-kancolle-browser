import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/fleet/anchorage_repair_view.dart';
import 'package:yahagi_kancolle_browser/src/fleet/nosaki_sparkle_view.dart';
import 'package:yahagi_kancolle_browser/src/fleet/repair_summary_card.dart';
import 'package:yahagi_kancolle_browser/src/fleet/resource_grid.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/layout/workspace_context_header.dart';

import 'nosaki_sparkle_calculator_test.dart' show buildNosakiTestState;

Widget _app(Locale locale, Widget child, {double scale = 1}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(body: child),
);

void main() {
  for (final (locale, labels, shortName) in [
    (
      const Locale('en'),
      ['Dock repair', 'Anchorage repair', 'Nosaki sparkling'],
      'Nosaki',
    ),
    (const Locale('ko'), ['입거 수리', '정박지 수리', '노사키 반짝이 작업'], '노사키'),
  ]) {
    for (final width in [320.0, 360.0]) {
      testWidgets(
        'repair page tabs localize and remain readable in $locale at $width',
        (tester) async {
          var selected = RepairCenterMode.dock;
          await tester.pumpWidget(
            _app(
              locale,
              Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: StatefulBuilder(
                    builder: (context, setState) => RepairModeTabs(
                      mode: selected,
                      onChanged: (value) => setState(() => selected = value),
                    ),
                  ),
                ),
              ),
              scale: 1.3,
            ),
          );
          for (final label in labels) {
            final text = find.text(label);
            expect(text, findsOneWidget);
            final paragraph = tester.renderObject<RenderParagraph>(text);
            expect(paragraph.didExceedMaxLines, isFalse);
            expect(
              paragraph.getMaxIntrinsicHeight(paragraph.size.width),
              lessThanOrEqualTo(paragraph.size.height + .1),
            );
          }
          await tester.ensureVisible(
            find.byKey(const Key('repair-mode-anchorage')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('repair-mode-anchorage')));
          await tester.pump();
          expect(selected, RepairCenterMode.anchorage);
          await tester.ensureVisible(
            find.byKey(const Key('repair-mode-nosaki')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('repair-mode-nosaki')));
          await tester.pump();
          expect(selected, RepairCenterMode.nosaki);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'repair workspace header reveals its selected translated mode in $locale',
      (tester) async {
        await tester.pumpWidget(
          _app(
            locale,
            Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 320,
                height: 54,
                child: WorkspaceContextHeader(
                  workspaceIndex: 3,
                  state: GameState.empty,
                  selectedFleetId: 1,
                  repairMode: RepairCenterMode.nosaki,
                ),
              ),
            ),
            scale: 1.3,
          ),
        );
        await tester.pumpAndSettle();
        final tab = find.byKey(const Key('repair-mode-nosaki'));
        final selected = find.descendant(
          of: tab,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                (widget.data == labels[2] || widget.data == shortName),
          ),
        );
        expect(selected, findsOneWidget);
        expect(
          tester
              .widget<Tooltip>(
                find.descendant(of: tab, matching: find.byType(Tooltip)),
              )
              .message,
          labels[2],
        );
        final textBounds = tester.getRect(selected);
        final barBounds = tester.getRect(
          find.byKey(const Key('repair-mode-segmented')),
        );
        expect(textBounds.left, greaterThanOrEqualTo(barBounds.left));
        expect(textBounds.right, lessThanOrEqualTo(barBounds.right));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'repair summary localizes full and compact feature labels in $locale',
      (tester) async {
        final controller = GameStateController(initialState: GameState.empty);
        addTearDown(controller.dispose);
        for (final width in [180.0, 300.0, 500.0]) {
          await tester.pumpWidget(
            _app(
              locale,
              Center(
                child: SizedBox(
                  width: width,
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
              ),
            ),
          );
          final selector = find.byKey(
            const Key('repair-summary-mode-selector'),
          );
          for (var i = 0; i < labels.length; i++) {
            final mode = ['dock', 'anchorage', 'nosaki'][i];
            final button = find.byKey(Key('repair-summary-mode-$mode'));
            final tooltip = tester.widget<Tooltip>(
              find.descendant(of: button, matching: find.byType(Tooltip)),
            );
            expect(tooltip.message, labels[i]);
          }
          expect(
            find.descendant(of: selector, matching: find.text('野埼')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets('header timer and its tooltip use the UI name in $locale', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          locale,
          const Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 500,
              child: CompactResourceBar(state: GameState.empty),
            ),
          ),
        ),
      );
      final capsule = find.byKey(const Key('header-nosaki-timer-summary'));
      expect(
        find.descendant(
          of: capsule,
          matching: find.text('$shortName: --:--:--'),
        ),
        findsOneWidget,
      );
      expect(
        find.byTooltip(
          '${labels[2]}${locale.languageCode == 'en' ? ' timer' : ' 타이머'}',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Nosaki feature UI preserves actual ship names in $locale', (
      tester,
    ) async {
      final state = buildNosakiTestState(flagshipMasterId: 1002);
      final controller = GameStateController(initialState: state);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(locale, NosakiSparkleView(controller: controller)),
      );
      await tester.pump();
      expect(find.text('野埼改'), findsOneWidget);
      expect(state.masterShips[1002]!.name, '野埼改');
      expect(tester.takeException(), isNull);
    });
  }
}
