import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_catalog.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_center_page.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/display_mode_store.dart';

void main() {
  testWidgets('short portrait list gives its unused half to visible detail', (
    tester,
  ) async {
    await _pump(tester, count: 1);
    final (list, detail) = _panes(tester);
    expect(list.height, lessThan((list.height + detail.height) / 2));
    expect(detail.top, closeTo(list.bottom + 1, .1));
    expect(detail.bottom, closeTo(844, .1));
    expect(find.byKey(const Key('quest-detail-title-201')), findsOneWidget);
    expect(find.byKey(const Key('quest-back-to-list')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long portrait list caps at half and scrolls independently', (
    tester,
  ) async {
    await _pump(tester, count: 30);
    final (list, detail) = _panes(tester);
    expect(list.height, closeTo(detail.height, .1));
    final listScrollable = _scrollable('quest-list-panel');
    final detailScrollable = _scrollable('quest-detail-panel');
    expect(
      tester.state<ScrollableState>(listScrollable).position.maxScrollExtent,
      greaterThan(0),
    );
    await tester.drag(listScrollable, const Offset(0, -180));
    await tester.pumpAndSettle();
    final offset = tester
        .state<ScrollableState>(listScrollable)
        .position
        .pixels;
    expect(offset, greaterThan(0));
    expect(tester.state<ScrollableState>(detailScrollable).position.pixels, 0);
    final visible = find
        .descendant(
          of: find.byKey(const Key('quest-list-panel')),
          matching: find.byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('quest-card-') &&
                RegExp(
                  r'^quest-card-\d+$',
                ).hasMatch((w.key! as ValueKey<String>).value),
          ),
        )
        .hitTestable()
        .first;
    final id = (tester.widget(visible).key! as ValueKey<String>).value
        .split('-')
        .last;
    await tester.tap(visible);
    await tester.pumpAndSettle();
    expect(find.byKey(Key('quest-detail-title-$id')), findsOneWidget);
    expect(find.byKey(const Key('quest-list-panel')), findsOneWidget);
    expect(
      tester.state<ScrollableState>(listScrollable).position.pixels,
      closeTo(offset, .1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('query contracts portrait list and leaves selection explicit', (
    tester,
  ) async {
    final filters = QuestFilterController();
    addTearDown(filters.dispose);
    await _pump(tester, count: 30, filters: filters);
    final initialHeight = _panes(tester).$1.height;
    filters.setQuery('229');
    await tester.pumpAndSettle();
    final list = tester.getRect(find.byKey(const Key('quest-list-panel')));
    final placeholder = tester.getRect(
      find.byKey(const Key('quest-detail-placeholder')),
    );
    expect(list.height, lessThan(initialHeight));
    expect(placeholder.top, closeTo(list.bottom + 1, .1));
    expect(find.byKey(const Key('quest-detail-title-229')), findsNothing);
    await tester.tap(find.byKey(const Key('quest-card-229')));
    await tester.pumpAndSettle();
    expect(_panes(tester).$1.height, closeTo(list.height, .1));
    expect(find.byKey(const Key('quest-detail-title-229')), findsOneWidget);
    filters.setQuery('zznonexistentzz');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('quest-detail-placeholder')), findsOneWidget);
    final emptyList = tester.getRect(find.byKey(const Key('quest-list-panel')));
    final emptyDetail = tester.getRect(
      find.byKey(const Key('quest-detail-placeholder')),
    );
    expect(emptyList.height, lessThan(emptyDetail.height));
  });

  testWidgets('translation and enlarged text remeasure real list content', (
    tester,
  ) async {
    await _pump(tester, count: 1, textScale: 1.3);
    final before = _panes(tester).$1.height;
    await tester.tap(find.byKey(const Key('quest-translation-toggle')));
    await tester.pumpAndSettle();
    final (list, detail) = _panes(tester);
    expect(list.height, greaterThan(before));
    expect(list.height, lessThanOrEqualTo(detail.height + .1));
    expect(detail.top, closeTo(list.bottom + 1, .1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty portrait task state also gives unused space to detail', (
    tester,
  ) async {
    await _pump(tester, count: 0);
    final list = tester.getRect(find.byKey(const Key('quest-list-panel')));
    final detail = tester.getRect(
      find.byKey(const Key('quest-detail-placeholder')),
    );
    expect(list.height, lessThan(detail.height));
    expect(detail.top, closeTo(list.bottom + 1, .1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rotation keeps task selection and list scroll in both layouts', (
    tester,
  ) async {
    await _pump(tester, count: 30);
    await tester.drag(_scrollable('quest-list-panel'), const Offset(0, -180));
    await tester.pumpAndSettle();
    final offset = tester
        .state<ScrollableState>(_scrollable('quest-list-panel'))
        .position
        .pixels;
    await tester.drag(_scrollable('quest-detail-panel'), const Offset(0, -220));
    await tester.pumpAndSettle();
    final detailOffset = tester
        .state<ScrollableState>(_scrollable('quest-detail-panel'))
        .position
        .pixels;
    expect(detailOffset, greaterThan(0));
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    final (wideList, wideDetail) = _panes(tester);
    expect(wideDetail.left, closeTo(wideList.right + 1, .1));
    expect(find.byKey(const Key('quest-detail-title-201')), findsOneWidget);
    expect(
      tester
          .state<ScrollableState>(_scrollable('quest-detail-panel'))
          .position
          .pixels,
      closeTo(detailOffset, .1),
    );
    expect(
      tester
          .state<ScrollableState>(_scrollable('quest-list-panel'))
          .position
          .pixels,
      closeTo(offset, .1),
    );
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    final (list, detail) = _panes(tester);
    expect(list.height, closeTo(detail.height, .1));
    expect(
      tester
          .state<ScrollableState>(_scrollable('quest-detail-panel'))
          .position
          .pixels,
      closeTo(detailOffset, .1),
    );
    expect(
      tester
          .state<ScrollableState>(_scrollable('quest-list-panel'))
          .position
          .pixels,
      closeTo(offset, .1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'collapsed portrait content does not create negative constraints',
    (tester) async {
      await _pump(tester, count: 1, displayMode: DisplayMode.portrait);
      tester.view.physicalSize = const Size(390, 48);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quest-detail-title-201')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('portrait relation Back restores task while both panes remain', (
    tester,
  ) async {
    await _pump(tester, count: 1);
    await tester.tap(find.byKey(const Key('quest-detail-tab-relations')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('quest-relation-pre-101')));
    await tester.tap(find.byKey(const Key('quest-relation-pre-101')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quest-detail-title-101')), findsOneWidget);
    expect(find.byKey(const Key('quest-list-panel')), findsOneWidget);
    expect(_popScope(tester).canPop, isFalse);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quest-detail-title-201')), findsOneWidget);
    expect(_popScope(tester).canPop, isTrue);
    expect(find.byKey(const Key('quest-back-to-list')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

(Rect, Rect) _panes(WidgetTester tester) => (
  tester.getRect(find.byKey(const Key('quest-list-panel'))),
  tester.getRect(find.byKey(const Key('quest-detail-panel'))),
);

Finder _scrollable(String key) => find
    .descendant(of: find.byKey(Key(key)), matching: find.byType(Scrollable))
    .first;

PopScope<Object?> _popScope(WidgetTester tester) => tester.widget(
  find.descendant(
    of: find.byType(QuestCenterPage),
    matching: find.byWidgetPredicate((w) => w is PopScope<Object?>),
  ),
);

Future<void> _pump(
  WidgetTester tester, {
  required int count,
  QuestFilterController? filters,
  double textScale = 1,
  DisplayMode displayMode = DisplayMode.auto,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final quests = {
    for (var i = 0; i < count; i++)
      201 + i: GameQuest(
        id: 201 + i,
        title: 'Task ${201 + i}',
        detail: 'Original conditions. ' * 80,
        category: 2,
        type: 1,
        state: 2,
        progressFlag: 0,
      ),
  };
  final controller = GameStateController(questStore: _Store(quests));
  addTearDown(controller.dispose);
  await controller.idle;
  final catalog = QuestCatalog([
    const QuestCatalogEntry(
      gameId: 101,
      code: 'A1',
      name: 'Prerequisite task',
      description: 'Prerequisite conditions.',
    ),
    for (var i = 0; i < count; i++)
      QuestCatalogEntry(
        gameId: 201 + i,
        code: 'B${i + 1}',
        name: 'Task ${201 + i}',
        description: 'Original conditions. ' * 80,
        translatedName: '这是一项名称很长的任务，用来确认切换中文翻译以后，列表会按照实际文字排版高度重新计算布局。',
        prerequisites: const ['A1'],
      ),
  ]);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: QuestCenterPage(
          controller: controller,
          catalog: catalog,
          filterController: filters,
          displayMode: displayMode,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Store extends QuestStore {
  _Store(this.quests);
  final Map<int, GameQuest> quests;
  @override
  Future<Map<int, GameQuest>> loadQuests() async => quests;
  @override
  Future<void> saveQuests(Map<int, GameQuest> quests) async {}
  @override
  Future<void> clearQuests() async {}
}
