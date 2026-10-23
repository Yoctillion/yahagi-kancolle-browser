import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/prediction/battle_prediction_executor.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_api_event_pipeline.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';

void main() {
  test(
    'remaining repeated personnel precedes expansion goddess across nodes',
    () async {
      final state = GameStateController(
        initialState: GameState(
          hasPortData: true,
          hasEquipmentInventory: true,
          ships: const <int, OwnedShip>{
            1001: OwnedShip(
              id: 1001,
              masterId: 1,
              level: 50,
              currentHp: 100,
              maxHp: 100,
              slotIds: <int>[501, 502],
              extraSlotId: 503,
            ),
          },
          slotItems: const <int, OwnedSlotItem>{
            501: OwnedSlotItem(instanceId: 501, masterSlotItemId: 42),
            502: OwnedSlotItem(instanceId: 502, masterSlotItemId: 42),
            503: OwnedSlotItem(instanceId: 503, masterSlotItemId: 43),
          },
          fleets: const <Fleet>[
            Fleet(id: 1, name: 'Test', shipIds: <int>[1001]),
          ],
        ),
      );
      addTearDown(state.dispose);
      await state.initialize();
      final battle = BattleController(
        gameState: () => state.state,
        waitForGameState: () => state.idle,
        onFriendlyHpUpdated: state.applyFriendlyBattleHp,
        onDamageControlConsumed: state.applyDamageControlConsumption,
        predictionExecutor: const ImmediateBattlePredictionExecutor(),
      );
      addTearDown(battle.dispose);
      final pipeline = GameApiEventPipeline(
        consumers: <GameApiEventConsumer>[state, battle],
        settleGameState: () async {
          await state.idle;
          await battle.idle;
          await state.idle;
        },
      );
      var sequence = 0;
      Future<void> publish(String path, Map<String, Object?> data) async {
        pipeline.add(
          CapturedApiEvent(
            path: path,
            responseBody: jsonEncode(<String, Object?>{
              'api_result': 1,
              'api_data': data,
            }),
            requestParams: const <String, Object?>{'api_deck_id': '1'},
            source: CaptureSource.xhr,
            sourceOrigin: 'https://w01y.kancolle-server.com',
            capturedAt: DateTime.utc(2026, 10, 23),
            sequence: ++sequence,
          ),
        );
        await pipeline.idle;
      }

      await publish('/kcsapi/api_req_map/start', _node(1));
      await publish('/kcsapi/api_req_sortie/battle', _battle(100, <int>[100]));
      expect(battle.lastError, isNull);
      expect(state.state.ships[1001]!.currentHp, 20);
      expect(state.state.ships[1001]!.slotIds, <int>[-1, 502]);
      expect(state.state.ships[1001]!.extraSlotId, 503);
      expect(state.state.slotItems.keys, unorderedEquals(<int>[502, 503]));

      await publish('/kcsapi/api_req_map/next', _node(2));
      await publish(
        '/kcsapi/api_req_sortie/battle',
        _battle(20, <int>[65, 24]),
      );

      expect(battle.lastError, isNull);
      expect(state.lastError, isNull);
      expect(battle.isDamageControlStateTrusted, isTrue);
      expect(state.state.ships[1001]!.currentHp, 100);
      expect(battle.current!.friendMain.single.usedDamageControlItemIds, <int>[
        42,
        42,
        43,
      ]);
      expect(state.state.ships[1001]!.slotIds, <int>[-1, -1]);
      expect(state.state.ships[1001]!.extraSlotId, -1);
      expect(state.state.slotItems, isEmpty);
    },
  );
}

Map<String, Object?> _node(int node) => <String, Object?>{
  'api_maparea_id': 1,
  'api_mapinfo_no': 1,
  'api_no': node,
};

Map<String, Object?> _battle(int openingHp, List<int> damage) =>
    <String, Object?>{
      'api_deck_id': 1,
      'api_f_nowhps': <int>[-1, openingHp],
      'api_f_maxhps': const <int>[-1, 100],
      'api_e_nowhps': const <int>[-1, 20],
      'api_e_maxhps': const <int>[-1, 20],
      'api_ship_ke': const <int>[-1, 501],
      'api_hougeki1': <String, Object?>{
        'api_at_eflag': List<int>.filled(damage.length, 1),
        'api_at_list': List<int>.filled(damage.length, 0),
        'api_df_list': List<List<int>>.filled(damage.length, const <int>[0]),
        'api_damage': <Object?>[
          for (final amount in damage) <int>[amount],
        ],
      },
    };
