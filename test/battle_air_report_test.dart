import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_air_report.dart';

Map<String, Object?> _stage1({
  int fCount = 0,
  int fLost = 0,
  int eCount = 0,
  int eLost = 0,
  List<int>? touch,
}) => {
  'api_f_count': fCount,
  'api_f_lostcount': fLost,
  'api_e_count': eCount,
  'api_e_lostcount': eLost,
  'api_touch_plane': ?touch,
};

Map<String, Object?> _stage2({
  int fCount = 0,
  int fLost = 0,
  int eCount = 0,
  int eLost = 0,
  Map<String, Object?>? airFire,
}) => {
  'api_f_count': fCount,
  'api_f_lostcount': fLost,
  'api_e_count': eCount,
  'api_e_lostcount': eLost,
  'api_air_fire': ?airFire,
};

Map<String, Object?> _stage3(List<num> edam) => {'api_edam': edam};

Map<String, Object?> _landBase(int baseId) => {
  'api_base_id': baseId,
  'api_stage1': _stage1(fCount: 18, eCount: 50, eLost: 10),
  'api_stage2': _stage2(),
  'api_stage3': _stage3([40, 0]),
};

void main() {
  test('parses main table with jets and second wave', () {
    final report = parseDayAirReport({
      'api_injection_kouku': {
        'api_stage1': _stage1(fCount: 12, fLost: 1, eCount: 135, eLost: 9),
        'api_stage2': _stage2(),
      },
      'api_kouku': {
        'api_stage1': _stage1(fCount: 168, fLost: 10, eCount: 156, eLost: 90),
        'api_stage2': _stage2(fCount: 102, fLost: 6, eCount: 58, eLost: 25),
      },
      'api_kouku2': {
        'api_stage1': _stage1(fLost: 2, eLost: 8),
        'api_stage2': _stage2(fLost: 2, eLost: 6),
      },
    })!;

    expect(
      report.jet,
      const PlaneExchange(friend: PlaneCount(12, 1), enemy: PlaneCount(135, 9)),
    );
    expect(
      report.fighter,
      const PlaneExchange(
        friend: PlaneCount(168, 12),
        enemy: PlaneCount(156, 98),
      ),
    );
    expect(
      report.antiAir,
      const PlaneExchange(
        friend: PlaneCount(102, 8),
        enemy: PlaneCount(58, 31),
      ),
    );
    expect(report.secondWave, isTrue);
    expect(report.hasMainTable, isTrue);
  });

  test('orders phases and numbers land-base waves per base', () {
    final report = parseDayAirReport({
      'api_air_base_injection': {
        'api_stage1': _stage1(fCount: 36),
        'api_stage2': _stage2(fLost: 14),
        'api_stage3': _stage3([90, 0, 0, 0, 0, 0]),
        'api_stage3_combined': _stage3([0, 0, 0, 0, 0, 0]),
      },
      'api_air_base_attack': [
        for (final id in [1, 1, 2, 2, 3, 3]) _landBase(id),
      ],
      'api_support_flag': 1,
      'api_support_info': {
        'api_support_airatack': {
          'api_stage3': _stage3([10]),
        },
      },
    })!;

    expect(report.phases.map((p) => p.kind).toList(), [
      AirPhaseKind.landBaseJet,
      ...List.filled(6, AirPhaseKind.landBase),
      AirPhaseKind.supportAir,
    ]);
    final lands = report.phases.where((p) => p.kind == AirPhaseKind.landBase);
    expect(lands.map((p) => (p.baseId, p.wave)).toList(), [
      (1, 1),
      (1, 2),
      (2, 1),
      (2, 2),
      (3, 1),
      (3, 2),
    ]);
    final jet = report.phases.first;
    expect(jet.planes.friend, const PlaneCount(36, 14));
    expect(jet.damage, 90);
    expect(report.hasMainTable, isFalse);
  });

  test('sums support damage with flooring', () {
    final shelling = parseDayAirReport({
      'api_support_flag': 2,
      'api_support_info': {
        'api_support_hourai': {
          'api_damage': [10.1, 0, 45.9],
        },
      },
    })!;
    expect(shelling.phases.single.kind, AirPhaseKind.supportShelling);
    expect(shelling.phases.single.damage, 55);

    final air = parseDayAirReport({
      'api_support_flag': 1,
      'api_support_info': {
        'api_support_airatack': {
          'api_stage3': _stage3([100.1, 20]),
        },
      },
    })!;
    expect(air.phases.single.kind, AirPhaseKind.supportAir);
    expect(air.phases.single.damage, 120);
  });

  test('reads contact and AACI', () {
    final report = parseDayAirReport({
      'api_kouku': {
        'api_stage1': _stage1(fCount: 10, eCount: 10, touch: [54, -1]),
        'api_stage2': _stage2(
          fCount: 10,
          airFire: {'api_idx': 2, 'api_kind': 10},
        ),
      },
    })!;
    expect(report.friendContactPlaneId, 54);
    expect(report.enemyContactPlaneId, -1);
    expect(report.antiAirCutIns, const [AntiAirCutIn(position: 2, kind: 10)]);
  });

  test('maps combined-fleet AACI and flare positions', () {
    final report = parseDayAirReport({
      'api_kouku': {
        'api_stage1': _stage1(fCount: 10, eCount: 10),
        'api_stage2': _stage2(
          fCount: 10,
          airFire: {'api_idx': 11, 'api_kind': 5},
        ),
      },
    })!;
    expect(report.antiAirCutIns.single.position, 11);

    final night = parseNightReport({
      'api_flare_pos': [9, -1],
    })!;
    expect(night.friendFlarePosition, 3);
    expect(night.enemyFlarePosition, -1);
  });

  test('tolerates missing stages and fields', () {
    final report = parseDayAirReport({
      'api_injection_kouku': {
        'api_stage1': _stage1(fCount: 20, fLost: 2, eCount: 30, eLost: 5),
      },
      'api_kouku': {'api_stage1': null, 'api_stage2': null, 'api_stage3': null},
    })!;
    expect(
      report.jet,
      const PlaneExchange(friend: PlaneCount(20, 2), enemy: PlaneCount(30, 5)),
    );
    expect(report.fighter, isNull);
    expect(report.antiAir, isNull);
    expect(report.hasMainTable, isTrue);
    expect(report.friendContactPlaneId, -1);
  });

  test('returns null when no aircraft and no phases', () {
    expect(
      parseDayAirReport({
        'api_hougeki1': {
          'api_damage': [1],
        },
      }),
      isNull,
    );
  });

  test('parses night contact, flare and night support', () {
    final night = parseNightReport({
      'api_touch_plane': [102, -1],
      'api_flare_pos': [3, -1],
      'api_n_support_flag': 2,
      'api_n_support_info': {
        'api_support_hourai': {
          'api_damage': [30, 0.1],
        },
      },
    })!;
    expect(
      night,
      const NightReport(
        friendContactPlaneId: 102,
        friendFlarePosition: 3,
        supportDamage: 30,
      ),
    );
    expect(
      parseNightReport({
        'api_touch_plane': [-1, -1],
      }),
      isNull,
    );
  });
}
