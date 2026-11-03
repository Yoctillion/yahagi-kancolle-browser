import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_attack/night_attack.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_attack/ship_loadout.dart';

import '_fixtures.dart';

ShipLoadout _loadout(ShipSpec spec) {
  final state = buildState(<ShipSpec>[spec]);
  return ShipLoadout.fromState(state, state.ships[spec.id]!)!;
}

const _noLights = NightFleetConditions(searchlight: false, starshell: false);

final _dGun = gear(267, t2: 1, firepower: 3);
final _torpedo = gear(58, t2: 5, torpedo: 12);
final _radar = gear(28, t2: 12, lineOfSight: 5);
final _mainGun = gear(50, t2: 2, firepower: 10);
final _secondary = gear(51, t2: 4, firepower: 4);

ShipSpec destroyer({List<GearSpec?>? gears}) => ShipSpec(
  id: 1,
  shipTypeId: 2,
  luck: 50,
  firepower: 60,
  torpedo: 90,
  gears:
      gears ??
      <GearSpec?>[GearSpec(_dGun), GearSpec(_torpedo), GearSpec(_radar)],
);

void main() {
  test('destroyer D-gun torpedo radar cutin', () {
    final l = _loadout(destroyer());
    expect(
      nightCutinTerm(l, isFlagship: false, fleet: _noLights, zuiun: false),
      72,
    );

    final profile = computeNightProfile(
      l,
      isFlagship: false,
      fleet: _noLights,
    )!;
    expect(profile.rows.map((row) => row.label), <String>['主魚電', '主魚', '通常攻击']);
    expect(profile.rows[0].rate, closeTo(0.631579, 1e-6));
    expect(profile.rows[0].powerPerHit, 243);
    expect(profile.rows[0].hits, 1.65);
    expect(profile.rows[1].rate, closeTo(0.230664, 1e-6));
    expect(profile.rows[1].powerPerHit, 195);
    expect(profile.rows[1].hits, 2);
    expect(profile.rows[2].rate, closeTo(0.137757, 1e-6));
    expect(profile.rows[2].powerPerHit, 150);
    expect(profile.expectedPower, closeTo(363.85, 0.01));
  });

  test('lookout bonuses', () {
    int term(ShipSpec spec) => nightCutinTerm(
      _loadout(spec),
      isFlagship: false,
      fleet: _noLights,
      zuiun: false,
    );
    final base = term(destroyer());
    final tslo = gear(412, t2: 39, t3: 32, torpedo: 3, lineOfSight: 2);
    final lookout = gear(129, t2: 39, t3: 32, lineOfSight: 2);
    expect(
      term(destroyer(gears: <GearSpec?>[GearSpec(_dGun), GearSpec(tslo)])),
      base + 8,
    );
    expect(
      term(destroyer(gears: <GearSpec?>[GearSpec(_dGun), GearSpec(lookout)])),
      base + 5,
    );
    final battleship = ShipSpec(id: 1, shipTypeId: 9, luck: 50);
    final battleshipWithTslo = ShipSpec(
      id: 1,
      shipTypeId: 9,
      luck: 50,
      gears: <GearSpec?>[GearSpec(tslo)],
    );
    expect(term(battleshipWithTslo), term(battleship));
  });

  test('fleet searchlight and starshell', () {
    final l = _loadout(destroyer());
    final base = nightCutinTerm(
      l,
      isFlagship: false,
      fleet: _noLights,
      zuiun: false,
    );
    final state = buildState(<ShipSpec>[
      destroyer(),
      ShipSpec(
        id: 2,
        shipTypeId: 3,
        gears: <GearSpec?>[GearSpec(gear(74, t2: 29))],
      ),
      ShipSpec(
        id: 3,
        shipTypeId: 3,
        gears: <GearSpec?>[GearSpec(gear(101, t2: 33))],
      ),
    ]);
    final fleet = nightFleetConditions(<ShipLoadout>[
      for (final id in <int>[1, 2, 3])
        ShipLoadout.fromState(state, state.ships[id]!)!,
    ]);
    expect(fleet.searchlight, isTrue);
    expect(fleet.starshell, isTrue);
    expect(
      nightCutinTerm(l, isFlagship: false, fleet: fleet, zuiun: false),
      base + 11,
    );
    expect(
      nightCutinTerm(l, isFlagship: true, fleet: _noLights, zuiun: false),
      base + 15,
    );
  });

  test('normal cutins are exclusive', () {
    final l = _loadout(
      ShipSpec(
        id: 1,
        shipTypeId: 5,
        firepower: 80,
        torpedo: 40,
        gears: <GearSpec?>[
          GearSpec(_mainGun),
          GearSpec(_mainGun),
          GearSpec(_mainGun),
          GearSpec(_torpedo),
          GearSpec(_torpedo),
        ],
      ),
    );
    final profile = computeNightProfile(
      l,
      isFlagship: false,
      fleet: _noLights,
    )!;
    expect(profile.rows.map((row) => row.label), <String>['主主主', '通常攻击']);
  });

  test('double attack fixed rate', () {
    final l = _loadout(
      ShipSpec(
        id: 1,
        shipTypeId: 5,
        firepower: 80,
        gears: <GearSpec?>[GearSpec(_mainGun), GearSpec(_secondary)],
      ),
    );
    final profile = computeNightProfile(
      l,
      isFlagship: false,
      fleet: _noLights,
    )!;
    expect(profile.rows.first.label, '连击');
    expect(profile.rows.first.rate, closeTo(109 / 110, 1e-12));
    expect(profile.rows.first.hits, 2);
  });

  test('night carrier cvci', () {
    final nightFighter = gear(338, t2: 6, t3: 45, firepower: 10);
    final nightAttacker = gear(345, t2: 8, t3: 46, torpedo: 9);
    final l = _loadout(
      ShipSpec(
        id: 1,
        shipTypeId: 11,
        luck: 10,
        baseFirepower: 0,
        gears: <GearSpec?>[
          GearSpec(nightFighter),
          GearSpec(nightFighter),
          GearSpec(nightFighter),
          GearSpec(nightAttacker),
          GearSpec(gear(258, t2: 35, t3: 29)),
        ],
        slotCapacities: const <int>[18, 18, 18, 18, 0],
      ),
    );
    final term = nightCutinTerm(
      l,
      isFlagship: false,
      fleet: _noLights,
      zuiun: false,
    );
    expect(term, 32);
    final profile = computeNightProfile(
      l,
      isFlagship: false,
      fleet: _noLights,
    )!;
    expect(profile.rows.map((row) => row.label), <String>[
      '夜襲CI 1.25',
      '夜襲CI 1.20',
      '夜襲CI 1.18',
      '通常攻击',
    ]);
    final r1 = 32 / 105;
    final r2 = (1 - r1) * 32 / 115;
    final r3 = (1 - r1 - r2) * 32 / 125;
    expect(profile.rows[0].rate, closeTo(r1, 1e-9));
    expect(profile.rows[1].rate, closeTo(r2, 1e-9));
    expect(profile.rows[2].rate, closeTo(r3, 1e-9));
  });

  test('night zuiun uses its own term', () {
    final l = _loadout(
      ShipSpec(
        id: 1,
        shipTypeId: 6,
        firepower: 70,
        gears: <GearSpec?>[
          GearSpec(_mainGun),
          GearSpec(_mainGun),
          GearSpec(gear(490, t2: 11, t3: 51, firepower: 3, lineOfSight: 7)),
          GearSpec(gear(129, t2: 39, t3: 32, lineOfSight: 2)),
        ],
        slotCapacities: const <int>[3, 3, 2, 0],
      ),
    );
    final normalTerm = nightCutinTerm(
      l,
      isFlagship: false,
      fleet: _noLights,
      zuiun: false,
    );
    final zuiunTerm = nightCutinTerm(
      l,
      isFlagship: false,
      fleet: _noLights,
      zuiun: true,
    );
    // luck 0, Lv 99 → base 22; normal term adds +5 for lookouts, zuiun +8.
    expect(normalTerm, 27);
    expect(zuiunTerm, 30);
    final profile = computeNightProfile(
      l,
      isFlagship: false,
      fleet: _noLights,
    )!;
    expect(profile.rows.first.label, '夜間瑞雲');
    expect(profile.rows.first.rate, closeTo(30 / 135, 1e-9));
  });

  test('ship that cannot night attack', () {
    final l = _loadout(const ShipSpec(id: 1, shipTypeId: 16, baseFirepower: 0));
    expect(computeNightProfile(l, isFlagship: false, fleet: _noLights), isNull);
  });
}
