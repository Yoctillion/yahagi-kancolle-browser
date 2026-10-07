import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ScreenAwakeStore {
  Future<bool?> readEnabled();

  Future<void> writeEnabled(bool enabled);
}

final class SharedPreferencesScreenAwakeStore implements ScreenAwakeStore {
  static const _key = 'screen_awake_enabled';

  @override
  Future<bool?> readEnabled() async {
    return (await SharedPreferences.getInstance()).getBool(_key);
  }

  @override
  Future<void> writeEnabled(bool enabled) async {
    final saved = await (await SharedPreferences.getInstance()).setBool(
      _key,
      enabled,
    );
    if (!saved) {
      throw StateError('screen awake preference was not saved');
    }
  }
}

abstract interface class ScreenAwakePort {
  Future<void> setEnabled(bool enabled);

  Future<bool> isEnabled();
}

final class MethodChannelScreenAwakePort implements ScreenAwakePort {
  const MethodChannelScreenAwakePort([
    this.channel = const MethodChannel(
      'app.yahagi.kancollebrowser/screen_awake',
    ),
  ]);

  final MethodChannel channel;

  @override
  Future<bool> isEnabled() async {
    return await channel.invokeMethod<bool>('isEnabled') ?? false;
  }

  @override
  Future<void> setEnabled(bool enabled) {
    return channel.invokeMethod<void>('setEnabled', <String, Object?>{
      'enabled': enabled,
    });
  }
}

final class ScreenAwakeController extends ChangeNotifier {
  ScreenAwakeController._(this._store, this._enabled)
    : _savedEnabled = _enabled;

  static Future<ScreenAwakeController> load(ScreenAwakeStore store) async {
    return ScreenAwakeController._(store, await store.readEnabled() ?? false);
  }

  final ScreenAwakeStore _store;
  ScreenAwakePort? _port;
  bool _enabled;
  bool _foreground = true;
  bool? _lastApplied;
  String? _errorMessage;
  bool _savedEnabled;
  bool _disposed = false;
  int _portGeneration = 0;
  int _settingsRevision = 0;
  Future<void> _nativeTail = Future<void>.value();
  Future<void> _settingsTail = Future<void>.value();

  bool get enabled => _enabled;
  String? get errorMessage => _errorMessage;
  bool get _effectiveEnabled => _enabled && _foreground;

  Future<void> attachPort(ScreenAwakePort port) async {
    if (_disposed) return;
    _port = port;
    final generation = ++_portGeneration;
    _lastApplied = null;
    try {
      await _apply();
    } catch (error) {
      if (_disposed || generation != _portGeneration) return;
      _errorMessage = '屏幕常亮不可用：$error';
      _notify();
    }
  }

  Future<void> setEnabled(bool enabled) async {
    if (_disposed || _enabled == enabled) {
      return;
    }
    final revision = ++_settingsRevision;
    _enabled = enabled;
    _errorMessage = null;
    _notify();
    final result = _settingsTail.then((_) async {
      if (_disposed || revision != _settingsRevision) return;
      final previous = _savedEnabled;
      try {
        await _store.writeEnabled(enabled);
        _savedEnabled = enabled;
        await _apply();
      } catch (error) {
        if (_disposed || revision != _settingsRevision) return;
        _enabled = previous;
        try {
          await _store.writeEnabled(previous);
          _savedEnabled = previous;
        } catch (_) {}
        try {
          await _apply();
        } catch (_) {}
        if (_disposed || revision != _settingsRevision) return;
        _errorMessage = '屏幕常亮设置失败：$error';
        _notify();
      }
    });
    _settingsTail = result.catchError((Object _) {});
    await result;
  }

  Future<void> handleLifecycleState(AppLifecycleState state) async {
    if (_disposed) return;
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground == foreground) {
      return;
    }
    _foreground = foreground;
    try {
      await _apply();
    } catch (error) {
      _errorMessage = '屏幕常亮同步失败：$error';
      _notify();
    }
  }

  Future<void> _apply() {
    final result = _nativeTail.then((_) => _reconcileNative());
    _nativeTail = result.catchError((Object _) {});
    return result;
  }

  Future<void> _reconcileNative() async {
    while (!_disposed) {
      final port = _port;
      final generation = _portGeneration;
      final target = _effectiveEnabled;
      if (port == null || _lastApplied == target) return;
      try {
        await port.setEnabled(target);
        if (_disposed || generation != _portGeneration) continue;
        final actual = await port.isEnabled();
        if (_disposed || generation != _portGeneration) continue;
        if (actual != target) {
          throw StateError('native window flag did not match requested state');
        }
        _lastApplied = actual;
      } catch (_) {
        if (_disposed || generation != _portGeneration) continue;
        _lastApplied = null;
        rethrow;
      }
      _errorMessage = null;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_portGeneration;
    _port = null;
    super.dispose();
  }
}
