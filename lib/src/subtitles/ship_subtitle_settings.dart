import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ship_subtitle_language.dart';

enum ShipSubtitleFontSize {
  small,
  medium,
  large;

  String get wireName => name;
}

/// Saved subtitle choices. Positions are relative to the visible game frame.
final class ShipSubtitleSettingsController extends ChangeNotifier {
  ShipSubtitleSettingsController._(this._preferences, this._settings);

  static const preferenceKey = 'game.shipSubtitles';
  final SharedPreferences _preferences;
  _SubtitleSettings _settings;
  Future<void> _pending = Future<void>.value();
  int _pendingCount = 0;
  bool _saveFailed = false;
  bool _disposed = false;

  bool get enabled => _settings.enabled;
  ShipSubtitleFontSize get fontSize => _settings.fontSize;
  ShipSubtitleLanguage get language => _settings.language;
  double get x => _settings.x;
  double get y => _settings.y;
  bool get saving => _pendingCount > 0;
  bool get saveFailed => _saveFailed;

  static Future<ShipSubtitleSettingsController> load({
    SharedPreferences? preferences,
  }) async {
    final store = preferences ?? await SharedPreferences.getInstance();
    final raw = store.get(preferenceKey);
    var settings = const _SubtitleSettings();
    if (raw is String) {
      try {
        final value = jsonDecode(raw);
        if (value is Map<String, dynamic>) {
          settings = _SubtitleSettings(
            enabled: value['enabled'] is bool
                ? value['enabled'] as bool
                : false,
            fontSize: ShipSubtitleFontSize.values.firstWhere(
              (size) => size.wireName == value['fontSize'],
              orElse: () => ShipSubtitleFontSize.medium,
            ),
            language: ShipSubtitleLanguage.fromStoredValue(value['language']),
            x: _readPosition(value['x'], .5),
            y: _readPosition(value['y'], .9),
          );
        }
      } on FormatException {
        // Retain safe defaults if an older or interrupted write is malformed.
      }
    }
    return ShipSubtitleSettingsController._(store, settings);
  }

  static double _readPosition(Object? value, double fallback) =>
      value is num && value.isFinite
      ? value.toDouble().clamp(0.0, 1.0)
      : fallback;

  Future<void> setEnabled(bool enabled) =>
      _save((current) => current.copyWith(enabled: enabled));

  Future<void> setFontSize(ShipSubtitleFontSize fontSize) =>
      _save((current) => current.copyWith(fontSize: fontSize));

  Future<void> setLanguage(ShipSubtitleLanguage language) =>
      _save((current) => current.copyWith(language: language));

  Future<void> setPosition(double x, double y) {
    if (!x.isFinite || !y.isFinite) return Future<void>.value();
    return _save(
      (current) => current.copyWith(x: x.clamp(0.0, 1.0), y: y.clamp(0.0, 1.0)),
    );
  }

  Future<void> _save(
    _SubtitleSettings Function(_SubtitleSettings current) update,
  ) {
    if (_disposed) return Future<void>.value();
    _pendingCount++;
    notifyListeners();
    // Serializing a complete snapshot keeps the two position coordinates
    // together and preserves the final drag when platform writes are pending.
    final operation = _pending.then((_) async {
      if (_disposed) return;
      final previous = _settings;
      final next = update(previous);
      if (next.encode() == previous.encode()) return;
      _saveFailed = false;
      final previousCache = _preferences.get(preferenceKey);
      try {
        if (!await _preferences.setString(preferenceKey, next.encode())) {
          throw StateError('Subtitle settings were not saved');
        }
        _settings = next;
      } catch (_) {
        // SharedPreferences changes its Dart cache before platform completion.
        // Restore that cache so a newly created controller sees saved choices.
        try {
          if (previousCache is String) {
            await _preferences.setString(preferenceKey, previousCache);
          } else {
            await _preferences.remove(preferenceKey);
          }
        } catch (_) {}
        _saveFailed = true;
      }
    });
    _pending = operation.whenComplete(() {
      _pendingCount--;
      if (!_disposed) notifyListeners();
    });
    return _pending;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final class _SubtitleSettings {
  const _SubtitleSettings({
    this.enabled = false,
    this.fontSize = ShipSubtitleFontSize.medium,
    this.language = ShipSubtitleLanguage.simplifiedChinese,
    this.x = .5,
    this.y = .9,
  });

  final bool enabled;
  final ShipSubtitleFontSize fontSize;
  final ShipSubtitleLanguage language;
  final double x;
  final double y;

  _SubtitleSettings copyWith({
    bool? enabled,
    ShipSubtitleFontSize? fontSize,
    ShipSubtitleLanguage? language,
    double? x,
    double? y,
  }) => _SubtitleSettings(
    enabled: enabled ?? this.enabled,
    fontSize: fontSize ?? this.fontSize,
    language: language ?? this.language,
    x: x ?? this.x,
    y: y ?? this.y,
  );

  String encode() => jsonEncode({
    'enabled': enabled,
    'fontSize': fontSize.wireName,
    'language': language.code,
    'x': x,
    'y': y,
  });
}
