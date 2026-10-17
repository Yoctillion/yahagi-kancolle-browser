import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_catalog.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_center_page.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_store.dart';

const _rewards =
    '二回選択報酬：[装備運用枠+8、二式爆雷★4、開発資材×40]'
    '[61cm五連装(酸素)魚雷★4×2、12.7cm連装高角砲改二★4、新型兵装資材×3]';

void main() {
  for (final scenario
      in <({Size size, double sidebar, double textScale, List<int> materials})>[
        (
          size: const Size(320, 780),
          sidebar: 0,
          textScale: 1,
          materials: const [100, 0, 0, 0],
        ),
        (
          size: const Size(390, 780),
          sidebar: 0,
          textScale: 1.4,
          materials: const [1000, 12000, 999999, 0],
        ),
        (
          size: const Size(667, 375),
          sidebar: 48,
          textScale: 1,
          materials: const [100, 0, 0, 0],
        ),
        (
          size: const Size(740, 360),
          sidebar: 48,
          textScale: 1.4,
          materials: const [1000, 12000, 99999, 0],
        ),
        (
          size: const Size(1180, 820),
          sidebar: 48,
          textScale: 1,
          materials: const [1000, 12000, 999999, 0],
        ),
      ]) {
    testWidgets('four rewards stay on one line at ${scenario.size} '
        'with text scale ${scenario.textScale} in both quest modes', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = scenario.size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = GameStateController(
        questStore: _RewardQuestStore(scenario.materials),
      );
      addTearDown(controller.dispose);
      await controller.idle;
      final catalog = QuestCatalog(<QuestCatalogEntry>[
        QuestCatalogEntry(
          gameId: 201,
          code: 'B1',
          name: '報酬のある任務',
          description: '任務を達成せよ。',
          rewards: _rewards,
          materials: scenario.materials,
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scenario.textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.only(left: scenario.sidebar),
              child: QuestCenterPage(controller: controller, catalog: catalog),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final mode in const ['进行中', '全任务']) {
        await tester.tap(
          find.descendant(
            of: find.byKey(const Key('quest-mode-tabs')),
            matching: find.text(mode),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(_resourceIcon(1));
        await tester.pumpAndSettle();
        _expectSingleRewardLine(tester, scenario.materials, reason: mode);

        final reward = find.text(_rewards);
        await tester.ensureVisible(reward);
        await tester.pumpAndSettle();
        final text = tester.widget<Text>(reward);
        final paragraph = tester.renderObject<RenderParagraph>(reward);
        expect(text.maxLines, isNull);
        expect(text.overflow, isNot(TextOverflow.ellipsis));
        expect(
          paragraph.size.height,
          greaterThan(paragraph.getMinIntrinsicHeight(double.infinity) + 1),
          reason: '$mode: additional rewards must still wrap',
        );
        expect(tester.takeException(), isNull, reason: mode);
      }
    });
  }
}

Finder _resourceIcon(int index) => find.descendant(
  of: find.byKey(const Key('quest-detail-panel')),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is Image &&
        widget.image is AssetImage &&
        (widget.image as AssetImage).assetName ==
            'assets/images/material/${index.toString().padLeft(2, '0')}.png',
  ),
);

void _expectSingleRewardLine(
  WidgetTester tester,
  List<int> materials, {
  required String reason,
}) {
  final panel = tester.getRect(find.byKey(const Key('quest-detail-panel')));
  final first = tester.getRect(_resourceIcon(1));
  double previousRight = panel.left;
  for (var index = 0; index < 4; index++) {
    final icon = _resourceIcon(index + 1);
    expect(icon, findsOneWidget);
    final iconRect = tester.getRect(icon);
    expect(iconRect.width, closeTo(18, 0.01));
    expect(iconRect.height, closeTo(18, 0.01));
    expect(
      iconRect.top,
      closeTo(first.top, 0.01),
      reason: '$reason: all four resource icons must share one row',
    );
    expect(iconRect.left, greaterThanOrEqualTo(previousRight));
    final resource = find.ancestor(of: icon, matching: find.byType(Row)).first;
    final number = find.descendant(
      of: resource,
      matching: find.text('${materials[index]}'),
    );
    expect(number, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(number);
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: '$reason: resource ${index + 1} must display its full value',
    );
    final paintedNumber = MatrixUtils.transformRect(
      paragraph.getTransformTo(null),
      Offset.zero & paragraph.size,
    );
    expect(paintedNumber.center.dy, closeTo(iconRect.center.dy, 0.01));
    expect(paintedNumber.left, greaterThanOrEqualTo(iconRect.right));
    expect(paintedNumber.right, lessThanOrEqualTo(panel.right));
    previousRight = paintedNumber.right;
    expect(
      find.ancestor(
        of: icon,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        ),
      ),
      findsNothing,
    );
  }
}

final class _RewardQuestStore extends QuestStore {
  _RewardQuestStore(this.materials);
  final List<int> materials;

  @override
  Future<Map<int, GameQuest>> loadQuests() async => <int, GameQuest>{
    201: GameQuest(
      id: 201,
      title: '報酬のある任務',
      detail: '任務を達成せよ。',
      category: 2,
      type: 4,
      state: 2,
      progressFlag: 0,
      materials: materials,
    ),
  };

  @override
  Future<void> saveQuests(Map<int, GameQuest> quests) async {}

  @override
  Future<void> clearQuests() async {}
}
