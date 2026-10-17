import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_damage_level.dart';
import 'package:yahagi_kancolle_browser/src/settings/battle_status_effect_settings.dart';

void main() {
  test(
    'steady morale follows the master switch and display scope independently of damage',
    () {
      const steady = BattleStatusEffectSettings(
        moraleSparkleMode: MoraleSparkleMode.steady,
        displayScope: BattleEffectDisplayScope.fleetOnly,
      );
      expect(
        steady.sparkleModeFor(BattleEffectSurface.fleet),
        MoraleSparkleMode.steady,
      );
      expect(
        steady.sparkleModeFor(BattleEffectSurface.prediction),
        MoraleSparkleMode.off,
      );
      final disabled = steady.copyWith(enabled: false);
      expect(
        disabled.sparkleModeFor(BattleEffectSurface.fleet),
        MoraleSparkleMode.off,
      );
      expect(disabled.moraleSparkleMode, MoraleSparkleMode.steady);
      expect(
        steady.pulseFilterFor(BattleEffectSurface.fleet),
        DamagePulseFilter.all,
      );
      expect(steady.vibrates(ShipDamageLevel.heavy), isTrue);
      expect(
        steady,
        isNot(steady.copyWith(moraleSparkleMode: MoraleSparkleMode.blinking)),
      );
    },
  );

  test('defaults preserve all existing status effects on both surfaces', () {
    const settings = BattleStatusEffectSettings();

    expect(settings.enabled, isTrue);
    expect(settings.displayScope, BattleEffectDisplayScope.all);
    expect(
      settings.pulseFilterFor(BattleEffectSurface.prediction),
      DamagePulseFilter.all,
    );
    expect(
      settings.pulseFilterFor(BattleEffectSurface.fleet),
      DamagePulseFilter.all,
    );
    expect(
      settings.sparkleModeFor(BattleEffectSurface.prediction),
      MoraleSparkleMode.blinking,
    );
    expect(
      settings.sparkleModeFor(BattleEffectSurface.fleet),
      MoraleSparkleMode.blinking,
    );
    expect(settings.vibrates(ShipDamageLevel.moderate), isTrue);
    expect(settings.vibrates(ShipDamageLevel.heavy), isTrue);
  });

  test('display scope controls pulse and sparkle but never vibration', () {
    const settings = BattleStatusEffectSettings(
      displayScope: BattleEffectDisplayScope.predictionOnly,
      damageVibrationFilter: DamageVibrationFilter.heavyOnly,
    );

    expect(
      settings.pulseFilterFor(BattleEffectSurface.prediction),
      DamagePulseFilter.all,
    );
    expect(
      settings.pulseFilterFor(BattleEffectSurface.fleet),
      DamagePulseFilter.off,
    );
    expect(
      settings.sparkleModeFor(BattleEffectSurface.prediction),
      MoraleSparkleMode.blinking,
    );
    expect(
      settings.sparkleModeFor(BattleEffectSurface.fleet),
      MoraleSparkleMode.off,
    );
    expect(settings.vibrates(ShipDamageLevel.heavy), isTrue);
  });

  test('master switch disables pulse sparkle and vibration together', () {
    const settings = BattleStatusEffectSettings(enabled: false);

    expect(
      settings.pulseFilterFor(BattleEffectSurface.prediction),
      DamagePulseFilter.off,
    );
    expect(
      settings.pulseFilterFor(BattleEffectSurface.fleet),
      DamagePulseFilter.off,
    );
    expect(
      settings.sparkleModeFor(BattleEffectSurface.prediction),
      MoraleSparkleMode.off,
    );
    expect(settings.vibrates(ShipDamageLevel.heavy), isFalse);
  });

  test('only filters match the selected final damage band exactly', () {
    expect(DamagePulseFilter.minorOnly.matches(ShipDamageLevel.minor), isTrue);
    expect(
      DamagePulseFilter.minorOnly.matches(ShipDamageLevel.moderate),
      isFalse,
    );
    expect(
      DamagePulseFilter.moderateOnly.matches(ShipDamageLevel.moderate),
      isTrue,
    );
    expect(
      DamagePulseFilter.moderateOnly.matches(ShipDamageLevel.heavy),
      isFalse,
    );
    expect(DamagePulseFilter.heavyOnly.matches(ShipDamageLevel.heavy), isTrue);
    expect(DamagePulseFilter.all.matches(ShipDamageLevel.healthy), isFalse);

    expect(
      DamageVibrationFilter.moderateOnly.matches(ShipDamageLevel.moderate),
      isTrue,
    );
    expect(
      DamageVibrationFilter.moderateOnly.matches(ShipDamageLevel.heavy),
      isFalse,
    );
    expect(
      DamageVibrationFilter.heavyOnly.matches(ShipDamageLevel.heavy),
      isTrue,
    );
    expect(DamageVibrationFilter.all.matches(ShipDamageLevel.minor), isFalse);
  });

  test('morale sparkle switch does not change damage effects', () {
    const settings = BattleStatusEffectSettings(
      moraleSparkleMode: MoraleSparkleMode.off,
    );

    expect(
      settings.sparkleModeFor(BattleEffectSurface.fleet),
      MoraleSparkleMode.off,
    );
    expect(
      settings.pulseFilterFor(BattleEffectSurface.fleet),
      DamagePulseFilter.all,
    );
    expect(settings.vibrates(ShipDamageLevel.heavy), isTrue);
  });

  test('copyWith produces an independent immutable value', () {
    const settings = BattleStatusEffectSettings();
    final updated = settings.copyWith(
      displayScope: BattleEffectDisplayScope.fleetOnly,
      damagePulseFilter: DamagePulseFilter.moderateOnly,
      damageVibrationFilter: DamageVibrationFilter.off,
      moraleSparkleMode: MoraleSparkleMode.off,
    );

    expect(updated.displayScope, BattleEffectDisplayScope.fleetOnly);
    expect(updated.damagePulseFilter, DamagePulseFilter.moderateOnly);
    expect(updated.damageVibrationFilter, DamageVibrationFilter.off);
    expect(updated.moraleSparkleMode, MoraleSparkleMode.off);
    expect(settings, const BattleStatusEffectSettings());
  });
}
