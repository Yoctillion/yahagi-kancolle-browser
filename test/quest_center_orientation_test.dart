import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_catalog.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_center_page.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/display_mode_store.dart';

const _rewards = '二回選択報酬：[開発資材×40、二式爆雷★4][新型兵装資材×3、改修資材×5]';
final _catalog = QuestCatalog(const <QuestCatalogEntry>[
  QuestCatalogEntry(
    gameId: 201,
    code: 'B1',
    name: '横屏布局验证任务，包含较长的任务标题',
    description: '任务说明需要能够在详情中换行，并可滚动查看全部奖励。',
    rewards: _rewards,
    materials: <int>[100, 200, 300, 400],
  ),
]);

void main() {
  for (final mode in QuestCenterMode.values) {
    for (final window in const <Size>[
      Size(667, 375),
      Size(740, 360),
      Size(844, 390),
    ]) {
      testWidgets('narrow landscape $window keeps $mode list beside detail', (
        tester,
      ) async {
        final controller = await _prepare(tester, window);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.only(left: 48),
                child: QuestCenterPage(
                  controller: controller,
                  catalog: _catalog,
                  mode: mode,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        _expectSideBySide(tester);
        await tester.ensureVisible(find.text(_rewards));
        await tester.pumpAndSettle();
        expect(find.text(_rewards), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('automatic portrait keeps the list above detail', (tester) async {
    final controller = await _prepare(tester, const Size(390, 780));
    await tester.pumpWidget(
      MaterialApp(
        home: QuestCenterPage(controller: controller, catalog: _catalog),
      ),
    );
    await tester.pumpAndSettle();
    _expectStacked(tester);
    expect(tester.takeException(), isNull);
  });

  for (final window in const <Size>[
    Size(844, 390),
    Size(1280, 800),
    Size(800, 1280),
  ]) {
    for (final displayMode in <DisplayMode>[
      DisplayMode.landscape,
      DisplayMode.portrait,
    ]) {
      testWidgets('$displayMode overrides window geometry $window', (
        tester,
      ) async {
        final controller = await _prepare(tester, window);
        await tester.pumpWidget(
          MaterialApp(
            home: QuestCenterPage(
              controller: controller,
              catalog: _catalog,
              displayMode: displayMode,
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (displayMode == DisplayMode.landscape) {
          _expectSideBySide(tester);
        } else {
          _expectStacked(tester);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final window in const <Size>[
    Size(650, 481),
    Size(650, 482),
    Size(800, 1280),
    Size(1280, 800),
    Size(590, 650),
    Size(650, 590),
  ]) {
    testWidgets('automatic mode follows actual screen orientation at $window', (
      tester,
    ) async {
      final controller = await _prepare(tester, window);
      await tester.pumpWidget(
        MaterialApp(
          home: QuestCenterPage(controller: controller, catalog: _catalog),
        ),
      );
      await tester.pumpAndSettle();
      if (window.width > window.height) {
        _expectSideBySide(tester);
      } else {
        _expectStacked(tester);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final window in const <Size>[
    Size(673, 841),
    Size(841, 673),
    Size(720, 720),
    Size(600, 700),
  ]) {
    for (final displayMode in DisplayMode.values) {
      for (final mode in QuestCenterMode.values) {
        testWidgets('near-square foldable $window keeps $mode side by side '
            'in $displayMode with a sidebar', (tester) async {
          final controller = await _prepare(tester, window);
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(1.3)),
                child: child!,
              ),
              home: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: QuestCenterPage(
                    controller: controller,
                    catalog: _catalog,
                    mode: mode,
                    displayMode: displayMode,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          _expectSideBySide(tester);
          await tester.ensureVisible(find.text(_rewards));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  for (final mode in QuestCenterMode.values) {
    for (final window in const <Size>[Size(600, 320), Size(390, 780)]) {
      testWidgets('forced landscape $window with enlarged $mode cards fits', (
        tester,
      ) async {
        final controller = await _prepare(tester, window, category: 5);
        final catalog = QuestCatalog(const <QuestCatalogEntry>[
          QuestCatalogEntry(
            gameId: 201,
            code: 'L2507C1',
            name: '横屏布局验证任务，包含较长的任务标题',
            description: '任务说明需要能够在详情中换行，并可滚动查看全部奖励。',
            rewards: _rewards,
            materials: <int>[100, 200, 300, 400],
          ),
        ]);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.3)),
              child: child!,
            ),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.only(left: 48),
                child: QuestCenterPage(
                  controller: controller,
                  catalog: catalog,
                  mode: mode,
                  displayMode: DisplayMode.landscape,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        _expectSideBySide(tester);
        final card = tester.getRect(find.byKey(const Key('quest-card-201')));
        final code = tester.getRect(
          find.byKey(const Key('quest-card-code-201')),
        );
        expect(code.left, greaterThanOrEqualTo(card.left));
        expect(code.right, lessThanOrEqualTo(card.right));
        final status = tester.getRect(
          find.byKey(const Key('quest-card-status-201')),
        );
        expect(status.right, lessThanOrEqualTo(card.right));
        expect(status.bottom, lessThanOrEqualTo(card.bottom));
        await tester.ensureVisible(find.text(_rewards));
        await tester.pumpAndSettle();
        final reward = tester.getRect(find.text(_rewards));
        final panel = tester.getRect(
          find.byKey(const Key('quest-detail-panel')),
        );
        expect(reward.left, greaterThanOrEqualTo(panel.left));
        expect(reward.right, lessThanOrEqualTo(panel.right));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('unknown quest labels remain readable in narrow landscape', (
    tester,
  ) async {
    final controller = await _prepare(
      tester,
      const Size(390, 780),
      store: _EmptyStore(),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.only(left: 48),
            child: QuestCenterPage(
              controller: controller,
              catalog: _catalog,
              mode: QuestCenterMode.all,
              displayMode: DisplayMode.landscape,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    _expectSideBySide(tester);
    final card = find.byKey(const Key('quest-card-201'));
    expect(
      find.descendant(of: card, matching: find.text('状态未知')),
      findsOneWidget,
    );
    for (final label in <String>['出击', '单次']) {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: card, matching: find.text(label)),
      );
      expect(
        paragraph.size.width,
        greaterThanOrEqualTo(paragraph.getMinIntrinsicWidth(double.infinity)),
        reason:
            '$label needs enough width to paint at least one full character',
      );
    }
    expect(tester.takeException(), isNull);
  });
}

Future<GameStateController> _prepare(
  WidgetTester tester,
  Size size, {
  int category = 2,
  QuestStore? store,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final controller = GameStateController(questStore: store ?? _Store(category));
  addTearDown(controller.dispose);
  await controller.idle;
  return controller;
}

void _expectSideBySide(WidgetTester tester) {
  final card = tester.getRect(find.byKey(const Key('quest-card-201')));
  final detail = tester.getRect(find.byKey(const Key('quest-detail-panel')));
  expect(detail.left, greaterThanOrEqualTo(card.right));
  expect(detail.top, lessThan(card.bottom));
  expect(detail.bottom, greaterThan(card.top));
}

void _expectStacked(WidgetTester tester) {
  final card = tester.getRect(find.byKey(const Key('quest-card-201')));
  final detail = tester.getRect(find.byKey(const Key('quest-detail-panel')));
  expect(detail.top, greaterThanOrEqualTo(card.bottom));
  expect(detail.left, lessThan(card.right));
}

class _Store extends QuestStore {
  _Store(this.category);

  final int category;

  @override
  Future<Map<int, GameQuest>> loadQuests() async => <int, GameQuest>{
    201: GameQuest(
      id: 201,
      title: '横屏布局验证任务，包含较长的任务标题',
      detail: '任务说明需要能够在详情中换行，并可滚动查看全部奖励。',
      category: category,
      type: 4,
      state: 2,
      progressFlag: 1,
      materials: <int>[100, 200, 300, 400],
    ),
  };

  @override
  Future<void> saveQuests(Map<int, GameQuest> quests) async {}

  @override
  Future<void> clearQuests() async {}
}

class _EmptyStore extends QuestStore {
  @override
  Future<Map<int, GameQuest>> loadQuests() async => <int, GameQuest>{};

  @override
  Future<void> saveQuests(Map<int, GameQuest> quests) async {}

  @override
  Future<void> clearQuests() async {}
}
