import 'dart:math' as math;

import 'attack_power.dart';
import 'attack_profile.dart';
import 'gear_traits.dart';
import 'ship_loadout.dart';

// Values and ordering from fleethub master_data night_cutin (2026-10).
// KC3 and kc-web use 115 for 主魚電; kc-web uses 124 for 魚水魚 (KC3 126).
const _mainTorpRadar = CutinDef('主魚電', 1.3, 114, 1.65);
const _torpLookoutRadar = CutinDef('魚見電', 1.2, 140, 1.5);
const _torpTsloTorp = CutinDef('魚水魚', 1.5, 126, 1.875);
const _torpTsloDrum = CutinDef('魚水ド', 1.3, 122, 1.55);
const _nightZuiun2Radar = CutinDef('夜間瑞雲×2+電探', 1.36, 135, 2);
const _nightZuiun2 = CutinDef('夜間瑞雲×2', 1.32, 135, 2);
const _nightZuiunRadar = CutinDef('夜間瑞雲+電探', 1.28, 135, 2);
const _nightZuiun = CutinDef('夜間瑞雲', 1.24, 135, 2);
const _doubleAttack = CutinDef('連撃', 1.2, 0, 2);
const _torpTorpMain = CutinDef('主魚', 1.3, 115, 2);
const _torpTorpTorp = CutinDef('魚魚', 1.5, 122, 2);
const _mainMainSec = CutinDef('主主副', 1.75, 130, 1);
const _mainMainMain = CutinDef('主主主', 2.0, 140, 1);
const _subTorpTorp = CutinDef('潜水魚魚', 1.6, 110, 2);
const _subRadarTorp = CutinDef('潜水電探魚', 1.75, 105, 2);
const _cvci125 = CutinDef('夜襲CI 1.25', 1.25, 105, 1);
const _cvci120 = CutinDef('夜襲CI 1.20', 1.2, 115, 1);
const _photobomber = CutinDef('光電管彗星夜襲', 1.2, 115, 1);
const _cvci118 = CutinDef('夜襲CI 1.18', 1.18, 125, 1);

const _nightCutinOrder = <CutinDef>[
  _mainTorpRadar,
  _torpLookoutRadar,
  _torpTsloTorp,
  _torpTsloDrum,
  _nightZuiun2Radar,
  _nightZuiun2,
  _nightZuiunRadar,
  _nightZuiun,
  _doubleAttack,
  _torpTorpMain,
  _torpTorpTorp,
  _mainMainSec,
  _mainMainMain,
  _subTorpTorp,
  _subRadarTorp,
  _cvci125,
  _cvci120,
  _photobomber,
  _cvci118,
];

const _nightZuiunCutins = <CutinDef>{
  _nightZuiun2Radar,
  _nightZuiun2,
  _nightZuiunRadar,
  _nightZuiun,
};

const _modelDCutins = <CutinDef>{_mainTorpRadar, _torpLookoutRadar};

class NightFleetConditions {
  const NightFleetConditions({
    required this.searchlight,
    required this.starshell,
  });

  final bool searchlight;
  final bool starshell;
}

NightFleetConditions nightFleetConditions(List<ShipLoadout> fleet) =>
    NightFleetConditions(
      searchlight: fleet.any((l) => l.has((g) => g.isSearchlight)),
      starshell: fleet.any((l) => l.has((g) => g.isStarshell)),
    );

int nightCutinTerm(
  ShipLoadout l, {
  required bool isFlagship,
  required NightFleetConditions fleet,
  required bool zuiun,
}) {
  final level = l.ship.level.toDouble();
  final luck = l.ship.luck;
  var term = luck < 50
      ? (luck + 15 + 0.75 * math.sqrt(level)).floor()
      : (math.sqrt(luck - 50).floor() + 65 + 0.8 * math.sqrt(level)).floor();
  if (isFlagship) term += 15;

  final hasLookouts = l.has((g) => g.id == GearIds.skilledLookouts);
  if (zuiun) {
    if (hasLookouts) term += 8;
    if (fleet.searchlight) term -= 10;
    if (fleet.starshell) term -= 10;
    return term;
  }

  final stype = l.master.shipTypeId;
  final isDestroyerOrLightCruiser =
      stype == ShipTypeIds.destroyer ||
      ShipTypeIds.lightCruisers.contains(stype);
  // https://twitter.com/Divinity__123/status/1479343022974324739
  if (isDestroyerOrLightCruiser &&
      l.has((g) => g.id == GearIds.torpedoSquadronLookouts)) {
    term += 8;
  }
  if (hasLookouts) term += 5;
  if (fleet.searchlight) term += 7;
  if (fleet.starshell) term += 4;
  return term;
}

Set<CutinDef> _possibleNightCutins(ShipLoadout l, NightAttackKind kind) {
  final set = <CutinDef>{};
  if (kind == NightAttackKind.carrierAerial) {
    final nf = l.countNonZeroSlot((g) => g.isNightFighter);
    final na = l.countNonZeroSlot((g) => g.isNightAttacker);
    final nb = l.countNonZeroSlot((g) => g.isNightBomber);
    final hasPhotobomber = l.hasNonZeroSlot(
      (g) => g.id == GearIds.photoelectricSuisei,
    );
    if (nf >= 2 && na >= 1) set.add(_cvci125);
    if (nf >= 1 && na >= 1) set.add(_cvci120);
    if ((hasPhotobomber && nf + na + nb >= 1) || (nb >= 1 && nf + na >= 1)) {
      set.add(_photobomber);
    }
    if (nf >= 1) {
      final semi = l.countNonZeroSlot((g) => g.isSemiNightPlane);
      if (nf + semi >= 3 || na + nb + semi >= 2) set.add(_cvci118);
    }
    return set;
  }
  if (kind == NightAttackKind.swordfish) return set;

  final torpedoes = l.count((g) => g.isTorpedo);
  final allTorpedoes = torpedoes + l.count((g) => g.isSubmarineTorpedo);
  final mainGuns = l.count((g) => g.isMainGun);
  final secondaryGuns = l.count((g) => g.isSecondaryGun);
  final hasSurfaceRadar = l.has((g) => g.isSurfaceRadar);
  final stype = l.master.shipTypeId;

  if (stype == ShipTypeIds.destroyer && torpedoes >= 1) {
    final hasTslo = l.has((g) => g.id == GearIds.torpedoSquadronLookouts);
    final hasLookout = hasTslo || l.has((g) => g.id == GearIds.skilledLookouts);
    if (hasSurfaceRadar) {
      if (mainGuns >= 1) set.add(_mainTorpRadar);
      if (hasLookout) set.add(_torpLookoutRadar);
    }
    if (hasTslo) {
      if (torpedoes >= 2) set.add(_torpTsloTorp);
      if (l.has((g) => g.id == GearIds.transportDrum)) set.add(_torpTsloDrum);
    }
  }

  if (ShipTypeIds.nightZuiunCapable.contains(stype) && mainGuns >= 2) {
    final zuiun = l.countNonZeroSlot((g) => g.id == GearIds.nightZuiun);
    if (zuiun >= 2) {
      if (hasSurfaceRadar) set.add(_nightZuiun2Radar);
      set.add(_nightZuiun2);
    }
    if (zuiun >= 1) {
      if (hasSurfaceRadar) set.add(_nightZuiunRadar);
      set.add(_nightZuiun);
    }
  }

  final lateTorpedoes = l.count((g) => g.isLateModelBowTorpedo);
  final hasSubmarineRadar = l.has((g) => g.isSubmarineEquipment);
  if (lateTorpedoes >= 1 && hasSubmarineRadar) {
    set.add(_subRadarTorp);
  } else if (lateTorpedoes >= 2) {
    set.add(_subTorpTorp);
  } else if (mainGuns >= 3) {
    set.add(_mainMainMain);
  } else if (mainGuns >= 2 && secondaryGuns >= 1) {
    set.add(_mainMainSec);
  } else if (allTorpedoes >= 2) {
    set.add(_torpTorpTorp);
  } else if (allTorpedoes >= 1 && mainGuns >= 1) {
    set.add(_torpTorpMain);
  } else if (mainGuns + secondaryGuns >= 2) {
    set.add(_doubleAttack);
  }
  return set;
}

AttackPhaseProfile? computeNightProfile(
  ShipLoadout l, {
  required bool isFlagship,
  required NightFleetConditions fleet,
}) {
  final kind = nightAttackKind(l);
  if (kind == null) return null;

  final possible = _possibleNightCutins(l, kind);
  final term = nightCutinTerm(
    l,
    isFlagship: isFlagship,
    fleet: fleet,
    zuiun: possible.any(_nightZuiunCutins.contains),
  );
  final basic = nightBasicPrecap(l, kind);
  final modelD = modelDSmallGunMod(l);
  final fitBonus = cruiserFitBonus(l);
  // Fractional hit counts blend single and double variants; the double
  // variants need Lv 80.
  final canDoubleHit = l.ship.level >= 80;

  final rates = sequentialRates(
    _nightCutinOrder.where(possible.contains),
    (def) => identical(def, _doubleAttack)
        ? 109 / 110
        : term.toDouble() / def.typeFactor,
  );
  AttackStyleRow row(CutinDef? def, double rate) {
    // Night cut-in multipliers apply before the cap, unlike day ones.
    final precap =
        basic *
            (def?.powerMod ?? 1) *
            (_modelDCutins.contains(def) ? modelD : 1) +
        fitBonus;
    final hits = def?.hits ?? 1;
    return AttackStyleRow(
      label: def?.label ?? normalAttackLabel,
      rate: rate,
      powerMod: def?.powerMod ?? 1,
      hits: canDoubleHit ? hits : hits.floorToDouble(),
      powerPerHit: floorPower(softCap(precap, nightPowerCap)),
      capped: precap > nightPowerCap,
    );
  }

  return AttackPhaseProfile(<AttackStyleRow>[
    for (final (def, rate) in rates) row(def, rate),
  ]);
}
