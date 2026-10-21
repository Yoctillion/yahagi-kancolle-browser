import 'dart:async';

/// Serializes native visibility changes and coalesces queued lifecycle changes.
/// Waiters for superseded states settle with the newest queued state.
final class NativeGameSurfaceVisibility {
  NativeGameSurfaceVisibility(this._onVisibilityChanged);

  Future<void> Function(bool visible) _onVisibilityChanged;

  bool _routeVisible = true;
  bool _appVisible = true;
  bool _workspaceVisible = true;
  bool _slotAttached = false;
  bool _desiredVisible = false;
  bool _lastDeliveredVisible = false;
  int _desiredVersion = 0;
  int? _failedVersion;
  _VisibilityRequest? _inFlight;
  _VisibilityRequest? _queued;
  final Map<int, List<Completer<void>>> _waiters =
      <int, List<Completer<void>>>{};

  Future<void> setRouteVisible(bool visible) {
    _routeVisible = visible;
    return _requestCurrentVisibility();
  }

  Future<void> setAppVisible(bool visible) {
    _appVisible = visible;
    return _requestCurrentVisibility();
  }

  Future<void> setWorkspaceVisible(bool visible) {
    _workspaceVisible = visible;
    return _requestCurrentVisibility();
  }

  Future<void> setSlotAttached(bool attached) {
    _slotAttached = attached;
    return _requestCurrentVisibility();
  }

  Future<void> dispose() => setSlotAttached(false);

  void updateCallback(Future<void> Function(bool visible) callback) {
    _onVisibilityChanged = callback;
  }

  Future<void> _requestCurrentVisibility() {
    final visible =
        _routeVisible && _appVisible && _workspaceVisible && _slotAttached;
    var enqueue = false;
    if (visible != _desiredVisible) {
      _desiredVisible = visible;
      _desiredVersion++;
      enqueue = true;
    } else if (_failedVersion == _desiredVersion && _inFlight == null) {
      _failedVersion = null;
      _desiredVersion++;
      enqueue = true;
    }
    if (!enqueue &&
        _inFlight == null &&
        _queued == null &&
        _desiredVisible == _lastDeliveredVisible) {
      return Future<void>.value();
    }

    final waiter = Completer<void>();
    (_waiters[_desiredVersion] ??= <Completer<void>>[]).add(waiter);
    if (enqueue) {
      _queued = _VisibilityRequest(_desiredVisible, _desiredVersion);
    }
    _drain();
    return waiter.future;
  }

  void _drain() {
    final request = _queued;
    if (_inFlight != null || request == null) {
      return;
    }
    _queued = null;
    _inFlight = request;
    unawaited(_deliver(request));
  }

  Future<void> _deliver(_VisibilityRequest request) async {
    try {
      await _onVisibilityChanged(request.visible);
      _lastDeliveredVisible = request.visible;
      _completeWaiters(request.version);
    } catch (error, stackTrace) {
      _failedVersion = request.version;
      _completeWaitersWithError(request.version, error, stackTrace);
    } finally {
      _inFlight = null;
    }
    _drain();
  }

  void _completeWaiters(int version) {
    final completed = _waiters.keys.where((key) => key <= version).toList();
    for (final key in completed) {
      for (final waiter in _waiters.remove(key)!) {
        if (!waiter.isCompleted) waiter.complete();
      }
    }
  }

  void _completeWaitersWithError(
    int version,
    Object error,
    StackTrace stackTrace,
  ) {
    final completed = _waiters.keys.where((key) => key <= version).toList();
    for (final key in completed) {
      for (final waiter in _waiters.remove(key)!) {
        if (!waiter.isCompleted) waiter.completeError(error, stackTrace);
      }
    }
  }
}

final class _VisibilityRequest {
  const _VisibilityRequest(this.visible, this.version);

  final bool visible;
  final int version;
}
