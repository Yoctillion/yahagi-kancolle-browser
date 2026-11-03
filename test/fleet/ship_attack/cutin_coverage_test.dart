import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_attack/attack_power.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_attack/day_attack.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_attack/night_attack.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_attack/ship_loadout.dart';

import '_fixtures.dart';

ShipLoadout _loadout(ShipSpec spec) {
  final state = buildState(<ShipSpec>[spec]);
  return ShipLoadout.fromState(state, state.ships[spec.id]!)!;
}

const _noLights = NightFleetConditions(searchlight: false, starshell: false);

List<String> _dayLabels(ShipSpec spec) => computeDayProfile(
  _loadout(spec),
  fleetLosMod: 10,
  isFlagship: false,
)!.rows.map((row) => row.label).toList();

List<String> _nightLabels(ShipSpec spec) => computeNightProfile(
  _loadout(spec),
  isFlagship: false,
  fleet: _noLights,
)!.rows.map((row) => row.label).toList();

final _bigGun = gear(8, t2: 3, firepower: 20);
final _torpedo = gear(58, t2: 5, torpedo: 12);

void main() {
  group('real master IDs', () {
    // Ise Kai Ni (553) has api_sortno 353; the Kai Ni check must not rely on
    // the encyclopedia number.
    for (final masterId in const <int>[553, 554]) {
      test('ise-class kai2 $masterId gets zuiun and air-sea attacks', () {
        final labels = _dayLabels(
          ShipSpec(
            id: 1,
            masterId: masterId,
            shipTypeId: 10,
            classTypeId: 2,
            sortNo: 353,
            firepower: 90,
            luck: 30,
            gears: <GearSpec?>[
              GearSpec(_bigGun),
              GearSpec(_bigGun),
              GearSpec(gear(26, t2: 11, bombing: 4, lineOfSight: 6)),
              GearSpec(gear(26, t2: 11, bombing: 4, lineOfSight: 6)),
              GearSpec(gear(319, t2: 7, bombing: 12)),
              GearSpec(gear(291, t2: 7, bombing: 11)),
            ],
            slotCapacities: const <int>[2, 2, 22, 11, 8, 8],
          ),
        );
        expect(labels.take(2), <String>['瑞雲立体攻撃', '海空立体攻撃']);
      });
    }

    test('ise kai (non kai2) has no zuiun attack', () {
      final labels = _dayLabels(
        ShipSpec(
          id: 1,
          masterId: 82,
          shipTypeId: 10,
          classTypeId: 2,
          firepower: 80,
          gears: <GearSpec?>[
            GearSpec(_bigGun),
            GearSpec(_bigGun),
            GearSpec(gear(26, t2: 11, lineOfSight: 6)),
            GearSpec(gear(26, t2: 11, lineOfSight: 6)),
          ],
          slotCapacities: const <int>[11, 11, 11, 14],
        ),
      );
      expect(labels, isNot(contains('瑞雲立体攻撃')));
    });

    test('toku1tl class 132 with attack planes is carrier-like', () {
      ShipLoadout ship(int classTypeId) => _loadout(
        ShipSpec(
          id: 1,
          masterId: 1003,
          shipTypeId: 22,
          classTypeId: classTypeId,
          gears: <GearSpec?>[GearSpec(gear(52, t2: 8, torpedo: 13))],
          slotCapacities: const <int>[8],
        ),
      );
      expect(isCarrierLike(ship(132)), isTrue);
      expect(isCarrierLike(ship(119)), isFalse);
    });
  });

  group('night power', () {
    test('light cruiser fit bonus applies at night', () {
      final profile = computeNightProfile(
        _loadout(
          ShipSpec(
            id: 1,
            shipTypeId: 3,
            firepower: 50,
            torpedo: 30,
            gears: <GearSpec?>[
              GearSpec(gear(407, t2: 2, firepower: 6)),
              GearSpec(gear(407, t2: 2, firepower: 6)),
            ],
          ),
        ),
        isFlagship: false,
        fleet: _noLights,
      )!;
      // (50 + 30) + 2 * sqrt(2) = 82.83
      expect(profile.rows.last.label, '通常攻撃');
      expect(profile.rows.last.powerPerHit, 82);
      // 連撃: 80 * 1.2 + 2 * sqrt(2) = 98.83
      expect(profile.rows.first.powerPerHit, 98);
    });

    test('destroyer below level 80 lands whole hits only', () {
      final profile = computeNightProfile(
        _loadout(
          ShipSpec(
            id: 1,
            shipTypeId: 2,
            level: 70,
            luck: 50,
            firepower: 60,
            torpedo: 90,
            gears: <GearSpec?>[
              GearSpec(gear(267, t2: 1, firepower: 3)),
              GearSpec(_torpedo),
              GearSpec(gear(28, t2: 12, lineOfSight: 5)),
            ],
          ),
        ),
        isFlagship: false,
        fleet: _noLights,
      )!;
      expect(profile.rows.first.label, '主魚電');
      expect(profile.rows.first.hits, 1);
    });
  });

  test('carrier day power keeps torpedo visible bonus', () {
    // Equipment torpedo 13 + visible bonus 2 shows up as ship torpedo 15.
    // aerial = floor(1.3 * 11) + 15 + 15 = 44; floor((75 + 44) * 1.5) + 25 = 203
    final l = _loadout(
      ShipSpec(
        id: 1,
        shipTypeId: 11,
        firepower: 70,
        torpedo: 15,
        baseTorpedo: 0,
        gears: <GearSpec?>[
          GearSpec(gear(24, t2: 7, bombing: 11)),
          GearSpec(gear(52, t2: 8, torpedo: 13)),
        ],
        slotCapacities: const <int>[20, 20],
      ),
    );
    expect(dayBasicPrecap(l), 203);
  });

  group('cut-in coverage', () {
    test('main gun with secondary, radar and AP shell', () {
      final labels = _dayLabels(
        ShipSpec(
          id: 1,
          shipTypeId: 5,
          firepower: 80,
          luck: 20,
          gears: <GearSpec?>[
            GearSpec(gear(50, t2: 2, firepower: 10)),
            GearSpec(gear(51, t2: 4, firepower: 4)),
            GearSpec(gear(28, t2: 12, lineOfSight: 5)),
            GearSpec(gear(116, t2: 19, firepower: 9)),
            GearSpec(gear(59, t2: 10, lineOfSight: 6)),
          ],
          slotCapacities: const <int>[2, 2, 2, 2, 2],
        ),
      );
      expect(labels, <String>['主徹', '主電', '主副', '通常攻撃']);
    });

    test('jet cut-ins', () {
      final labels = _dayLabels(
        ShipSpec(
          id: 1,
          shipTypeId: 18,
          firepower: 60,
          torpedo: 13,
          gears: <GearSpec?>[
            GearSpec(gear(500, t2: 56)),
            GearSpec(gear(199, t2: 57, bombing: 13)),
            GearSpec(gear(199, t2: 57, bombing: 13)),
            GearSpec(gear(24, t2: 7, bombing: 11)),
            GearSpec(gear(52, t2: 8, torpedo: 13)),
          ],
          slotCapacities: const <int>[10, 10, 10, 10, 10],
        ),
      );
      expect(labels, containsAll(<String>['噴戦噴爆噴爆', '噴戦噴爆', '噴戦爆攻', '爆攻']));
    });

    test('destroyer lookout cut-ins with torpedoes and drum', () {
      final labels = _nightLabels(
        ShipSpec(
          id: 1,
          shipTypeId: 2,
          luck: 40,
          firepower: 50,
          torpedo: 90,
          gears: <GearSpec?>[
            GearSpec(_torpedo),
            GearSpec(_torpedo),
            GearSpec(gear(412, t2: 39, t3: 32, torpedo: 3, lineOfSight: 2)),
            GearSpec(gear(75, t2: 30, t3: 25)),
          ],
        ),
      );
      expect(labels.take(2), <String>['魚水魚', '魚水ド']);
    });

    test('submarine cut-ins', () {
      final late = gear(213, t2: 32, torpedo: 15);
      expect(
        _nightLabels(
          ShipSpec(
            id: 1,
            shipTypeId: 13,
            baseTorpedo: 20,
            torpedo: 80,
            gears: <GearSpec?>[
              GearSpec(late),
              GearSpec(gear(458, t2: 51, lineOfSight: 2)),
            ],
          ),
        ).first,
        '潜水電探魚',
      );
      expect(
        _nightLabels(
          ShipSpec(
            id: 1,
            shipTypeId: 13,
            baseTorpedo: 20,
            torpedo: 80,
            gears: <GearSpec?>[GearSpec(late), GearSpec(late)],
          ),
        ).first,
        '潜水魚魚',
      );
    });

    test('photoelectric suisei night attack', () {
      final labels = _nightLabels(
        ShipSpec(
          id: 1,
          shipTypeId: 11,
          baseFirepower: 0,
          gears: <GearSpec?>[
            GearSpec(gear(338, t2: 6, t3: 45, firepower: 10)),
            GearSpec(gear(320, t2: 7, t3: 7, bombing: 11)),
            GearSpec(gear(258, t2: 35, t3: 29)),
          ],
          slotCapacities: const <int>[18, 18, 0],
        ),
      );
      expect(labels, contains('光電管彗星夜襲'));
    });

    test('ark royal swordfish night attack', () {
      final l = _loadout(
        ShipSpec(
          id: 1,
          shipTypeId: 11,
          classTypeId: 78,
          baseFirepower: 0,
          gears: <GearSpec?>[
            GearSpec(gear(242, t2: 8, firepower: 2, torpedo: 3)),
          ],
          slotCapacities: const <int>[24],
        ),
      );
      expect(nightAttackKind(l), NightAttackKind.swordfish);
      final profile = computeNightProfile(
        l,
        isFlagship: false,
        fleet: _noLights,
      )!;
      expect(profile.rows.single.label, '通常攻撃');
      expect(profile.rows.single.powerPerHit, 5);
    });
  });
}
