import 'dart:async';

import 'package:flutter/foundation.dart';

import 'game_resource_cache_channel.dart';
import 'game_resource_cache_store.dart';

String formatCacheCompleteness(int cachedBytes, [int? targetBytes]) {
  final cachedGb = cachedBytes / 1000000000;
  return '${cachedGb.toStringAsFixed(2)} GB';
}

final class GameResourceCacheController extends ChangeNotifier {
  GameResourceCacheController({
    GameResourceCacheStore? store,
    GameResourceCachePort? port,
  }) : _store = store ?? SharedPreferencesGameResourceCacheStore(),
       _port = port ?? const MethodChannelGameResourceCachePort();

  final GameResourceCacheStore _store;
  final GameResourceCachePort _port;
  GameResourceCacheMode _mode = GameResourceCacheMode.temporary;
  GameResourceCacheStatus _status = GameResourceCacheStatus.empty;
  bool _initialized = false;
  bool _manifestError = false;
  bool _busy = false;
  int _busyCount = 0;
  Future<void> _modeChangeTail = Future<void>.value();
  bool _pageVisible = false;
  Future<void>? _refreshFuture;
  bool _refreshPending = false;
  Timer? _timer;
  bool _disposed = false;
  int _modeEpoch = 0;
  Future<void>? _initializationFuture;

  GameResourceCacheMode get mode => _mode;
  GameResourceCacheStatus get status => _status;
  bool get initialized => _initialized;
  bool get manifestError => _manifestError;
  bool get busy => _busy;
  String get completenessLine =>
      formatCacheCompleteness(_status.cachedBytes, _status.targetBytes);

  Future<void> initialize({bool loadStatus = true}) {
    if (_disposed) return Future<void>.value();
    final active = _initializationFuture;
    if (active != null) return active;
    final pending = _modeChangeTail.then((_) => _initialize(loadStatus));
    _initializationFuture = pending;
    _modeChangeTail = pending;
    return pending;
  }

  Future<void> _initialize(bool loadStatus) async {
    try {
      final savedMode = await _store.load();
      if (_disposed) return;
      _mode = savedMode;
      final configured = await _port.configure(_mode);
      if (_disposed) return;
      if (!configured) {
        // A saved off preference must never temporarily enable interception.
        if (savedMode == GameResourceCacheMode.none) {
          throw StateError('Local cache configuration failed');
        }
        _mode = GameResourceCacheMode.temporary;
        final fallbackConfigured = await _port.configure(_mode);
        if (_disposed) return;
        if (!fallbackConfigured) {
          throw StateError('Local cache configuration failed');
        }
        await _store.save(_mode);
        if (_disposed) return;
      }
      _initialized = true;
      if (loadStatus) await refresh();
      if (_disposed) return;
      _updatePolling();
    } catch (_) {
      // Cache I/O is optional and must not block the browser's startup.
      if (_disposed) return;
      _status = GameResourceCacheStatus.empty;
      _initialized = false;
    }
    _notify();
  }

  Future<bool> setMode(GameResourceCacheMode value) {
    if (_disposed) return Future<bool>.value(false);
    _beginBusy();
    final pending = _modeChangeTail.then((_) => _applyMode(value));
    _modeChangeTail = pending.then<void>((_) {});
    return pending.whenComplete(_endBusy);
  }

  Future<bool> _applyMode(GameResourceCacheMode value) async {
    if (_disposed) return false;
    if (_mode == value && _initialized) return true;
    _modeEpoch++;
    final previous = _mode;
    try {
      final configured = await _port.configure(value);
      if (_disposed) return false;
      if (!configured) {
        await _restoreNativeMode(previous);
        return false;
      }
      await _store.save(value);
      if (_disposed) return false;
      _mode = value;
      _initialized = true;
      try {
        await refresh();
      } catch (_) {
        _notify();
      }
      return true;
    } catch (_) {
      if (_mode == previous) await _restoreNativeMode(previous);
      return false;
    }
  }

  Future<void> _restoreNativeMode(GameResourceCacheMode previous) async {
    if (_disposed) return;
    try {
      if (!await _port.configure(previous)) {
        _initialized = false;
        _notify();
      }
    } catch (_) {
      _initialized = false;
      _notify();
    }
  }

  Future<bool> submitManifest(
    GameResourceManifest manifest, {
    bool Function()? shouldContinue,
  }) async {
    if (_disposed) return false;
    final submitted = await _port.setManifest(
      manifest,
      shouldContinue: () => !_disposed && (shouldContinue?.call() ?? true),
    );
    if (_disposed || !submitted) return false;
    if (_manifestError) {
      _manifestError = false;
      _notify();
    }
    await refresh();
    return true;
  }

  void reportManifestFailure() {
    if (_disposed || _manifestError) return;
    _manifestError = true;
    _notify();
  }

  Future<bool> startDownload({bool allowMetered = false}) =>
      _action(() => _port.startDownload(allowMetered: allowMetered));
  Future<bool> pauseDownload() => _action(_port.pauseDownload);
  Future<bool> repair({bool allowMetered = false}) =>
      _action(() => _port.repair(allowMetered: allowMetered));
  Future<bool> clear() => _action(_port.clear);

  Future<GameResourceCacheStatus> checkIntegrity() async {
    if (_disposed) return _status;
    final epoch = _modeEpoch;
    _beginBusy();
    try {
      final checked = await _port.checkIntegrity();
      if (!_disposed && epoch == _modeEpoch) _status = checked;
      return _status;
    } finally {
      _endBusy();
      _updatePolling();
    }
  }

  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    final active = _refreshFuture;
    if (active != null) {
      _refreshPending = true;
      return active;
    }
    late final Future<void> future;
    future = _refreshLoop().whenComplete(() {
      if (identical(_refreshFuture, future)) _refreshFuture = null;
    });
    _refreshFuture = future;
    return future;
  }

  Future<void> _refreshLoop() async {
    do {
      _refreshPending = false;
      final epoch = _modeEpoch;
      try {
        final status = await _port.status();
        if (_disposed) return;
        if (epoch != _modeEpoch) continue;
        _status = status;
      } catch (_) {
        // A deferred startup refresh or polling failure keeps the usable mode.
        if (_disposed) return;
      }
      _updatePolling();
      _notify();
    } while (!_disposed && _refreshPending);
  }

  void setPageVisible(bool visible) {
    if (_disposed) return;
    _pageVisible = visible;
    _updatePolling();
  }

  Future<bool> _action(Future<bool> Function() action) async {
    if (_disposed) return false;
    _beginBusy();
    try {
      final result = await action();
      if (_disposed) return false;
      await refresh();
      return result;
    } catch (_) {
      try {
        await refresh();
      } catch (_) {
        // The operation failed; keep the last usable status for the UI.
      }
      return false;
    } finally {
      _endBusy();
      _updatePolling();
    }
  }

  void _beginBusy() {
    _busyCount++;
    _busy = true;
    _notify();
  }

  void _endBusy() {
    _busyCount--;
    _busy = _busyCount > 0;
    _notify();
  }

  void _updatePolling() {
    if (_disposed) return;
    final shouldPoll = _pageVisible || _status.isRunning;
    if (shouldPoll && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
    } else if (!shouldPoll) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _modeEpoch++;
    _refreshPending = false;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
