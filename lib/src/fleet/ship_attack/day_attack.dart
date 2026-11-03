import 'dart:math' as math;

import 'attack_power.dart';
import 'attack_profile.dart';
import 'gear_traits.dart';
import 'ship_loadout.dart';

// Values and ordering from fleethub master_data day_cutin (2026-10); the
// list order is the in-game roll order.
const _zuiun = CutinDef('瑞雲立体攻撃', 1.35, 120, 1);
const _airSea = CutinDef('海空立体攻撃', 1.3, 120, 1);
const _mainMain = CutinDef('主主徹', 1.5, 150, 1);
const _mainAp = CutinDef('主徹', 1.3, 140, 1);
const _mainRadar = CutinDef('主電', 1.2, 130, 1);
const _mainSec = CutinDef('主副', 1.1, 120, 1);
const _doubleAttack = CutinDef('連撃', 1.2, 130, 2);
const _jfjbjb = CutinDef('噴戦噴爆噴爆', 1.35, 135, 1);
const _jfjb = CutinDef('噴戦噴爆', 1.3, 125, 1);
const _jfba = CutinDef('噴戦爆攻', 1.27, 115, 1);
const _fba = CutinDef('戦爆攻', 1.25, 125, 1);
const _bba = CutinDef('爆爆攻', 1.2, 140, 1);
const _ba = CutinDef('爆攻', 1.15, 155, 1);

const _dayCutinOrder = <CutinDef>[
  _zuiun,
  _airSea,
  _mainMain,
  _mainAp,
  _mainRadar,
  _mainSec,
  _doubleAttack,
  _jfjbjb,
  _jfjb,
  _jfba,
  _fba,
  _bba,
  _ba,
];

int fleetObservationLosMod(List<ShipLoadout> fleet) {
  var total = 0.0;
  for (final l in fleet) {
    total += l.nakedLineOfSight;
    for (final slot in l.slots) {
      if (slot.isExSlot || !slot.item.isObservationSeaplane) continue;
      total += slot.item.lineOfSight * math.sqrt(slot.planes).floor();
    }
  }
  return (math.sqrt(total) + 0.1 * total).floor();
}

/// Assumes air supremacy, the fixed condition of this view.
int dayObservationTerm(
  ShipLoadout l, {
  required int fleetLosMod,
  required bool isFlagship,
}) {
  final luckFactor = (math.sqrt(l.ship.luck) + 10).floor();
  final equipmentLos = l.sumEquipment((g) => g.lineOfSight);
  return (luckFactor + 0.7 * (fleetLosMod + 1.6 * equipmentLos) + 10).floor() +
      (isFlagship ? 15 : 0);
}

Set<CutinDef> _possibleDayCutins(ShipLoadout l) {
  final set = <CutinDef>{};
  if (isCarrierLike(l)) {
    final bombers = l.count((g) => g.isCbDiveBomber);
    final hasTorpedoBomber = l.hasNonZeroSlot((g) => g.isCbTorpedoBomber);
    final hasFighter = l.hasNonZeroSlot((g) => g.isCbFighter);
    final hasJetFighter = l.hasNonZeroSlot((g) => g.isJetFighter);
    final jetBombers = l.count((g) => g.isJetFighterBomber);
    if (bombers >= 1 && hasTorpedoBomber) set.add(_ba);
    if (bombers >= 2 && hasTorpedoBomber) set.add(_bba);
    if (hasFighter && bombers >= 1 && hasTorpedoBomber) set.add(_fba);
    if (hasJetFighter && jetBombers >= 2) set.add(_jfjbjb);
    if (hasJetFighter && jetBombers >= 1) set.add(_jfjb);
    if (hasJetFighter && bombers >= 1 && hasTorpedoBomber) set.add(_jfba);
    return set;
  }

  final mainGuns = l.count((g) => g.isMainGun);
  if (mainGuns == 0) return set;

  final sortSuffix = l.master.sortNo % 10;
  final isIseKai2 =
      l.master.classTypeId == ShipClassIds.ise &&
      sortSuffix >= 6 &&
      sortSuffix < 9;
  if (isIseKai2) {
    if (l.countNonZeroSlot((g) => GearIds.iseZuiun.contains(g.id)) >= 2) {
      set.add(_zuiun);
    }
    if (l.countNonZeroSlot((g) => GearIds.ise634Suisei.contains(g.id)) >= 2) {
      set.add(_airSea);
    }
  }

  if (!l.hasNonZeroSlot((g) => g.isObservationSeaplane)) return set;

  final secondaryGuns = l.count((g) => g.isSecondaryGun);
  final hasApShell = l.has((g) => g.isApShell);
  final hasRadar = l.has((g) => g.isRadar);
  if (mainGuns >= 2) {
    set.add(_doubleAttack);
    if (hasApShell) set.add(_mainMain);
  }
  if (secondaryGuns >= 1) {
    set.add(_mainSec);
    if (hasRadar) set.add(_mainRadar);
    if (hasApShell) set.add(_mainAp);
  }
  return set;
}

bool _participatesInDay(ShipLoadout l) {
  if (ShipTypeIds.submarines.contains(l.master.shipTypeId)) return false;
  if (isCarrierLike(l)) {
    return l.hasNonZeroSlot((g) => g.isCarrierShellingPlane);
  }
  return l.nakedFirepower > 0;
}

AttackPhaseProfile? computeDayProfile(
  ShipLoadout l, {
  required int fleetLosMod,
  required bool isFlagship,
}) {
  if (!_participatesInDay(l)) return null;

  final term = dayObservationTerm(
    l,
    fleetLosMod: fleetLosMod,
    isFlagship: isFlagship,
  );
  final possible = _possibleDayCutins(l);
  final precap = dayBasicPrecap(l);
  final cappedPower = floorPower(softCap(precap, shellingPowerCap));
  final capped = precap > shellingPowerCap;

  final rates = sequentialRates(
    _dayCutinOrder.where(possible.contains),
    (def) => term / def.typeFactor,
  );
  return AttackPhaseProfile(<AttackStyleRow>[
    for (final (def, rate) in rates)
      AttackStyleRow(
        label: def?.label ?? normalAttackLabel,
        rate: rate,
        powerMod: def?.powerMod ?? 1,
        hits: def?.hits ?? 1,
        powerPerHit: floorPower(cappedPower * (def?.powerMod ?? 1)),
        capped: capped,
      ),
  ]);
}
