import 'dart:math' as math;

import '../../game_state/game_state.dart';
import 'gear_traits.dart';

// Rules mirror fleethub master_data ibonuses (2026-10); the first matching
// rule wins. KC3 Gear.js#attackPowerImprovementBonus differs in places: it
// gates the 1.5 coefficient on gear type as well as firepower > 12, and picks
// 0.2 / 0.3 for secondary guns by icon instead of an ID list.

const _secondaryPointTwo = <int>{10, 66, 220, 275, 358, 464, 524, 565};
const _secondaryPointThree = <int>{12, 234, 247, 467};
const _shellingNoBonusAsw = <int>{226, 227, 378, 488};
const _shellingSqrtTypes = <int>{
  1, 2, 3, 4, 18, 19, 21, 24, 29, 36, 37, 42, 46, 34, 39, 32, 35, 54, //
};
const _nightSqrtTypes = <int>{
  1, 2, 3, 4, 5, 18, 19, 22, 24, 29, 36, 37, 42, 46, 34, 39, 35, 54, //
};

double shellingImprovementBonus(MasterSlotItem item, int stars) {
  if (stars <= 0) return 0;
  final x = stars.toDouble();
  final type = item.categoryId;
  if (item.firepower > 12) return 1.5 * math.sqrt(x);
  if (_secondaryPointTwo.contains(item.id)) return 0.2 * x;
  if (_secondaryPointThree.contains(item.id)) return 0.3 * x;
  if (const <int>{14, 40, 15}.contains(type) &&
      !_shellingNoBonusAsw.contains(item.id)) {
    return 0.75 * math.sqrt(x);
  }
  if (_shellingSqrtTypes.contains(type)) return math.sqrt(x);
  return 0;
}

double nightImprovementBonus(MasterSlotItem item, int stars) {
  if (stars <= 0) return 0;
  final x = stars.toDouble();
  if (item.isSubmarineTorpedo || _secondaryPointTwo.contains(item.id)) {
    return 0.2 * x;
  }
  if (_secondaryPointThree.contains(item.id)) return 0.3 * x;
  if (_nightSqrtTypes.contains(item.categoryId)) return math.sqrt(x);
  return 0;
}

double carrierAerialImprovementBonus(MasterSlotItem item, int stars) {
  if (stars <= 0) return 0;
  if (item.isCbTorpedoBomber ||
      (item.isCbDiveBomber && !item.isCbFighterBomber)) {
    return 0.2 * stars;
  }
  return 0;
}
