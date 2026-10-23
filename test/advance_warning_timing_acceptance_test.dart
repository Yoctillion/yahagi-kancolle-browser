import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_api_decoder.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_api_event_pipeline.dart';

import 'fixtures/kcsapi_fixtures.dart';

void main() {
  test('an event never added has no acceptance receipt', () async {
    final consumer = _RecordingConsumer();
    final pipeline = _pipeline(consumer);
    final event = kcsapiEvent(
      '/kcsapi/api_req_sortie/battleresult',
      <String, Object?>{},
    );

    expect(pipeline.wasEventAccepted(event), isFalse);
    await pipeline.dispatchIdle;
    expect(pipeline.wasEventAccepted(event), isFalse);
    expect(consumer.events, isEmpty);
  });

  for (final path in <String>[
    '/kcsapi/api_req_sortie/battleresult',
    '/kcsapi/api_req_combined_battle/battleresult',
    '/kcsapi/api_req_map/start',
    '/kcsapi/api_req_map/next',
  ]) {
    test(
      'successful $path grants only the original object a receipt',
      () async {
        final consumer = _RecordingConsumer();
        final pipeline = _pipeline(consumer);
        final event = kcsapiEvent(path, <String, Object?>{});

        pipeline.add(event);
        expect(pipeline.wasEventAccepted(event), isFalse);
        await pipeline.dispatchIdle;

        expect(consumer.events, hasLength(1));
        final prepared = consumer.events.single;
        expect(prepared.hasDecodedEnvelope, isTrue);
        expect(identical(prepared, event), isFalse);
        expect(pipeline.wasEventAccepted(event), isTrue);
        expect(pipeline.wasEventAccepted(prepared), isFalse);
      },
    );
  }

  test(
    'a rejected same-sequence copy does not inherit or erase a receipt',
    () async {
      final consumer = _RecordingConsumer();
      final pipeline = _pipeline(consumer);
      final accepted = kcsapiEvent(
        '/kcsapi/api_req_sortie/battleresult',
        <String, Object?>{},
        sequence: 10,
      );
      final duplicate = kcsapiEvent(
        '/kcsapi/api_req_sortie/battleresult',
        <String, Object?>{},
        sequence: 10,
      );
      final subsequent = kcsapiEvent(
        '/kcsapi/api_req_sortie/battleresult',
        <String, Object?>{},
        sequence: 11,
      );

      pipeline.add(accepted);
      await pipeline.dispatchIdle;
      expect(pipeline.wasEventAccepted(accepted), isTrue);
      expect(pipeline.wasEventAccepted(duplicate), isFalse);

      pipeline.add(duplicate);
      await pipeline.dispatchIdle;
      expect(consumer.events, hasLength(1));
      expect(pipeline.wasEventAccepted(duplicate), isFalse);
      expect(pipeline.wasEventAccepted(accepted), isTrue);

      pipeline.add(subsequent);
      await pipeline.dispatchIdle;
      expect(consumer.events, hasLength(2));
      expect(pipeline.wasEventAccepted(subsequent), isTrue);
      expect(pipeline.wasEventAccepted(accepted), isTrue);
      expect(pipeline.wasEventAccepted(duplicate), isFalse);
    },
  );

  test('api_result zero never grants an acceptance receipt', () async {
    final consumer = _RecordingConsumer();
    final pipeline = _pipeline(consumer);
    final rejected = kcsapiEvent(
      '/kcsapi/api_req_sortie/battleresult',
      <String, Object?>{},
      apiResult: 0,
    );
    final subsequent = kcsapiEvent(
      '/kcsapi/api_req_sortie/battleresult',
      <String, Object?>{},
      sequence: 2,
    );

    pipeline.add(rejected);
    await pipeline.dispatchIdle;
    expect(pipeline.isCurrentDocument(rejected), isTrue);
    expect(pipeline.wasEventAccepted(rejected), isFalse);
    expect(consumer.events, isEmpty);

    pipeline.add(subsequent);
    await pipeline.dispatchIdle;
    expect(pipeline.wasEventAccepted(subsequent), isTrue);
    expect(pipeline.wasEventAccepted(rejected), isFalse);
  });

  for (final responseBody in <String>['not-json', '[]', '{"api_data":{}}']) {
    test(
      'malformed envelope $responseBody has no acceptance receipt',
      () async {
        final consumer = _RecordingConsumer();
        final pipeline = _pipeline(consumer);
        final rejected = CapturedApiEvent(
          path: '/kcsapi/api_req_sortie/battleresult',
          responseBody: responseBody,
          source: CaptureSource.xhr,
          capturedAt: DateTime.utc(2026, 10, 23),
          sequence: 1,
        );
        final subsequent = kcsapiEvent(
          '/kcsapi/api_req_sortie/battleresult',
          <String, Object?>{},
          sequence: 2,
        );

        pipeline.add(rejected);
        await pipeline.dispatchIdle;
        expect(pipeline.wasEventAccepted(rejected), isFalse);

        pipeline.add(subsequent);
        await pipeline.dispatchIdle;
        expect(pipeline.wasEventAccepted(subsequent), isTrue);
        expect(pipeline.wasEventAccepted(rejected), isFalse);
      },
    );
  }

  test(
    'dispatch has no receipt until game-state settlement completes',
    () async {
      final consumer = _RecordingConsumer();
      final enteredSettlement = Completer<void>();
      final releaseSettlement = Completer<void>();
      addTearDown(() {
        if (!releaseSettlement.isCompleted) releaseSettlement.complete();
      });
      final pipeline = GameApiEventPipeline(
        consumers: <GameApiEventConsumer>[consumer],
        settleGameState: () {
          enteredSettlement.complete();
          return releaseSettlement.future;
        },
      );
      final event = kcsapiEvent(
        '/kcsapi/api_req_sortie/battleresult',
        <String, Object?>{},
      );

      pipeline.add(event);
      await enteredSettlement.future;
      expect(consumer.events, hasLength(1));
      expect(pipeline.wasEventAccepted(event), isFalse);

      releaseSettlement.complete();
      await pipeline.dispatchIdle;
      expect(pipeline.wasEventAccepted(event), isTrue);
    },
  );

  test(
    'a continuity interruption during settlement can never grant the old receipt',
    () async {
      final consumer = _RecordingConsumer();
      final enteredSettlement = Completer<void>();
      final releaseSettlement = Completer<void>();
      addTearDown(() {
        if (!releaseSettlement.isCompleted) releaseSettlement.complete();
      });
      final pipeline = GameApiEventPipeline(
        consumers: <GameApiEventConsumer>[consumer],
        settleGameState: () {
          if (!enteredSettlement.isCompleted) enteredSettlement.complete();
          return releaseSettlement.future;
        },
      );
      final interrupted = _documentEvent(
        '/kcsapi/api_req_sortie/battleresult',
        sequence: 1,
      );
      final subsequent = _documentEvent(
        '/kcsapi/api_req_sortie/battleresult',
        sequence: 2,
      );

      pipeline.add(interrupted);
      await enteredSettlement.future;
      pipeline.invalidateQueuedEvents();
      expect(consumer.interruptions, 1);
      expect(pipeline.isCurrentDocument(interrupted), isTrue);
      expect(pipeline.wasEventAccepted(interrupted), isFalse);

      releaseSettlement.complete();
      await pipeline.dispatchIdle;
      expect(pipeline.wasEventAccepted(interrupted), isFalse);
      pipeline.add(subsequent);
      await pipeline.dispatchIdle;
      expect(pipeline.wasEventAccepted(subsequent), isTrue);
      expect(pipeline.wasEventAccepted(interrupted), isFalse);
    },
  );

  final invalidations = <String, void Function(GameApiEventPipeline)>{
    'invalidateQueuedEvents': (pipeline) => pipeline.invalidateQueuedEvents(),
    'invalidatePendingEvents': (pipeline) => pipeline.invalidatePendingEvents(),
    'pauseForMaintenance': (pipeline) => pipeline.pauseForMaintenance(),
  };
  for (final invalidation in invalidations.entries) {
    test('${invalidation.key} revokes an already settled receipt', () async {
      final consumer = _RecordingConsumer();
      final pipeline = _pipeline(consumer);
      final event = _documentEvent(
        '/kcsapi/api_req_sortie/battleresult',
        sequence: 1,
      );

      pipeline.add(event);
      await pipeline.dispatchIdle;
      expect(pipeline.wasEventAccepted(event), isTrue);

      invalidation.value(pipeline);
      expect(pipeline.wasEventAccepted(event), isFalse);
      await pipeline.dispatchIdle;
      expect(pipeline.wasEventAccepted(event), isFalse);
    });
  }

  test(
    'a newer successful getData revokes receipts from the old document',
    () async {
      final consumer = _RecordingConsumer();
      final pipeline = _pipeline(consumer);
      final oldResult = _documentEvent(
        '/kcsapi/api_req_sortie/battleresult',
        sequence: 1,
        documentId: 'old-document',
        documentStartedAt: 1000,
      );
      final newLogin = _documentEvent(
        '/kcsapi/api_start2/getData',
        sequence: 1,
        documentId: 'new-document',
        documentStartedAt: 2000,
      );
      final staleResult = _documentEvent(
        '/kcsapi/api_req_sortie/battleresult',
        sequence: 2,
        documentId: 'old-document',
        documentStartedAt: 1000,
      );
      final newResult = _documentEvent(
        '/kcsapi/api_req_sortie/battleresult',
        sequence: 2,
        documentId: 'new-document',
        documentStartedAt: 2000,
      );

      pipeline.add(oldResult);
      await pipeline.dispatchIdle;
      expect(pipeline.wasEventAccepted(oldResult), isTrue);
      pipeline.add(newLogin);
      await pipeline.dispatchIdle;
      expect(pipeline.wasEventAccepted(newLogin), isTrue);
      expect(pipeline.isCurrentDocument(oldResult), isFalse);
      expect(pipeline.wasEventAccepted(oldResult), isFalse);

      pipeline.add(staleResult);
      pipeline.add(newResult);
      await pipeline.dispatchIdle;
      expect(pipeline.wasEventAccepted(staleResult), isFalse);
      expect(pipeline.wasEventAccepted(oldResult), isFalse);
      expect(pipeline.wasEventAccepted(newResult), isTrue);
      expect(consumer.events, hasLength(3));
    },
  );

  test(
    'a continuity guard rejection in the current document has no receipt',
    () async {
      final consumer = _RecordingConsumer();
      final pipeline = _pipeline(consumer);
      final login = _documentEvent('/kcsapi/api_start2/getData', sequence: 1);
      final rejected = _documentEvent(
        '/kcsapi/api_req_sortie/battleresult',
        sequence: 2,
      );
      final subsequent = _documentEvent(
        '/kcsapi/api_req_sortie/battleresult',
        sequence: 3,
      );
      pipeline.add(login);
      await pipeline.dispatchIdle;
      consumer.allowsEvents = false;

      pipeline.add(rejected);
      await pipeline.dispatchIdle;
      expect(pipeline.isCurrentDocument(rejected), isTrue);
      expect(pipeline.wasEventAccepted(rejected), isFalse);
      expect(consumer.events, hasLength(1));

      consumer.allowsEvents = true;
      pipeline.add(subsequent);
      await pipeline.dispatchIdle;
      expect(pipeline.wasEventAccepted(subsequent), isTrue);
      expect(pipeline.wasEventAccepted(rejected), isFalse);
      expect(consumer.events, hasLength(2));
    },
  );
}

GameApiEventPipeline _pipeline(_RecordingConsumer consumer) =>
    GameApiEventPipeline(
      consumers: <GameApiEventConsumer>[consumer],
      decodeEnvelope: (responseBody) async =>
          GameApiDecoder.decodeEnvelope(responseBody),
    );

CapturedApiEvent _documentEvent(
  String path, {
  required int sequence,
  String documentId = 'active-document',
  double documentStartedAt = 1000,
}) => CapturedApiEvent(
  path: path,
  responseBody: '{"api_result":1,"api_data":{}}',
  source: CaptureSource.xhr,
  capturedAt: DateTime.utc(2026, 10, 23),
  sequence: sequence,
  captureSessionId: 'active-capture-session',
  captureDocumentId: documentId,
  captureDocumentStartedAtEpochMs: documentStartedAt,
);

final class _RecordingConsumer
    implements GameApiEventConsumer, GameApiContinuityGuard {
  final List<CapturedApiEvent> events = <CapturedApiEvent>[];
  bool allowsEvents = true;
  int interruptions = 0;

  @override
  bool supportsPath(String path) => true;

  @override
  void accept(CapturedApiEvent event) => events.add(event);

  @override
  Future<void> get idle => Future<void>.value();

  @override
  void interruptCaptureContinuity() => interruptions++;

  @override
  bool allowsCaptureEvent(CapturedApiEvent event) => allowsEvents;
}
