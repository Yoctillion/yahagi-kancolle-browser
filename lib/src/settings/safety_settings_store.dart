// Keep the public named constructor argument while storing it privately.
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'advance_warning_timing_settings.dart';
import 'battle_status_effect_settings.dart';

export 'advance_warning_timing_settings.dart';

enum BattleWarningMode { off, confirm }

enum AdvanceWarningDisplayMode { alwaysConfirm, smart }

abstract class SafetySettingsStore {
  Future<BattleWarningMode> loadWarningMode();
  Future<void> saveWarningMode(BattleWarningMode mode);
  Future<AdvanceWarningDisplayMode> loadAdvanceWarningDisplayMode();
  Future<void> saveAdvanceWarningDisplayMode(AdvanceWarningDisplayMode mode);
  Future<AdvanceWarningTimingSettings> loadAdvanceWarningTimings();
  Future<void> saveAdvanceWarningTimings(AdvanceWarningTimingSettings settings);
  Future<BattleStatusEffectSettings> loadBattleStatusEffects();
  Future<void> saveBattleStatusEffects(BattleStatusEffectSettings settings);
}

class SharedPreferencesSafetySettingsStore implements SafetySettingsStore {
  static const String _modeKey = 'safety.battleWarningMode';
  static const String _advanceWarningDisplayModeKey =
      'safety.advanceWarningDisplayMode';
  static const String _advanceWarningTimingModeKey =
      'safety.advanceWarningTimingMode';
  static const String _advanceWarningTimingsKey =
      'safety.advanceWarningTimings';
  static const String _damageVibrationKey = 'battle.damageVibrationEnabled';
  static const String _statusEffectsEnabledKey = 'battle.statusEffects.enabled';
  static const String _displayScopeKey = 'battle.statusEffects.displayScope';
  static const String _damagePulseFilterKey =
      'battle.statusEffects.damagePulseFilter';
  static const String _damageVibrationFilterKey =
      'battle.statusEffects.damageVibrationFilter';
  static const String _moraleSparkleEnabledKey =
      'battle.statusEffects.moraleSparkleEnabled';
  static const String _moraleSparkleModeKey =
      'battle.statusEffects.moraleSparkleMode';

  @override
  Future<BattleWarningMode> loadWarningMode() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_modeKey);
    return BattleWarningMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => BattleWarningMode.confirm,
    );
  }

  @override
  Future<void> saveWarningMode(BattleWarningMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.name);
  }

  @override
  Future<AdvanceWarningDisplayMode> loadAdvanceWarningDisplayMode() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.get(_advanceWarningDisplayModeKey);
    return _enumByName(
      AdvanceWarningDisplayMode.values,
      value is String ? value : null,
      AdvanceWarningDisplayMode.alwaysConfirm,
    );
  }

  @override
  Future<void> saveAdvanceWarningDisplayMode(
    AdvanceWarningDisplayMode mode,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_advanceWarningDisplayModeKey, mode.name);
  }

  @override
  Future<AdvanceWarningTimingSettings> loadAdvanceWarningTimings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_advanceWarningTimingsKey)) {
      return prefs.get(_advanceWarningTimingModeKey) == 'kca'
          ? AdvanceWarningTimingSettings.battleAndAdvance
          : AdvanceWarningTimingSettings.advanceOnly;
    }
    final value = prefs.get(_advanceWarningTimingsKey);
    if (value is! String) {
      return AdvanceWarningTimingSettings.advanceOnly;
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic> ||
          decoded['postBattle'] is! bool ||
          decoded['afterAdvance'] is! bool) {
        return AdvanceWarningTimingSettings.advanceOnly;
      }
      final settings = AdvanceWarningTimingSettings(
        postBattle: decoded['postBattle'] as bool,
        afterAdvance: decoded['afterAdvance'] as bool,
      );
      return settings.hasAny
          ? settings
          : AdvanceWarningTimingSettings.advanceOnly;
    } on FormatException {
      return AdvanceWarningTimingSettings.advanceOnly;
    }
  }

  @override
  Future<void> saveAdvanceWarningTimings(
    AdvanceWarningTimingSettings settings,
  ) async {
    if (!settings.hasAny) {
      throw ArgumentError.value(
        settings,
        'settings',
        'Select a warning timing',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _advanceWarningTimingsKey,
      jsonEncode(<String, bool>{
        'postBattle': settings.postBattle,
        'afterAdvance': settings.afterAdvance,
      }),
    );
  }

  @override
  Future<BattleStatusEffectSettings> loadBattleStatusEffects() async {
    final prefs = await SharedPreferences.getInstance();
    final legacyVibrationEnabled = prefs.getBool(_damageVibrationKey) ?? true;
    return BattleStatusEffectSettings(
      enabled: prefs.getBool(_statusEffectsEnabledKey) ?? true,
      displayScope: _enumByName(
        BattleEffectDisplayScope.values,
        prefs.getString(_displayScopeKey),
        BattleEffectDisplayScope.all,
      ),
      damagePulseFilter: _enumByName(
        DamagePulseFilter.values,
        prefs.getString(_damagePulseFilterKey),
        DamagePulseFilter.all,
      ),
      damageVibrationFilter: _enumByName(
        DamageVibrationFilter.values,
        prefs.getString(_damageVibrationFilterKey),
        legacyVibrationEnabled
            ? DamageVibrationFilter.all
            : DamageVibrationFilter.off,
      ),
      moraleSparkleMode: _enumByName(
        MoraleSparkleMode.values,
        prefs.getString(_moraleSparkleModeKey),
        (prefs.getBool(_moraleSparkleEnabledKey) ?? true)
            ? MoraleSparkleMode.blinking
            : MoraleSparkleMode.off,
      ),
    );
  }

  @override
  Future<void> saveBattleStatusEffects(
    BattleStatusEffectSettings settings,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait(<Future<bool>>[
      prefs.setBool(_statusEffectsEnabledKey, settings.enabled),
      prefs.setString(_displayScopeKey, settings.displayScope.name),
      prefs.setString(_damagePulseFilterKey, settings.damagePulseFilter.name),
      prefs.setString(
        _damageVibrationFilterKey,
        settings.damageVibrationFilter.name,
      ),
      prefs.setString(_moraleSparkleModeKey, settings.moraleSparkleMode.name),
    ]);
  }
}

class MemorySafetySettingsStore implements SafetySettingsStore {
  MemorySafetySettingsStore({
    BattleStatusEffectSettings battleStatusEffects =
        const BattleStatusEffectSettings(),
  }) : _battleStatusEffects = battleStatusEffects;

  BattleWarningMode _mode = BattleWarningMode.confirm;
  AdvanceWarningDisplayMode _advanceWarningDisplayMode =
      AdvanceWarningDisplayMode.alwaysConfirm;
  AdvanceWarningTimingSettings _advanceWarningTimings =
      AdvanceWarningTimingSettings.advanceOnly;
  BattleStatusEffectSettings _battleStatusEffects;

  @override
  Future<BattleWarningMode> loadWarningMode() async => _mode;

  @override
  Future<void> saveWarningMode(BattleWarningMode mode) async {
    _mode = mode;
  }

  @override
  Future<AdvanceWarningDisplayMode> loadAdvanceWarningDisplayMode() async =>
      _advanceWarningDisplayMode;

  @override
  Future<void> saveAdvanceWarningDisplayMode(
    AdvanceWarningDisplayMode mode,
  ) async {
    _advanceWarningDisplayMode = mode;
  }

  @override
  Future<AdvanceWarningTimingSettings> loadAdvanceWarningTimings() async =>
      _advanceWarningTimings;

  @override
  Future<void> saveAdvanceWarningTimings(
    AdvanceWarningTimingSettings settings,
  ) async {
    if (!settings.hasAny) {
      throw ArgumentError.value(
        settings,
        'settings',
        'Select a warning timing',
      );
    }
    _advanceWarningTimings = settings;
  }

  @override
  Future<BattleStatusEffectSettings> loadBattleStatusEffects() async =>
      _battleStatusEffects;

  @override
  Future<void> saveBattleStatusEffects(
    BattleStatusEffectSettings settings,
  ) async {
    _battleStatusEffects = settings;
  }
}

T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
  for (final value in values) {
    if (value.name == name) {
      return value;
    }
  }
  return fallback;
}
