import 'package:flutter/foundation.dart';

import 'battle_status_effect_settings.dart';
import 'safety_settings_store.dart';

class SafetySettingsController extends ChangeNotifier {
  SafetySettingsController._(this._store);

  final SafetySettingsStore _store;
  late BattleWarningMode _battleWarningMode;
  late AdvanceWarningDisplayMode _advanceWarningDisplayMode;
  late AdvanceWarningTimingSettings _advanceWarningTimings;
  late BattleStatusEffectSettings _battleStatusEffects;

  BattleWarningMode get battleWarningMode => _battleWarningMode;
  AdvanceWarningDisplayMode get advanceWarningDisplayMode =>
      _advanceWarningDisplayMode;
  AdvanceWarningTimingSettings get advanceWarningTimings =>
      _advanceWarningTimings;
  BattleStatusEffectSettings get battleStatusEffects => _battleStatusEffects;

  static Future<SafetySettingsController> load(
    SafetySettingsStore store,
  ) async {
    final controller = SafetySettingsController._(store);
    await controller.loadSettings();
    return controller;
  }

  Future<void> loadSettings() async {
    _battleWarningMode = await _store.loadWarningMode();
    _advanceWarningDisplayMode = await _store.loadAdvanceWarningDisplayMode();
    final timings = await _store.loadAdvanceWarningTimings();
    _advanceWarningTimings = timings.hasAny
        ? timings
        : AdvanceWarningTimingSettings.advanceOnly;
    _battleStatusEffects = await _store.loadBattleStatusEffects();
    notifyListeners();
  }

  Future<void> setBattleWarningMode(BattleWarningMode mode) async {
    if (_battleWarningMode == mode) return;
    _battleWarningMode = mode;
    notifyListeners();
    await _store.saveWarningMode(mode);
  }

  Future<void> setAdvanceWarningDisplayMode(
    AdvanceWarningDisplayMode mode,
  ) async {
    if (_advanceWarningDisplayMode == mode) return;
    _advanceWarningDisplayMode = mode;
    notifyListeners();
    await _store.saveAdvanceWarningDisplayMode(mode);
  }

  Future<void> setAdvanceWarningTimings(
    AdvanceWarningTimingSettings settings,
  ) async {
    if (!settings.hasAny) {
      throw ArgumentError.value(
        settings,
        'settings',
        'Select a warning timing',
      );
    }
    if (_advanceWarningTimings == settings) return;
    _advanceWarningTimings = settings;
    notifyListeners();
    await _store.saveAdvanceWarningTimings(settings);
  }

  Future<void> setBattleStatusEffects(
    BattleStatusEffectSettings settings,
  ) async {
    if (_battleStatusEffects == settings) return;
    _battleStatusEffects = settings;
    notifyListeners();
    await _store.saveBattleStatusEffects(settings);
  }

  Future<void> setBattleStatusEffectsEnabled(bool enabled) =>
      setBattleStatusEffects(_battleStatusEffects.copyWith(enabled: enabled));

  Future<void> setBattleEffectDisplayScope(BattleEffectDisplayScope scope) =>
      setBattleStatusEffects(
        _battleStatusEffects.copyWith(displayScope: scope),
      );

  Future<void> setDamagePulseFilter(DamagePulseFilter filter) =>
      setBattleStatusEffects(
        _battleStatusEffects.copyWith(damagePulseFilter: filter),
      );

  Future<void> setDamageVibrationFilter(DamageVibrationFilter filter) =>
      setBattleStatusEffects(
        _battleStatusEffects.copyWith(damageVibrationFilter: filter),
      );

  Future<void> setMoraleSparkleMode(MoraleSparkleMode mode) =>
      setBattleStatusEffects(
        _battleStatusEffects.copyWith(moraleSparkleMode: mode),
      );
}
