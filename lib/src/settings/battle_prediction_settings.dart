import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum EnemyPreviewPosition { above, below }

abstract interface class BattlePredictionSettingsStore {
  Future<void> initialize();

  Future<bool> loadEnemyPortraitsEnabled();

  Future<void> saveEnemyPortraitsEnabled(bool enabled);

  Future<bool> loadLastFormationHintEnabled();

  Future<void> saveLastFormationHintEnabled(bool enabled);

  Future<EnemyPreviewPosition> loadEnemyPreviewPosition();

  Future<void> saveEnemyPreviewPosition(EnemyPreviewPosition position);
}

final class SharedPreferencesBattlePredictionSettingsStore
    implements BattlePredictionSettingsStore {
  static const String _legacyPredictionMethodKey = 'battle.predictionMethod';
  static const String _enemyPortraitsKey =
      'battle.enemyPreviewPortraitsEnabled';
  static const String _lastFormationHintKey = 'battle.lastFormationHintEnabled';
  static const String _enemyPreviewPositionKey = 'battle.enemyPreviewPosition';

  @override
  Future<void> initialize() async {
    await (await SharedPreferences.getInstance()).remove(
      _legacyPredictionMethodKey,
    );
  }

  @override
  Future<bool> loadEnemyPortraitsEnabled() async {
    return (await SharedPreferences.getInstance()).getBool(
          _enemyPortraitsKey,
        ) ??
        true;
  }

  @override
  Future<void> saveEnemyPortraitsEnabled(bool enabled) async {
    final saved = await (await SharedPreferences.getInstance()).setBool(
      _enemyPortraitsKey,
      enabled,
    );
    if (!saved) throw StateError('enemy portrait setting was not saved');
  }

  @override
  Future<bool> loadLastFormationHintEnabled() async {
    return (await SharedPreferences.getInstance()).getBool(
          _lastFormationHintKey,
        ) ??
        true;
  }

  @override
  Future<void> saveLastFormationHintEnabled(bool enabled) async {
    final saved = await (await SharedPreferences.getInstance()).setBool(
      _lastFormationHintKey,
      enabled,
    );
    if (!saved) throw StateError('last formation hint setting was not saved');
  }

  @override
  Future<EnemyPreviewPosition> loadEnemyPreviewPosition() async {
    final value = (await SharedPreferences.getInstance()).getString(
      _enemyPreviewPositionKey,
    );
    return EnemyPreviewPosition.values.firstWhere(
      (position) => position.name == value,
      orElse: () => EnemyPreviewPosition.above,
    );
  }

  @override
  Future<void> saveEnemyPreviewPosition(EnemyPreviewPosition position) async {
    final saved = await (await SharedPreferences.getInstance()).setString(
      _enemyPreviewPositionKey,
      position.name,
    );
    if (!saved) throw StateError('enemy preview position was not saved');
  }
}

final class MemoryBattlePredictionSettingsStore
    implements BattlePredictionSettingsStore {
  MemoryBattlePredictionSettingsStore([
    this._enemyPortraitsEnabled = true,
    this._lastFormationHintEnabled = true,
    this._enemyPreviewPosition = EnemyPreviewPosition.above,
  ]);

  bool _enemyPortraitsEnabled;
  bool _lastFormationHintEnabled;
  EnemyPreviewPosition _enemyPreviewPosition;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> loadEnemyPortraitsEnabled() async => _enemyPortraitsEnabled;

  @override
  Future<void> saveEnemyPortraitsEnabled(bool enabled) async {
    _enemyPortraitsEnabled = enabled;
  }

  @override
  Future<bool> loadLastFormationHintEnabled() async =>
      _lastFormationHintEnabled;

  @override
  Future<void> saveLastFormationHintEnabled(bool enabled) async {
    _lastFormationHintEnabled = enabled;
  }

  @override
  Future<EnemyPreviewPosition> loadEnemyPreviewPosition() async =>
      _enemyPreviewPosition;

  @override
  Future<void> saveEnemyPreviewPosition(EnemyPreviewPosition position) async {
    _enemyPreviewPosition = position;
  }
}

final class BattlePredictionSettingsController extends ChangeNotifier {
  BattlePredictionSettingsController._(this._store);

  final BattlePredictionSettingsStore _store;
  bool _enemyPortraitsEnabled = true;
  bool _lastFormationHintEnabled = true;
  EnemyPreviewPosition _enemyPreviewPosition = EnemyPreviewPosition.above;

  bool get enemyPortraitsEnabled => _enemyPortraitsEnabled;
  bool get lastFormationHintEnabled => _lastFormationHintEnabled;
  EnemyPreviewPosition get enemyPreviewPosition => _enemyPreviewPosition;

  static Future<BattlePredictionSettingsController> load(
    BattlePredictionSettingsStore store,
  ) async {
    final controller = BattlePredictionSettingsController._(store);
    try {
      await store.initialize();
    } catch (_) {
      // A stale engine preference must never block the remaining settings.
    }
    controller._enemyPortraitsEnabled = await store.loadEnemyPortraitsEnabled();
    controller._lastFormationHintEnabled = await store
        .loadLastFormationHintEnabled();
    controller._enemyPreviewPosition = await store.loadEnemyPreviewPosition();
    return controller;
  }

  Future<void> setEnemyPortraitsEnabled(bool enabled) async {
    if (_enemyPortraitsEnabled == enabled) return;
    await _store.saveEnemyPortraitsEnabled(enabled);
    _enemyPortraitsEnabled = enabled;
    notifyListeners();
  }

  Future<void> setLastFormationHintEnabled(bool enabled) async {
    if (_lastFormationHintEnabled == enabled) return;
    await _store.saveLastFormationHintEnabled(enabled);
    _lastFormationHintEnabled = enabled;
    notifyListeners();
  }

  Future<void> setEnemyPreviewPosition(EnemyPreviewPosition position) async {
    if (_enemyPreviewPosition == position) return;
    await _store.saveEnemyPreviewPosition(position);
    _enemyPreviewPosition = position;
    notifyListeners();
  }
}
