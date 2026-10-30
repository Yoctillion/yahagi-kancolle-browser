import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_models.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_node_label_resolver.dart';
import 'package:yahagi_kancolle_browser/src/battle/prediction/battle_prediction_executor.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';

import 'fixtures/kcsapi_fixtures.dart';

void main() {
  group('compass result decoding', () {
    const cases = <(int, int, int, BattleNodeKind, String)>[
      (0, 0, 0, BattleNodeKind.start, '起点'),
      (1, 0, 0, BattleNodeKind.quiet, '无战斗'),
      (2, 0, 0, BattleNodeKind.resource, '资源获得'),
      (3, 0, 0, BattleNodeKind.maelstrom, '资源损失'),
      (4, 0, 0, BattleNodeKind.battle, '普通战斗'),
      (4, 1, 0, BattleNodeKind.battle, '普通战斗'),
      (4, 2, 0, BattleNodeKind.nightBattle, '夜战'),
      (4, 3, 0, BattleNodeKind.nightBattle, '夜战'),
      (4, 4, 0, BattleNodeKind.airBattle, '航空战'),
      (4, 5, 0, BattleNodeKind.enemyCombined, '敌联合舰队'),
      (4, 6, 0, BattleNodeKind.airRaid, '长距离空袭战'),
      (4, 7, 0, BattleNodeKind.nightToDay, '夜转昼战'),
      (4, 8, 0, BattleNodeKind.radarAmbush, '雷达射击'),
      (4, 1, 15, BattleNodeKind.antiSubAir, '对潜空袭'),
      (6, 0, 0, BattleNodeKind.quiet, '无战斗'),
      (6, 1, 0, BattleNodeKind.quiet, '无战斗'),
      (6, 2, 0, BattleNodeKind.routeSelect, '路线选择'),
      (7, 0, 0, BattleNodeKind.airRecon, '航空侦察'),
      (7, 4, 0, BattleNodeKind.airBattle, '航空战'),
      (8, 0, 0, BattleNodeKind.escort, '护送成功'),
      (9, 0, 0, BattleNodeKind.transport, '运输点'),
      (10, 0, 0, BattleNodeKind.anchorage, '泊地修理'),
      (10, 1, 0, BattleNodeKind.airRaid, '长距离空袭战'),
      (99, 0, 0, BattleNodeKind.unknown, '节点事件'),
    ];
    for (final (eventId, eventKind, colorNo, kind, label) in cases) {
      test('event $eventId kind $eventKind color $colorNo is $label', () {
        final context = BattleContext(
          eventId: eventId,
          eventKind: eventKind,
          colorNo: colorNo,
        );

        expect(context.nodeKind, kind);
        expect(context.nodeTypeLabel, label);
        expect(context.isBossNode, isFalse);
      });
    }

    test('a boss node keeps its battle kind behind the boss label', () {
      const context = BattleContext(eventId: 5, eventKind: 2);

      expect(context.isBossNode, isTrue);
      expect(context.nodeKind, BattleNodeKind.nightBattle);
      expect(context.nodeTypeLabels, <String>['Boss 战']);
    });

    test('a submarine override replaces the label but not the node kind', () {
      const context = BattleContext(
        eventId: 4,
        eventKind: 1,
        nodeTypeOverride: '潜艇战',
      );

      expect(context.nodeKind, BattleNodeKind.battle);
      expect(context.nodeTypeLabels, <String>['潜艇战']);
    });

    test('practice is a plain battle whatever the stale event says', () {
      const context = BattleContext(practice: true, eventId: 5, eventKind: 2);

      expect(context.nodeKind, BattleNodeKind.battle);
      expect(context.isBossNode, isFalse);
      expect(context.nodeTypeLabel, '普通战斗');
    });
  });

  group('node name on the badge', () {
    test('a resolved letter sits on the badge and needs no text', () {
      const context = BattleContext(node: 3, nodeDisplayLabel: ' E ');

      expect(context.nodeBadgeLetter, 'E');
      expect(context.nodeTextBesideBadge, isNull);
    });

    test('an unresolved node falls back to a mark plus the spelled name', () {
      const context = BattleContext(node: 3);

      expect(context.nodeBadgeLetter, '?');
      expect(context.nodeTextBesideBadge, '节点 3');
    });

    test('practice has no letter to show', () {
      const context = BattleContext(practice: true);

      expect(context.nodeBadgeLetter, isEmpty);
      expect(context.nodeTextBesideBadge, '演习');
    });
  });

  group('color number parsing', () {
    late BattleController controller;

    setUp(() {
      controller = BattleController(
        gameState: () => GameState.empty,
        nodeLabelResolver: const EmptyBattleNodeLabelResolver(),
        predictionExecutor: const ImmediateBattlePredictionExecutor(),
      );
    });

    tearDown(() => controller.dispose());

    Future<void> navigate(String path, Map<String, Object?> extra, int seq) {
      controller.accept(
        kcsapiEvent(path, <String, Object?>{
          'api_maparea_id': 1,
          'api_mapinfo_no': 1,
          'api_no': seq,
          'api_event_id': 4,
          'api_event_kind': 1,
          ...extra,
        }, sequence: seq),
      );
      return controller.idle;
    }

    test(
      'an anti-submarine node is recognized from the compass reply',
      () async {
        await navigate('/kcsapi/api_req_map/start', <String, Object?>{
          'api_color_no': 15,
        }, 1);

        expect(controller.current!.context.nodeKind, BattleNodeKind.antiSubAir);
      },
    );

    test('the next node does not inherit the previous color', () async {
      await navigate('/kcsapi/api_req_map/start', <String, Object?>{
        'api_color_no': 15,
      }, 1);
      await navigate('/kcsapi/api_req_map/next', const <String, Object?>{}, 2);

      expect(controller.current!.context.nodeKind, BattleNodeKind.battle);
    });
  });
}
