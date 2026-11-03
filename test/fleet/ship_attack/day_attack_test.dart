import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_attack/attack_profile.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_attack/day_attack.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_attack/ship_loadout.dart';

import '_fixtures.dart';

ShipLoadout _loadout(ShipSpec spec) {
  final state = buildState(<ShipSpec>[spec]);
  return ShipLoadout.fromState(state, state.ships[spec.id]!)!;
}

final _bigGun = gear(8, t2: 3, firepower: 20);
final _apShell = gear(116, t2: 19, firepower: 9);
final _seaplane = gear(59, t2: 10, lineOfSight: 6);

ShipSpec battleship({
  int firepower = 150,
  int luck = 20,
  int seaplaneCapacity = 3,
  bool seaplane = true,
}) => ShipSpec(
  id: 1,
  shipTypeId: 9,
  firepower: firepower,
  luck: luck,
  lineOfSight: 40,
  gears: <GearSpec?>[
    GearSpec(_bigGun),
    GearSpec(_bigGun),
    GearSpec(_apShell),
    if (seaplane) GearSpec(_seaplane),
  ],
  slotCapacities: <int>[4, 4, 4, if (seaplane) seaplaneCapacity],
);

void _expectRow(
  AttackStyleRow row, {
  required String label,
  required double rate,
  required int power,
  double hits = 1,
}) {
  expect(row.label, label);
  expect(row.rate, closeTo(rate, 1e-6));
  expect(row.powerPerHit, power);
  expect(row.hits, hits);
}

void main() {
  test('battleship main-main-AP spotting', () {
    final l = _loadout(battleship());
    final fleetLosMod = fleetObservationLosMod(<ShipLoadout>[l]);
    expect(fleetLosMod, 10);
    expect(dayObservationTerm(l, fleetLosMod: 10, isFlagship: true), 52);

    final profile = computeDayProfile(l, fleetLosMod: 10, isFlagship: true)!;
    expect(profile.rows, hasLength(3));
    _expectRow(profile.rows[0], label: '主主徹', rate: 0.346667, power: 232);
    _expectRow(
      profile.rows[1],
      label: '连击',
      rate: 0.261333,
      power: 186,
      hits: 2,
    );
    _expectRow(profile.rows[2], label: '通常攻击', rate: 0.392, power: 155);
    expect(profile.expectedPower, closeTo(238.40, 0.01));
  });

  test('carrier FBA and BA', () {
    final l = _loadout(
      ShipSpec(
        id: 1,
        shipTypeId: 11,
        firepower: 70,
        luck: 10,
        lineOfSight: 70,
        gears: <GearSpec?>[
          GearSpec(gear(22, t2: 6)),
          GearSpec(gear(24, t2: 7, bombing: 11)),
          GearSpec(gear(52, t2: 8, torpedo: 13)),
          GearSpec(gear(54, t2: 9, lineOfSight: 9)),
        ],
        slotCapacities: const <int>[20, 20, 20, 5],
      ),
    );
    final fleetLosMod = fleetObservationLosMod(<ShipLoadout>[l]);
    expect(
      dayObservationTerm(l, fleetLosMod: fleetLosMod, isFlagship: true),
      57,
    );

    final profile = computeDayProfile(
      l,
      fleetLosMod: fleetLosMod,
      isFlagship: true,
    )!;
    expect(profile.rows, hasLength(3));
    _expectRow(profile.rows[0], label: '戦爆攻', rate: 0.456, power: 250);
    _expectRow(profile.rows[1], label: '爆攻', rate: 0.200052, power: 230);
    _expectRow(profile.rows[2], label: '通常攻击', rate: 0.343948, power: 200);
    expect(profile.expectedPower, closeTo(228.80, 0.01));
  });

  test('capped power', () {
    final l = _loadout(battleship(firepower: 250));
    final profile = computeDayProfile(l, fleetLosMod: 10, isFlagship: true)!;
    expect(profile.rows.first.label, '主主徹');
    expect(profile.rows.first.powerPerHit, 337);
    expect(profile.rows.last.powerPerHit, 225);
    expect(profile.rows.every((row) => row.capped), isTrue);
  });

  test('rate is clamped to 1', () {
    final l = _loadout(battleship(luck: 99));
    final profile = computeDayProfile(l, fleetLosMod: 200, isFlagship: true)!;
    expect(profile.rows, hasLength(1));
    expect(profile.rows.single.label, '主主徹');
    expect(profile.rows.single.rate, 1);
  });

  test('no observation plane means normal attack only', () {
    final l = _loadout(battleship(seaplane: false));
    final profile = computeDayProfile(l, fleetLosMod: 10, isFlagship: true)!;
    expect(profile.rows, hasLength(1));
    _expectRow(profile.rows.single, label: '通常攻击', rate: 1, power: 155);
  });

  test('zero-plane observation slot disables spotting', () {
    final l = _loadout(battleship(seaplaneCapacity: 0));
    final profile = computeDayProfile(l, fleetLosMod: 10, isFlagship: true)!;
    expect(profile.rows.map((row) => row.label), <String>['通常攻击']);
  });

  test('ship outside fleet uses own LoS only', () {
    final l = _loadout(battleship());
    expect(fleetObservationLosMod(<ShipLoadout>[l]), 10);
    expect(fleetObservationLosMod(<ShipLoadout>[l, l]), 16);
  });

  test('submarine has no day phase', () {
    final l = _loadout(
      ShipSpec(
        id: 1,
        shipTypeId: 13,
        torpedo: 80,
        gears: <GearSpec?>[GearSpec(gear(213, t2: 32, torpedo: 15))],
      ),
    );
    expect(computeDayProfile(l, fleetLosMod: 0, isFlagship: false), isNull);
  });

  test('carrier without attack planes has no day phase', () {
    final l = _loadout(
      ShipSpec(
        id: 1,
        shipTypeId: 11,
        firepower: 50,
        gears: <GearSpec?>[GearSpec(gear(22, t2: 6))],
        slotCapacities: const <int>[20],
      ),
    );
    expect(computeDayProfile(l, fleetLosMod: 0, isFlagship: false), isNull);
  });
}
