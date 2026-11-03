import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_attack/ship_attack_profile.dart';

import '_fixtures.dart';

final _bigGun = gear(8, t2: 3, firepower: 20);
final _apShell = gear(116, t2: 19, firepower: 9);
final _seaplane = gear(59, t2: 10, lineOfSight: 6);

ShipSpec _battleship(int id) => ShipSpec(
  id: id,
  shipTypeId: 9,
  firepower: 150,
  luck: 20,
  lineOfSight: 40,
  gears: <GearSpec?>[
    GearSpec(_bigGun),
    GearSpec(_bigGun),
    GearSpec(_apShell),
    GearSpec(_seaplane),
  ],
  slotCapacities: const <int>[4, 4, 4, 3],
);

const _escort = ShipSpec(id: 2, shipTypeId: 2, firepower: 30, torpedo: 40);

double _mainMainRate(ShipAttackProfile profile) =>
    profile.day!.rows.firstWhere((row) => row.label == '主主徹').rate;

void main() {
  test('uses fleet flagship position', () {
    final ships = <ShipSpec>[_battleship(1), _escort];
    final asFlagship = buildState(
      ships,
      fleets: const <List<int>>[
        <int>[1, 2],
      ],
    );
    final asEscort = buildState(
      ships,
      fleets: const <List<int>>[
        <int>[2, 1],
      ],
    );
    expect(
      _mainMainRate(
        computeShipAttackProfile(asFlagship, asFlagship.ships[1]!)!,
      ),
      closeTo(52 / 150, 1e-9),
    );
    expect(
      _mainMainRate(computeShipAttackProfile(asEscort, asEscort.ships[1]!)!),
      closeTo(37 / 150, 1e-9),
    );
  });

  test('fleet LoS sums all members', () {
    final scout = ShipSpec(
      id: 2,
      shipTypeId: 6,
      lineOfSight: 60,
      gears: <GearSpec?>[GearSpec(_seaplane)],
      slotCapacities: const <int>[3],
    );
    final alone = buildState(
      <ShipSpec>[_battleship(1)],
      fleets: const <List<int>>[
        <int>[1],
      ],
    );
    final withScout = buildState(
      <ShipSpec>[_battleship(1), scout],
      fleets: const <List<int>>[
        <int>[1, 2],
      ],
    );
    expect(
      _mainMainRate(computeShipAttackProfile(withScout, withScout.ships[1]!)!),
      greaterThan(
        _mainMainRate(computeShipAttackProfile(alone, alone.ships[1]!)!),
      ),
    );
  });

  test('ship outside fleet uses own LoS only and is not flagship', () {
    final state = buildState(<ShipSpec>[_battleship(1)]);
    final profile = computeShipAttackProfile(state, state.ships[1]!)!;
    expect(_mainMainRate(profile), closeTo(37 / 150, 1e-9));
  });

  test('submarine has no day phase', () {
    final state = buildState(<ShipSpec>[
      ShipSpec(
        id: 1,
        shipTypeId: 13,
        torpedo: 80,
        baseFirepower: 0,
        baseTorpedo: 20,
        gears: <GearSpec?>[GearSpec(gear(213, t2: 32, torpedo: 15))],
      ),
    ]);
    final profile = computeShipAttackProfile(state, state.ships[1]!)!;
    expect(profile.day, isNull);
    expect(profile.night, isNotNull);
  });

  test('omitsBombingBonus only for carriers', () {
    final state = buildState(<ShipSpec>[
      _battleship(1),
      ShipSpec(
        id: 3,
        shipTypeId: 11,
        firepower: 70,
        gears: <GearSpec?>[
          GearSpec(gear(24, t2: 7, bombing: 11)),
          GearSpec(gear(52, t2: 8, torpedo: 13)),
        ],
        slotCapacities: const <int>[20, 20],
      ),
    ]);
    expect(
      computeShipAttackProfile(state, state.ships[1]!)!.omitsBombingBonus,
      isFalse,
    );
    expect(
      computeShipAttackProfile(state, state.ships[3]!)!.omitsBombingBonus,
      isTrue,
    );
  });

  test('returns null when ship master is missing', () {
    final state = buildState(<ShipSpec>[_battleship(1)]);
    final orphan = state.ships[1]!;
    final empty = buildState(const <ShipSpec>[]);
    expect(computeShipAttackProfile(empty, orphan), isNull);
  });
}
