import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_frame_rate_runtime_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/game_frame_rate_settings.dart';

void main() {
  test('newly ready pages receive a sampling grace period', () async {
    final settings = await GameFrameRateSettingsController.load(
      MemoryGameFrameRateSettingsStore(GameFrameRateMode.automatic),
    );
    final port = _FakeRuntimePort(const <double>[]);
    final timers = _FakeTimerFactory();
    final runtime = GameFrameRateRuntimeController(
      settings: settings,
      port: port,
      timerFactory: timers.call,
      addTimingsCallback: (_) {},
      removeTimingsCallback: (_) {},
    );
    addTearDown(() {
      runtime.dispose();
      settings.dispose();
    });

    await runtime.onPageReady();
    timers.timer!.fire();
    await runtime.idle;
    expect(port.measurementCalls, 0);
  });

  test('does not sample before the game page is ready', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);

    fixture.runtime.onPageStarted();

    expect(fixture.timer, isNull);
    expect(fixture.port.measurementCalls, 0);
    expect(fixture.port.appliedTargets, isEmpty);
  });

  test('does not sample or apply a target on a login page', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);

    await fixture.runtime.onPageReady(samplingEnabled: false);
    fixture.runtime.recordFlutterFrame(const Duration(milliseconds: 40));

    expect(fixture.port.appliedTargets, isEmpty);
    expect(fixture.timer, isNull);
    expect(fixture.runtime.policy.flutterFrameCount, 0);
  });

  test(
    'automatic mode starts at 60 and samples at most once per tick',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      await fixture.runtime.onPageReady();
      fixture.timer!.fire();
      await fixture.runtime.idle;

      expect(fixture.port.appliedTargets, <GameFrameRateTarget>[
        GameFrameRateTarget.fps60,
      ]);
      expect(fixture.port.measurementCalls, 1);
    },
  );

  test('two unstable windows apply 30 FPS and continue monitoring', () async {
    final fixture = await _Fixture.create(
      measurements: <double>[49, 48, 47, 55, 56, 49, 48, 47, 55, 56],
    );
    addTearDown(fixture.dispose);

    await fixture.runtime.onPageReady();
    for (var index = 0; index < 10; index++) {
      fixture.timer!.fire();
      await fixture.runtime.idle;
    }

    expect(fixture.port.appliedTargets, <GameFrameRateTarget>[
      GameFrameRateTarget.fps60,
      GameFrameRateTarget.fps30,
    ]);
    expect(fixture.timer!.isActive, isTrue);

    fixture.runtime.onPageStarted();
    await fixture.runtime.onPageReady();
    expect(fixture.port.appliedTargets.last, GameFrameRateTarget.fps30);
  });

  test('timer ticks do not queue duplicate pending measurements', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.runtime.onPageReady();
    final pending = Completer<double?>();
    fixture.port.measure = () => pending.future;

    fixture.timer!.fire();
    await Future<void>.delayed(Duration.zero);
    for (var i = 0; i < 8; i++) {
      fixture.timer!.fire();
    }
    pending.complete(60);
    await fixture.runtime.idle;

    expect(fixture.port.measurementCalls, 1);
  });

  test(
    'navigation discards pending samples and previous instability',
    () async {
      final fixture = await _Fixture.create(
        measurements: List<double>.filled(10, 40),
      );
      addTearDown(fixture.dispose);
      await fixture.runtime.onPageReady();
      for (var i = 0; i < 5; i++) {
        fixture.timer!.fire();
        await fixture.runtime.idle;
      }
      final pending = Completer<double?>();
      fixture.port.measure = () => pending.future;
      fixture.timer!.fire();
      await Future<void>.delayed(Duration.zero);

      fixture.runtime.onPageStarted();
      final ready = fixture.runtime.onPageReady();
      pending.complete(40);
      await ready;
      fixture.port.measure = null;
      for (var i = 0; i < 5; i++) {
        fixture.timer!.fire();
        await fixture.runtime.idle;
      }
      expect(
        fixture.port.appliedTargets,
        everyElement(GameFrameRateTarget.fps60),
      );
    },
  );

  test(
    'an initial apply failure can retry without another page event',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      fixture.port.applyFailures = 1;

      await fixture.runtime.onPageReady();
      expect(fixture.timer?.isActive, isTrue);
      fixture.timer!.fire();
      await fixture.runtime.idle;
      fixture.timer!.fire();
      await fixture.runtime.idle;

      expect(fixture.port.appliedTargets.length, 2);
      expect(fixture.port.measurementCalls, 1);
    },
  );

  test(
    'records Flutter timings only while automatic sampling is active',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      fixture.runtime.recordFlutterFrame(const Duration(milliseconds: 40));
      expect(fixture.runtime.policy.flutterFrameCount, 0);

      await fixture.runtime.onPageReady();
      fixture.runtime.recordFlutterFrame(const Duration(milliseconds: 40));
      expect(fixture.runtime.policy.flutterFrameCount, 1);
    },
  );

  test('a player mode change applies immediately without reloading', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.runtime.onPageReady();

    await fixture.settings.setMode(GameFrameRateMode.stable30);
    await fixture.runtime.idle;

    expect(fixture.port.appliedTargets.last, GameFrameRateTarget.fps30);
    expect(fixture.timer!.isActive, isFalse);
  });

  test('manual modes always apply their exact target', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.runtime.onPageReady();

    await fixture.settings.setMode(GameFrameRateMode.stable60);
    await fixture.runtime.idle;
    await fixture.settings.setMode(GameFrameRateMode.highRefresh);
    await fixture.runtime.idle;

    expect(
      fixture.port.appliedTargets,
      containsAllInOrder(<GameFrameRateTarget>[
        GameFrameRateTarget.fps60,
        GameFrameRateTarget.highRefresh,
      ]),
    );
    expect(fixture.timer!.isActive, isFalse);
  });

  test('manual modes are not lowered by app lifecycle changes', () async {
    for (final entry in <GameFrameRateMode, GameFrameRateTarget>{
      GameFrameRateMode.stable60: GameFrameRateTarget.fps60,
      GameFrameRateMode.stable30: GameFrameRateTarget.fps30,
      GameFrameRateMode.highRefresh: GameFrameRateTarget.highRefresh,
    }.entries) {
      final fixture = await _Fixture.create(initialMode: entry.key);
      addTearDown(fixture.dispose);
      await fixture.runtime.onPageReady();

      fixture.runtime.onLifecycleChanged(AppLifecycleState.paused);
      await fixture.runtime.idle;

      expect(fixture.port.appliedTargets.last, entry.value);
    }
  });

  test('leaving the foreground lowers load and resume restores mode', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.runtime.onPageReady();

    fixture.runtime.onLifecycleChanged(AppLifecycleState.paused);
    await fixture.runtime.idle;
    expect(fixture.port.appliedTargets.last, GameFrameRateTarget.fps30);

    fixture.runtime.onLifecycleChanged(AppLifecycleState.resumed);
    await fixture.runtime.idle;
    expect(fixture.port.appliedTargets.last, GameFrameRateTarget.fps60);
  });

  test(
    'automatic mode recovers after thirty seconds of stable 30 FPS',
    () async {
      final fixture = await _Fixture.create(
        measurements: <double>[
          ...List<double>.filled(10, 40),
          ...List<double>.filled(30, 30),
        ],
      );
      addTearDown(fixture.dispose);
      await fixture.runtime.onPageReady();
      await fixture.fire(39);
      expect(fixture.port.appliedTargets.last, GameFrameRateTarget.fps30);
      await fixture.fire(1);
      expect(fixture.port.appliedTargets, <GameFrameRateTarget>[
        GameFrameRateTarget.fps60,
        GameFrameRateTarget.fps30,
        GameFrameRateTarget.fps60,
      ]);
      expect(fixture.timer!.isActive, isTrue);
    },
  );

  test('system-constrained null samples cannot trigger recovery', () async {
    final fixture = await _Fixture.create(
      measurements: <double?>[
        ...List<double>.filled(10, 40),
        ...List<double?>.filled(50, null),
        ...List<double>.filled(15, 30),
      ],
    );
    addTearDown(fixture.dispose);
    await fixture.runtime.onPageReady();
    await fixture.fire(60);
    expect(fixture.port.appliedTargets.last, GameFrameRateTarget.fps30);
    await fixture.fire(14);
    expect(fixture.port.appliedTargets.last, GameFrameRateTarget.fps30);
    await fixture.fire(1);
    expect(fixture.port.appliedTargets.last, GameFrameRateTarget.fps60);
  });

  test(
    'resume and mode changes restart the three second sampling grace',
    () async {
      final fixture = await _Fixture.create(
        samplingGracePeriod: const Duration(seconds: 3),
      );
      addTearDown(fixture.dispose);
      await fixture.runtime.onPageReady();
      await fixture.fire(2);
      expect(fixture.port.measurementCalls, 0);
      await fixture.fire(1);
      expect(fixture.port.measurementCalls, 1);

      fixture.runtime.onLifecycleChanged(AppLifecycleState.paused);
      await fixture.runtime.idle;
      fixture.runtime.onLifecycleChanged(AppLifecycleState.resumed);
      await fixture.runtime.idle;
      await fixture.fire(2);
      expect(fixture.port.measurementCalls, 1);
      await fixture.fire(1);
      expect(fixture.port.measurementCalls, 2);

      await fixture.settings.setMode(GameFrameRateMode.stable60);
      await fixture.runtime.idle;
      await fixture.settings.setMode(GameFrameRateMode.automatic);
      await fixture.runtime.idle;
      await fixture.fire(2);
      expect(fixture.port.measurementCalls, 2);
      await fixture.fire(1);
      expect(fixture.port.measurementCalls, 3);
    },
  );

  test(
    'failed downgrade retries without interpreting the old 60 FPS target',
    () async {
      final fixture = await _Fixture.create(
        measurements: List<double>.filled(10, 40),
      );
      addTearDown(fixture.dispose);
      await fixture.runtime.onPageReady();
      await fixture.fire(9);
      fixture.port.applyFailures = 1;
      await fixture.fire(1);
      expect(fixture.port.measurementCalls, 10);
      await fixture.fire(1);
      expect(fixture.port.measurementCalls, 10);
      expect(fixture.port.appliedTargets, <GameFrameRateTarget>[
        GameFrameRateTarget.fps60,
        GameFrameRateTarget.fps30,
        GameFrameRateTarget.fps30,
      ]);
    },
  );

  test('successful manual retry stops the retry timer', () async {
    final fixture = await _Fixture.create(
      initialMode: GameFrameRateMode.stable60,
    );
    addTearDown(fixture.dispose);
    fixture.port.applyFailures = 1;
    await fixture.runtime.onPageReady();
    expect(fixture.timer!.isActive, isTrue);
    await fixture.fire(1);
    expect(fixture.timer!.isActive, isFalse);
    expect(fixture.port.measurementCalls, 0);
  });

  test(
    'a timed out apply cannot overwrite a later mode when it completes',
    () async {
      final fixture = await _Fixture.create(
        operationTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(fixture.dispose);
      final pending = Completer<void>();
      fixture.port.applyOperation = () => pending.future;
      await fixture.runtime.onPageReady();
      expect(fixture.timer!.isActive, isTrue);

      fixture.port.applyOperation = null;
      await fixture.settings.setMode(GameFrameRateMode.stable30);
      await fixture.runtime.idle;
      pending.complete();
      await Future<void>.delayed(Duration.zero);
      await fixture.runtime.idle;
      expect(fixture.port.appliedTargets, <GameFrameRateTarget>[
        GameFrameRateTarget.fps60,
        GameFrameRateTarget.fps30,
        GameFrameRateTarget.fps30,
      ]);
    },
  );

  test(
    'a stalled measurement times out and does not block future sampling',
    () async {
      final fixture = await _Fixture.create(
        operationTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(fixture.dispose);
      await fixture.runtime.onPageReady();
      final pending = Completer<double?>();
      fixture.port.measure = () => pending.future;
      await fixture.fire(1);
      fixture.port.measure = null;
      await fixture.fire(1);
      pending.complete(20);
      await fixture.runtime.idle;
      expect(fixture.port.measurementCalls, 2);
      expect(fixture.port.appliedTargets, <GameFrameRateTarget>[
        GameFrameRateTarget.fps60,
      ]);
    },
  );

  test('dispose cancels timers and unregisters the timings callback', () async {
    final fixture = await _Fixture.create();
    await fixture.runtime.onPageReady();

    fixture.runtime.dispose();

    expect(fixture.timer!.isActive, isFalse);
    expect(fixture.removedTimingCallback, same(fixture.addedTimingCallback));
    fixture.settings.dispose();
  });
}

final class _Fixture {
  _Fixture._({
    required this.settings,
    required this.port,
    required this.runtime,
    required this.timerFactory,
  });

  final GameFrameRateSettingsController settings;
  final _FakeRuntimePort port;
  final GameFrameRateRuntimeController runtime;
  final _FakeTimerFactory timerFactory;
  TimingsCallback? get addedTimingCallback => timerFactory.addedTimingCallback;
  TimingsCallback? get removedTimingCallback =>
      timerFactory.removedTimingCallback;

  _FakeTimer? get timer => timerFactory.timer;

  static Future<_Fixture> create({
    List<double?> measurements = const <double>[],
    GameFrameRateMode initialMode = GameFrameRateMode.automatic,
    Duration samplingGracePeriod = Duration.zero,
    Duration operationTimeout = const Duration(seconds: 5),
  }) async {
    final settings = await GameFrameRateSettingsController.load(
      MemoryGameFrameRateSettingsStore(initialMode),
    );
    final port = _FakeRuntimePort(measurements);
    final timerFactory = _FakeTimerFactory();
    final runtime = GameFrameRateRuntimeController(
      settings: settings,
      port: port,
      timerFactory: timerFactory.call,
      samplingGracePeriod: samplingGracePeriod,
      operationTimeout: operationTimeout,
      now: () => timerFactory.now,
      addTimingsCallback: (callback) =>
          timerFactory.addedTimingCallback = callback,
      removeTimingsCallback: (callback) =>
          timerFactory.removedTimingCallback = callback,
    );
    final fixture = _Fixture._(
      settings: settings,
      port: port,
      runtime: runtime,
      timerFactory: timerFactory,
    );
    return fixture;
  }

  void dispose() {
    runtime.dispose();
    settings.dispose();
  }

  Future<void> fire(int count) async {
    for (var i = 0; i < count; i++) {
      timer!.fire();
      await runtime.idle;
    }
  }
}

final class _FakeRuntimePort implements GameFrameRateRuntimePort {
  _FakeRuntimePort(List<double?> measurements)
    : _measurements = List<double?>.of(measurements);

  final List<double?> _measurements;
  final List<GameFrameRateTarget> appliedTargets = <GameFrameRateTarget>[];
  int measurementCalls = 0;
  int applyFailures = 0;
  Future<double?> Function()? measure;
  Future<void> Function()? applyOperation;

  @override
  Future<void> apply(GameFrameRateTarget target) async {
    appliedTargets.add(target);
    if (applyFailures > 0) {
      applyFailures -= 1;
      throw StateError('temporarily unavailable');
    }
    await applyOperation?.call();
  }

  @override
  Future<double?> measuredFps() async {
    measurementCalls += 1;
    if (measure != null) return measure!();
    return _measurements.isEmpty ? 60 : _measurements.removeAt(0);
  }
}

final class _FakeTimerFactory {
  _FakeTimer? timer;
  DateTime now = DateTime.utc(2026);
  TimingsCallback? addedTimingCallback;
  TimingsCallback? removedTimingCallback;

  Timer call(Duration duration, void Function(Timer timer) callback) {
    return timer = _FakeTimer((timer) {
      now = now.add(duration);
      callback(timer);
    });
  }
}

final class _FakeTimer implements Timer {
  _FakeTimer(this._callback);

  final void Function(Timer timer) _callback;
  bool _active = true;
  int _tick = 0;

  void fire() {
    if (!_active) return;
    _tick += 1;
    _callback(this);
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;
}
