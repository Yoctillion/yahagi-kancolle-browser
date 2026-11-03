import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_attack/gear_traits.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_attack/ship_loadout.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';

import '_fixtures.dart';

ShipLoadout _loadout(ShipSpec spec, {Map<int, MasterSlotItem>? extra}) {
  final state = buildState(<ShipSpec>[spec], extraMasterSlotItems: extra ?? {});
  return ShipLoadout.fromState(state, state.ships[spec.id]!)!;
}

void main() {
  final gun = gear(1, t2: 1);
  final seaplane = gear(2, t2: 10, lineOfSight: 6);

  test('planes use maxSlotCounts then master capacity', () {
    final loadout = _loadout(
      ShipSpec(
        id: 1,
        shipTypeId: 9,
        gears: <GearSpec?>[GearSpec(gun), GearSpec(seaplane)],
        maxSlotCounts: const <int>[18, 0],
        slotCapacities: const <int>[12, 9],
      ),
    );
    expect(loadout.slots.map((s) => s.planes), <int>[18, 9]);
  });

  test('preserves original slot index when a middle slot is empty', () {
    final loadout = _loadout(
      ShipSpec(
        id: 1,
        shipTypeId: 9,
        gears: <GearSpec?>[GearSpec(gun), null, GearSpec(seaplane)],
        slotCapacities: const <int>[3, 4, 5],
      ),
    );
    expect(loadout.slots.map((s) => s.planes), <int>[3, 5]);
  });

  test('ex slot is appended with zero planes', () {
    final loadout = _loadout(
      ShipSpec(
        id: 1,
        shipTypeId: 9,
        gears: <GearSpec?>[GearSpec(gun)],
        slotCapacities: const <int>[3],
        exGear: GearSpec(seaplane),
      ),
    );
    expect(loadout.slots.last.isExSlot, isTrue);
    expect(loadout.slots.last.planes, 0);
    expect(loadout.slots.first.isExSlot, isFalse);
  });

  test('zero-capacity slot does not count as non-zero plane slot', () {
    final loadout = _loadout(
      ShipSpec(
        id: 1,
        shipTypeId: 9,
        gears: <GearSpec?>[GearSpec(seaplane)],
        slotCapacities: const <int>[0],
      ),
    );
    expect(loadout.countNonZeroSlot((g) => g.isObservationSeaplane), 0);
    expect(loadout.count((g) => g.isObservationSeaplane), 1);
  });

  test('skips equipment whose master is missing', () {
    final state = buildState(<ShipSpec>[
      ShipSpec(
        id: 1,
        shipTypeId: 9,
        gears: <GearSpec?>[GearSpec(gun), GearSpec(seaplane)],
        slotCapacities: const <int>[1, 1],
      ),
    ]);
    final broken = GameState(
      masterShips: state.masterShips,
      ships: state.ships,
      slotItems: state.slotItems,
      masterSlotItems: <int, MasterSlotItem>{gun.id: gun},
    );
    final loadout = ShipLoadout.fromState(broken, broken.ships[1]!)!;
    expect(loadout.slots, hasLength(1));
  });

  test('nakedFirepower uses base plus modernization', () {
    final loadout = _loadout(
      const ShipSpec(
        id: 1,
        shipTypeId: 9,
        baseFirepower: 30,
        modernization: <int>[12, 0, 0, 0, 0],
      ),
    );
    expect(loadout.nakedFirepower, 42);
  });

  test('nakedLineOfSight subtracts equipment panel LoS', () {
    final loadout = _loadout(
      ShipSpec(
        id: 1,
        shipTypeId: 9,
        lineOfSight: 40,
        gears: <GearSpec?>[GearSpec(seaplane)],
        slotCapacities: const <int>[3],
      ),
    );
    expect(loadout.nakedLineOfSight, 34);
  });

  test('returns null when ship master is missing', () {
    const state = GameState(
      ships: <int, OwnedShip>{1: OwnedShip(id: 1, masterId: 5, level: 1)},
    );
    expect(ShipLoadout.fromState(state, state.ships[1]!), isNull);
  });

  test('isSurfaceRadar requires los 5', () {
    expect(gear(3, t2: 12, lineOfSight: 5).isSurfaceRadar, isTrue);
    expect(gear(3, t2: 12, lineOfSight: 4).isSurfaceRadar, isFalse);
    expect(gear(3, t2: 13, lineOfSight: 9).isSurfaceRadar, isTrue);
  });
}
