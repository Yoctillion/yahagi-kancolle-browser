import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/prediction/battle_prediction_executor.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/capture/advance_warning_details.dart';
import 'package:yahagi_kancolle_browser/src/game_state/combat_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_reducer.dart';

void main() {
  test(
    'mixed controls retain exact remaining instances across three nodes',
    () async {
      final reducer = GameStateReducer();
      var state = _inventoryState();
      final controller = BattleController(
        gameState: () => state,
        predictionExecutor: const ImmediateBattlePredictionExecutor(),
        onFriendlyHpUpdated: (hp, capturedAt) {
          state = reducer.applyFriendlyBattleHp(state, hp, capturedAt);
        },
        onDamageControlConsumed: (consumed, capturedAt) {
          state = reducer.applyDamageControlConsumption(
            state,
            consumed,
            capturedAt,
          );
        },
      );
      addTearDown(controller.dispose);

      Future<void> publish(
        String path,
        Map<String, Object?> data,
        int sequence,
      ) async {
        final event = _event(path, data, sequence);
        state = reducer.reduce(state, event);
        controller.accept(event);
        await controller.idle;
        expect(controller.lastError, isNull);
        expect(controller.isDamageControlStateTrusted, isTrue);
      }

      await publish('/kcsapi/api_req_map/start', _mapData, 1);
      await publish(
        '/kcsapi/api_req_sortie/battle',
        _battleData(100, [100]),
        2,
      );
      expect(state.ships[2]!.slotIds, <int>[-1, 503]);
      expect(state.ships[2]!.extraSlotId, 502);
      expect(_warning(state, controller).remainingDamageControls, <int, int>{
        42: 1,
        43: 1,
      });

      final afterFirstConsumption = state;
      controller.bindDamageControlUpdater((consumed, capturedAt) {
        state = reducer.applyDamageControlConsumption(
          state,
          consumed,
          capturedAt,
        );
      });
      expect(state, same(afterFirstConsumption));
      controller.accept(
        _event('/kcsapi/api_req_sortie/battle', _battleData(100, [100]), 2),
      );
      await controller.idle;
      expect(state, same(afterFirstConsumption));

      await publish('/kcsapi/api_req_map/next', _mapData, 3);
      await publish(
        '/kcsapi/api_req_sortie/battle',
        _battleData(20, [20, 80]),
        4,
      );
      expect(state.ships[2]!.slotIds, <int>[-1, -1]);
      expect(state.ships[2]!.extraSlotId, 502);
      expect(state.slotItems.keys, <int>[502]);
      expect(_warning(state, controller).remainingDamageControls, <int, int>{
        42: 1,
      });

      await publish('/kcsapi/api_req_map/next', _mapData, 5);
      await publish('/kcsapi/api_req_sortie/battle', _battleData(20, [20]), 6);
      expect(state.ships[2]!.slotIds, <int>[-1, -1]);
      expect(state.ships[2]!.extraSlotId, -1);
      expect(state.slotItems, isEmpty);
      expect(
        _warning(state, controller).damageControlStatus,
        AdvanceDamageControlStatus.missing,
      );
      expect(_warning(state, controller).remainingDamageControls, isEmpty);
    },
  );

  test(
    'combined retreat proposals remain visible until actual confirmation',
    () {
      final reducer = GameStateReducer();
      var state = _inventoryState().copyWith(
        combinedFleetType: CombinedFleetType.carrierTaskForce,
        ships: <int, OwnedShip>{
          for (var shipId = 1; shipId <= 6; shipId++)
            shipId: OwnedShip(
              id: shipId,
              masterId: shipId,
              level: 50,
              currentHp: 20,
              maxHp: 100,
              slotIds: <int>[500 + shipId],
            ),
        },
        slotItems: <int, OwnedSlotItem>{
          for (var shipId = 1; shipId <= 6; shipId++)
            500 + shipId: OwnedSlotItem(
              instanceId: 500 + shipId,
              masterSlotItemId: 42,
            ),
        },
        fleets: const <Fleet>[
          Fleet(id: 1, name: 'Main', shipIds: <int>[1, 2, 3]),
          Fleet(id: 2, name: 'Escort', shipIds: <int>[4, 5, 6]),
        ],
      );

      state = reducer.reduce(
        state,
        _event(
          '/kcsapi/api_req_combined_battle/battleresult',
          <String, Object?>{
            'api_escape_flag': 1,
            'api_escape': <String, Object?>{
              'api_escape_idx': <int>[2],
              'api_tow_idx': <int>[9],
            },
          },
          1,
        ),
      );
      expect(state.combatState.pendingEscapeShipIds, <int>[2, 6]);
      expect(state.combatState.escapedShipIds, isEmpty);
      expect(
        collectAdvanceWarningShips(
          state,
          damageControlStateTrusted: true,
        ).map((detail) => detail.ship.id),
        <int>[2, 3, 5, 6],
      );

      state = reducer.reduce(
        state,
        _event(
          '/kcsapi/api_req_combined_battle/goback_port',
          <String, Object?>{},
          2,
        ),
      );
      final remaining = collectAdvanceWarningShips(
        state,
        damageControlStateTrusted: true,
      );
      expect(state.combatState.escapedShipIds, <int>{2, 6});
      expect(remaining.map((detail) => detail.ship.id), <int>[3, 5]);
      expect(remaining.map((detail) => detail.position), <int>[3, 2]);
      expect(remaining.map((detail) => detail.fleetId), <int>[1, 2]);
      expect(
        remaining.every((detail) => detail.remainingDamageControls[42] == 1),
        isTrue,
      );
    },
  );

  test(
    'a port without ship data cannot restore interrupted inventory trust',
    () async {
      final reducer = GameStateReducer();
      var state = _inventoryState();
      final controller = BattleController(gameState: () => state);
      addTearDown(controller.dispose);

      Future<void> publish(
        String path,
        Map<String, Object?> data,
        int sequence,
      ) async {
        final event = _event(path, data, sequence);
        state = reducer.reduce(state, event);
        controller.accept(event);
        await controller.idle;
        expect(controller.lastError, isNull);
      }

      await publish('/kcsapi/api_req_map/start', _mapData, 1);
      controller.invalidateCaptureContinuity();
      await publish('/kcsapi/api_port/port', <String, Object?>{}, 2);
      await publish('/kcsapi/api_req_map/start', _mapData, 3);
      expect(controller.isDamageControlStateTrusted, isFalse);
      expect(
        _warning(state, controller).damageControlStatus,
        AdvanceDamageControlStatus.unknown,
      );
      expect(_warning(state, controller).remainingDamageControls, isEmpty);

      await publish('/kcsapi/api_port/port', <String, Object?>{
        'api_ship': <Object?>[
          for (final ship in state.ships.values)
            <String, Object?>{
              'api_id': ship.id,
              'api_ship_id': ship.masterId,
              'api_lv': ship.level,
              'api_nowhp': ship.currentHp,
              'api_maxhp': ship.maxHp,
              'api_slot': ship.slotIds,
              'api_slot_ex': ship.extraSlotId,
            },
        ],
      }, 4);
      await publish('/kcsapi/api_req_map/start', _mapData, 5);
      expect(controller.isDamageControlStateTrusted, isTrue);
      expect(_warning(state, controller).remainingDamageControls, <int, int>{
        42: 2,
        43: 1,
      });
    },
  );
}

AdvanceWarningShip _warning(GameState state, BattleController controller) =>
    collectAdvanceWarningShips(
      state,
      damageControlStateTrusted: controller.isDamageControlStateTrusted,
    ).single;

const _mapData = <String, Object?>{
  'api_maparea_id': 1,
  'api_mapinfo_no': 1,
  'api_no': 1,
};

GameState _inventoryState() => GameState(
  hasPortData: true,
  hasEquipmentInventory: true,
  combatState: const CombatState(isActive: true, sortieFleetId: 1),
  ships: const <int, OwnedShip>{
    1: OwnedShip(id: 1, masterId: 1, level: 50, currentHp: 100, maxHp: 100),
    2: OwnedShip(
      id: 2,
      masterId: 2,
      level: 50,
      currentHp: 20,
      maxHp: 100,
      slotIds: <int>[501, 503],
      extraSlotId: 502,
    ),
  },
  fleets: const <Fleet>[
    Fleet(id: 1, name: 'Main', shipIds: <int>[1, 2]),
  ],
  slotItems: const <int, OwnedSlotItem>{
    501: OwnedSlotItem(instanceId: 501, masterSlotItemId: 42),
    502: OwnedSlotItem(instanceId: 502, masterSlotItemId: 42),
    503: OwnedSlotItem(instanceId: 503, masterSlotItemId: 43),
  },
);

CapturedApiEvent _event(String path, Map<String, Object?> data, int sequence) =>
    CapturedApiEvent(
      path: path,
      responseBody: jsonEncode(<String, Object?>{
        'api_result': 1,
        'api_data': data,
      }),
      requestParams: path.endsWith('/start')
          ? const <String, Object?>{'api_deck_id': '1'}
          : const <String, Object?>{},
      source: CaptureSource.xhr,
      sourceOrigin: 'https://w01y.kancolle-server.com',
      capturedAt: DateTime.utc(2026, 10, 23),
      sequence: sequence,
    );

Map<String, Object?> _battleData(
  int openingHp,
  List<int> damages,
) => <String, Object?>{
  'api_deck_id': 1,
  'api_f_nowhps': <int>[-1, 100, openingHp],
  'api_f_maxhps': <int>[-1, 100, 100],
  'api_e_nowhps': <int>[-1, 20],
  'api_e_maxhps': <int>[-1, 20],
  'api_ship_ke': <int>[-1, 501],
  'api_hougeki1': <String, Object?>{
    'api_at_eflag': List<int>.filled(damages.length, 1),
    'api_at_list': List<int>.filled(damages.length, 0),
    'api_df_list': List<List<int>>.generate(damages.length, (_) => <int>[1]),
    'api_damage': <Object?>[
      for (final damage in damages) <int>[damage],
    ],
  },
};
