import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_models.dart';
import 'package:yahagi_kancolle_browser/src/battle/prediction/battle_prediction_executor.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/capture/advance_warning_details.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_api_event_pipeline.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';

const _cases = <_PartialFleetCase>[
  _PartialFleetCase(
    name: 'six-ship missing flagship',
    count: 6,
    missingPosition: 0,
    targetPosition: 5,
  ),
  _PartialFleetCase(
    name: 'seven-ship missing middle ship',
    count: 7,
    missingPosition: 3,
    targetPosition: 6,
  ),
  _PartialFleetCase(
    name: 'combined main missing middle ship',
    count: 12,
    missingPosition: 1,
    targetPosition: 5,
    combined: true,
  ),
  _PartialFleetCase(
    name: 'combined escort missing flagship',
    count: 12,
    missingPosition: 6,
    targetPosition: 11,
    combined: true,
  ),
];

void main() {
  _trailingMainGapTests();
  for (final scenario in _cases) {
    test(
      '${scenario.name} keeps depleted wing HP at its original slot',
      () async {
        final fixture = await _PartialFleetFixture.create(
          scenario,
          startWithMissingShip: true,
        );
        addTearDown(fixture.dispose);

        await fixture.navigate(start: true);
        fixture.expectWarning();
        await fixture.fight();

        fixture.expectMappedHp();
        await fixture.navigate();
        fixture.expectWarning();
      },
    );

    test(
      '${scenario.name} stays depleted after require_info loses a ship',
      () async {
        final fixture = await _PartialFleetFixture.create(
          scenario,
          startWithMissingShip: false,
        );
        addTearDown(fixture.dispose);

        await fixture.navigate(start: true);
        await fixture.fight(consume: true);
        expect(fixture.state.state.slotItems, isEmpty);
        expect(fixture.state.state.ships[scenario.targetId]!.slotIds, <int>[
          -1,
        ]);
        expect(fixture.state.state.ships[scenario.targetId]!.extraSlotId, -1);
        expect(
          fixture.battle.current!.friendShips
              .singleWhere((ship) => ship.ownedShipId == scenario.targetId)
              .usedDamageControlItemIds,
          <int>[42, 43],
        );

        await fixture.publish(
          '/kcsapi/api_get_member/require_info',
          <String, Object?>{
            'api_ship': <Object?>[
              for (var position = 0; position < scenario.count; position++)
                if (position != scenario.missingPosition)
                  <String, Object?>{
                    'api_id': 1000 + position,
                    'api_ship_id': 1000 + position,
                    'api_lv': 50,
                    'api_nowhp': position == scenario.targetPosition ? 20 : 100,
                    'api_maxhp': 100,
                    'api_slot': <int>[
                      if (position == scenario.targetPosition) -1,
                    ],
                    'api_slot_ex': -1,
                  },
            ],
          },
        );
        expect(
          fixture.state.state.ships.containsKey(scenario.missingId),
          isFalse,
        );
        fixture.expectWarning();
        await fixture.navigate();
        await fixture.fight();

        fixture.expectMappedHp();
        expect(fixture.state.state.slotItems, isEmpty);
        await fixture.navigate();
        fixture.expectWarning();
      },
    );
  }
}

void _trailingMainGapTests() {
  for (final absoluteTarget in <int>[6, 7]) {
    test(
      'missing last main ship keeps absolute target $absoluteTarget on its escort slot',
      () async {
        final scenario = _PartialFleetCase(
          name: 'combined missing last main ship',
          count: 12,
          missingPosition: 5,
          targetPosition: absoluteTarget,
          combined: true,
        );
        final fixture = await _PartialFleetFixture.create(
          scenario,
          startWithMissingShip: true,
        );
        addTearDown(fixture.dispose);
        await fixture.navigate(start: true);
        await fixture.publish(
          '/kcsapi/api_req_combined_battle/battle',
          <String, Object?>{
            'api_deck_id': 1,
            'api_f_nowhps': <int>[-1, 100, 100, 100, 100, 100, 100],
            'api_f_maxhps': <int>[-1, 100, 100, 100, 100, 100, 100],
            'api_f_nowhps_combined': <int>[
              -1,
              for (var position = 6; position < 12; position++)
                position == absoluteTarget ? 20 : 100,
            ],
            'api_f_maxhps_combined': <int>[-1, 100, 100, 100, 100, 100, 100],
            'api_e_nowhps': <int>[-1, 20],
            'api_e_maxhps': <int>[-1, 20],
            'api_ship_ke': <int>[-1, 501],
            'api_hougeki1': <String, Object?>{
              'api_at_eflag': <int>[1],
              'api_at_list': <int>[0],
              'api_df_list': <Object?>[
                <int>[absoluteTarget],
              ],
              'api_damage': <Object?>[
                <int>[1],
              ],
            },
          },
        );

        expect(fixture.state.state.ships[scenario.targetId]!.currentHp, 19);
        expect(fixture.battle.isDamageControlStateTrusted, isTrue);
        for (var position = 0; position < 12; position++) {
          if (position == 5) continue;
          expect(
            fixture.state.state.ships[1000 + position]!.currentHp,
            position == absoluteTarget ? 19 : 100,
            reason: 'only absolute target $absoluteTarget may receive damage',
          );
        }
        final prediction = fixture.battle.current!.friendEscort.singleWhere(
          (ship) => ship.ownedShipId == scenario.targetId,
        );
        expect(prediction.position, absoluteTarget - 6);
        expect(prediction.currentHp, 19);
        await fixture.navigate();
        final warnings = collectAdvanceWarningShips(
          fixture.state.state,
          damageControlStateTrusted: fixture.battle.isDamageControlStateTrusted,
        );
        expect(warnings.map((warning) => warning.ship.id), <int>[
          if (absoluteTarget == 7) scenario.targetId,
        ]);
        if (absoluteTarget == 7) {
          expect(warnings.single.fleetId, 2);
          expect(warnings.single.position, 2);
          expect(
            warnings.single.damageControlStatus,
            AdvanceDamageControlStatus.missing,
          );
        }
      },
    );
  }
}

final class _PartialFleetCase {
  const _PartialFleetCase({
    required this.name,
    required this.count,
    required this.missingPosition,
    required this.targetPosition,
    this.combined = false,
  });

  final String name;
  final int count;
  final int missingPosition;
  final int targetPosition;
  final bool combined;

  int get targetId => 1000 + targetPosition;
  int get missingId => 1000 + missingPosition;
  int get fleetId => count == 7 ? 3 : 1;
  int get targetFleetId => combined && targetPosition >= 6 ? 2 : fleetId;
  int get targetFleetPosition => combined ? targetPosition % 6 : targetPosition;
}

final class _PartialFleetFixture {
  _PartialFleetFixture(this.scenario, this.state, this.battle, this.pipeline);

  final _PartialFleetCase scenario;
  final GameStateController state;
  final BattleController battle;
  final GameApiEventPipeline pipeline;
  var sequence = 0;
  var node = 0;

  static Future<_PartialFleetFixture> create(
    _PartialFleetCase scenario, {
    required bool startWithMissingShip,
  }) async {
    final state = GameStateController(
      initialState: GameState(
        memberId: 1001,
        hasPortData: true,
        hasEquipmentInventory: true,
        combinedFleetType: scenario.combined
            ? CombinedFleetType.carrierTaskForce
            : CombinedFleetType.none,
        ships: <int, OwnedShip>{
          for (var position = 0; position < scenario.count; position++)
            if (!startWithMissingShip || position != scenario.missingPosition)
              1000 + position: OwnedShip(
                id: 1000 + position,
                masterId: 1000 + position,
                level: 50,
                currentHp: position == scenario.targetPosition ? 20 : 100,
                maxHp: 100,
                slotIds: <int>[
                  if (position == scenario.targetPosition)
                    startWithMissingShip ? -1 : 501,
                ],
                extraSlotId:
                    position == scenario.targetPosition && !startWithMissingShip
                    ? 502
                    : -1,
              ),
        },
        slotItems: <int, OwnedSlotItem>{
          if (!startWithMissingShip) ...<int, OwnedSlotItem>{
            501: const OwnedSlotItem(instanceId: 501, masterSlotItemId: 42),
            502: const OwnedSlotItem(instanceId: 502, masterSlotItemId: 43),
          },
        },
        fleets: <Fleet>[
          Fleet(
            id: scenario.fleetId,
            name: 'Main',
            shipIds: <int>[
              for (
                var position = 0;
                position < (scenario.combined ? 6 : scenario.count);
                position++
              )
                1000 + position,
            ],
            slotCount: scenario.combined ? 6 : scenario.count,
          ),
          if (scenario.combined)
            const Fleet(
              id: 2,
              name: 'Escort',
              shipIds: <int>[1006, 1007, 1008, 1009, 1010, 1011],
            ),
        ],
      ),
    );
    await state.initialize();
    final battle = BattleController(
      gameState: () => state.state,
      waitForGameState: () => state.idle,
      onFriendlyHpUpdated: state.applyFriendlyBattleHp,
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
    return _PartialFleetFixture(scenario, state, battle, pipeline);
  }

  Future<void> navigate({bool start = false}) => publish(
    start ? '/kcsapi/api_req_map/start' : '/kcsapi/api_req_map/next',
    <String, Object?>{
      'api_maparea_id': 1,
      'api_mapinfo_no': 1,
      'api_no': ++node,
    },
    requestParams: <String, Object?>{'api_deck_id': '${scenario.fleetId}'},
  );

  Future<void> fight({bool consume = false}) => publish(
    scenario.combined
        ? '/kcsapi/api_req_combined_battle/battle'
        : '/kcsapi/api_req_sortie/battle',
    <String, Object?>{
      'api_deck_id': scenario.fleetId,
      'api_f_nowhps': <int>[
        -1,
        for (
          var position = 0;
          position < (scenario.combined ? 6 : scenario.count);
          position++
        )
          position == scenario.targetPosition ? 20 : 100,
      ],
      'api_f_maxhps': <int>[
        -1,
        ...List<int>.filled(scenario.combined ? 6 : scenario.count, 100),
      ],
      if (scenario.combined)
        'api_f_nowhps_combined': <int>[
          -1,
          for (var position = 6; position < 12; position++)
            position == scenario.targetPosition ? 20 : 100,
        ],
      if (scenario.combined)
        'api_f_maxhps_combined': <int>[-1, ...List<int>.filled(6, 100)],
      'api_e_nowhps': <int>[-1, 20],
      'api_e_maxhps': <int>[-1, 20],
      'api_ship_ke': <int>[-1, 501],
      if (consume)
        'api_hougeki1': <String, Object?>{
          'api_at_eflag': <int>[1, 1, 1],
          'api_at_list': <int>[0, 0, 0],
          'api_df_list': <Object?>[
            for (var attack = 0; attack < 3; attack++)
              <int>[scenario.targetPosition],
          ],
          'api_damage': <Object?>[
            <int>[20],
            <int>[20],
            <int>[80],
          ],
        },
    },
  );

  Future<void> publish(
    String path,
    Object? data, {
    Map<String, Object?> requestParams = const <String, Object?>{},
  }) async {
    pipeline.add(
      CapturedApiEvent(
        path: path,
        requestParams: requestParams,
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

  void expectMappedHp() {
    expect(state.state.ships[scenario.targetId]!.currentHp, 20);
    final prediction = battle.current!.friendShips.singleWhere(
      (ship) => ship.ownedShipId == scenario.targetId,
    );
    expect(prediction.currentHp, 20);
    expect(prediction.position, scenario.targetFleetPosition);
    expect(
      prediction.fleetRole,
      scenario.targetFleetId == 2
          ? BattleFleetRole.escort
          : BattleFleetRole.main,
    );
    for (var position = 0; position < scenario.count; position++) {
      if (position == scenario.missingPosition) continue;
      expect(
        state.state.ships[1000 + position]!.currentHp,
        position == scenario.targetPosition ? 20 : 100,
      );
    }
    expectWarning();
  }

  void expectWarning() {
    expect(battle.isDamageControlStateTrusted, isTrue);
    final warnings = collectAdvanceWarningShips(
      state.state,
      damageControlStateTrusted: battle.isDamageControlStateTrusted,
    );
    expect(warnings.map((warning) => warning.ship.id), <int>[
      scenario.targetId,
    ]);
    expect(warnings.single.fleetId, scenario.targetFleetId);
    expect(warnings.single.position, scenario.targetFleetPosition + 1);
    expect(
      warnings.single.damageControlStatus,
      AdvanceDamageControlStatus.missing,
    );
    expect(warnings.single.remainingDamageControls, isEmpty);
  }

  void dispose() {
    battle.dispose();
    state.dispose();
  }
}
