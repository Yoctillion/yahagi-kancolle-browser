import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Confirmation before a system Back action moves the app to the background.
final class AppExitSettingsController extends ChangeNotifier {
  AppExitSettingsController._(this._preferences, this._enabled);

  static const preferenceKey = 'app.confirmBeforeExit';
  final SharedPreferences _preferences;
  bool _enabled;
  bool _saving = false;
  bool _disposed = false;
  bool _saveFailed = false;

  bool get enabled => _enabled;
  bool get saving => _saving;
  bool get saveFailed => _saveFailed;

  static Future<AppExitSettingsController> load() async {
    final preferences = await SharedPreferences.getInstance();
    return AppExitSettingsController._(
      preferences,
      preferences.getBool(preferenceKey) ?? true,
    );
  }

  Future<void> setEnabled(bool enabled) async {
    if (_disposed || _saving || enabled == _enabled) return;
    _saving = true;
    _saveFailed = false;
    notifyListeners();
    try {
      if (!await _preferences.setBool(preferenceKey, enabled)) {
        throw StateError('Exit confirmation preference was not saved');
      }
      _enabled = enabled;
    } catch (_) {
      // SharedPreferences updates its Dart cache before awaiting the platform.
      // Restore the confirmed value in that cache if the platform write fails.
      try {
        await _preferences.setBool(preferenceKey, _enabled);
      } catch (_) {}
      _saveFailed = true;
    } finally {
      _saving = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
