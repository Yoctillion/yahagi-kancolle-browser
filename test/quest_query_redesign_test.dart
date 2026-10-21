import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_catalog.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_center_page.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_store.dart';

void main() {
  testWidgets(
    'portrait caps its list and retains scroll while updating detail',
    (tester) async {
      await _pumpPage(
        tester,
        size: const Size(390, 844),
        quests: <int, GameQuest>{
          ..._syntheticQuests,
          for (var id = 203; id < 233; id++)
            id: GameQuest(
              id: id,
              title: '一覧位置を保持する任務 $id',
              detail: '合成した公開テスト用の任務。',
              category: 2,
              type: 2,
              state: 2,
              progressFlag: 0,
            ),
        },
      );
      expect(find.byKey(const Key('quest-card-201')), findsOneWidget);
      expect(find.byKey(const Key('quest-detail-panel')), findsOneWidget);
      expect(find.byKey(const Key('quest-detail-title-201')), findsOneWidget);
      expect(find.byKey(const Key('quest-back-to-list')), findsNothing);
      final list = find.byKey(const Key('quest-list-panel'));
      final listRect = tester.getRect(list);
      final detailRect = tester.getRect(
        find.byKey(const Key('quest-detail-panel')),
      );
      final contentHeight = detailRect.bottom - listRect.top;
      expect(listRect.height, lessThanOrEqualTo(contentHeight * .5 + 1));
      expect(listRect.height, greaterThan(contentHeight * .4));
      expect(detailRect.top, greaterThanOrEqualTo(listRect.bottom));
      expect(
        detailRect.bottom,
        closeTo(tester.getRect(find.byType(QuestCenterPage)).bottom, 1),
      );
      await tester.tap(find.byKey(const Key('quest-card-201')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quest-detail-panel')), findsOneWidget);
      expect(find.byKey(const Key('quest-card-201')), findsOneWidget);
      await tester.drag(list, const Offset(0, -550));
      await tester.pumpAndSettle();
      final scrollable = find.descendant(
        of: list,
        matching: find.byType(Scrollable),
      );
      final before = tester.state<ScrollableState>(scrollable).position.pixels;
      expect(before, greaterThan(0));
      final visibleCard = find
          .byWidgetPredicate(
            (widget) =>
                widget is Material &&
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'quest-card-',
                ),
          )
          .hitTestable()
          .first;
      final cardKey =
          tester.widget<Material>(visibleCard).key! as ValueKey<String>;
      final selectedId = int.parse(
        cardKey.value.substring('quest-card-'.length),
      );
      await tester.tap(visibleCard);
      await tester.pumpAndSettle();
      expect(find.byKey(Key('quest-detail-title-$selectedId')), findsOneWidget);
      expect(
        tester.state<ScrollableState>(scrollable).position.pixels,
        closeTo(before, 1),
      );

      expect(find.byKey(const Key('quest-detail-panel')), findsOneWidget);
      expect(find.byKey(const Key('quest-list-panel')), findsOneWidget);
      expect(find.byKey(const Key('quest-back-to-list')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('translation consistently changes list and detail titles', (
    tester,
  ) async {
    await _pumpPage(tester);
    final card = find.byKey(const Key('quest-card-201'));
    expect(
      find.descendant(of: card, matching: find.text('敵艦隊を撃破せよ！')),
      findsOneWidget,
    );
    expect(find.text('击破敌方舰队！'), findsNothing);
    await tester.tap(find.byKey(const Key('quest-translation-toggle')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: card, matching: find.text('击破敌方舰队！')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('quest-detail-panel')),
        matching: find.text('击破敌方舰队！'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('quest-detail-panel')),
        matching: find.text('敵艦隊を撃破せよ！'),
      ),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('quest-detail-tab-relations')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('quest-relation-pre-202')),
        matching: find.text('做好航海准备！'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('query drafts preview their count and cancel without applying', (
    tester,
  ) async {
    final filters = QuestFilterController()..setQuery('敵艦隊');
    addTearDown(filters.dispose);
    await _pumpPage(tester, filter: filters, mode: QuestCenterMode.all);
    expect(find.byKey(const Key('quest-search-button')), findsOneWidget);
    expect(find.byKey(const Key('quest-filter-button')), findsNothing);
    await tester.tap(find.byKey(const Key('quest-search-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('quest-search-field')),
      '見つからない任務',
    );
    await tester.pumpAndSettle();
    expect(filters.query, '敵艦隊');
    expect(
      find.descendant(
        of: find.byKey(const Key('quest-query-apply')),
        matching: find.textContaining('0'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('quest-query-cancel')));
    await tester.pumpAndSettle();
    expect(filters.query, '敵艦隊');
    expect(find.byKey(const Key('quest-card-201')), findsOneWidget);

    await tester.tap(find.byKey(const Key('quest-search-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('quest-search-field')), '航海');
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('quest-query-apply')),
        matching: find.textContaining('1'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('quest-query-apply')));
    await tester.pumpAndSettle();
    expect(filters.query, '航海');
    expect(find.byKey(const Key('quest-card-202')), findsOneWidget);
    expect(find.byKey(const Key('quest-card-201')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset clears only the query draft until apply', (tester) async {
    final filters = QuestFilterController()
      ..setQuery('敵艦隊')
      ..setCategory(2)
      ..setPeriod(1);
    addTearDown(filters.dispose);
    await _pumpPage(tester, filter: filters, mode: QuestCenterMode.all);
    await tester.tap(find.byKey(const Key('quest-search-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quest-query-reset')));
    await tester.pumpAndSettle();
    expect(filters.query, '敵艦隊');
    expect(filters.category, 2);
    expect(filters.period, 1);
    await tester.tap(find.byKey(const Key('quest-query-apply')));
    await tester.pumpAndSettle();
    expect(filters.hasSearch, isFalse);
    expect(filters.hasFilters, isFalse);
    expect(find.byKey(const Key('quest-card-201')), findsOneWidget);
    expect(find.byKey(const Key('quest-card-202')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'relation navigation retains query and mode and returns to target',
    (tester) async {
      final emittedModes = <QuestCenterMode>[];
      final filters = QuestFilterController()
        ..setQuery('敵艦隊')
        ..setCategory(2)
        ..setPeriod(1);
      addTearDown(filters.dispose);
      await _pumpPage(
        tester,
        filter: filters,
        mode: QuestCenterMode.all,
        onModeChanged: emittedModes.add,
      );
      await tester.tap(find.byKey(const Key('quest-detail-tab-relations')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quest-relation-pre-202')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quest-detail-title-202')), findsOneWidget);
      expect(find.byKey(const Key('quest-return-target')), findsNothing);
      expect(filters.query, '敵艦隊');
      expect(filters.category, 2);
      expect(filters.period, 1);
      expect(find.byKey(const Key('quest-card-201')), findsOneWidget);
      expect(find.byKey(const Key('quest-card-202')), findsNothing);
      await tester.tap(find.byKey(const Key('quest-detail-tab-relations')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quest-relation-pre-203')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quest-detail-title-203')), findsOneWidget);
      expect(find.byKey(const Key('quest-return-target')), findsOneWidget);
      await tester.tap(find.byKey(const Key('quest-relation-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quest-detail-title-202')), findsOneWidget);
      expect(find.byKey(const Key('quest-return-target')), findsNothing);
      await tester.tap(find.byKey(const Key('quest-relation-pre-203')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quest-return-target')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quest-detail-title-201')), findsOneWidget);
      expect(filters.query, '敵艦隊');
      expect(emittedModes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'relation shortcuts avoid duplicate targets after revisiting tasks',
    (tester) async {
      await _pumpPage(tester, mode: QuestCenterMode.all);
      Future<void> openRelation(String key) async {
        final tab = find.byKey(const Key('quest-detail-tab-relations'));
        await tester.ensureVisible(tab);
        await tester.pumpAndSettle();
        await tester.tap(tab);
        await tester.pumpAndSettle();
        final relation = find.byKey(Key(key));
        await tester.ensureVisible(relation);
        await tester.pumpAndSettle();
        await tester.tap(relation);
        await tester.pumpAndSettle();
      }

      await openRelation('quest-relation-pre-202');
      expect(find.byKey(const Key('quest-return-target')), findsNothing);
      await openRelation('quest-relation-post-201');
      expect(find.byKey(const Key('quest-detail-title-201')), findsOneWidget);
      expect(find.byKey(const Key('quest-return-target')), findsNothing);
      await openRelation('quest-relation-pre-202');
      expect(find.byKey(const Key('quest-detail-title-202')), findsOneWidget);
      expect(find.byKey(const Key('quest-return-target')), findsNothing);
      await openRelation('quest-relation-pre-203');
      expect(find.byKey(const Key('quest-return-target')), findsOneWidget);
      await tester.tap(find.byKey(const Key('quest-return-target')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quest-detail-title-201')), findsOneWidget);
      expect(find.byKey(const Key('quest-relation-back')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('narrow landscape keeps panes and the full long title readable', (
    tester,
  ) async {
    const title = '精鋭なる第一艦隊を南西海域の最前線へ展開し、敵主力艦隊を捕捉撃滅せよ！';
    final catalog = QuestCatalog(const <QuestCatalogEntry>[
      QuestCatalogEntry(
        gameId: 201,
        code: 'B999',
        name: title,
        description: '原文の任務説明。',
      ),
    ]);
    await _pumpPage(
      tester,
      size: const Size(667, 375),
      catalog: catalog,
      mode: QuestCenterMode.all,
    );
    final card = find.byKey(const Key('quest-card-201'));
    final detail = find.byKey(const Key('quest-detail-panel'));
    expect(
      tester.getRect(detail).left,
      greaterThan(tester.getRect(card).right),
    );
    final titleWidget = tester.widget<Text>(
      find.descendant(of: detail, matching: find.text(title)),
    );
    expect(titleWidget.maxLines, isNull);
    expect(titleWidget.overflow, isNot(TextOverflow.ellipsis));
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown requirements keep source text without invented counts', (
    tester,
  ) async {
    const description = '指定された特殊編成で作戦を実施せよ。詳細条件は未確認。';
    final catalog = QuestCatalog(const <QuestCatalogEntry>[
      QuestCatalogEntry(
        gameId: 99001,
        code: 'B9999',
        name: '条件を確認中の任務',
        description: description,
      ),
    ]);
    await _pumpPage(tester, catalog: catalog, mode: QuestCenterMode.all);
    await tester.tap(find.byKey(const Key('quest-detail-tab-conditions')));
    await tester.pumpAndSettle();
    final detail = find.byKey(const Key('quest-detail-panel'));
    expect(
      find.descendant(of: detail, matching: find.text(description)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: detail, matching: find.textContaining('0/1')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('portrait panes do not intercept system back at the root route', (
    tester,
  ) async {
    await _pumpPage(tester, size: const Size(390, 844));
    await tester.tap(find.byKey(const Key('quest-card-201')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quest-detail-panel')), findsOneWidget);
    final pagePopScope = find.descendant(
      of: find.byType(QuestCenterPage),
      matching: find.byWidgetPredicate((w) => w is PopScope<Object?>),
    );
    expect(tester.widget<PopScope<Object?>>(pagePopScope).canPop, isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quest-card-201')), findsOneWidget);
    expect(find.byKey(const Key('quest-detail-panel')), findsOneWidget);
    expect(find.byKey(const Key('quest-detail-title-201')), findsOneWidget);
    expect(find.byKey(const Key('quest-back-to-list')), findsNothing);
    expect(find.byType(QuestCenterPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  Size size = const Size(844, 390),
  QuestFilterController? filter,
  QuestCatalog? catalog,
  QuestCenterMode mode = QuestCenterMode.active,
  Map<int, GameQuest>? quests,
  ValueChanged<QuestCenterMode>? onModeChanged,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final controller = GameStateController(
    questStore: _SyntheticQuestStore(quests ?? _syntheticQuests),
  );
  addTearDown(controller.dispose);
  await controller.idle;
  await tester.pumpWidget(
    MaterialApp(
      home: QuestCenterPage(
        controller: controller,
        catalog: catalog ?? _catalog,
        filterController: filter,
        mode: mode,
        onModeChanged: onModeChanged,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _catalog = QuestCatalog(const <QuestCatalogEntry>[
  QuestCatalogEntry(
    gameId: 201,
    code: 'Bd1',
    name: '敵艦隊を撃破せよ！',
    description: '敵艦隊を捕捉、これを撃破せよ！',
    translatedName: '击破敌方舰队！',
    translatedDescription: '捕捉并击破敌方舰队！',
    rewards: '開発資材×1',
    prerequisites: <String>['A1'],
  ),
  QuestCatalogEntry(
    gameId: 202,
    code: 'A1',
    name: '航海の準備をせよ！',
    description: '艦隊を編成せよ。',
    translatedName: '做好航海准备！',
    translatedDescription: '编成舰队。',
    prerequisites: <String>['A2'],
  ),
  QuestCatalogEntry(
    gameId: 203,
    code: 'A2',
    name: '最初の編成',
    description: '最初の艦隊を編成せよ。',
    translatedName: '最初的编成',
  ),
]);

const _syntheticQuests = <int, GameQuest>{
  201: GameQuest(
    id: 201,
    title: '敵艦隊を撃破せよ！',
    detail: '敵艦隊を捕捉、これを撃破せよ！',
    category: 2,
    type: 2,
    state: 2,
    progressFlag: 0,
    materials: <int>[50, 50, 0, 0],
  ),
};

class _SyntheticQuestStore extends QuestStore {
  _SyntheticQuestStore(this.quests);

  final Map<int, GameQuest> quests;

  @override
  Future<Map<int, GameQuest>> loadQuests() async => quests;

  @override
  Future<void> saveQuests(Map<int, GameQuest> quests) async {}

  @override
  Future<void> clearQuests() async {}
}
