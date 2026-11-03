import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_attack/improvement_bonus.dart';

import '_fixtures.dart';

void main() {
  test('large gun with firepower above 12 uses 1.5 sqrt', () {
    expect(shellingImprovementBonus(gear(8, t2: 3, firepower: 20), 4), 3.0);
  });

  test('small main gun uses sqrt for day and night', () {
    final gun = gear(2, t2: 1, firepower: 3);
    expect(shellingImprovementBonus(gun, 9), 3.0);
    expect(nightImprovementBonus(gun, 9), 3.0);
  });

  test('listed high-angle secondary uses 0.2 per star', () {
    expect(shellingImprovementBonus(gear(10, t2: 4, firepower: 2), 10), 2.0);
    expect(nightImprovementBonus(gear(10, t2: 4, firepower: 2), 10), 2.0);
  });

  test('listed secondary uses 0.3 per star', () {
    expect(
      shellingImprovementBonus(gear(12, t2: 4, firepower: 4), 10),
      closeTo(3.0, 1e-9),
    );
  });

  test('torpedo improves night power only', () {
    final torpedo = gear(58, t2: 5, torpedo: 12);
    expect(shellingImprovementBonus(torpedo, 4), 0);
    expect(nightImprovementBonus(torpedo, 4), 2.0);
  });

  test('sonar uses 0.75 sqrt except excluded depth charges', () {
    expect(shellingImprovementBonus(gear(47, t2: 14), 4), 1.5);
    expect(shellingImprovementBonus(gear(226, t2: 15), 4), 0);
  });

  test('carrier aerial bonus for torpedo bomber and non-fighter dive bomber', () {
    expect(carrierAerialImprovementBonus(gear(52, t2: 8), 5), 1.0);
    expect(carrierAerialImprovementBonus(gear(24, t2: 7), 5), 1.0);
    expect(carrierAerialImprovementBonus(gear(60, t2: 7), 5), 0);
  });

  test('zero stars give no bonus', () {
    expect(shellingImprovementBonus(gear(8, t2: 3, firepower: 20), 0), 0);
    expect(nightImprovementBonus(gear(2, t2: 1), 0), 0);
    expect(carrierAerialImprovementBonus(gear(52, t2: 8), 0), 0);
  });
}
