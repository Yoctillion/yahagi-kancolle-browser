import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/layout/hd_dashboard_content.dart';
import 'package:yahagi_kancolle_browser/src/quest/pinned_quests_summary.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_catalog.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_center_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'QuestAuditCjk',
    )..addFont(rootBundle.load('assets/fonts/HarmonyOS_Sans_SC.ttf'))).load();
  });

  for (final category in [2, 8, 9, 10, 11]) {
    testWidgets('active API category $category uses the normalized category', (
      tester,
    ) async {
      final expectedCategory = category == 11 ? 6 : 2;
      final filters = QuestFilterController();
      addTearDown(filters.dispose);
      await _page(
        tester,
        state: _state(_quest(category: category)),
        filters: filters,
      );
      final l10n = lookupAppLocalizations(const Locale('zh'));
      final card = find.byKey(const Key('quest-card-901'));
      final badge = find.descendant(
        of: card,
        matching: find.text(
          expectedCategory == 6 ? l10n.questFactory : l10n.questSortie,
        ),
      );
      expect(badge, findsOneWidget);
      expect(
        tester.widget<Text>(badge).style?.color,
        expectedCategory == 6
            ? const Color(0xff805444)
            : const Color(0xffe73939),
      );
      filters.setCategory(expectedCategory);
      await tester.pumpAndSettle();
      expect(card, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final periodCase in [
    (code: 'By1', period: 6),
    (code: 'Bq1', period: 5),
    (code: 'B1', period: 5),
    (code: null, period: 5),
  ]) {
    testWidgets('API type 5 resolves period with catalog ${periodCase.code}', (
      tester,
    ) async {
      final filters = QuestFilterController();
      addTearDown(filters.dispose);
      await _page(
        tester,
        state: _state(_quest(type: 5)),
        filters: filters,
        catalog: QuestCatalog([
          if (periodCase.code case final code?)
            QuestCatalogEntry(
              gameId: 901,
              code: code,
              name: '周期任务',
              description: '',
            ),
        ]),
      );
      filters.setPeriod(periodCase.period);
      await tester.pumpAndSettle();
      final card = find.byKey(const Key('quest-card-901'));
      expect(card, findsOneWidget);
      final l10n = lookupAppLocalizations(const Locale('zh'));
      expect(
        find.descendant(
          of: card,
          matching: find.text(
            periodCase.period == 6 ? l10n.questYearly : l10n.questSeasonal,
          ),
        ),
        findsOneWidget,
      );
      filters.setPeriod(periodCase.period == 6 ? 5 : 6);
      await tester.pumpAndSettle();
      expect(card, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('synced zero accepted quests has an empty message in $locale', (
      tester,
    ) async {
      await _page(
        tester,
        state: const GameState(hasQuestData: true, activeQuestCount: 0),
        locale: locale,
      );
      final l10n = lookupAppLocalizations(locale);
      expect(find.text(l10n.noPinnedQuests), findsOneWidget);
      expect(find.text(l10n.waitingQuestData), findsNothing);
      expect(find.text(l10n.waitingQuestDataDesc), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final state in [
    const GameState(),
    const GameState(hasQuestData: true, activeQuestCount: 2),
  ]) {
    testWidgets(
      'missing accepted quest data still requests sync: ${state.hasQuestData}',
      (tester) async {
        await _page(tester, state: state);
        final l10n = lookupAppLocalizations(const Locale('zh'));
        expect(find.text(l10n.waitingQuestData), findsOneWidget);
        expect(find.text(l10n.waitingQuestDataDesc), findsOneWidget);
        expect(find.text(l10n.noPinnedQuests), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('empty filtered accepted quests still shows no results', (
    tester,
  ) async {
    final filters = QuestFilterController()..setCategory(1);
    addTearDown(filters.dispose);
    await _page(tester, state: _state(_quest()), filters: filters);
    final l10n = lookupAppLocalizations(const Locale('zh'));
    expect(find.text(l10n.questNoResults), findsOneWidget);
    expect(find.text(l10n.noPinnedQuests), findsNothing);
    expect(find.text(l10n.waitingQuestData), findsNothing);
  });

  for (final hasResolvedParent in [false, true]) {
    testWidgets(
      'relation page preserves missing prerequisites: $hasResolvedParent',
      (tester) async {
        await _page(
          tester,
          state: _state(_quest()),
          catalog: QuestCatalog([
            const QuestCatalogEntry(
              gameId: 1,
              code: 'A1',
              name: '前置任务',
              description: '',
              prerequisites: ['MissingGrandparent'],
            ),
            QuestCatalogEntry(
              gameId: 901,
              code: 'B1',
              name: '审计任务',
              description: '',
              prerequisites: [if (hasResolvedParent) 'A1', 'MissingParent'],
            ),
          ]),
        );
        final tab = find.byKey(const Key('quest-detail-tab-relations'));
        await tester.ensureVisible(tab);
        await tester.tap(tab);
        await tester.pumpAndSettle();
        final missing = find.byKey(
          const Key('quest-relation-pre-unresolved-MissingParent'),
        );
        final l10n = lookupAppLocalizations(const Locale('zh'));
        expect(missing, findsOneWidget);
        expect(
          find.descendant(of: missing, matching: find.text('MissingParent')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: missing,
            matching: find.text(l10n.questStateUnknown),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: missing, matching: find.byType(InkWell)),
          findsNothing,
        );
        expect(find.text(l10n.questNoPrerequisites), findsNothing);
        if (hasResolvedParent) {
          final expansion = find.byKey(
            const PageStorageKey('quest-expand-pre-1'),
          );
          await tester.ensureVisible(expansion);
          await tester.tap(expansion);
          await tester.pumpAndSettle();
          expect(
            find.byKey(
              const Key('quest-relation-pre-1-unresolved-MissingGrandparent'),
            ),
            findsOneWidget,
          );
          final parent = find.byKey(const Key('quest-relation-pre-1'));
          await tester.ensureVisible(parent);
          expect(tester.widget<InkWell>(parent).onTap, isNotNull);
          await tester.tap(parent);
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('quest-detail-title-1')), findsOneWidget);
          await tester.ensureVisible(tab);
          await tester.tap(tab);
          await tester.pumpAndSettle();
          expect(find.text('MissingGrandparent'), findsOneWidget);
          expect(find.text(l10n.questNoPrerequisites), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final locale in AppLocalizations.supportedLocales) {
    for (final pending in [false, true]) {
      testWidgets(
        'HD narrow columns preserve name and progress: $locale $pending',
        (tester) async {
          final quest = _quest(
            title: '大規模演習を連続達成する任務',
            current: pending ? 30 : 12,
            required: 30,
            verified: false,
          );
          final controller = GameStateController(initialState: _state(quest));
          addTearDown(controller.dispose);
          await controller.initialize();
          await tester.pumpWidget(
            _app(
              Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 665,
                  child: HdModuleColumns(
                    columns: 3,
                    child: PinnedQuestsSummary(
                      controller: controller,
                      collapsed: false,
                      onToggleCollapse: () {},
                      onOpenQuest: (_) {},
                    ),
                  ),
                ),
              ),
              locale: locale,
              textScale: 1.3,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final item = find.byKey(const Key('quest-summary-item-901'));
          final title = find.descendant(
            of: item,
            matching: find.text(quest.title),
          );
          final titleParagraph = tester.renderObject<RenderParagraph>(title);
          expect(titleParagraph.size.width, greaterThanOrEqualTo(140));
          final l10n = lookupAppLocalizations(locale);
          final label = pending
              ? '30/30 · ${l10n.questAwaitingConfirmation}'
              : '12/30';
          final progress = find.descendant(
            of: item,
            matching: find.text(label),
          );
          expect(progress, findsOneWidget);
          final itemBounds = tester.getRect(item).inflate(0.1);
          for (final text in [title, progress]) {
            final bounds = tester.getRect(text);
            expect(itemBounds.contains(bounds.topLeft), isTrue);
            expect(itemBounds.contains(bounds.bottomRight), isTrue);
          }
          await tester.tap(item);
        },
      );
    }
  }
}

GameQuest _quest({
  int category = 2,
  int type = 4,
  String title = '审计任务',
  int? current,
  int? required,
  bool? verified,
}) => GameQuest(
  id: 901,
  title: title,
  detail: '',
  category: category,
  type: type,
  state: 2,
  progressFlag: 0,
  progressCurrent: current,
  progressRequired: required,
  localCompletionVerified: verified,
);

GameState _state(GameQuest quest) => GameState(
  quests: {quest.id: quest},
  hasQuestData: true,
  activeQuestCount: 1,
);

Future<void> _page(
  WidgetTester tester, {
  required GameState state,
  QuestFilterController? filters,
  QuestCatalog? catalog,
  Locale locale = const Locale('zh'),
}) async {
  final controller = GameStateController(initialState: state);
  addTearDown(controller.dispose);
  await controller.initialize();
  await tester.pumpWidget(
    _app(
      QuestCenterPage(
        controller: controller,
        filterController: filters,
        catalog: catalog ?? QuestCatalog(const []),
      ),
      locale: locale,
    ),
  );
  await tester.pumpAndSettle();
}

Widget _app(
  Widget body, {
  Locale locale = const Locale('zh'),
  double textScale = 1,
}) => MaterialApp(
  theme: ThemeData(fontFamily: 'QuestAuditCjk'),
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(body: body),
);
