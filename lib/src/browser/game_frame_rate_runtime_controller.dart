import 'dart:async';

import 'package:flutter/scheduler.dart';

import '../settings/game_frame_rate_settings.dart';
import 'game_frame_rate_policy.dart';

enum GameFrameRateTarget { fps30, fps60, highRefresh }

abstract interface class GameFrameRateRuntimePort {
  Future<void> apply(GameFrameRateTarget target);

  Future<double?> measuredFps();
}

typedef GameFrameRateTimerFactory =
    Timer Function(Duration duration, void Function(Timer timer) callback);

final class GameFrameRateRuntimeController {
  GameFrameRateRuntimeController({
    required this.settings,
    required this.port,
    GameFrameRatePolicy? policy,
    GameFrameRateTimerFactory? timerFactory,
    void Function(TimingsCallback callback)? addTimingsCallback,
    void Function(TimingsCallback callback)? removeTimingsCallback,
    this.sampleInterval = const Duration(seconds: 1),
    this.samplesPerWindow = 5,
    this.samplingGracePeriod = const Duration(seconds: 3),
    this.operationTimeout = const Duration(seconds: 5),
    DateTime Function()? now,
  }) : assert(samplesPerWindow > 0),
       policy = policy ?? GameFrameRatePolicy(mode: settings.mode),
       _timerFactory = timerFactory ?? Timer.periodic,
       _now = now ?? DateTime.now,
       _addTimingsCallback =
           addTimingsCallback ?? SchedulerBinding.instance.addTimingsCallback,
       _removeTimingsCallback =
           removeTimingsCallback ??
           SchedulerBinding.instance.removeTimingsCallback {
    settings.addListener(_onSettingsChanged);
    _addTimingsCallback(_timingsCallback);
  }

  final GameFrameRateSettingsController settings;
  final GameFrameRateRuntimePort port;
  final GameFrameRatePolicy policy;
  final GameFrameRateTimerFactory _timerFactory;
  final void Function(TimingsCallback callback) _addTimingsCallback;
  final void Function(TimingsCallback callback) _removeTimingsCallback;
  final Duration sampleInterval;
  final int samplesPerWindow;
  final Duration samplingGracePeriod;
  final Duration operationTimeout;
  final DateTime Function() _now;

  Future<void> _queue = Future<void>.value();
  Timer? _sampleTimer;
  bool _ready = false;
  bool _foreground = true;
  bool _disposed = false;
  int _sampleTicks = 0;
  int _generation = 0;
  bool _samplePending = false;
  bool _needsApply = true;
  DateTime? _sampleAfter;
  DateTime? _windowStarted;
  late final TimingsCallback _timingsCallback = _onFrameTimings;

  Future<void> get idle => _queue;

  void onPageStarted() {
    if (_disposed) return;
    _ready = false;
    _invalidateObservation();
  }

  Future<void> onPageReady({bool samplingEnabled = true}) async {
    if (_disposed) return;
    _ready = samplingEnabled;
    _invalidateObservation();
    if (!samplingEnabled) return;
    _enqueueApply();
    await idle;
  }

  void onLifecycleChanged(AppLifecycleState state) {
    if (_disposed) return;
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground == foreground) return;
    _foreground = foreground;
    _invalidateObservation();
    if (_ready) _enqueueApply();
  }

  void recordFlutterFrame(Duration totalSpan) {
    if (!_canSample) return;
    policy.addFlutterFrame(totalSpan);
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (!_canSample) return;
    for (final timing in timings) {
      policy.addFlutterFrame(timing.totalSpan);
    }
  }

  bool get _canObserve => !_disposed && _ready && _foreground;

  bool get _canSample =>
      _canObserve &&
      settings.mode == GameFrameRateMode.automatic &&
      !_needsApply &&
      _sampleAfter != null &&
      !_now().isBefore(_sampleAfter!);

  void _onSettingsChanged() {
    if (_disposed) return;
    policy.setMode(settings.mode);
    _invalidateObservation();
    if (_ready) _enqueueApply();
  }

  void _enqueueApply() {
    final generation = _generation;
    _enqueue(() => _applyCurrentLifecycleTarget(generation));
  }

  GameFrameRateTarget get _target => switch (settings.mode) {
    GameFrameRateMode.stable30 => GameFrameRateTarget.fps30,
    GameFrameRateMode.stable60 => GameFrameRateTarget.fps60,
    GameFrameRateMode.highRefresh => GameFrameRateTarget.highRefresh,
    GameFrameRateMode.automatic when !_foreground || policy.isLockedTo30 =>
      GameFrameRateTarget.fps30,
    GameFrameRateMode.automatic => GameFrameRateTarget.fps60,
  };

  bool _isCurrent(int generation) =>
      !_disposed && _ready && generation == _generation;

  Future<void> _applyCurrentLifecycleTarget(int generation) async {
    if (!_isCurrent(generation)) return;
    final applying = Future<void>.sync(() => port.apply(_target));
    try {
      await applying.timeout(operationTimeout);
      if (!_isCurrent(generation)) return;
      _needsApply = false;
      _sampleTicks = 0;
      policy.resetObservation();
      _sampleAfter = _now().add(samplingGracePeriod);
      _windowStarted = _sampleAfter;
      if (settings.mode != GameFrameRateMode.automatic) _stopTimer();
    } on TimeoutException {
      // The platform operation cannot be cancelled. If it finishes after a
      // newer target, reconcile once more so the late write cannot win.
      unawaited(
        applying
            .then((_) {
              if (_disposed || !_ready) return;
              _invalidateObservation();
              _enqueueApply();
            })
            .catchError((_) {}),
      );
    } catch (_) {
      // Keep a retry timer alive until the page accepts the selected target.
    }
    if (_isCurrent(generation) &&
        _canObserve &&
        (settings.mode == GameFrameRateMode.automatic || _needsApply)) {
      _sampleTimer ??= _timerFactory(sampleInterval, _onSampleTimer);
    }
  }

  void _onSampleTimer(Timer _) {
    if (!_canObserve || _samplePending) return;
    if (!_needsApply && !_canSample) return;
    final generation = _generation;
    _samplePending = true;
    _enqueue(() async {
      try {
        if (!_isCurrent(generation)) return;
        if (_needsApply) {
          await _applyCurrentLifecycleTarget(generation);
        } else {
          await _sampleOnce(generation);
        }
      } finally {
        _samplePending = false;
      }
    });
  }

  Future<void> _sampleOnce(int generation) async {
    if (!_isCurrent(generation) || !_canSample) return;
    double? fps;
    try {
      fps = await port.measuredFps().timeout(operationTimeout);
    } catch (_) {
      // A missing or navigating page simply contributes no sample.
    }
    if (!_isCurrent(generation) || !_canSample) return;
    policy.addCreateJsSample(fps);
    _sampleTicks += 1;
    if (_sampleTicks < samplesPerWindow) return;
    _sampleTicks = 0;
    final now = _now();
    final decision = policy.completeWindow(
      elapsed: now.difference(_windowStarted ?? now),
    );
    _windowStarted = now;
    if (decision == FrameRateDecision.downgradeTo30 ||
        decision == FrameRateDecision.upgradeTo60) {
      _invalidateObservation();
      await _applyCurrentLifecycleTarget(_generation);
    }
  }

  void _invalidateObservation() {
    _generation += 1;
    _needsApply = true;
    _sampleAfter = null;
    _windowStarted = null;
    _sampleTicks = 0;
    _stopTimer();
    policy.resetObservation();
  }

  void _enqueue(Future<void> Function() operation) {
    _queue = _queue.then((_) => operation()).catchError((_) {});
  }

  void _stopTimer() {
    _sampleTimer?.cancel();
    _sampleTimer = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stopTimer();
    settings.removeListener(_onSettingsChanged);
    _removeTimingsCallback(_timingsCallback);
  }
}
