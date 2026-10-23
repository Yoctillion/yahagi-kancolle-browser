import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/battle/sortie_damage_control_ledger.dart';
import 'package:yahagi_kancolle_browser/src/capture/advance_warning_details.dart';
import 'package:yahagi_kancolle_browser/src/game_state/combat_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_reducer.dart';

void main() {
  test('counts personnel and goddess from normal and expansion slots', () {
    final ship = warningShip(2, slots: <int>[501, 502], extraSlotId: 503);
    final details = collectAdvanceWarningShips(
      sortieState(
        ships: <OwnedShip>[ship],
        slotItems: const <OwnedSlotItem>[
          OwnedSlotItem(instanceId: 501, masterSlotItemId: 42),
          OwnedSlotItem(instanceId: 502, masterSlotItemId: 42),
          OwnedSlotItem(instanceId: 503, masterSlotItemId: 43),
        ],
      ),
      damageControlStateTrusted: true,
    );

    expect(details.single.ship, same(ship));
    expect(details.single.fleetId, 1);
    expect(details.single.position, 2);
    expect(
      details.single.damageControlStatus,
      AdvanceDamageControlStatus.equipped,
    );
    expect(details.single.remainingDamageControls, <int, int>{42: 2, 43: 1});
  });

  test('uses equipment master ids without requiring master equipment data', () {
    final details = collectAdvanceWarningShips(
      sortieState(
        ships: <OwnedShip>[
          warningShip(2, slots: <int>[42, 43, 500]),
        ],
        slotItems: const <OwnedSlotItem>[
          OwnedSlotItem(instanceId: 42, masterSlotItemId: 1),
          OwnedSlotItem(instanceId: 43, masterSlotItemId: 2),
          OwnedSlotItem(instanceId: 500, masterSlotItemId: 145),
        ],
      ),
      damageControlStateTrusted: true,
    );

    expect(
      details.single.damageControlStatus,
      AdvanceDamageControlStatus.missing,
    );
    expect(details.single.remainingDamageControls, isEmpty);
  });

  test(
    'empty and unavailable expansion slots prove damage control missing',
    () {
      for (final extraSlotId in <int>[-1, 0]) {
        final details = collectAdvanceWarningShips(
          sortieState(
            ships: <OwnedShip>[
              warningShip(2, slots: <int>[-1, 0], extraSlotId: extraSlotId),
            ],
          ),
          damageControlStateTrusted: true,
        );

        expect(
          details.single.damageControlStatus,
          AdvanceDamageControlStatus.missing,
        );
        expect(details.single.remainingDamageControls, isEmpty);
      }
    },
  );

  test('reflects remaining damage control after real reducer consumption', () {
    final reducer = GameStateReducer();
    var state = sortieState(
      ships: <OwnedShip>[
        warningShip(2, slots: <int>[501], extraSlotId: 502),
      ],
      slotItems: const <OwnedSlotItem>[
        OwnedSlotItem(instanceId: 501, masterSlotItemId: 42),
        OwnedSlotItem(instanceId: 502, masterSlotItemId: 42),
      ],
    );

    expect(
      collectAdvanceWarningShips(
        state,
        damageControlStateTrusted: true,
      ).single.remainingDamageControls,
      <int, int>{42: 2},
    );

    state = reducer.applyDamageControlConsumption(
      state,
      const <int, List<DamageControlEquipmentRef>>{
        2: <DamageControlEquipmentRef>[
          DamageControlEquipmentRef(instanceId: 501, masterId: 42),
        ],
      },
      DateTime.utc(2026),
    );
    final oneRemaining = collectAdvanceWarningShips(
      state,
      damageControlStateTrusted: true,
    ).single;

    expect(
      oneRemaining.damageControlStatus,
      AdvanceDamageControlStatus.equipped,
    );
    expect(oneRemaining.remainingDamageControls, <int, int>{42: 1});
    expect(state.ships[2]!.slotIds, <int>[-1]);
    expect(state.slotItems.containsKey(501), isFalse);

    state = reducer.applyDamageControlConsumption(
      state,
      const <int, List<DamageControlEquipmentRef>>{
        2: <DamageControlEquipmentRef>[
          DamageControlEquipmentRef(instanceId: 501, masterId: 42),
          DamageControlEquipmentRef(instanceId: 502, masterId: 42),
        ],
      },
      DateTime.utc(2026, 1, 2),
    );
    final noneRemaining = collectAdvanceWarningShips(
      state,
      damageControlStateTrusted: true,
    ).single;

    expect(
      noneRemaining.damageControlStatus,
      AdvanceDamageControlStatus.missing,
    );
    expect(noneRemaining.remainingDamageControls, isEmpty);
    expect(state.ships[2]!.extraSlotId, -1);
    expect(state.slotItems, isEmpty);
  });

  test(
    'missing owned equipment makes status unknown despite a known control',
    () {
      final details = collectAdvanceWarningShips(
        sortieState(
          ships: <OwnedShip>[
            warningShip(2, slots: <int>[501, 502]),
          ],
          slotItems: const <OwnedSlotItem>[
            OwnedSlotItem(instanceId: 501, masterSlotItemId: 42),
          ],
        ),
        damageControlStateTrusted: true,
      );

      expect(
        details.single.damageControlStatus,
        AdvanceDamageControlStatus.unknown,
      );
      expect(details.single.remainingDamageControls, isEmpty);
    },
  );

  test('missing expansion-slot instance makes status unknown', () {
    final details = collectAdvanceWarningShips(
      sortieState(ships: <OwnedShip>[warningShip(2, extraSlotId: 501)]),
      damageControlStateTrusted: true,
    );

    expect(
      details.single.damageControlStatus,
      AdvanceDamageControlStatus.unknown,
    );
    expect(details.single.remainingDamageControls, isEmpty);
  });

  test(
    'inventory must be complete before any damage control status is known',
    () {
      for (final slots in <List<int>>[
        <int>[],
        <int>[501],
      ]) {
        final details = collectAdvanceWarningShips(
          sortieState(
            ships: <OwnedShip>[warningShip(2, slots: slots)],
            slotItems: const <OwnedSlotItem>[
              OwnedSlotItem(instanceId: 501, masterSlotItemId: 42),
            ],
            hasEquipmentInventory: false,
          ),
          damageControlStateTrusted: true,
        );

        expect(
          details.single.damageControlStatus,
          AdvanceDamageControlStatus.unknown,
        );
        expect(details.single.remainingDamageControls, isEmpty);
      }
    },
  );

  test('untrusted consumption state suppresses all reliable counts', () {
    for (final slots in <List<int>>[
      <int>[],
      <int>[501],
    ]) {
      final details = collectAdvanceWarningShips(
        sortieState(
          ships: <OwnedShip>[warningShip(2, slots: slots)],
          slotItems: const <OwnedSlotItem>[
            OwnedSlotItem(instanceId: 501, masterSlotItemId: 42),
          ],
        ),
        damageControlStateTrusted: false,
      );

      expect(
        details.single.damageControlStatus,
        AdvanceDamageControlStatus.unknown,
      );
      expect(details.single.remainingDamageControls, isEmpty);
    }
  });

  test('nonpositive equipment master ids make status unknown', () {
    for (final masterId in <int>[-1, 0]) {
      final details = collectAdvanceWarningShips(
        sortieState(
          ships: <OwnedShip>[
            warningShip(2, slots: <int>[501, 502]),
          ],
          slotItems: <OwnedSlotItem>[
            const OwnedSlotItem(instanceId: 501, masterSlotItemId: 42),
            OwnedSlotItem(instanceId: 502, masterSlotItemId: masterId),
          ],
        ),
        damageControlStateTrusted: true,
      );

      expect(
        details.single.damageControlStatus,
        AdvanceDamageControlStatus.unknown,
      );
      expect(details.single.remainingDamageControls, isEmpty);
    }
  });

  test('repeated owned instance is unknown instead of counted twice', () {
    for (final ship in <OwnedShip>[
      warningShip(2, slots: <int>[501, 501]),
      warningShip(2, slots: <int>[501], extraSlotId: 501),
    ]) {
      final details = collectAdvanceWarningShips(
        sortieState(
          ships: <OwnedShip>[ship],
          slotItems: const <OwnedSlotItem>[
            OwnedSlotItem(instanceId: 501, masterSlotItemId: 42),
          ],
        ),
        damageControlStateTrusted: true,
      );

      expect(
        details.single.damageControlStatus,
        AdvanceDamageControlStatus.unknown,
      );
      expect(details.single.remainingDamageControls, isEmpty);
    }
  });

  test(
    'stable status ordering preserves fleet positions within each status',
    () {
      final details = collectAdvanceWarningShips(
        sortieState(
          ships: <OwnedShip>[
            warningShip(2, slots: <int>[501]),
            warningShip(3, slots: <int>[999]),
            warningShip(4),
            warningShip(5, slots: <int>[502]),
            warningShip(6),
            warningShip(7, slots: <int>[998]),
          ],
          slotItems: const <OwnedSlotItem>[
            OwnedSlotItem(instanceId: 501, masterSlotItemId: 42),
            OwnedSlotItem(instanceId: 502, masterSlotItemId: 43),
          ],
        ),
        damageControlStateTrusted: true,
      );

      expect(details.map((detail) => detail.ship.id), <int>[4, 6, 3, 7, 2, 5]);
      expect(details.map((detail) => detail.position), <int>[4, 6, 3, 7, 2, 5]);
    },
  );

  test('only duplicate warning names require disambiguation', () {
    final details = collectAdvanceWarningShips(
      sortieState(
        ships: <OwnedShip>[
          warningShip(2, masterId: 100),
          warningShip(3, masterId: 101),
          warningShip(4, masterId: 102),
          warningShip(5, masterId: 102, currentHp: 100),
          warningShip(6, masterId: 999),
        ],
        masterShips: const <int, MasterShip>{
          100: MasterShip(id: 100, name: '矢矧', shipTypeId: 3),
          101: MasterShip(id: 101, name: '矢矧', shipTypeId: 3),
          102: MasterShip(id: 102, name: '雪風', shipTypeId: 2),
        },
      ),
      damageControlStateTrusted: true,
    );

    expect(details.map((detail) => detail.name), <String>[
      '矢矧',
      '矢矧',
      '雪風',
      '#6',
    ]);
    expect(details.map((detail) => detail.requiresDisambiguation), <bool>[
      true,
      true,
      false,
      false,
    ]);
  });

  test(
    'includes only living non-flagships at or below the heavy threshold',
    () {
      final details = collectAdvanceWarningShips(
        sortieState(
          ships: <OwnedShip>[
            warningShip(1),
            warningShip(2, currentHp: 25),
            warningShip(3, currentHp: 26),
            warningShip(4, currentHp: 0),
            warningShip(5, currentHp: -1),
            warningShip(6, currentHp: 1, maxHp: 0),
            warningShip(7, currentHp: 1),
          ],
          fleets: const <Fleet>[
            Fleet(id: 1, name: 'First', shipIds: <int>[1, 2, 3, 4, 5, 6, 7]),
          ],
        ),
        damageControlStateTrusted: true,
      );

      expect(details.map((detail) => detail.ship.id), <int>[2, 7]);
      expect(details.map((detail) => detail.position), <int>[2, 7]);
    },
  );

  test('missing flagship and missing members keep original slot positions', () {
    final details = collectAdvanceWarningShips(
      sortieState(
        ships: <OwnedShip>[warningShip(2), warningShip(3)],
        fleets: const <Fleet>[
          Fleet(id: 1, name: 'First', shipIds: <int>[999, 2, -1, 998, 3]),
        ],
      ),
      damageControlStateTrusted: true,
    );

    expect(details.map((detail) => detail.ship.id), <int>[2, 3]);
    expect(details.map((detail) => detail.position), <int>[2, 5]);
  });

  test('combined sortie includes both fleets but excludes both flagships', () {
    final details = collectAdvanceWarningShips(
      multiFleetState(),
      damageControlStateTrusted: true,
    );

    expect(details.map((detail) => detail.ship.id), <int>[2, 4]);
    expect(details.map((detail) => detail.fleetId), <int>[1, 2]);
    expect(details.map((detail) => detail.position), <int>[2, 2]);
  });

  test('normal sortie excludes the escort fleet', () {
    final details = collectAdvanceWarningShips(
      multiFleetState().copyWith(combinedFleetType: CombinedFleetType.none),
      damageControlStateTrusted: true,
    );

    expect(details.map((detail) => detail.ship.id), <int>[2]);
  });

  test('third-fleet sortie excludes combined first and second fleets', () {
    final state = multiFleetState();
    final details = collectAdvanceWarningShips(
      state.copyWith(combatState: state.combatState.copyWith(sortieFleetId: 3)),
      damageControlStateTrusted: true,
    );

    expect(details.map((detail) => detail.ship.id), <int>[6]);
    expect(details.single.fleetId, 3);
  });

  test(
    'second-fleet sortie excludes the first fleet even in combined mode',
    () {
      final state = multiFleetState();
      final details = collectAdvanceWarningShips(
        state.copyWith(
          combatState: state.combatState.copyWith(sortieFleetId: 2),
        ),
        damageControlStateTrusted: true,
      );

      expect(details.map((detail) => detail.ship.id), <int>[4]);
    },
  );

  test('escaped ships are omitted from both combined fleets', () {
    final state = multiFleetState();
    final details = collectAdvanceWarningShips(
      state.copyWith(
        combatState: state.combatState.copyWith(escapedShipIds: <int>{2, 4}),
      ),
      damageControlStateTrusted: true,
    );

    expect(details, isEmpty);
  });

  test('requires an active sortie and a valid sortie fleet id', () {
    for (final combatState in <CombatState>[
      const CombatState(isActive: false, sortieFleetId: 1),
      const CombatState(isActive: true),
      const CombatState(isActive: true, sortieFleetId: -1),
      const CombatState(isActive: true, sortieFleetId: 99),
    ]) {
      final details = collectAdvanceWarningShips(
        multiFleetState().copyWith(combatState: combatState),
        damageControlStateTrusted: true,
      );

      expect(details, isEmpty);
    }
  });
}

OwnedShip warningShip(
  int id, {
  int masterId = 100,
  int currentHp = 20,
  int maxHp = 100,
  List<int> slots = const <int>[],
  int extraSlotId = -1,
}) => OwnedShip(
  id: id,
  masterId: masterId,
  level: 50,
  currentHp: currentHp,
  maxHp: maxHp,
  slotIds: slots,
  extraSlotId: extraSlotId,
);

GameState sortieState({
  required List<OwnedShip> ships,
  List<OwnedSlotItem> slotItems = const <OwnedSlotItem>[],
  List<Fleet>? fleets,
  Map<int, MasterShip> masterShips = const <int, MasterShip>{},
  bool hasEquipmentInventory = true,
}) => GameState(
  ships: <int, OwnedShip>{for (final ship in ships) ship.id: ship},
  slotItems: <int, OwnedSlotItem>{
    for (final item in slotItems) item.instanceId: item,
  },
  fleets:
      fleets ??
      <Fleet>[
        Fleet(
          id: 1,
          name: 'First',
          shipIds: <int>[
            1,
            ...ships.where((ship) => ship.id != 1).map((ship) => ship.id),
          ],
        ),
      ],
  masterShips: masterShips,
  hasEquipmentInventory: hasEquipmentInventory,
  combatState: const CombatState(isActive: true, sortieFleetId: 1),
);

GameState multiFleetState() => sortieState(
  ships: <OwnedShip>[
    for (var shipId = 1; shipId <= 6; shipId++) warningShip(shipId),
  ],
  fleets: const <Fleet>[
    Fleet(id: 1, name: 'First', shipIds: <int>[1, 2]),
    Fleet(id: 2, name: 'Second', shipIds: <int>[3, 4]),
    Fleet(id: 3, name: 'Third', shipIds: <int>[5, 6]),
  ],
).copyWith(combinedFleetType: CombinedFleetType.carrierTaskForce);
