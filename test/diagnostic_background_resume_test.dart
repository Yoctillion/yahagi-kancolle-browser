import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/diagnostics/diagnostic_event.dart';
import 'package:yahagi_kancolle_browser/src/diagnostics/diagnostic_performance_monitor.dart';
import 'package:yahagi_kancolle_browser/src/diagnostics/diagnostic_platform_port.dart';
import 'package:yahagi_kancolle_browser/src/diagnostics/diagnostic_recorder.dart';
import 'package:yahagi_kancolle_browser/src/diagnostics/diagnostic_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'lifecycle diagnostics distinguish focus loss from background',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.monitor.attach();
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.resumed,
      ]) {
        fixture.monitor.didChangeAppLifecycleState(state);
      }
      await fixture.recorder.flush();
      expect(
        fixture.sink.events
            .where((event) => event.type == 'lifecycle')
            .map((event) => event.fields['state']),
        ['inactive', 'hidden', 'paused', 'resumed'],
      );
    },
  );

  test('overlapping memory samples share a single native request', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.monitor.attach();
    final gate = Completer<DiagnosticRuntimeSnapshot>();
    fixture.platform.gate = gate;
    final first = fixture.monitor.sample();
    final second = fixture.monitor.sample();
    final nativeCalls = fixture.platform.calls;
    gate.complete(_runtime);
    await Future.wait([first, second]);
    await fixture.recorder.flush();
    expect(nativeCalls, 1);
    expect(
      fixture.sink.events.where((event) => event.type == 'performanceSample'),
      hasLength(1),
    );
  });

  test('a pre-background sample cannot be recorded after resume', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.monitor.attach();
    final gate = Completer<DiagnosticRuntimeSnapshot>();
    fixture.platform.gate = gate;
    final oldSample = fixture.monitor.sample();
    fixture.monitor.didChangeAppLifecycleState(AppLifecycleState.paused);
    fixture.monitor.didChangeAppLifecycleState(AppLifecycleState.resumed);
    gate.complete(_runtime);
    await oldSample;
    await fixture.recorder.flush();
    expect(
      fixture.sink.events.where((event) => event.type == 'performanceSample'),
      isEmpty,
    );
  });

  test('resume captures promptly and cancels capture when paused again', () {
    fakeAsync((clock) {
      final fixture = _Fixture();
      fixture.monitor.attach();
      try {
        fixture.monitor.didChangeAppLifecycleState(AppLifecycleState.paused);
        fixture.monitor.didChangeAppLifecycleState(AppLifecycleState.resumed);
        clock.elapse(const Duration(seconds: 3));
        expect(fixture.platform.calls, 1);
        fixture.monitor.didChangeAppLifecycleState(AppLifecycleState.paused);
        fixture.monitor.didChangeAppLifecycleState(AppLifecycleState.resumed);
        fixture.monitor.didChangeAppLifecycleState(AppLifecycleState.paused);
        clock.elapse(const Duration(seconds: 3));
        expect(fixture.platform.calls, 1);
      } finally {
        unawaited(fixture.dispose());
        clock.flushMicrotasks();
      }
    });
  });

  test('resume can sample while an older native request is hung', () {
    fakeAsync((clock) {
      final fixture = _Fixture();
      fixture.monitor.attach();
      try {
        fixture.platform.gate = Completer<DiagnosticRuntimeSnapshot>();
        unawaited(fixture.monitor.sample());
        clock.flushMicrotasks();
        fixture.monitor.didChangeAppLifecycleState(AppLifecycleState.paused);
        fixture.monitor.didChangeAppLifecycleState(AppLifecycleState.resumed);
        fixture.platform.gate = null;
        clock.elapse(const Duration(milliseconds: 2100));
        expect(fixture.platform.calls, 2);
      } finally {
        unawaited(fixture.dispose());
        clock.elapse(const Duration(seconds: 4));
      }
    });
  });

  test('records game counters separately from host Flutter frames', () async {
    final fixture = _Fixture(
      gamePerformanceSnapshot: () async => {
        'fresh': true,
        'sampleAgeMs': 25,
        'sample': {
          'target': 'fps60',
          'visible': true,
          'fps': null,
          'renderFps': 0,
        },
      },
    );
    addTearDown(fixture.dispose);
    fixture.monitor.attach();
    await fixture.monitor.sample();
    await fixture.recorder.flush();
    final event = fixture.sink.events.singleWhere(
      (event) => event.type == 'gameLoopSample',
    );
    expect(event.fields['gameFps'], isNull);
    expect(event.fields['gameRenderFps'], 0);
    expect(
      fixture.sink.events.where((event) => event.type == 'performanceSample'),
      hasLength(1),
    );
  });

  test(
    'timed out game samples are discarded and later sampling still works',
    () {
      fakeAsync((clock) {
        final gate = Completer<Map<Object?, Object?>?>();
        var reads = 0;
        final fixture = _Fixture(
          gamePerformanceSnapshot: () {
            reads++;
            return reads == 1 ? gate.future : Future.value({'fresh': false});
          },
        );
        fixture.monitor.attach();
        try {
          var settled = false;
          unawaited(fixture.monitor.sample().then((_) => settled = true));
          clock.elapse(const Duration(milliseconds: 3100));
          expect(settled, isTrue);
          gate.complete({
            'fresh': true,
            'sample': {'fps': 60},
          });
          clock.flushMicrotasks();
          unawaited(fixture.recorder.flush());
          clock.flushMicrotasks();
          expect(
            fixture.sink.events.where((e) => e.type == 'gameLoopSample'),
            isEmpty,
          );
          unawaited(fixture.monitor.sample());
          clock.flushMicrotasks();
          unawaited(fixture.recorder.flush());
          clock.flushMicrotasks();
          expect(reads, 2);
          expect(
            fixture.sink.events.where((e) => e.type == 'gameLoopSample'),
            hasLength(1),
          );
        } finally {
          unawaited(fixture.dispose());
          clock.flushMicrotasks();
        }
      });
    },
  );

  test(
    'detaching and reattaching cannot publish the retired game sample',
    () async {
      final gate = Completer<Map<Object?, Object?>?>();
      final fixture = _Fixture(gamePerformanceSnapshot: () => gate.future);
      addTearDown(fixture.dispose);
      fixture.monitor.attach();
      final retired = fixture.monitor.sample();
      fixture.monitor.detach();
      fixture.monitor.attach();
      gate.complete({
        'fresh': true,
        'sample': {'fps': 60},
      });
      await retired;
      await fixture.recorder.flush();
      expect(
        fixture.sink.events.where((e) => e.type == 'gameLoopSample'),
        isEmpty,
      );
    },
  );
}

const _runtime = DiagnosticRuntimeSnapshot(
  pssKb: 100,
  javaHeapKb: 20,
  nativeHeapKb: 30,
  graphicsKb: 10,
  privateOtherKb: 5,
  systemAvailableKb: 1000,
  lowMemory: false,
);

class _Fixture {
  _Fixture({this.gamePerformanceSnapshot});

  final Future<Map<Object?, Object?>?> Function()? gamePerformanceSnapshot;
  final sink = _Sink();
  final platform = _Platform();
  late final recorder = DiagnosticRecorder(sink: sink);
  late final monitor = DiagnosticPerformanceMonitor(
    recorder: recorder,
    platform: platform,
    pendingApiEvents: () => 0,
    activeApiPath: () => null,
    backgroundDecodeFallbacks: () => 0,
    databaseBytes: () async => 0,
    gamePerformanceSnapshot: gamePerformanceSnapshot,
  );

  Future<void> dispose() async {
    monitor.detach();
    await recorder.dispose();
  }
}

class _Sink implements DiagnosticSink {
  final events = <DiagnosticEvent>[];

  @override
  Future<void> appendAll(List<DiagnosticEvent> values) async {
    events.addAll(values);
  }
}

class _Platform implements DiagnosticPlatformPort {
  Completer<DiagnosticRuntimeSnapshot>? gate;
  int calls = 0;

  @override
  Future<DiagnosticRuntimeSnapshot> runtimeSnapshot() {
    calls++;
    return gate?.future ?? Future.value(_runtime);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
