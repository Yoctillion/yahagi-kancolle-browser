import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/layout/panel_style.dart';
import 'package:yahagi_kancolle_browser/src/quest/pinned_quests_summary.dart';

void main() {
  for (final style in PanelStyle.values) {
    for (final locale in [
      const Locale('zh'),
      const Locale('ja'),
      const Locale('en'),
    ]) {
      for (final width in [200.0, 280.0, 430.0]) {
        for (final scale in [1.0, 1.5]) {
          testWidgets(
            'quest stays on one line: $style $locale $width scale $scale',
            (tester) async {
              const title = '改装特务空母「Gambier Bay Mk.II」抜錨！非常に長い任務名';
              final controller = GameStateController(
                initialState: GameState(
                  hasQuestData: true,
                  activeQuestCount: 1,
                  quests: const {
                    901: GameQuest(
                      id: 901,
                      title: title,
                      detail: '',
                      category: 2,
                      type: 1,
                      state: 2,
                      progressFlag: 0,
                      progressCurrent: 1,
                      progressRequired: 5,
                    ),
                  },
                ),
              );
              addTearDown(controller.dispose);
              await controller.initialize();
              int? opened;
              await tester.pumpWidget(
                MaterialApp(
                  locale: locale,
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: Scaffold(
                    body: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: width,
                        child: PanelStyleScope(
                          style: style,
                          child: PinnedQuestsSummary(
                            controller: controller,
                            collapsed: false,
                            onToggleCollapse: () {},
                            onOpenQuest: (id) => opened = id,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              final item = find.byKey(const Key('quest-summary-item-901'));
              Finder text(String value) =>
                  find.descendant(of: item, matching: find.text(value));
              final type = text(lookupAppLocalizations(locale).questSortie);
              final number = text('#901');
              final name = text(title);
              final progress = text('1/5');
              for (final field in [type, number, name, progress]) {
                expect(field, findsOneWidget);
              }
              final rects = [
                type,
                number,
                name,
                progress,
              ].map(tester.getRect).toList();
              for (final rect in rects) {
                expect(rect.center.dy, closeTo(rects.first.center.dy, .1));
              }
              expect(
                find.descendant(of: item, matching: find.byType(Wrap)),
                findsNothing,
              );
              expect(tester.widget<Text>(name).maxLines, 1);
              expect(tester.widget<Text>(name).overflow, TextOverflow.ellipsis);
              expect(
                tester.renderObject<RenderParagraph>(name).didExceedMaxLines,
                isTrue,
              );
              expect(
                rects.last.right,
                closeTo(
                  tester.getRect(item).right -
                      (style == PanelStyle.card ? 8 : 0),
                  .1,
                ),
              );
              expect(rects[2].left, greaterThanOrEqualTo(rects[1].right));
              expect(rects[2].right, lessThanOrEqualTo(rects[3].left));
              await tester.tap(item);
              expect(opened, 901);
            },
          );
        }
      }
    }
  }

  for (final fields in [
    const {'type', 'number'},
    const {'progress'},
  ]) {
    testWidgets('single visible group keeps its full width: $fields', (
      tester,
    ) async {
      final controller = GameStateController(
        initialState: GameState(
          hasQuestData: true,
          activeQuestCount: 1,
          quests: const {
            901: GameQuest(
              id: 901,
              title: 'Long quest',
              detail: '',
              category: 5,
              type: 1,
              state: 2,
              progressFlag: 0,
              progressCurrent: 30,
              progressRequired: 30,
              localCompletionVerified: false,
            ),
          },
        ),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SizedBox(
              width: 160,
              child: PinnedQuestsSummary(
                controller: controller,
                collapsed: false,
                onToggleCollapse: () {},
                onOpenQuest: (_) {},
                visible: fields,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('quest-summary-item-901')), findsOneWidget);
    });
  }
}
