import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/capture/android_game_capture_port.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_controller.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_port.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_api_event_pipeline.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('capture interruption notifications', () {
    for (final operation in ['clear', 'configure disable', 'attach disable']) {
      test(
        '$operation notifies even without a previous captured event',
        () async {
          var interruptions = 0;
          final port = _ContinuityCapturePort();
          final controller = GameCaptureController(
            onCaptureInterrupted: () => interruptions += 1,
          );
          addTearDown(() async {
            controller.dispose();
            await port.close();
          });
          await controller.attach(port, enabled: true);
          expect(interruptions, 0);
          expect(controller.latestEvent, isNull);

          switch (operation) {
            case 'clear':
              controller.clearCapturedEvents();
            case 'configure disable':
              await controller.configure(enabled: false);
            case 'attach disable':
              await controller.attach(port, enabled: false);
          }

          expect(interruptions, greaterThan(0));
        },
      );
    }

    test('replacing an installed port notifies interruption', () async {
      var interruptions = 0;
      final firstPort = _ContinuityCapturePort();
      final nextPort = _ContinuityCapturePort();
      final controller = GameCaptureController(
        onCaptureInterrupted: () => interruptions += 1,
      );
      addTearDown(() async {
        controller.dispose();
        await firstPort.close();
        await nextPort.close();
      });
      await controller.attach(firstPort, enabled: true);
      expect(interruptions, 0);

      await controller.attach(nextPort, enabled: true);

      expect(interruptions, greaterThan(0));
      expect(controller.state, GameCaptureState.ready);
    });

    test(
      'retired and disposed port interruptions cannot affect the current stream',
      () async {
        var interruptions = 0;
        final firstPort = _ContinuityCapturePort();
        final nextPort = _ContinuityCapturePort();
        final controller = GameCaptureController(
          onCaptureInterrupted: () => interruptions += 1,
        );
        addTearDown(() async {
          controller.dispose();
          await firstPort.close();
          await nextPort.close();
        });
        await controller.attach(firstPort, enabled: true);
        await controller.attach(nextPort, enabled: true);
        final afterReplacement = interruptions;

        firstPort.interrupt();
        expect(interruptions, afterReplacement);
        nextPort.interrupt();
        expect(interruptions, afterReplacement + 1);
        nextPort.add(_event(sequence: 1));
        expect(controller.latestEvent?.sequence, 1);
        controller.dispose();
        nextPort.interrupt();
        expect(interruptions, afterReplacement + 1);
      },
    );

    test(
      'malformed native capture invalidates continuity without ending valid capture',
      () async {
        const channel = MethodChannel('test/capture_continuity_native');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'isSupported') return true;
          return null;
        });
        var interruptions = 0;
        final accepted = <CapturedApiEvent>[];
        final port = MethodChannelGameCapturePort(channel: channel);
        final controller = GameCaptureController(
          onAcceptedEvent: accepted.add,
          onCaptureInterrupted: () => interruptions += 1,
        );
        addTearDown(() {
          controller.dispose();
          port.dispose();
          messenger.setMockMethodCallHandler(channel, null);
        });
        await controller.attach(port, enabled: true);
        final invalid = _nativePayload(sequence: 1)
          ..remove('responseBody')
          ..['responseBodyBytes'] = Uint8List.fromList([0xff]);

        await _sendNativeCapture(channel, invalid);

        expect(interruptions, 1);
        expect(accepted, isEmpty);
        expect(controller.state, GameCaptureState.ready);
        await _sendNativeCapture(channel, _nativePayload(sequence: 2));
        expect(accepted.single.path, '/kcsapi/api_req_map/next');
        expect(accepted.single.sequence, 2);
        expect(controller.state, GameCaptureState.capturing);
        expect(interruptions, 1);
      },
    );

    for (final failure in ['unsupported', 'configuration error']) {
      test('$failure notifies interruption', () async {
        var interruptions = 0;
        final port = _ContinuityCapturePort(
          supported: failure != 'unsupported',
          failConfiguration: failure == 'configuration error',
        );
        final controller = GameCaptureController(
          onCaptureInterrupted: () => interruptions += 1,
        );
        addTearDown(() async {
          controller.dispose();
          await port.close();
        });

        await controller.attach(port, enabled: true);

        expect(interruptions, greaterThan(0));
        expect(
          controller.state,
          failure == 'unsupported'
              ? GameCaptureState.unsupported
              : GameCaptureState.error,
        );
      });
    }

    for (final terminal in ['stream error', 'stream close']) {
      test('$terminal notifies interruption', () async {
        var interruptions = 0;
        final port = _ContinuityCapturePort();
        final controller = GameCaptureController(
          onCaptureInterrupted: () => interruptions += 1,
        );
        addTearDown(() async {
          controller.dispose();
          await port.close();
        });
        await controller.attach(port, enabled: true);
        expect(interruptions, 0);

        if (terminal == 'stream error') {
          port.fail();
        } else {
          await port.close();
        }

        expect(interruptions, greaterThan(0));
        expect(controller.state, GameCaptureState.error);
      });
    }

    for (final measuredBytes in [false, true]) {
      test(
        'oversized response notifies with declared bytes $measuredBytes',
        () async {
          var interruptions = 0;
          final accepted = <CapturedApiEvent>[];
          final port = _ContinuityCapturePort();
          final controller = GameCaptureController(
            maxResponseBytes: 64,
            onAcceptedEvent: accepted.add,
            onCaptureInterrupted: () => interruptions += 1,
          );
          addTearDown(() async {
            controller.dispose();
            await port.close();
          });
          await controller.attach(port, enabled: true);
          port.add(_event(sequence: 1));

          port.add(
            _event(
              sequence: 2,
              responseBody: measuredBytes
                  ? null
                  : List<String>.filled(65, 'x').join(),
              responseByteLength: measuredBytes ? 65 : null,
            ),
          );

          expect(interruptions, 1);
          expect(accepted.map((event) => event.sequence), [1]);
          expect(controller.latestEvent?.sequence, 1);
          port.add(_event(sequence: 3));
          expect(accepted.map((event) => event.sequence), [1, 3]);
          expect(interruptions, 1);
        },
      );
    }
  });

  group('queued capture invalidation boundaries', () {
    test(
      'drops only queued work and accepts subsequent current events',
      () async {
        final consumer = _ContinuityConsumer();
        final pipeline = GameApiEventPipeline(consumers: [consumer]);
        pipeline.add(_event(sequence: 1));

        pipeline.invalidateQueuedEvents();
        pipeline.add(_event(sequence: 2));
        await pipeline.idle;

        expect(consumer.events.map((event) => event.sequence), [2]);
      },
    );

    test('preserves the requirement for a successful login start', () async {
      final consumer = _ContinuityConsumer();
      final pipeline = GameApiEventPipeline(consumers: [consumer]);
      pipeline.invalidatePendingEvents(waitForLoginStart: true);

      pipeline.invalidateQueuedEvents();
      pipeline.add(_event(sequence: 1));
      pipeline.add(
        _event(
          path: '/kcsapi/api_start2/getData',
          sequence: 2,
          responseBody: '{"api_result":0,"api_data":{}}',
        ),
      );
      await pipeline.idle;
      expect(consumer.events, isEmpty);
      expect(pipeline.isCurrentDocument(_event(sequence: 3)), isFalse);
      pipeline.add(_event(path: '/kcsapi/api_start2/getData', sequence: 3));
      pipeline.add(_event(sequence: 4));
      await pipeline.idle;

      expect(consumer.events.map((event) => event.sequence), [3, 4]);
    });

    test('preserves active and retired document guards', () async {
      final consumer = _ContinuityConsumer();
      final pipeline = GameApiEventPipeline(consumers: [consumer]);
      pipeline.add(
        _event(
          path: '/kcsapi/api_start2/getData',
          document: 'old',
          documentStartedAt: 1000,
          sequence: 1,
        ),
      );
      pipeline.add(
        _event(
          path: '/kcsapi/api_start2/getData',
          document: 'current',
          documentStartedAt: 2000,
          sequence: 2,
        ),
      );
      await pipeline.idle;
      consumer.events.clear();

      pipeline.invalidateQueuedEvents();
      pipeline.add(
        _event(document: 'old', documentStartedAt: 1000, sequence: 3),
      );
      pipeline.add(
        _event(
          path: '/kcsapi/api_start2/getData',
          document: 'old',
          documentStartedAt: 1000,
          sequence: 4,
        ),
      );
      pipeline.add(_event(sequence: 5));
      final current = _event(
        document: 'current',
        documentStartedAt: 2000,
        sequence: 6,
      );
      pipeline.add(current);
      await pipeline.idle;

      expect(consumer.events.map((event) => event.sequence), [6]);
      expect(pipeline.isCurrentDocument(current), isTrue);
      expect(
        pipeline.isCurrentDocument(
          _event(document: 'old', documentStartedAt: 1000, sequence: 7),
        ),
        isFalse,
      );
    });

    test('preserves maintenance pause and resumed document cutoff', () async {
      final consumer = _ContinuityConsumer();
      final pipeline = GameApiEventPipeline(consumers: [consumer]);
      final oldTimestamp =
          DateTime.now().millisecondsSinceEpoch.toDouble() - 1000;
      pipeline.pauseForMaintenance();

      pipeline.invalidateQueuedEvents();
      pipeline.add(
        _event(
          path: '/kcsapi/api_start2/getData',
          document: 'during-maintenance',
          documentStartedAt: oldTimestamp,
          sequence: 1,
        ),
      );
      await pipeline.idle;
      expect(consumer.events, isEmpty);
      pipeline.resumeAfterMaintenance();
      pipeline.invalidateQueuedEvents();
      pipeline.add(_event(path: '/kcsapi/api_start2/getData', sequence: 2));
      pipeline.add(
        _event(
          path: '/kcsapi/api_start2/getData',
          document: 'old',
          documentStartedAt: oldTimestamp,
          sequence: 3,
        ),
      );
      pipeline.add(
        _event(
          path: '/kcsapi/api_start2/getData',
          document: 'fresh',
          documentStartedAt:
              DateTime.now().millisecondsSinceEpoch.toDouble() + 1000,
          sequence: 4,
        ),
      );
      await pipeline.idle;

      expect(consumer.events.map((event) => event.sequence), [4]);
    });
  });
}

CapturedApiEvent _event({
  String path = '/kcsapi/api_port/port',
  required int sequence,
  String? responseBody,
  int? responseByteLength,
  String? document,
  double? documentStartedAt,
}) => CapturedApiEvent(
  path: path,
  responseBody: responseBody ?? '{"api_result":1,"api_data":{}}',
  responseByteLength: responseByteLength,
  source: CaptureSource.xhr,
  capturedAt: DateTime.utc(2026, 10, 23),
  sequence: sequence,
  captureDocumentId: document,
  captureDocumentStartedAtEpochMs: documentStartedAt,
);

final class _ContinuityConsumer implements GameApiEventConsumer {
  final List<CapturedApiEvent> events = [];

  @override
  void accept(CapturedApiEvent event) => events.add(event);

  @override
  Future<void> get idle => Future<void>.value();

  @override
  bool supportsPath(String path) => true;
}

final class _ContinuityCapturePort
    implements GameCapturePort, GameCaptureContinuityPort {
  _ContinuityCapturePort({
    this.supported = true,
    this.failConfiguration = false,
  });

  final bool supported;
  final bool failConfiguration;
  final StreamController<CapturedApiEvent> _events =
      StreamController<CapturedApiEvent>.broadcast(sync: true);
  final StreamController<void> _interruptions =
      StreamController<void>.broadcast(sync: true);

  @override
  Stream<CapturedApiEvent> get events => _events.stream;

  @override
  Stream<void> get interruptions => _interruptions.stream;

  void add(CapturedApiEvent event) => _events.add(event);

  void fail() => _events.addError(StateError('capture stream failed'));

  void interrupt() => _interruptions.add(null);

  Future<void> close() async {
    if (!_events.isClosed) await _events.close();
    if (!_interruptions.isClosed) await _interruptions.close();
  }

  @override
  Future<void> configure({
    required bool enabled,
    required String script,
  }) async {
    if (failConfiguration) throw StateError('capture configuration failed');
  }

  @override
  Future<bool> isSupported() async => supported;

  @override
  void dispose() => unawaited(close());
}

Map<String, Object?> _nativePayload({required int sequence}) => {
  'version': 1,
  'kind': 'kcsapi_response',
  'method': 'POST',
  'path': '/kcsapi/api_req_map/next',
  'requestParams': <String, Object?>{},
  'responseBody': 'svdata={"api_result":1,"api_data":{}}',
  'statusCode': 200,
  'transport': 'xhr',
  'sourceOrigin': 'https://w01y.kancolle-server.com',
  'capturedAt': '2026-10-23T10:00:00.000Z',
  'sequence': sequence,
};

Future<void> _sendNativeCapture(
  MethodChannel channel,
  Map<String, Object?> payload,
) async {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final reply = Completer<void>();
  await messenger.handlePlatformMessage(
    channel.name,
    channel.codec.encodeMethodCall(MethodCall('onCaptureEvent', payload)),
    (_) => reply.complete(),
  );
  await reply.future;
  await Future<void>.delayed(Duration.zero);
}
