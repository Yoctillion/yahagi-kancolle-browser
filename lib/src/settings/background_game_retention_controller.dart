import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../browser/game_toolbar_controller.dart';

abstract interface class BackgroundGameRetentionStore {
  Future<bool?> readEnabled();

  Future<void> writeEnabled(bool enabled);
}

final class SharedPreferencesBackgroundGameRetentionStore
    implements BackgroundGameRetentionStore {
  static const _key = 'background_game_retention_enabled';

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
      throw StateError('background game retention preference was not saved');
    }
  }
}

abstract interface class BackgroundGameRetentionPort {
  Future<void> setRetaining(bool retaining);
}

final class MethodChannelBackgroundGameRetentionPort
    implements BackgroundGameRetentionPort {
  const MethodChannelBackgroundGameRetentionPort([
    this.channel = const MethodChannel(
      'app.yahagi.kancollebrowser/background_game_retention',
    ),
  ]);

  final MethodChannel channel;

  @override
  Future<void> setRetaining(bool retaining) {
    return channel.invokeMethod<void>('setRetaining', <String, Object?>{
      'retaining': retaining,
    });
  }
}

final class BackgroundGameRetentionController extends ChangeNotifier {
  BackgroundGameRetentionController._(this._store, this._enabled)
    : _persistedEnabled = _enabled;

  static Future<BackgroundGameRetentionController> load(
    BackgroundGameRetentionStore store,
  ) async {
    return BackgroundGameRetentionController._(
      store,
      await store.readEnabled() ?? true,
    );
  }

  final BackgroundGameRetentionStore _store;
  bool _enabled;
  bool _persistedEnabled;
  bool _disposed = false;
  int _settingRevision = 0;
  Future<void> _writes = Future<void>.value();
  String? _settingErrorMessage;
  String? _syncErrorMessage;

  bool get enabled => _enabled;
  String? get errorMessage => _settingErrorMessage ?? _syncErrorMessage;

  void reportSyncError(String? message) {
    if (_disposed || _syncErrorMessage == message) return;
    _syncErrorMessage = message;
    notifyListeners();
  }

  Future<void> setEnabled(bool enabled) {
    if (_disposed) return Future<void>.value();
    if (_enabled == enabled) return _writes;
    final revision = ++_settingRevision;
    _enabled = enabled;
    _settingErrorMessage = null;
    notifyListeners();
    return _writes = _writes.then((_) async {
      try {
        await _store.writeEnabled(enabled);
        _persistedEnabled = enabled;
      } catch (error) {
        if (_disposed || revision != _settingRevision) return;
        _enabled = _persistedEnabled;
        _settingErrorMessage = '后台保活设置失败：$error';
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final class BackgroundGameRetentionCoordinator {
  BackgroundGameRetentionCoordinator({
    required this.controller,
    required this.toolbarController,
    required this.port,
    this.onFailure,
    this.operationTimeout = const Duration(seconds: 10),
    this.retryDelay = const Duration(milliseconds: 500),
  }) : assert(operationTimeout > Duration.zero),
       assert(retryDelay >= Duration.zero) {
    controller.addListener(_handleInputChanged);
    toolbarController.addListener(_handleInputChanged);
    _enqueueCurrentTarget();
  }

  final BackgroundGameRetentionController controller;
  final GameToolbarController toolbarController;
  final BackgroundGameRetentionPort port;
  final void Function(Object error)? onFailure;
  final Duration operationTimeout;
  final Duration retryDelay;

  static const _maxAttempts = 3;

  bool _detached = false;
  bool _disposed = false;
  bool? _pendingTarget;
  bool? _lastRequestedTarget;
  bool? _lastApplied;
  Future<void>? _drainFuture;
  Completer<void>? _waitInvalidator;
  int _requestRevision = 0;
  String? _errorMessage;

  String? get errorMessage => _errorMessage;

  Future<void> handleLifecycleState(AppLifecycleState state) async {
    if (_disposed) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _detached = false;
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        break;
      case AppLifecycleState.detached:
        _detached = true;
      case AppLifecycleState.inactive:
        return;
    }
    _enqueueCurrentTarget();
  }

  Future<void> settle() => _drainFuture ?? Future<void>.value();

  void dispose() {
    if (_disposed) return;
    controller.removeListener(_handleInputChanged);
    toolbarController.removeListener(_handleInputChanged);
    _detached = true;
    _disposed = true;
    _enqueueCurrentTarget();
  }

  void _handleInputChanged() {
    if (_disposed) return;
    if (_target == _lastRequestedTarget) return;
    _enqueueCurrentTarget();
  }

  bool get _target =>
      !_detached &&
      controller.enabled &&
      toolbarController.stage == GameSurfaceStage.game;

  void _enqueueCurrentTarget({bool force = false}) {
    _pendingTarget = _target;
    if (force || _pendingTarget != _lastRequestedTarget) {
      _requestRevision++;
      _waitInvalidator?.complete();
      _waitInvalidator = null;
    }
    _lastRequestedTarget = _pendingTarget;
    if (_drainFuture != null) return;
    final drain = _drain();
    _drainFuture = drain.whenComplete(() {
      _drainFuture = null;
      if (_pendingTarget != null) _enqueueCurrentTarget();
    });
  }

  Future<void> _drain() async {
    while (true) {
      final target = _pendingTarget;
      if (target == null) return;
      _pendingTarget = null;
      if (_lastApplied == target) continue;
      final revision = _requestRevision;
      Object? lastError;
      for (var attempt = 0; attempt < _maxAttempts; attempt++) {
        if (revision != _requestRevision) break;
        if (_lastApplied == target) {
          lastError = null;
          break;
        }
        try {
          if (!await _applyTarget(target, revision)) break;
          if (revision == _requestRevision) {
            _recordSuccess(target);
            lastError = null;
          }
          break;
        } catch (error) {
          _lastApplied = null;
          lastError = error;
        }
        if (revision != _requestRevision) break;
        if (attempt + 1 < _maxAttempts) await _waitBeforeRetry();
      }
      if (lastError != null && revision == _requestRevision) {
        _recordFailure(lastError);
      }
    }
  }

  Future<bool> _applyTarget(bool target, int revision) async {
    final invalidator = Completer<void>();
    _waitInvalidator = invalidator;
    // The service may apply this command before its acknowledgement arrives.
    _lastApplied = null;
    final operation = Future<void>.sync(() => port.setRetaining(target));
    final weakCoordinator = WeakReference(this);
    var retired = false;
    void reconcileStaleCompletion() {
      final coordinator = weakCoordinator.target;
      if (coordinator == null ||
          (!retired && revision == coordinator._requestRevision)) {
        return;
      }
      // A service may apply a command before either a success or error reply.
      // An obsolete opposite command must not undo the newest target.
      if (target != coordinator._target) {
        coordinator._lastApplied = null;
        coordinator._enqueueCurrentTarget(force: true);
      }
      // A stale same-target receipt is not a current acknowledgement: a
      // newer opposite command may already have applied before its reply.
      // Leave the current attempt/retry responsible for confirming success.
    }

    unawaited(
      operation.then<void>(
        (_) => reconcileStaleCompletion(),
        onError: (Object _) => reconcileStaleCompletion(),
      ),
    );
    try {
      final completed = await Future.any<bool>(<Future<bool>>[
        operation.then((_) => true),
        invalidator.future.then((_) => false),
      ]).timeout(operationTimeout);
      retired = !completed;
      return completed;
    } on TimeoutException {
      retired = true;
      rethrow;
    } finally {
      if (identical(_waitInvalidator, invalidator)) _waitInvalidator = null;
    }
  }

  Future<void> _waitBeforeRetry() async {
    final invalidator = Completer<void>();
    final elapsed = Completer<void>();
    _waitInvalidator = invalidator;
    final timer = Timer(retryDelay, elapsed.complete);
    try {
      await Future.any<void>(<Future<void>>[
        elapsed.future,
        invalidator.future,
      ]);
    } finally {
      timer.cancel();
      if (identical(_waitInvalidator, invalidator)) _waitInvalidator = null;
    }
  }

  void _recordSuccess(bool target) {
    _lastApplied = target;
    _errorMessage = null;
    if (!_disposed) controller.reportSyncError(null);
  }

  void _recordFailure(Object error) {
    _errorMessage = 'background game retention sync failed: $error';
    if (_disposed) return;
    controller.reportSyncError('后台保活状态同步失败：$error');
    try {
      onFailure?.call(error);
    } catch (_) {
      // Diagnostics must not interrupt a later retention state change.
    }
  }
}
