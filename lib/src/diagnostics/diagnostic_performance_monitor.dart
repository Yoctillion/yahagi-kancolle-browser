import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'diagnostic_event.dart';
import 'diagnostic_lifecycle.dart';
import 'diagnostic_platform_port.dart';
import 'diagnostic_recorder.dart';

final class DiagnosticFrameSnapshot {
  const DiagnosticFrameSnapshot({
    required this.totalFrames,
    required this.over16Ms,
    required this.over33Ms,
    required this.over100Ms,
    required this.maxFrameMicros,
  });

  final int totalFrames;
  final int over16Ms;
  final int over33Ms;
  final int over100Ms;
  final int maxFrameMicros;
}

final class DiagnosticFrameWindow {
  int _totalFrames = 0;
  int _over16Ms = 0;
  int _over33Ms = 0;
  int _over100Ms = 0;
  int _maxFrameMicros = 0;

  void add(Duration duration) {
    final micros = duration.inMicroseconds;
    _totalFrames += 1;
    if (micros > 16667) _over16Ms += 1;
    if (micros > 33333) _over33Ms += 1;
    if (micros > 100000) _over100Ms += 1;
    if (micros > _maxFrameMicros) _maxFrameMicros = micros;
  }

  DiagnosticFrameSnapshot takeSnapshot() {
    final result = DiagnosticFrameSnapshot(
      totalFrames: _totalFrames,
      over16Ms: _over16Ms,
      over33Ms: _over33Ms,
      over100Ms: _over100Ms,
      maxFrameMicros: _maxFrameMicros,
    );
    _totalFrames = 0;
    _over16Ms = 0;
    _over33Ms = 0;
    _over100Ms = 0;
    _maxFrameMicros = 0;
    return result;
  }
}

final class DiagnosticPerformanceMonitor with WidgetsBindingObserver {
  DiagnosticPerformanceMonitor({
    required this.recorder,
    required this.platform,
    required this.pendingApiEvents,
    required this.activeApiPath,
    required this.backgroundDecodeFallbacks,
    required this.databaseBytes,
    DiagnosticWebViewHost Function()? webViewHost,
    DiagnosticGameRenderer Function()? renderer,
    int Function()? generationId,
    this.gamePerformanceSnapshot,
    this.sampleInterval = const Duration(seconds: 60),
    this.sampleTimeout = const Duration(seconds: 3),
    this.resumeSampleDelay = const Duration(seconds: 2),
    DateTime Function()? now,
    Stopwatch? uptime,
  }) : webViewHost = webViewHost ?? _platformViewHost,
       renderer = renderer ?? _unknownRenderer,
       generationId = generationId ?? _zeroGeneration,
       _now = now ?? DateTime.now,
       _uptime = uptime ?? (Stopwatch()..start());

  static DiagnosticWebViewHost _platformViewHost() =>
      DiagnosticWebViewHost.flutterPlatformView;
  static DiagnosticGameRenderer _unknownRenderer() =>
      DiagnosticGameRenderer.unknown;
  static int _zeroGeneration() => 0;

  final DiagnosticRecorder recorder;
  final DiagnosticPlatformPort platform;
  final int Function() pendingApiEvents;
  final String? Function() activeApiPath;
  final int Function() backgroundDecodeFallbacks;
  final Future<int> Function() databaseBytes;
  final DiagnosticWebViewHost Function() webViewHost;
  final DiagnosticGameRenderer Function() renderer;
  final int Function() generationId;
  final Future<Map<Object?, Object?>?> Function()? gamePerformanceSnapshot;
  final Duration sampleInterval;
  final Duration sampleTimeout;
  final Duration resumeSampleDelay;
  final DateTime Function() _now;
  final Stopwatch _uptime;
  final DiagnosticFrameWindow _frames = DiagnosticFrameWindow();
  Timer? _timer;
  Timer? _resumeSampleTimer;
  Future<void>? _sampleFuture;
  int _sampleEpoch = 0;
  int _requestVersion = 0;
  bool _foreground = true;
  bool _attached = false;
  late final TimingsCallback _timingsCallback = _onTimings;

  void attach() {
    if (_attached || !recorder.enabled) return;
    _attached = true;
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _sampleEpoch++;
    WidgetsBinding.instance.addObserver(this);
    SchedulerBinding.instance.addTimingsCallback(_timingsCallback);
    if (_foreground) {
      _timer = Timer.periodic(sampleInterval, (_) => unawaited(sample()));
    }
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    _sampleEpoch++;
    _requestVersion++;
    _sampleFuture = null;
    _timer?.cancel();
    _timer = null;
    _resumeSampleTimer?.cancel();
    _resumeSampleTimer = null;
    SchedulerBinding.instance.removeTimingsCallback(_timingsCallback);
    WidgetsBinding.instance.removeObserver(this);
    _frames.takeSnapshot();
  }

  void _onTimings(List<FrameTiming> timings) {
    if (!_attached || !_foreground) return;
    for (final timing in timings) {
      _frames.add(timing.totalSpan);
    }
  }

  Future<void> sample() {
    if (!_attached || !recorder.enabled || !_foreground) {
      return Future<void>.value();
    }
    final pending = _sampleFuture;
    if (pending != null) return pending;
    final epoch = _sampleEpoch;
    final version = ++_requestVersion;
    late final Future<void> operation;
    operation =
        Future.wait<void>([
              _takeSample(epoch, version),
              _takeGameSample(epoch, version),
            ])
            .then<void>((_) {})
            .timeout(
              sampleTimeout,
              onTimeout: () {
                if (_requestVersion == version) _requestVersion++;
              },
            )
            .whenComplete(() {
              if (identical(_sampleFuture, operation)) _sampleFuture = null;
            });
    _sampleFuture = operation;
    return operation;
  }

  Future<void> _takeGameSample(int epoch, int version) async {
    final read = gamePerformanceSnapshot;
    if (read == null) return;
    try {
      final snapshot = await read();
      if (snapshot == null || !_canRecord(epoch, version)) return;
      recorder.record(
        DiagnosticEvent.gameLoopSample(occurredAt: _now(), snapshot: snapshot),
      );
    } catch (_) {
      // Unsupported or unavailable game sampling must not affect gameplay.
    }
  }

  bool _canRecord(int epoch, int version) =>
      _attached &&
      recorder.enabled &&
      _foreground &&
      epoch == _sampleEpoch &&
      version == _requestVersion;

  Future<void> _takeSample(int epoch, int version) async {
    try {
      final runtime = await platform.runtimeSnapshot();
      if (!_canRecord(epoch, version)) return;
      final bytes = await databaseBytes();
      if (!_canRecord(epoch, version)) return;
      final frames = _frames.takeSnapshot();
      recorder.record(
        DiagnosticEvent.performanceSample(
          occurredAt: _now(),
          uptimeMs: _uptime.elapsedMilliseconds,
          pssKb: runtime.pssKb,
          javaHeapKb: runtime.javaHeapKb,
          nativeHeapKb: runtime.nativeHeapKb,
          graphicsKb: runtime.graphicsKb,
          privateOtherKb: runtime.privateOtherKb,
          systemAvailableKb: runtime.systemAvailableKb,
          webViewHost: webViewHost(),
          renderer: renderer(),
          generationId: generationId(),
          totalFrames: frames.totalFrames,
          over16Ms: frames.over16Ms,
          over33Ms: frames.over33Ms,
          over100Ms: frames.over100Ms,
          maxFrameMicros: frames.maxFrameMicros,
          pendingApiEvents: pendingApiEvents(),
          activeApiPath: activeApiPath(),
          backgroundDecodeFallbacks: backgroundDecodeFallbacks(),
          databaseBytes: bytes,
        ),
      );
    } catch (_) {
      // Missing platform statistics must never affect the app or recurse.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_attached) return;
    final wasForeground = _foreground;
    _foreground = state == AppLifecycleState.resumed;
    _sampleEpoch++;
    _requestVersion++;
    _sampleFuture = null;
    _recordLifecycle(diagnosticLifecycleState(state)!);
    if (state == AppLifecycleState.resumed) {
      _timer ??= Timer.periodic(sampleInterval, (_) => unawaited(sample()));
      if (!wasForeground) {
        _resumeSampleTimer?.cancel();
        _resumeSampleTimer = Timer(resumeSampleDelay, () {
          _resumeSampleTimer = null;
          unawaited(sample());
        });
      }
    } else {
      _timer?.cancel();
      _timer = null;
      _resumeSampleTimer?.cancel();
      _resumeSampleTimer = null;
      _frames.takeSnapshot();
      unawaited(recorder.flush());
    }
  }

  @override
  void didHaveMemoryPressure() {
    if (!_attached) return;
    _recordLifecycle(DiagnosticLifecycleState.lowMemory);
    unawaited(sample());
  }

  void _recordLifecycle(DiagnosticLifecycleState state) {
    recorder.record(
      DiagnosticEvent.lifecycle(
        occurredAt: _now(),
        state: state,
        uptimeMs: _uptime.elapsedMilliseconds,
      ),
    );
  }
}
