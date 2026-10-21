import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_serializer.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_catalog.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_center_page.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_store.dart';
import 'package:yahagi_kancolle_browser/src/quest/shared_preferences_quest_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/display_mode_store.dart';

import 'fixtures/kcsapi_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Expectations come from the shipped JSON, independently of model parsing.
  final raw =
      jsonDecode(File('assets/data/quests-scn.json').readAsStringSync())
          as Map<String, dynamic>;
  final ids = raw.keys.map(int.parse).toList()..sort();
  late QuestCatalog catalog;

  setUpAll(() async {
    catalog = await QuestCatalog.loadAsset();
    expect(catalog.entries.length, ids.length);
    expect(ids.length, greaterThan(500));
  });

  test('every bundled reward survives translation fallback unchanged', () {
    final translated = catalog.withTranslationFallbackFrom(catalog);
    for (final id in ids) {
      final json = raw['$id'] as Map<String, dynamic>;
      final expected = _fixedResources(json);
      for (final source in <QuestCatalog>[catalog, translated]) {
        final entry = source.byGameId(id)!;
        expect(entry.materials, expected, reason: '$id/${json['code']}');
        expect(
          entry.rewards,
          _expectedRewards(id, json),
          reason: '$id/${json['code']}',
        );
      }
    }
  });

  test(
    'every bundled quest preserves resources through both account caches',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final quests = <int, GameQuest>{
        for (final id in ids)
          id: GameQuest(
            id: id,
            title: raw['$id']['name'] as String,
            detail: raw['$id']['desc'] as String,
            category: catalog.byGameId(id)!.category,
            type: catalog.byGameId(id)!.period,
            state: 2,
            progressFlag: 0,
            materials: _fixedResources(raw['$id'] as Map<String, dynamic>),
          ),
      };
      final state = GameState.empty.copyWith(quests: quests);
      final restoredState = GameStateSerializer.deserialize(
        GameStateSerializer.serialize(state),
      );
      final store = SharedPreferencesQuestStore(memberId: 1001);
      await store.saveQuests(quests);
      final restoredQuests = await store.loadQuests();
      for (final restored in <Map<int, GameQuest>>[
        restoredState.quests,
        restoredQuests,
      ]) {
        expect(restored.length, ids.length);
        for (final id in ids) {
          expect(
            restored[id]?.materials,
            _fixedResources(raw['$id'] as Map<String, dynamic>),
            reason: '$id',
          );
          expect(restored[id]?.state, 2, reason: '$id');
        }
      }
    },
  );

  const batchSize = 100;
  for (var first = 0; first < ids.length; first += batchSize) {
    final last = (first + batchSize).clamp(0, ids.length);
    final batch = ids.sublist(first, last);
    testWidgets('every bundled reward survives states and views '
        '(${first + 1}-$last of ${ids.length})', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = GameStateController(questStore: _EmptyQuestStore());
      addTearDown(controller.dispose);
      await controller.idle;
      var sequence = 0;

      Future<void> snapshot(int id, int state, List<int> materials) async {
        final json = raw['$id'] as Map<String, dynamic>;
        controller.accept(
          kcsapiEvent(
            '/kcsapi/api_get_member/questlist',
            <String, Object?>{
              'api_count': state == 0 ? 0 : 1,
              'api_page_count': 1,
              'api_exec_count': state >= 2 ? 1 : 0,
              'api_list': <Object?>[
                if (state != 0)
                  <String, Object?>{
                    'api_no': id,
                    'api_category': catalog.byGameId(id)!.category,
                    'api_type': catalog.byGameId(id)!.period,
                    'api_state': state,
                    'api_progress_flag': state == 3 ? 2 : 0,
                    'api_title': json['name'],
                    'api_detail': json['desc'],
                    'api_get_material': materials,
                  },
              ],
            },
            capturedAt: DateTime.now().toUtc(),
            sequence: ++sequence,
            requestParams: const <String, Object?>{
              'api_tab_id': '0',
              'api_page_no': '1',
              'yahagi_full_quest_snapshot': '1',
            },
          ),
        );
        await controller.idle;
        expect(controller.lastError, isNull, reason: '$id snapshot $state');
      }

      Future<void> action(int id, String action) async {
        controller.accept(
          kcsapiEvent(
            '/kcsapi/api_req_quest/$action',
            const <String, Object?>{},
            capturedAt: DateTime.now().toUtc(),
            sequence: ++sequence,
            requestParams: <String, Object?>{'api_quest_id': '$id'},
          ),
        );
        await controller.idle;
        expect(controller.lastError, isNull, reason: '$id $action');
      }

      Future<void> check(
        int id,
        QuestCenterMode mode,
        List<int> expected,
        String phase,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: QuestCenterPage(
              controller: controller,
              catalog: catalog,
              initialQuestId: id,
              mode: mode,
            ),
          ),
        );
        await _openRewardTab(tester, id);
        final json = raw['$id'] as Map<String, dynamic>;
        _expectReward(tester, id, json, expected, '$phase/${mode.name}');
        expect(tester.takeException(), isNull, reason: '$id/$phase');
      }

      for (final id in batch) {
        final json = raw['$id'] as Map<String, dynamic>;
        final materials = _fixedResources(json);
        await snapshot(id, 0, materials);
        await check(id, QuestCenterMode.all, materials, 'catalog only');
        await snapshot(id, 1, materials);
        await check(id, QuestCenterMode.all, materials, 'unaccepted');
        await action(id, 'start');
        expect(controller.state.quests[id]?.state, 2, reason: '$id start');
        await check(id, QuestCenterMode.all, materials, 'accepted');
        await check(id, QuestCenterMode.active, materials, 'accepted');
        await action(id, 'stop');
        expect(controller.state.quests.containsKey(id), isFalse);
        expect(controller.state.availableQuests[id]?.state, 1);
        await check(id, QuestCenterMode.all, materials, 'stopped');
        await action(id, 'start');
        await snapshot(id, 3, materials);
        await check(id, QuestCenterMode.all, materials, 'claimable');
        await check(id, QuestCenterMode.active, materials, 'claimable');
        await action(id, 'clearitemget');
        expect(controller.state.quests.containsKey(id), isFalse);
        expect(controller.state.availableQuests.containsKey(id), isFalse);
        await check(id, QuestCenterMode.all, materials, 'claimed');

        // Includes a legitimate zero, and every amount differs from static.
        final live = <int>[
          materials[0] == 0 ? 1 : 0,
          materials[1] + 17,
          materials[2] + 29,
          materials[3] + 41,
        ];
        await snapshot(id, 2, live);
        await check(id, QuestCenterMode.all, live, 'API override');
        await check(id, QuestCenterMode.active, live, 'API override');
        await action(id, 'stop');
        await check(id, QuestCenterMode.all, live, 'stopped API override');
      }
    }, timeout: const Timeout(Duration(minutes: 5)));

    testWidgets('phone shows every reward with enlarged text '
        '(${first + 1}-$last of ${ids.length})', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 780);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = GameStateController(questStore: _EmptyQuestStore());
      addTearDown(controller.dispose);
      await controller.idle;
      var sequence = 0;
      for (final id in batch) {
        final json = raw['$id'] as Map<String, dynamic>;
        final materials = _fixedResources(json);
        controller.accept(
          kcsapiEvent(
            '/kcsapi/api_get_member/questlist',
            <String, Object?>{
              'api_count': 1,
              'api_page_count': 1,
              'api_exec_count': 1,
              'api_list': <Object?>[
                <String, Object?>{
                  'api_no': id,
                  'api_category': catalog.byGameId(id)!.category,
                  'api_type': catalog.byGameId(id)!.period,
                  'api_state': 2,
                  'api_progress_flag': 0,
                  'api_title': json['name'],
                  'api_detail': json['desc'],
                  'api_get_material': materials,
                },
              ],
            },
            capturedAt: DateTime.now().toUtc(),
            sequence: ++sequence,
            requestParams: const <String, Object?>{
              'yahagi_full_quest_snapshot': '1',
            },
          ),
        );
        await controller.idle;
        for (final mode in <QuestCenterMode>[
          QuestCenterMode.all,
          QuestCenterMode.active,
        ]) {
          for (final displayMode in <DisplayMode>[
            DisplayMode.auto,
            DisplayMode.landscape,
          ]) {
            final phase = 'phone/${mode.name}/${displayMode.name}';
            final reason = '$id/${json['code']}/$phase';
            await tester.pumpWidget(
              MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(1.3)),
                  child: child!,
                ),
                home: Padding(
                  padding: EdgeInsets.only(
                    left: displayMode == DisplayMode.landscape ? 48 : 0,
                  ),
                  child: QuestCenterPage(
                    controller: controller,
                    catalog: catalog,
                    initialQuestId: id,
                    mode: mode,
                    displayMode: displayMode,
                  ),
                ),
              ),
            );
            await _openRewardTab(tester, id);
            _expectReward(tester, id, json, materials, phase);
            expect(
              find.byType(VerticalDivider),
              displayMode == DisplayMode.landscape
                  ? findsOneWidget
                  : findsNothing,
              reason: reason,
            );
            final reward = find.descendant(
              of: find.byKey(const Key('quest-detail-panel')),
              matching: find.text(_expectedRewards(id, json)),
            );
            await tester.ensureVisible(reward);
            await tester.pump();
            final text = tester.widget<Text>(reward);
            expect(text.maxLines, isNull, reason: reason);
            expect(text.overflow, isNot(TextOverflow.ellipsis), reason: reason);
            final panel = tester.getRect(
              find.byKey(const Key('quest-detail-panel')),
            );
            final rect = tester.getRect(reward);
            expect(rect.left, greaterThanOrEqualTo(panel.left), reason: reason);
            expect(rect.right, lessThanOrEqualTo(panel.right), reason: reason);
            expect(tester.takeException(), isNull, reason: reason);
          }
        }
      }
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}

// These six audited expectations are independent of the production correction
// registry: screenshots confirm the steel amount and the B209 choice amount.
String _expectedRewards(int id, Map<String, dynamic> json) => switch (id) {
  131 => '開発資材×3',
  315 => '給糧艦「間宮」, プレゼント箱',
  602 => '開発資材',
  603 => '開発資材, 高速建造材',
  1029 =>
    '二回選択報酬：[開発資材×13、新型砲熕兵装資材×2、改修資材×5]'
        '[25mm三連装機銃★9×2、13号対空電探改(後期型)★8、12.7cm連装砲D型改二★7]',
  _ => json['rewards'] as String,
};

List<int> _fixedResources(Map<String, dynamic> json) =>
    json['code'] == 'L2507C1'
    ? <int>[100, 100, 100, 100]
    : (json['resources'][0] as List<dynamic>)
          .map((value) => value == '' ? 0 : (value as num).toInt())
          .toList();

Future<void> _openRewardTab(WidgetTester tester, int id) async {
  // A portrait scope change returns to the list; explicit initialQuestId links
  // may already have opened the detail. Both paths now put rewards in a tab.
  if (find.byKey(const Key('quest-detail-panel')).evaluate().isEmpty) {
    final card = find.byKey(Key('quest-card-$id'));
    await tester.ensureVisible(card);
    await tester.pump();
    await tester.tap(card);
    await tester.pump();
  }
  final rewardsTab = find.byKey(const Key('quest-detail-tab-rewards'));
  await tester.ensureVisible(rewardsTab);
  await tester.pump();
  await tester.tap(rewardsTab);
  await tester.pump();
}

void _expectReward(
  WidgetTester tester,
  int id,
  Map<String, dynamic> raw,
  List<int> materials,
  String phase,
) {
  final reason = '$id/${raw['code']}/$phase';
  final panel = find.byKey(const Key('quest-detail-panel'));
  expect(
    find.byKey(Key('quest-detail-title-$id')),
    findsOneWidget,
    reason: reason,
  );
  expect(
    find.descendant(of: panel, matching: find.byType(Image)),
    findsNWidgets(4),
    reason: reason,
  );
  for (var index = 0; index < 4; index++) {
    final asset =
        'assets/images/material/${(index + 1).toString().padLeft(2, '0')}.png';
    final icon = find.descendant(
      of: panel,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName == asset,
      ),
    );
    expect(icon, findsOneWidget, reason: reason);
    final row = find.ancestor(of: icon, matching: find.byType(Row)).first;
    expect(
      find.descendant(of: row, matching: find.text('${materials[index]}')),
      findsOneWidget,
      reason: '$reason/resource ${index + 1}',
    );
  }
  expect(
    find.descendant(of: panel, matching: find.text(_expectedRewards(id, raw))),
    findsOneWidget,
    reason: reason,
  );
}

class _EmptyQuestStore extends QuestStore {
  @override
  Future<Map<int, GameQuest>> loadQuests() async => <int, GameQuest>{};

  @override
  Future<void> saveQuests(Map<int, GameQuest> quests) async {}

  @override
  Future<void> clearQuests() async {}
}
