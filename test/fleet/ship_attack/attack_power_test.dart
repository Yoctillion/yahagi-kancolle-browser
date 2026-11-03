import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_attack/attack_power.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_attack/ship_loadout.dart';

import '_fixtures.dart';

ShipLoadout _loadout(ShipSpec spec) {
  final state = buildState(<ShipSpec>[spec]);
  return ShipLoadout.fromState(state, state.ships[spec.id]!)!;
}

void main() {
  test('softCap applies square root above cap', () {
    expect(softCap(255, 220), closeTo(225.916, 0.001));
    expect(floorPower(softCap(255, 220)), 225);
    expect(softCap(200, 220), 200);
  });

  test('floorPower tolerates floating point error', () {
    expect(floorPower(200 * 1.15), 230);
  });

  test('battleship day basic power', () {
    final loadout = _loadout(
      ShipSpec(
        id: 1,
        shipTypeId: 9,
        firepower: 150,
        gears: <GearSpec?>[GearSpec(gear(8, t2: 3, firepower: 20))],
      ),
    );
    expect(isCarrierLike(loadout), isFalse);
    expect(dayBasicPrecap(loadout), 155);
  });

  test('carrier day basic power uses aerial formula', () {
    // aerial = floor(1.3 * 11) + 13 + 15 = 42
    // floor((5 + 70 + 42) * 1.5) + 25 = 200
    final loadout = _loadout(
      ShipSpec(
        id: 1,
        shipTypeId: 11,
        firepower: 70,
        gears: <GearSpec?>[
          GearSpec(gear(24, t2: 7, bombing: 11)),
          GearSpec(gear(52, t2: 8, torpedo: 13)),
        ],
        slotCapacities: const <int>[20, 20],
      ),
    );
    expect(isCarrierLike(loadout), isTrue);
    expect(dayBasicPrecap(loadout), 200);
  });

  test('cruiser fit bonus counts single and twin guns', () {
    final loadout = _loadout(
      ShipSpec(
        id: 1,
        shipTypeId: 3,
        gears: <GearSpec?>[
          GearSpec(gear(4, t2: 2)),
          GearSpec(gear(65, t2: 2)),
          GearSpec(gear(65, t2: 2)),
        ],
      ),
    );
    expect(cruiserFitBonus(loadout), closeTo(1 + 2 * math.sqrt2, 1e-9));
  });

  test('model D small gun modifier', () {
    ShipLoadout dd(List<int> ids) => _loadout(
      ShipSpec(
        id: 1,
        shipTypeId: 2,
        gears: <GearSpec?>[for (final id in ids) GearSpec(gear(id, t2: 1))],
      ),
    );
    expect(modelDSmallGunMod(dd(const <int>[])), 1.0);
    expect(modelDSmallGunMod(dd(const <int>[267])), 1.25);
    expect(
      modelDSmallGunMod(dd(const <int>[267, 366])),
      closeTo(1.4 * 1.05, 1e-9),
    );
    expect(
      modelDSmallGunMod(dd(const <int>[366, 366])),
      closeTo(1.4 * 1.1, 1e-9),
    );
  });

  test('destroyer normal night basic power', () {
    final loadout = _loadout(
      const ShipSpec(id: 1, shipTypeId: 2, firepower: 60, torpedo: 90),
    );
    expect(nightAttackKind(loadout), NightAttackKind.normal);
    expect(nightBasicPrecap(loadout, NightAttackKind.normal), 150);
  });

  test('night carrier aerial power', () {
    final loadout = _loadout(
      ShipSpec(
        id: 1,
        shipTypeId: 11,
        baseFirepower: 50,
        gears: <GearSpec?>[GearSpec(gear(338, t2: 6, t3: 45, firepower: 10))],
        slotCapacities: const <int>[18],
      ),
    );
    expect(
      nightBasicPrecap(loadout, NightAttackKind.carrierAerial),
      closeTo(50 + 10 + 54 + 0.45 * 10 * math.sqrt(18), 1e-9),
    );
  });

  test('night carrier attack needs night operation personnel', () {
    ShipSpec carrier({bool personnel = false}) => ShipSpec(
      id: 1,
      shipTypeId: 11,
      baseFirepower: 0,
      gears: <GearSpec?>[
        GearSpec(gear(345, t2: 8, t3: 46, torpedo: 9)),
        if (personnel) GearSpec(gear(258, t2: 35, t3: 29)),
      ],
      slotCapacities: const <int>[18, 0],
    );
    expect(nightAttackKind(_loadout(carrier())), isNull);
    expect(
      nightAttackKind(_loadout(carrier(personnel: true))),
      NightAttackKind.carrierAerial,
    );
  });
}
