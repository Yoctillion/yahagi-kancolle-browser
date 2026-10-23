import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_catalog.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_center_page.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_store.dart';

void main() {
  testWidgets('switching scope retains an explicitly cleared selection', (
    tester,
  ) async {
    final filters = QuestFilterController();
    addTearDown(filters.dispose);
    await _pump(tester, filters: filters);
    filters.setQuery('Beta');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quest-detail-panel')), findsNothing);
    await tester.tap(find.text('全任务'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quest-card-202')), findsOneWidget);
    expect(find.byKey(const Key('quest-detail-title-202')), findsNothing);
    expect(find.byKey(const Key('quest-detail-placeholder')), findsOneWidget);
  });

  testWidgets('disappearing portrait detail stops intercepting system back', (
    tester,
  ) async {
    final controller = await _pump(tester, size: const Size(390, 844));
    await tester.tap(find.byKey(const Key('quest-card-201')));
    await tester.pumpAndSettle();
    await controller.clearQuestsCache();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quest-detail-panel')), findsNothing);
    final scope = tester.widget<PopScope<Object?>>(
      find.descendant(
        of: find.byType(QuestCenterPage),
        matching: find.byWidgetPredicate((w) => w is PopScope<Object?>),
      ),
    );
    expect(scope.canPop, isTrue);
  });

  testWidgets('initial task target opens outside the retained query', (
    tester,
  ) async {
    final filters = QuestFilterController()..setQuery('Beta');
    addTearDown(filters.dispose);
    await _pump(tester, filters: filters, initialQuestId: 201);
    expect(find.byKey(const Key('quest-detail-title-201')), findsOneWidget);
    expect(find.byKey(const Key('quest-card-201')), findsNothing);
    expect(filters.query, 'Beta');
  });

  testWidgets('updated task target opens outside the retained query', (
    tester,
  ) async {
    final filters = QuestFilterController()..setQuery('Beta');
    addTearDown(filters.dispose);
    await _pump(tester, filters: filters);
    await _pump(tester, filters: filters, initialQuestId: 201);
    expect(find.byKey(const Key('quest-detail-title-201')), findsOneWidget);
    expect(find.byKey(const Key('quest-card-201')), findsNothing);
    expect(filters.query, 'Beta');
  });

  testWidgets('waiting task list scrolls in low landscape with enlarged text', (
    tester,
  ) async {
    await _pump(
      tester,
      size: const Size(570, 180),
      quests: const {},
      textScale: 1.3,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('等待任务数据'), findsOneWidget);
  });
}

Future<GameStateController> _pump(
  WidgetTester tester, {
  Size size = const Size(800, 400),
  QuestFilterController? filters,
  int? initialQuestId,
  Map<int, GameQuest> quests = const {
    201: GameQuest(
      id: 201,
      title: 'Alpha',
      detail: 'Original Alpha',
      category: 2,
      type: 4,
      state: 2,
      progressFlag: 0,
    ),
  },
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final controller = GameStateController(questStore: _Store(quests));
  addTearDown(controller.dispose);
  await controller.idle;
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
          initialQuestId: initialQuestId,
          filterController: filters,
          catalog: QuestCatalog(const [
            QuestCatalogEntry(
              gameId: 201,
              code: 'B1',
              name: 'Alpha',
              description: 'Original Alpha',
            ),
            QuestCatalogEntry(
              gameId: 202,
              code: 'B2',
              name: 'Beta',
              description: 'Original Beta',
            ),
          ]),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
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
