import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_models.dart';
import 'package:yahagi_kancolle_browser/src/battle/prediction/battle_prediction_executor.dart';
import 'package:yahagi_kancolle_browser/src/battle/sortie_damage_control_ledger.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/capture/advance_warning_details.dart';
import 'package:yahagi_kancolle_browser/src/game_state/combat_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_api_event_pipeline.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';

void main() {
  test('4096 seeded fleet snapshots preserve per-ship inventory decisions', () {
    final random = Random(0x4d4357);
    var checkedShips = 0;
    for (var scenario = 0; scenario < 4096; scenario++) {
      final combined = scenario.isEven;
      final sortieFleetId = scenario % 3 == 0 ? 3 : 1;
      final active = scenario % 17 != 0;
      final trusted = scenario % 11 != 0;
      final hasInventory = scenario % 13 != 0;
      final ships = <int, OwnedShip>{};
      final inventory = <int, OwnedSlotItem>{};
      final expected = <int, (AdvanceDamageControlStatus, Map<int, int>)>{};
      final escaped = <int>{};
      for (var fleetId = 1; fleetId <= 3; fleetId++) {
        for (var position = 0; position < 7; position++) {
          final shipId = fleetId * 100 + position;
          final instanceId = shipId * 10;
          final hp = <int>[0, 1, 20, 25, 26, 50, 100][random.nextInt(7)];
          final layout = random.nextInt(8);
          final slots = <int>[];
          var extraSlotId = -1;
          var expectedStatus = AdvanceDamageControlStatus.missing;
          var expectedCounts = <int, int>{};
          switch (layout) {
            case 0:
              slots.add(-1);
            case 1:
              slots.add(instanceId);
              inventory[instanceId] = OwnedSlotItem(
                instanceId: instanceId,
                masterSlotItemId: 42,
              );
              expectedStatus = AdvanceDamageControlStatus.equipped;
              expectedCounts = <int, int>{42: 1};
            case 2:
              extraSlotId = instanceId;
              inventory[instanceId] = OwnedSlotItem(
                instanceId: instanceId,
                masterSlotItemId: 43,
              );
              expectedStatus = AdvanceDamageControlStatus.equipped;
              expectedCounts = <int, int>{43: 1};
            case 3:
              slots.addAll(<int>[instanceId, instanceId + 1]);
              extraSlotId = instanceId + 2;
              for (
                var equipmentIndex = 0;
                equipmentIndex < 3;
                equipmentIndex++
              ) {
                inventory[instanceId + equipmentIndex] = OwnedSlotItem(
                  instanceId: instanceId + equipmentIndex,
                  masterSlotItemId: equipmentIndex == 1 ? 43 : 42,
                );
              }
              expectedStatus = AdvanceDamageControlStatus.equipped;
              expectedCounts = <int, int>{42: 2, 43: 1};
            case 4:
              slots.add(instanceId);
              expectedStatus = AdvanceDamageControlStatus.unknown;
            case 5:
              extraSlotId = instanceId;
              inventory[instanceId] = OwnedSlotItem(
                instanceId: instanceId,
                masterSlotItemId: 0,
              );
              expectedStatus = AdvanceDamageControlStatus.unknown;
            case 6:
              slots.add(instanceId);
              extraSlotId = instanceId;
              inventory[instanceId] = OwnedSlotItem(
                instanceId: instanceId,
                masterSlotItemId: 42,
              );
              expectedStatus = AdvanceDamageControlStatus.unknown;
            case 7:
              slots.add(instanceId);
              inventory[instanceId] = OwnedSlotItem(
                instanceId: instanceId,
                masterSlotItemId: 1,
              );
          }
          ships[shipId] = OwnedShip(
            id: shipId,
            masterId: shipId,
            level: 50,
            currentHp: hp,
            maxHp: 100,
            slotIds: slots,
            extraSlotId: extraSlotId,
          );
          if (random.nextInt(5) == 0) escaped.add(shipId);
          final fleetParticipates =
              fleetId == sortieFleetId ||
              (sortieFleetId == 1 && combined && fleetId == 2);
          if (active &&
              fleetParticipates &&
              position > 0 &&
              hp > 0 &&
              hp <= 25 &&
              !escaped.contains(shipId)) {
            if (!trusted || !hasInventory) {
              expectedStatus = AdvanceDamageControlStatus.unknown;
              expectedCounts = <int, int>{};
            }
            expected[shipId] = (expectedStatus, expectedCounts);
          }
        }
      }
      final state = GameState(
        hasPortData: true,
        hasEquipmentInventory: hasInventory,
        combinedFleetType: combined
            ? CombinedFleetType.carrierTaskForce
            : CombinedFleetType.none,
        ships: ships,
        slotItems: inventory,
        fleets: <Fleet>[
          for (var fleetId = 1; fleetId <= 3; fleetId++)
            Fleet(
              id: fleetId,
              name: 'Fleet $fleetId',
              shipIds: <int>[
                for (var position = 0; position < 7; position++)
                  fleetId * 100 + position,
              ],
              slotCount: 7,
            ),
        ],
        combatState: CombatState(
          isActive: active,
          sortieFleetId: sortieFleetId,
          escapedShipIds: escaped,
        ),
      );

      final warnings = collectAdvanceWarningShips(
        state,
        damageControlStateTrusted: trusted,
      );

      expect(
        warnings.map((warning) => warning.ship.id),
        unorderedEquals(expected.keys),
        reason: 'scenario $scenario',
      );
      for (final warning in warnings) {
        final expectedShip = expected[warning.ship.id]!;
        expect(warning.damageControlStatus, expectedShip.$1);
        expect(warning.remainingDamageControls, expectedShip.$2);
        expect(warning.position, warning.ship.id % 100 + 1);
        expect(warning.fleetId, warning.ship.id ~/ 100);
        checkedShips++;
      }
      expect(
        warnings.map((warning) => warning.damageControlStatus.index),
        orderedEquals(
          warnings.map((warning) => warning.damageControlStatus.index).toList()
            ..sort(),
        ),
      );
    }
    expect(checkedShips, greaterThan(10000));
  });

  test('512 seeded ledgers retain instances through 12288 reordered turns', () {
    final random = Random(0x42a43);
    for (var scenario = 0; scenario < 512; scenario++) {
      final ledger = SortieDamageControlLedger()..beginSortie();
      final equipment = <int, List<DamageControlEquipmentRef>>{};
      final consumed = <int, List<DamageControlEquipmentRef>>{};
      for (var shipId = 1; shipId <= 8; shipId++) {
        equipment[shipId] = <DamageControlEquipmentRef>[
          for (var position = 0; position < 1 + random.nextInt(4); position++)
            DamageControlEquipmentRef(
              instanceId: shipId * 100 + position,
              masterId: random.nextBool() ? 42 : 43,
            ),
        ];
        consumed[shipId] = <DamageControlEquipmentRef>[];
      }
      for (var turn = 0; turn < 24; turn++) {
        final changedShipId = 1 + random.nextInt(8);
        final current = consumed[changedShipId]!;
        final available = equipment[changedShipId]!;
        if (current.length < available.length) {
          current.add(available[current.length]);
        }
        final shipIds = equipment.keys.toList()..shuffle(random);
        final snapshots = <BattleShipSnapshot>[
          for (var position = 0; position < shipIds.length; position++)
            _snapshot(
              shipIds[position],
              position: position,
              used: consumed[shipIds[position]]!
                  .map((item) => item.masterId)
                  .toList(),
            ),
        ];
        ledger.synchronize(ships: snapshots, equipmentByShipId: equipment);
        expect(ledger.isTrusted, isTrue, reason: '$scenario / $turn');
        for (final shipId in shipIds) {
          expect(
            ledger.consumptionsForShip(shipId).map((item) => item.instanceId),
            consumed[shipId]!.map((item) => item.instanceId),
          );
        }
        final seeded = ledger.seedFleet(<BattleShipSnapshot>[
          for (var position = 0; position < shipIds.length; position++)
            _snapshot(shipIds[position], position: position),
        ]);
        for (final ship in seeded) {
          expect(
            ship.usedDamageControlItemIds,
            consumed[ship.ownedShipId]!.map((item) => item.masterId),
          );
        }
      }
      ledger.endSortie();
      expect(ledger.consumedByShipId, isEmpty);
      expect(ledger.isActive, isFalse);
    }
  });

  test('ledger corruption is atomic and remains untrusted until reset', () {
    const equipment = <int, List<DamageControlEquipmentRef>>{
      1: <DamageControlEquipmentRef>[
        DamageControlEquipmentRef(instanceId: 11, masterId: 42),
        DamageControlEquipmentRef(instanceId: 12, masterId: 43),
      ],
      2: <DamageControlEquipmentRef>[
        DamageControlEquipmentRef(instanceId: 21, masterId: 43),
      ],
    };
    final corruptions = <List<BattleShipSnapshot>>[
      <BattleShipSnapshot>[
        _snapshot(1, used: <int>[43]),
      ],
      <BattleShipSnapshot>[
        _snapshot(1, used: <int>[42, 1]),
      ],
      <BattleShipSnapshot>[
        _snapshot(1, used: <int>[42, 43, 42]),
      ],
      <BattleShipSnapshot>[
        _snapshot(999, used: <int>[42]),
      ],
      <BattleShipSnapshot>[
        _snapshot(null, used: <int>[42]),
      ],
    ];
    for (final corruption in corruptions) {
      final ledger = SortieDamageControlLedger()..beginSortie();
      ledger.synchronize(
        ships: <BattleShipSnapshot>[
          _snapshot(1, used: <int>[42]),
        ],
        equipmentByShipId: equipment,
      );
      ledger.synchronize(
        ships: <BattleShipSnapshot>[
          _snapshot(2, used: <int>[43]),
          ...corruption,
        ],
        equipmentByShipId: equipment,
      );
      expect(ledger.isTrusted, isFalse);
      expect(ledger.usedMasterIdsForShip(1), <int>[42]);
      expect(ledger.usedMasterIdsForShip(2), isEmpty);
      final firstReason = ledger.untrustedReason;
      ledger.markUntrusted('later error');
      ledger.synchronize(
        ships: <BattleShipSnapshot>[
          _snapshot(1, used: <int>[42, 43]),
        ],
        equipmentByShipId: equipment,
      );
      expect(ledger.untrustedReason, firstReason);
      expect(ledger.usedMasterIdsForShip(1), <int>[42]);
      ledger.beginSortie();
      expect(ledger.isTrusted, isTrue);
      expect(ledger.consumedByShipId, isEmpty);
    }
  });

  test(
    'duplicate personnel before an expansion goddess preserve node order',
    () async {
      final ship = _SimulatedShip(
        1001,
        <(int, int)>[(501, 42), (502, 42)],
        (503, 43),
      );
      final flagship = _SimulatedShip(1000, <(int, int)>[], null);
      final ships = <_SimulatedShip>[flagship, ship];
      final fixture = await _PipelineFixture.create(_simulatedState(ships, 1));
      addTearDown(fixture.dispose);
      await fixture.publish(
        '/kcsapi/api_req_map/start',
        _mapData,
        requestParams: const <String, Object?>{'api_deck_id': '1'},
      );
      await fixture.publish(
        '/kcsapi/api_req_sortie/battle',
        _battleData(1, <int>[100, 100], <(int, int)>[(1, 100)]),
      );
      expect(fixture.state.state.ships[1001]!.currentHp, 20);
      expect(fixture.state.state.ships[1001]!.slotIds, <int>[-1, 502]);
      await fixture.publish('/kcsapi/api_req_map/next', <String, Object?>{
        ..._mapData,
        'api_no': 2,
      });

      await fixture.publish(
        '/kcsapi/api_req_sortie/battle',
        _battleData(1, <int>[100, 20], <(int, int)>[(1, 65), (1, 24)]),
      );

      expect(fixture.battle.isDamageControlStateTrusted, isTrue);
      expect(fixture.state.state.ships[1001]!.currentHp, 100);
      expect(fixture.state.state.ships[1001]!.slotIds, <int>[-1, -1]);
      expect(fixture.state.state.ships[1001]!.extraSlotId, -1);
      expect(fixture.state.state.slotItems, isEmpty);
    },
  );

  test(
    '45 inventory layouts consume 132 controls and then remain missing',
    () async {
      var layouts = 0;
      var consumptions = 0;
      for (var normalCount = 0; normalCount <= 3; normalCount++) {
        for (var mask = 0; mask < 1 << normalCount; mask++) {
          for (final expansionMasterId in <int>[0, 42, 43]) {
            final ship =
                _SimulatedShip(1001, <(int, int)>[
                    for (var position = 0; position < normalCount; position++)
                      (501 + position, mask & (1 << position) == 0 ? 42 : 43),
                  ], expansionMasterId == 0 ? null : (510, expansionMasterId))
                  ..hp = 20;
            final ships = <_SimulatedShip>[
              _SimulatedShip(1000, <(int, int)>[], null),
              ship,
            ];
            final fixture = await _PipelineFixture.create(
              _simulatedState(ships, 1),
            );
            try {
              await fixture.publish(
                '/kcsapi/api_req_map/start',
                _mapData,
                requestParams: const <String, Object?>{'api_deck_id': '1'},
              );
              var node = 1;
              _expectSimulation(
                fixture,
                ships,
                1,
                reason:
                    'layout $normalCount / $mask / $expansionMasterId start',
              );
              while (ship.remainingControls.isNotEmpty) {
                final openingHp = ship.hp;
                final nextMasterId = ship.remainingControls.first.$2;
                final attacks = <(int, int)>[(1, openingHp)];
                ship.receive(openingHp);
                if (nextMasterId == 43) {
                  attacks.add((1, 80));
                  ship.receive(80);
                }
                await fixture.publish(
                  '/kcsapi/api_req_sortie/battle',
                  _battleData(1, <int>[100, openingHp], attacks),
                );
                consumptions++;
                _expectSimulation(
                  fixture,
                  ships,
                  1,
                  reason:
                      'layout $normalCount / $mask / $expansionMasterId node $node',
                );
                await fixture.publish(
                  '/kcsapi/api_req_map/next',
                  <String, Object?>{..._mapData, 'api_no': ++node},
                );
              }
              final warning = collectAdvanceWarningShips(
                fixture.state.state,
                damageControlStateTrusted:
                    fixture.battle.isDamageControlStateTrusted,
              ).single;
              expect(
                warning.damageControlStatus,
                AdvanceDamageControlStatus.missing,
              );
              expect(warning.remainingDamageControls, isEmpty);
              ship.receive(5);
              await fixture.publish(
                '/kcsapi/api_req_sortie/battle',
                _battleData(1, <int>[100, 20], <(int, int)>[(1, 5)]),
              );
              _expectSimulation(
                fixture,
                ships,
                1,
                reason: 'depleted layout $layouts',
              );
              expect(
                collectAdvanceWarningShips(
                  fixture.state.state,
                  damageControlStateTrusted: true,
                ).single.damageControlStatus,
                AdvanceDamageControlStatus.missing,
              );
              layouts++;
            } finally {
              fixture.dispose();
            }
          }
        }
      }
      expect(layouts, 45);
      expect(consumptions, 132);
    },
  );

  test(
    '24 interrupted pipelines need a ship snapshot to restore inventory trust',
    () async {
      for (var scenario = 0; scenario < 24; scenario++) {
        final ships = <_SimulatedShip>[
          _SimulatedShip(1000, <(int, int)>[], null),
          _SimulatedShip(1001, <(int, int)>[
            (501, scenario.isEven ? 42 : 43),
          ], scenario % 3 == 0 ? (502, 43) : null)..hp = 20,
        ];
        final fixture = await _PipelineFixture.create(
          _simulatedState(ships, 1),
        );
        try {
          await fixture.publish(
            '/kcsapi/api_req_map/start',
            _mapData,
            requestParams: const <String, Object?>{'api_deck_id': '1'},
          );
          expect(fixture.battle.isDamageControlStateTrusted, isTrue);
          fixture.battle.invalidateCaptureContinuity();
          await fixture.publish('/kcsapi/api_req_map/next', _mapData);
          expect(fixture.battle.isDamageControlStateTrusted, isFalse);
          await fixture.publish(
            '/kcsapi/api_req_sortie/battle',
            _battleData(1, <int>[100, 20], <(int, int)>[(1, 20)]),
          );
          expect(fixture.state.state.ships[1001]!.currentHp, 1);
          expect(fixture.battle.isPredictionConfirmed, isFalse);
          ships[1].hp = 1;
          expect(fixture.state.state.ships[1001]!.slotIds, <int>[501]);
          expect(
            collectAdvanceWarningShips(
              fixture.state.state,
              damageControlStateTrusted:
                  fixture.battle.isDamageControlStateTrusted,
            ).single.damageControlStatus,
            AdvanceDamageControlStatus.unknown,
          );
          await fixture.publish('/kcsapi/api_port/port', <String, Object?>{});
          await fixture.publish(
            '/kcsapi/api_req_map/start',
            _mapData,
            requestParams: const <String, Object?>{'api_deck_id': '1'},
          );
          expect(fixture.battle.isDamageControlStateTrusted, isFalse);
          await fixture.publish('/kcsapi/api_port/port', <String, Object?>{
            'api_ship': <Object?>[
              for (final ship in fixture.state.state.ships.values)
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
          });
          await fixture.publish(
            '/kcsapi/api_req_map/start',
            _mapData,
            requestParams: const <String, Object?>{'api_deck_id': '1'},
          );
          _expectSimulation(
            fixture,
            ships,
            1,
            reason: 'restored scenario $scenario',
          );
        } finally {
          fixture.dispose();
        }
      }
    },
  );

  test(
    '64 seeded production pipelines match 768 battle inventory outcomes',
    () async {
      final random = Random(0x20261023);
      var battles = 0;
      var replayedPackets = 0;
      for (var scenario = 0; scenario < 64; scenario++) {
        final shipCount = 2 + random.nextInt(6);
        final fleetId = shipCount == 7 ? 3 : 1;
        final ships = <_SimulatedShip>[
          for (var position = 0; position < shipCount; position++)
            _SimulatedShip.random(1000 + position, random),
        ];
        final fixture = await _PipelineFixture.create(
          _simulatedState(ships, fleetId),
        );
        try {
          await fixture.publish(
            '/kcsapi/api_req_map/start',
            _mapData,
            requestParams: <String, Object?>{'api_deck_id': '$fleetId'},
          );
          CapturedApiEvent? previousBattle;
          for (var node = 0; node < 12; node++) {
            if (node > 0) {
              await fixture.publish(
                '/kcsapi/api_req_map/next',
                <String, Object?>{..._mapData, 'api_no': node + 1},
              );
            }
            final openingHp = ships.map((ship) => ship.hp).toList();
            final attacks = <(int, int)>[];
            for (var position = 0; position < ships.length; position++) {
              final ship = ships[position];
              if (ship.hp <= 0) continue;
              final hitCount = 1 + random.nextInt(3);
              for (var hit = 0; hit < hitCount && ship.hp > 0; hit++) {
                final damage = node % 3 == 0
                    ? ship.hp
                    : 1 + random.nextInt(100);
                attacks.add((position, damage));
                ship.receive(damage);
              }
            }
            final event = await fixture.publish(
              '/kcsapi/api_req_sortie/battle',
              _battleData(fleetId, openingHp, attacks),
            );
            battles++;
            _expectSimulation(
              fixture,
              ships,
              fleetId,
              reason:
                  'scenario $scenario node $node opening $openingHp attacks $attacks',
            );
            if (node % 3 == 0) {
              fixture.pipeline.add(event);
              if (previousBattle != null) {
                fixture.pipeline.add(previousBattle);
                replayedPackets++;
              }
              replayedPackets++;
              await fixture.pipeline.idle;
              _expectSimulation(
                fixture,
                ships,
                fleetId,
                reason: 'replayed scenario $scenario node $node',
              );
            }
            previousBattle = event;
          }
        } finally {
          fixture.dispose();
        }
      }
      expect(battles, 768);
      expect(replayedPackets, 448);
    },
  );

  test('inventory keys must match the stored damage-control instance', () {
    for (final masterId in <int>[42, 43]) {
      for (final expansion in <bool>[false, true]) {
        for (final storedInstanceId in <int>[0, 502]) {
          final ships = <_SimulatedShip>[
            _SimulatedShip(1000, <(int, int)>[], null),
            _SimulatedShip(
              1001,
              expansion ? <(int, int)>[] : <(int, int)>[(501, masterId)],
              expansion ? (501, masterId) : null,
            )..hp = 20,
          ];
          final state = _simulatedState(ships, 1).copyWith(
            combatState: const CombatState(isActive: true, sortieFleetId: 1),
            slotItems: <int, OwnedSlotItem>{
              501: OwnedSlotItem(
                instanceId: storedInstanceId,
                masterSlotItemId: masterId,
              ),
            },
          );

          final warning = collectAdvanceWarningShips(
            state,
            damageControlStateTrusted: true,
          ).single;

          expect(
            warning.damageControlStatus,
            AdvanceDamageControlStatus.unknown,
            reason: '$masterId expansion=$expansion stored=$storedInstanceId',
          );
          expect(warning.remainingDamageControls, isEmpty);
        }
      }
    }
  });

  for (final conflict in <String>[
    'another heavily damaged ship',
    'healthy ship',
    'flagship',
    'escaped ship',
    'inactive fleet ship',
  ]) {
    for (final conflictInExpansion in <bool>[false, true]) {
      test(
        'shared instance is unknown with $conflict in ${conflictInExpansion ? 'expansion' : 'normal'} slot',
        () {
          final otherShipId = conflict == 'flagship' ? 1 : 3;
          final otherShip = OwnedShip(
            id: otherShipId,
            masterId: otherShipId,
            level: 50,
            currentHp: conflict == 'healthy ship' ? 100 : 20,
            maxHp: 100,
            slotIds: conflictInExpansion ? const <int>[] : const <int>[501],
            extraSlotId: conflictInExpansion ? 501 : -1,
          );
          final state = GameState(
            hasPortData: true,
            hasEquipmentInventory: true,
            ships: <int, OwnedShip>{
              1: const OwnedShip(
                id: 1,
                masterId: 1,
                level: 50,
                currentHp: 100,
                maxHp: 100,
              ),
              2: const OwnedShip(
                id: 2,
                masterId: 2,
                level: 50,
                currentHp: 20,
                maxHp: 100,
                slotIds: <int>[501],
              ),
              otherShipId: otherShip,
            },
            slotItems: const <int, OwnedSlotItem>{
              501: OwnedSlotItem(instanceId: 501, masterSlotItemId: 42),
            },
            fleets: <Fleet>[
              Fleet(
                id: 1,
                name: 'Main',
                shipIds: <int>[
                  1,
                  2,
                  if (otherShipId == 3 && conflict != 'inactive fleet ship') 3,
                ],
              ),
              if (conflict == 'inactive fleet ship')
                const Fleet(id: 2, name: 'Inactive', shipIds: <int>[3]),
            ],
            combatState: CombatState(
              isActive: true,
              sortieFleetId: 1,
              escapedShipIds: conflict == 'escaped ship'
                  ? const <int>{3}
                  : const <int>{},
            ),
          );

          final warnings = collectAdvanceWarningShips(
            state,
            damageControlStateTrusted: true,
          );

          expect(warnings, isNotEmpty);
          for (final warning in warnings) {
            expect(
              warning.damageControlStatus,
              AdvanceDamageControlStatus.unknown,
            );
            expect(warning.remainingDamageControls, isEmpty);
          }
        },
      );
    }
  }
}

BattleShipSnapshot _snapshot(
  int? shipId, {
  int position = 0,
  List<int> used = const <int>[],
}) => BattleShipSnapshot(
  masterId: shipId ?? 1,
  ownedShipId: shipId,
  name: 'Ship $shipId',
  side: BattleSide.friend,
  fleetRole: BattleFleetRole.main,
  position: position,
  initialHp: 100,
  currentHp: 20,
  maxHp: 100,
  usedDamageControlItemIds: used,
);

const _mapData = <String, Object?>{
  'api_maparea_id': 1,
  'api_mapinfo_no': 1,
  'api_no': 1,
};

Map<String, Object?> _battleData(
  int fleetId,
  List<int> openingHp,
  List<(int, int)> attacks,
) => <String, Object?>{
  'api_deck_id': fleetId,
  'api_f_nowhps': <int>[-1, ...openingHp],
  'api_f_maxhps': <int>[-1, ...List<int>.filled(openingHp.length, 100)],
  'api_e_nowhps': <int>[-1, 20],
  'api_e_maxhps': <int>[-1, 20],
  'api_ship_ke': <int>[-1, 501],
  'api_hougeki1': <String, Object?>{
    'api_at_eflag': List<int>.filled(attacks.length, 1),
    'api_at_list': List<int>.filled(attacks.length, 0),
    'api_df_list': <Object?>[
      for (final attack in attacks) <int>[attack.$1],
    ],
    'api_damage': <Object?>[
      for (final attack in attacks) <int>[attack.$2],
    ],
  },
};

GameState _simulatedState(List<_SimulatedShip> ships, int fleetId) => GameState(
  memberId: 1001,
  hasPortData: true,
  hasEquipmentInventory: true,
  ships: <int, OwnedShip>{
    for (final ship in ships)
      ship.id: OwnedShip(
        id: ship.id,
        masterId: ship.id,
        level: 50,
        currentHp: ship.hp,
        maxHp: 100,
        slotIds: ship.normal.map((item) => item.$1).toList(),
        extraSlotId: ship.expansion?.$1 ?? -1,
      ),
  },
  slotItems: <int, OwnedSlotItem>{
    for (final ship in ships)
      for (final equipment in ship.equipment)
        equipment.$1: OwnedSlotItem(
          instanceId: equipment.$1,
          masterSlotItemId: equipment.$2,
        ),
  },
  fleets: <Fleet>[
    Fleet(
      id: fleetId,
      name: 'Simulated',
      shipIds: ships.map((ship) => ship.id).toList(),
      slotCount: ships.length == 7 ? 7 : 6,
    ),
  ],
);

void _expectSimulation(
  _PipelineFixture fixture,
  List<_SimulatedShip> ships,
  int fleetId, {
  required String reason,
}) {
  expect(fixture.state.lastError, isNull, reason: reason);
  expect(fixture.battle.lastError, isNull, reason: reason);
  expect(fixture.battle.isDamageControlStateTrusted, isTrue, reason: reason);
  final state = fixture.state.state;
  for (final ship in ships) {
    final actual = state.ships[ship.id]!;
    expect(
      actual.currentHp,
      ship.hp,
      reason:
          '$reason ship ${ship.id} equipment ${ship.equipment} consumed ${ship.consumedInstances}',
    );
    expect(actual.slotIds, <int>[
      for (final item in ship.normal)
        ship.consumedInstances.contains(item.$1) ? -1 : item.$1,
    ], reason: reason);
    final expansionId = ship.expansion?.$1 ?? -1;
    expect(
      actual.extraSlotId,
      ship.consumedInstances.contains(expansionId) ? -1 : expansionId,
      reason: reason,
    );
  }
  expect(
    state.slotItems.keys,
    unorderedEquals(<int>[
      for (final ship in ships)
        for (final item in ship.equipment)
          if (!ship.consumedInstances.contains(item.$1)) item.$1,
    ]),
    reason: reason,
  );
  final warnings = collectAdvanceWarningShips(
    state,
    damageControlStateTrusted: fixture.battle.isDamageControlStateTrusted,
  );
  final expectedCandidates = ships
      .skip(1)
      .where((ship) => ship.hp > 0 && ship.hp <= 25);
  expect(
    warnings.map((warning) => warning.ship.id),
    unorderedEquals(expectedCandidates.map((ship) => ship.id)),
    reason: reason,
  );
  for (final warning in warnings) {
    final ship = ships.firstWhere((ship) => ship.id == warning.ship.id);
    final counts = <int, int>{};
    for (final item in ship.remainingControls) {
      counts.update(item.$2, (count) => count + 1, ifAbsent: () => 1);
    }
    expect(warning.remainingDamageControls, counts, reason: reason);
    expect(
      warning.damageControlStatus,
      counts.isEmpty
          ? AdvanceDamageControlStatus.missing
          : AdvanceDamageControlStatus.equipped,
      reason: reason,
    );
    expect(warning.fleetId, fleetId);
  }
}

final class _SimulatedShip {
  _SimulatedShip(this.id, this.normal, this.expansion);

  factory _SimulatedShip.random(int shipId, Random random) {
    final normalCount = random.nextInt(4);
    return _SimulatedShip(
      shipId,
      <(int, int)>[
        for (var position = 0; position < normalCount; position++)
          (shipId * 10 + position, <int>[1, 42, 43][random.nextInt(3)]),
      ],
      random.nextBool() ? (shipId * 10 + 4, random.nextBool() ? 42 : 43) : null,
    );
  }

  final int id;
  final List<(int, int)> normal;
  final (int, int)? expansion;
  final consumedInstances = <int>{};
  var hp = 100;

  List<(int, int)> get equipment => <(int, int)>[...normal, ?expansion];

  Iterable<(int, int)> get remainingControls => equipment.where(
    (item) =>
        (item.$2 == 42 || item.$2 == 43) &&
        !consumedInstances.contains(item.$1),
  );

  void receive(int damage) {
    hp = max(0, hp - damage);
    if (hp != 0) return;
    final controls = remainingControls.toList();
    if (controls.isEmpty) return;
    final consumed = controls.first;
    consumedInstances.add(consumed.$1);
    hp = consumed.$2 == 42 ? 20 : 100;
  }
}

final class _PipelineFixture {
  _PipelineFixture(this.state, this.battle, this.pipeline);

  final GameStateController state;
  final BattleController battle;
  final GameApiEventPipeline pipeline;
  var _sequence = 0;

  static Future<_PipelineFixture> create(GameState initialState) async {
    final state = GameStateController(initialState: initialState);
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
    return _PipelineFixture(state, battle, pipeline);
  }

  Future<CapturedApiEvent> publish(
    String path,
    Object? data, {
    Map<String, Object?> requestParams = const <String, Object?>{},
  }) async {
    final event = CapturedApiEvent(
      path: path,
      responseBody: jsonEncode(<String, Object?>{
        'api_result': 1,
        'api_data': data,
      }),
      requestParams: requestParams,
      source: CaptureSource.xhr,
      sourceOrigin: 'https://w01y.kancolle-server.com',
      capturedAt: DateTime.utc(2026, 10, 23).add(Duration(seconds: _sequence)),
      sequence: ++_sequence,
    );
    pipeline.add(event);
    await pipeline.idle;
    return event;
  }

  void dispose() {
    battle.dispose();
    state.dispose();
  }
}
