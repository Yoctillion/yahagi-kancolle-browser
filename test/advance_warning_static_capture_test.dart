import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/capture/android_game_capture_port.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_controller.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_port.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'same-port attach disable rejects events before the native reply',
    () async {
      final port = _DelayedDisableCapturePort();
      final accepted = <CapturedApiEvent>[];
      var interruptions = 0;
      final capture = GameCaptureController(
        onAcceptedEvent: accepted.add,
        onCaptureInterrupted: () => interruptions += 1,
      );
      addTearDown(() async {
        if (!port.releaseDisable.isCompleted) port.releaseDisable.complete();
        capture.dispose();
        await port.close();
      });
      await capture.attach(port, enabled: true);

      final disabling = capture.attach(port, enabled: false);
      await port.disableStarted.future;
      port.add(_event('/kcsapi/api_port/port', sequence: 1));
      port.add(_event('/kcsapi/api_req_map/start', sequence: 2));
      port.releaseDisable.complete();
      await disabling;

      expect(interruptions, greaterThan(0));
      expect(accepted, isEmpty);
      expect(capture.latestEvent, isNull);
      expect(capture.state, GameCaptureState.disabled);
    },
  );

  test('native late repair interrupts the current port continuity', () async {
    const channel = MethodChannel('test/advance_warning_static_late_repair');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final oldReply = Completer<void>();
    final configurations = <bool>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'isSupported') return true;
      if (call.method == 'configure') {
        final arguments = call.arguments as Map<Object?, Object?>;
        configurations.add(arguments['enabled']! as bool);
        if (configurations.length == 1) await oldReply.future;
      }
      return null;
    });
    final retired = MethodChannelGameCapturePort(
      channel: channel,
      configurationTimeout: const Duration(milliseconds: 1),
    );
    MethodChannelGameCapturePort? current;
    StreamSubscription<void>? interruptionsSubscription;
    var interruptions = 0;
    addTearDown(() async {
      if (!oldReply.isCompleted) oldReply.complete();
      await interruptionsSubscription?.cancel();
      retired.dispose();
      current?.dispose();
      messenger.setMockMethodCallHandler(channel, null);
    });
    await expectLater(
      retired.configure(enabled: false, script: ''),
      throwsA(isA<TimeoutException>()),
    );
    retired.dispose();
    final replacement = MethodChannelGameCapturePort(channel: channel);
    current = replacement;
    interruptionsSubscription = replacement.interruptions.listen(
      (_) => interruptions += 1,
    );
    await replacement.configure(enabled: true, script: 'current');
    expect(interruptions, 0);

    oldReply.complete();
    for (var attempt = 0; attempt < 20; attempt++) {
      await Future<void>.delayed(Duration.zero);
      if (configurations.length >= 3 && interruptions > 0) break;
    }

    expect(configurations, <bool>[false, true, true]);
    expect(interruptions, 1);
  });

  test(
    'native rejection marker advances capture continuity without an event',
    () async {
      const channel = MethodChannel('test/advance_warning_static_rejection');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'isSupported') return true;
        return null;
      });
      final port = MethodChannelGameCapturePort(channel: channel);
      final accepted = <CapturedApiEvent>[];
      var interruptions = 0;
      final capture = GameCaptureController(
        onAcceptedEvent: accepted.add,
        onCaptureInterrupted: () => interruptions += 1,
      );
      addTearDown(() {
        capture.dispose();
        port.dispose();
        messenger.setMockMethodCallHandler(channel, null);
      });
      await capture.attach(port, enabled: true);
      final previousGeneration = capture.continuityGeneration;
      final delivered = Completer<void>();
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onCaptureEvent', <String, Object?>{
            'version': 1,
            'kind': 'capture_interrupted',
          }),
        ),
        (_) => delivered.complete(),
      );
      await delivered.future;
      await Future<void>.delayed(Duration.zero);

      expect(interruptions, 1);
      expect(capture.continuityGeneration, previousGeneration + 1);
      expect(accepted, isEmpty);
      expect(capture.latestEvent, isNull);
      expect(capture.state, GameCaptureState.ready);
    },
  );
}

CapturedApiEvent _event(String path, {required int sequence}) =>
    CapturedApiEvent(
      path: path,
      responseBody: '{"api_result":1,"api_data":{}}',
      source: CaptureSource.xhr,
      capturedAt: DateTime.utc(2026, 10, 23),
      sequence: sequence,
    );

final class _DelayedDisableCapturePort implements GameCapturePort {
  final StreamController<CapturedApiEvent> _events =
      StreamController<CapturedApiEvent>.broadcast(sync: true);
  final Completer<void> disableStarted = Completer<void>();
  final Completer<void> releaseDisable = Completer<void>();

  @override
  Stream<CapturedApiEvent> get events => _events.stream;

  void add(CapturedApiEvent event) => _events.add(event);

  Future<void> close() => _events.close();

  @override
  Future<void> configure({
    required bool enabled,
    required String script,
  }) async {
    if (!enabled) {
      if (!disableStarted.isCompleted) disableStarted.complete();
      await releaseDisable.future;
    }
  }

  @override
  Future<bool> isSupported() async => true;

  @override
  void dispose() => unawaited(_events.close());
}
