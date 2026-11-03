import 'dart:math' as math;

import '../../game_state/game_state.dart';
import 'gear_traits.dart';
import 'improvement_bonus.dart';
import 'ship_loadout.dart';

const double shellingPowerCap = 220;
const double nightPowerCap = 360;

/// Products such as `200 * 1.15` land just below the integer in binary
/// floating point; the game computes them as exact decimals.
int floorPower(double x) => (x + 1e-9).floor();

double softCap(double precap, double cap) =>
    precap > cap ? cap + math.sqrt(precap - cap) : precap;

bool isCarrierLike(ShipLoadout l) {
  if (ShipTypeIds.carriers.contains(l.master.shipTypeId)) return true;
  final isAoCarrier =
      l.master.id == ShipIds.hayasuiKai ||
      l.master.classTypeId == ShipClassIds.toku2tl ||
      l.master.classTypeId == ShipClassIds.toku1tl;
  return isAoCarrier && l.has((g) => g.isCarrierShellingPlane);
}

double _sumBonus(
  ShipLoadout l,
  double Function(MasterSlotItem item, int stars) bonus,
) => l.slots.fold<double>(0, (sum, slot) => sum + bonus(slot.item, slot.stars));

double dayBasicPrecap(ShipLoadout l) {
  final shellingBonus = _sumBonus(l, shellingImprovementBonus);
  final basic = 5 + l.ship.firepower + shellingBonus;
  if (!isCarrierLike(l)) return basic + cruiserFitBonus(l);

  final aerialBonus = _sumBonus(l, carrierAerialImprovementBonus);
  final aerial =
      (1.3 * l.sumEquipment((g) => g.bombing)).floor() +
      l.sumEquipment((g) => g.torpedo) +
      15;
  return ((basic + aerialBonus + aerial) * 1.5).floor() +
      25 +
      cruiserFitBonus(l);
}

double cruiserFitBonus(ShipLoadout l) {
  if (ShipTypeIds.lightCruisers.contains(l.master.shipTypeId)) {
    final single = l.count((g) => GearIds.cruiserFitSingleGuns.contains(g.id));
    final twin = l.count((g) => GearIds.cruiserFitTwinGuns.contains(g.id));
    return math.sqrt(single) + 2 * math.sqrt(twin);
  }
  if (l.master.classTypeId == ShipClassIds.zara) {
    return math.sqrt(l.count((g) => g.id == GearIds.zara203mm53));
  }
  return 0;
}

double modelDSmallGunMod(ShipLoadout l) {
  final kai2 = l.count((g) => g.id == GearIds.modelDKai2);
  final kai3 = l.count((g) => g.id == GearIds.modelDKai3);
  final total = kai2 + kai3;
  if (total == 0) return 1;
  final base = total == 1 ? 1.25 : 1.4;
  if (kai3 == 1) return base * 1.05;
  if (kai3 >= 2) return base * 1.1;
  return base;
}

enum NightAttackKind { normal, carrierAerial, swordfish }

NightAttackKind? nightAttackKind(ShipLoadout l) {
  final master = l.master;
  if (ShipTypeIds.carriers.contains(master.shipTypeId) &&
      master.id != ShipIds.shimanemaruKai) {
    final hasPersonnel =
        ShipIds.nightCarriers.contains(master.id) ||
        l.has((g) => GearIds.nightOperationPersonnel.contains(g.id));
    if (hasPersonnel &&
        l.hasNonZeroSlot((g) => g.isNightAttacker || g.isNightFighter)) {
      return NightAttackKind.carrierAerial;
    }
  }
  if (master.classTypeId == ShipClassIds.arkRoyal &&
      l.hasNonZeroSlot((g) => g.isSwordfish)) {
    return NightAttackKind.swordfish;
  }
  if (master.baseFirepower + master.baseTorpedo > 0) {
    return NightAttackKind.normal;
  }
  return null;
}

double nightBasicPrecap(ShipLoadout l, NightAttackKind kind) {
  switch (kind) {
    case NightAttackKind.normal:
      return l.ship.firepower +
          l.ship.torpedo +
          _sumBonus(l, nightImprovementBonus);
    case NightAttackKind.carrierAerial:
      var power = l.nakedFirepower.toDouble();
      for (final slot in l.slots) {
        final g = slot.item;
        if (slot.isExSlot || slot.planes <= 0 || !g.isNightPlane) continue;
        final n = slot.planes.toDouble();
        // Night fighters and attackers do not add their bombing stat
        // directly (TBM-3S+3W), but it still feeds the plane multiplier.
        final base =
            g.firepower +
            g.torpedo +
            (g.isNightAttacker || g.isNightFighter ? 0 : g.bombing);
        final fullNightPlane =
            g.isNightAttacker || g.isNightFighter || g.isNightBomber;
        final a = fullNightPlane ? 3.0 : 0.0;
        final b = fullNightPlane ? 0.45 : 0.3;
        final multiplier = g.firepower + g.torpedo + g.bombing + g.antiSub;
        power +=
            base +
            a * n +
            b * multiplier * math.sqrt(n) +
            math.sqrt(slot.stars);
      }
      return power;
    case NightAttackKind.swordfish:
      var power = l.nakedFirepower.toDouble();
      for (final slot in l.slots) {
        if (slot.isExSlot || slot.planes <= 0 || !slot.item.isSwordfish) {
          continue;
        }
        power +=
            slot.item.firepower + slot.item.torpedo + math.sqrt(slot.stars);
      }
      return power;
  }
}
