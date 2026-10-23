import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/prediction/battle_prediction_executor.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/capture/advance_warning_details.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_api_event_pipeline.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';

void main() {
  for (final damageControlMasterId in <int>[42, 43]) {
    test(
      'late binding rejects untrusted resurrection by item $damageControlMasterId',
      () async {
        final fixture = await _LateHpFixture.create(
          damageControlMasterId: damageControlMasterId,
        );
        addTearDown(fixture.dispose);
        await fixture.navigate(start: true);
        fixture.interrupt();
        await fixture.navigate();
        await fixture.fight(openingHp: 100, damage: 100);
        expect(fixture.predictedHp, damageControlMasterId == 42 ? 20 : 100);
        expect(fixture.stateHp, 100);
        expect(
          fixture.battle.current!.friendShips
              .singleWhere((ship) => ship.ownedShipId == 1002)
              .usedDamageControlItemIds,
          <int>[damageControlMasterId],
        );

        await fixture.bindHpUpdater();

        expect(fixture.stateHp, 1);
        expect(fixture.battle.isDamageControlStateTrusted, isFalse);
        expect(fixture.battle.isPredictionConfirmed, isFalse);
        expect(fixture.warnings.map((warning) => warning.ship.id), <int>[1002]);
        expect(
          fixture.warnings.single.damageControlStatus,
          AdvanceDamageControlStatus.unknown,
        );
        expect(fixture.warnings.single.hasConfirmedDamageControl, isFalse);
        expect(fixture.warnings.single.remainingDamageControls, isEmpty);
        expect(fixture.state.state.ships[1002]!.slotIds, <int>[501]);
        expect(fixture.state.state.slotItems.keys, <int>[501]);
        expect(
          fixture.state.state.slotItems[501]!.masterSlotItemId,
          damageControlMasterId,
        );
        await fixture.navigate();
        expect(fixture.stateHp, 1);
        expect(fixture.warnings.map((warning) => warning.ship.id), <int>[1002]);
        expect(
          fixture.warnings.single.damageControlStatus,
          AdvanceDamageControlStatus.unknown,
        );
        expect(fixture.state.state.ships[1002]!.slotIds, <int>[501]);
        expect(fixture.state.state.slotItems.keys, <int>[501]);
      },
    );
  }

  test(
    'late binding after a gap never replays the previous trusted battle',
    () async {
      final fixture = await _LateHpFixture.create();
      addTearDown(fixture.dispose);
      await fixture.navigate(start: true);
      await fixture.fight(openingHp: 20);
      expect(fixture.predictedHp, 20);
      expect(fixture.stateHp, 100);
      expect(fixture.battle.isDamageControlStateTrusted, isTrue);

      fixture.interrupt();
      await fixture.bindHpUpdater();

      expect(fixture.stateHp, 100);
      expect(fixture.battle.isDamageControlStateTrusted, isFalse);
      expect(fixture.battle.isPredictionConfirmed, isFalse);
      expect(fixture.warnings, isEmpty);
    },
  );

  test('late binding replays a fresh untrusted HP decrease', () async {
    final fixture = await _LateHpFixture.create();
    addTearDown(fixture.dispose);
    await fixture.navigate(start: true);
    fixture.interrupt();
    await fixture.navigate();
    await fixture.fight(openingHp: 100, damage: 80);
    expect(fixture.predictedHp, 20);
    expect(fixture.stateHp, 100);
    expect(fixture.battle.isDamageControlStateTrusted, isFalse);

    await fixture.bindHpUpdater();

    expect(fixture.stateHp, 20);
    fixture.expectUnknownCandidate();
    await fixture.navigate();
    fixture.expectUnknownCandidate();
  });

  test(
    'late binding keeps an untrusted zero HP prediction as a one HP candidate',
    () async {
      final fixture = await _LateHpFixture.create();
      addTearDown(fixture.dispose);
      await fixture.navigate(start: true);
      fixture.interrupt();
      await fixture.navigate();
      await fixture.fight(openingHp: 100, damage: 100);
      expect(fixture.predictedHp, 0);
      expect(fixture.stateHp, 100);

      await fixture.bindHpUpdater();

      expect(fixture.stateHp, 1);
      fixture.expectUnknownCandidate();
      await fixture.navigate();
      fixture.expectUnknownCandidate();
    },
  );

  test(
    'late binding never revives a ship whose current state is already zero',
    () async {
      final fixture = await _LateHpFixture.create(currentHp: 0);
      addTearDown(fixture.dispose);
      await fixture.navigate(start: true);
      fixture.interrupt();
      await fixture.navigate();
      await fixture.fight(openingHp: 100, damage: 80);
      expect(fixture.predictedHp, 20);
      expect(fixture.stateHp, 0);

      await fixture.bindHpUpdater();

      expect(fixture.stateHp, 0);
      expect(fixture.warnings, isEmpty);
      expect(fixture.battle.isDamageControlStateTrusted, isFalse);
      expect(fixture.battle.isPredictionConfirmed, isFalse);
    },
  );

  test('late untrusted binding cannot overwrite a queued zero HP', () async {
    final fixture = await _LateHpFixture.create();
    addTearDown(fixture.dispose);
    await fixture.navigate(start: true);
    fixture.interrupt();
    await fixture.navigate();
    await fixture.fight(openingHp: 100, damage: 80);
    expect(fixture.predictedHp, 20);
    expect(fixture.stateHp, 100);

    fixture.state.applyFriendlyBattleHp(<int, int>{
      1002: 0,
    }, DateTime.utc(2026, 10, 23, 0, 1));
    expect(fixture.stateHp, 100);
    await fixture.bindHpUpdater();

    expect(fixture.stateHp, 0);
    expect(fixture.warnings, isEmpty);
    expect(fixture.battle.isDamageControlStateTrusted, isFalse);
    expect(fixture.battle.isPredictionConfirmed, isFalse);
    expect(fixture.state.state.slotItems, isEmpty);
  });

  test(
    'late untrusted binding cannot raise queued five HP to twenty',
    () async {
      final fixture = await _LateHpFixture.create();
      addTearDown(fixture.dispose);
      await fixture.navigate(start: true);
      fixture.interrupt();
      await fixture.navigate();
      await fixture.fight(openingHp: 100, damage: 80);
      expect(fixture.predictedHp, 20);
      expect(fixture.stateHp, 100);

      fixture.state.applyFriendlyBattleHp(<int, int>{
        1002: 5,
      }, DateTime.utc(2026, 10, 23, 0, 1));
      expect(fixture.stateHp, 100);
      await fixture.bindHpUpdater();

      expect(fixture.stateHp, 5);
      fixture.expectUnknownCandidate();
    },
  );

  test(
    'a new gap invalidates an already queued untrusted HP decrease',
    () async {
      final fixture = await _LateHpFixture.create();
      addTearDown(fixture.dispose);
      await fixture.navigate(start: true);
      fixture.interrupt();
      await fixture.navigate();
      await fixture.fight(openingHp: 100, damage: 80);
      expect(fixture.predictedHp, 20);
      expect(fixture.stateHp, 100);

      fixture.battle.bindFriendlyHpUpdater(fixture.state.applyFriendlyBattleHp);
      expect(fixture.stateHp, 100);
      fixture.interrupt();
      await fixture.state.idle;

      expect(fixture.stateHp, 100);
      expect(fixture.warnings, isEmpty);
      expect(fixture.battle.isDamageControlStateTrusted, isFalse);
      expect(fixture.battle.isPredictionConfirmed, isFalse);
      await fixture.navigate();
      await fixture.fight(openingHp: 100, damage: 80);

      expect(fixture.stateHp, 20);
      fixture.expectUnknownCandidate();
    },
  );
}

final class _LateHpFixture {
  _LateHpFixture(this.state, this.battle, this.pipeline);

  final GameStateController state;
  final BattleController battle;
  final GameApiEventPipeline pipeline;
  var sequence = 0;
  var node = 0;

  int get stateHp => state.state.ships[1002]!.currentHp;

  int get predictedHp => battle.current!.friendShips
      .singleWhere((ship) => ship.ownedShipId == 1002)
      .currentHp;

  List<AdvanceWarningShip> get warnings => collectAdvanceWarningShips(
    state.state,
    damageControlStateTrusted: battle.isDamageControlStateTrusted,
  );

  static Future<_LateHpFixture> create({
    int currentHp = 100,
    int? damageControlMasterId,
  }) async {
    final state = GameStateController(
      initialState: GameState(
        memberId: 1001,
        hasPortData: true,
        hasEquipmentInventory: true,
        ships: <int, OwnedShip>{
          1000: const OwnedShip(
            id: 1000,
            masterId: 1000,
            level: 50,
            currentHp: 100,
            maxHp: 100,
          ),
          1002: OwnedShip(
            id: 1002,
            masterId: 1002,
            level: 50,
            currentHp: currentHp,
            maxHp: 100,
            slotIds: <int>[damageControlMasterId == null ? -1 : 501],
            extraSlotId: -1,
          ),
        },
        slotItems: <int, OwnedSlotItem>{
          if (damageControlMasterId != null)
            501: OwnedSlotItem(
              instanceId: 501,
              masterSlotItemId: damageControlMasterId,
            ),
        },
        fleets: const <Fleet>[
          Fleet(id: 1, name: 'Late HP binding', shipIds: <int>[1000, 1002]),
        ],
      ),
    );
    await state.initialize();
    final battle = BattleController(
      gameState: () => state.state,
      waitForGameState: () => state.idle,
      onDamageControlConsumed: state.applyDamageControlConsumption,
      predictionExecutor: const ImmediateBattlePredictionExecutor(),
    );
    final pipeline = GameApiEventPipeline(
      consumers: <GameApiEventConsumer>[state, battle],
      settleGameState: () async {
        await state.idle;
        await battle.idle;
        await state.idle;
      },
    );
    return _LateHpFixture(state, battle, pipeline);
  }

  void interrupt() {
    pipeline.invalidateQueuedEvents();
    battle.invalidateCaptureContinuity();
  }

  Future<void> navigate({bool start = false}) => publish(
    start ? '/kcsapi/api_req_map/start' : '/kcsapi/api_req_map/next',
    <String, Object?>{
      'api_maparea_id': 1,
      'api_mapinfo_no': 1,
      'api_no': ++node,
    },
  );

  Future<void> fight({required int openingHp, int damage = 0}) =>
      publish('/kcsapi/api_req_sortie/battle', <String, Object?>{
        'api_deck_id': 1,
        'api_f_nowhps': <int>[-1, 100, openingHp],
        'api_f_maxhps': <int>[-1, 100, 100],
        'api_e_nowhps': <int>[-1, 20],
        'api_e_maxhps': <int>[-1, 20],
        'api_ship_ke': <int>[-1, 501],
        if (damage > 0)
          'api_hougeki1': <String, Object?>{
            'api_at_eflag': <int>[1],
            'api_at_list': <int>[0],
            'api_df_list': <Object?>[
              <int>[1],
            ],
            'api_damage': <Object?>[
              <int>[damage],
            ],
          },
      });

  Future<void> bindHpUpdater() async {
    battle.bindFriendlyHpUpdater(state.applyFriendlyBattleHp);
    await state.idle;
    expect(state.lastError, isNull);
  }

  Future<void> publish(String path, Object? data) async {
    pipeline.add(
      CapturedApiEvent(
        path: path,
        requestParams: const <String, Object?>{'api_deck_id': '1'},
        responseBody: jsonEncode(<String, Object?>{
          'api_result': 1,
          'api_data': data,
        }),
        source: CaptureSource.xhr,
        sourceOrigin: 'https://example.invalid',
        capturedAt: DateTime.utc(
          2026,
          10,
          23,
        ).add(Duration(seconds: ++sequence)),
        sequence: sequence,
      ),
    );
    await pipeline.idle;
    expect(state.lastError, isNull);
    expect(battle.lastError, isNull);
  }

  void expectUnknownCandidate() {
    expect(battle.isDamageControlStateTrusted, isFalse);
    expect(battle.isPredictionConfirmed, isFalse);
    expect(warnings.map((warning) => warning.ship.id), <int>[1002]);
    expect(
      warnings.single.damageControlStatus,
      AdvanceDamageControlStatus.unknown,
    );
    expect(warnings.single.hasConfirmedDamageControl, isFalse);
    expect(warnings.single.remainingDamageControls, isEmpty);
    expect(state.state.slotItems, isEmpty);
    expect(state.state.ships[1002]!.slotIds, <int>[-1]);
    expect(state.state.ships[1002]!.extraSlotId, -1);
  }

  void dispose() {
    battle.dispose();
    state.dispose();
  }
}
