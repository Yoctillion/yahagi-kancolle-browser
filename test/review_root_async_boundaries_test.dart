import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:yahagi_kancolle_browser/src/audio/game_audio_controller.dart';
import 'package:yahagi_kancolle_browser/src/audio/game_audio_port.dart';
import 'package:yahagi_kancolle_browser/src/audio/game_audio_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/screen_awake_controller.dart';
import 'package:yahagi_kancolle_browser/src/kcwiki_report/kcwiki_report_request.dart';
import 'package:yahagi_kancolle_browser/src/kcwiki_report/kcwiki_report_transport.dart';

void main() {
  test(
    'review: successful newer awake setting clears an obsolete rollback error',
    () async {
      final storage = _RollbackGateStore();
      final port = _AwakePort();
      final controller = await ScreenAwakeController.load(storage);
      addTearDown(controller.dispose);
      await controller.attachPort(port);
      final old = controller.setEnabled(true);
      await storage.rollbackStarted.future;
      final latest = controller.setEnabled(true);
      storage.rollbackRelease.complete();
      await Future.wait([old, latest]);
      expect(storage.saved, isTrue);
      expect(controller.enabled, isTrue);
      expect(port.value, isTrue);
      expect(controller.errorMessage, isNull);
    },
  );

  test(
    'review: successful newer audio policy clears an obsolete rollback error',
    () async {
      final storage = _RollbackGateStore();
      final port = _AudioPort();
      final controller = await GameAudioController.load(storage);
      addTearDown(controller.dispose);
      await controller.attachPort(port);
      final old = controller.setBackgroundPlaybackEnabled(true);
      await storage.rollbackStarted.future;
      final latest = controller.setBackgroundPlaybackEnabled(true);
      storage.rollbackRelease.complete();
      await Future.wait([old, latest]);
      expect(storage.saved, isTrue);
      expect(controller.backgroundPlaybackEnabled, isTrue);
      expect(port.value, isFalse);
      expect(controller.errorMessage, isNull);
    },
  );

  for (final lateHeaders in [false, true]) {
    test(
      'review: HTTP cancellation future errors are absorbed, late=$lateHeaders',
      () {
        fakeAsync((clock) {
          final client = _CancelErrorClient(lateHeaders: lateHeaders);
          final transport = HttpKcwikiReportTransport(
            client: client,
            baseUri: Uri.parse('https://example.test'),
            timeout: const Duration(seconds: 1),
          );
          KcwikiTransportResult? result;
          transport.send(_request()).then((value) => result = value);
          clock.flushMicrotasks();
          clock.elapse(const Duration(seconds: 2));
          expect(result?.failure, KcwikiTransportFailure.timeout);
          if (lateHeaders) {
            client.headers.complete(
              http.StreamedResponse(client.body.stream, 200),
            );
          }
          clock.flushMicrotasks();
          expect(client.cancels, 1);
          transport.close();
          clock.flushMicrotasks();
        });
      },
    );
  }

  test('review: HTTP body error aborts and clears its deadline', () {
    fakeAsync((clock) {
      final client = _CancelErrorClient(lateHeaders: false);
      final transport = HttpKcwikiReportTransport(
        client: client,
        baseUri: Uri.parse('https://example.test'),
      );
      KcwikiTransportResult? result;
      transport.send(_request()).then((value) => result = value);
      clock.flushMicrotasks();
      client.body.addError(StateError('body failed'));
      clock.flushMicrotasks();
      expect(result?.failure, KcwikiTransportFailure.network);
      expect(clock.nonPeriodicTimerCount, 0);
      expect(client.cancels, 1);
      transport.close();
    });
  });

  test('review: slow headers and body share one absolute HTTP deadline', () {
    fakeAsync((clock) {
      final client = _CancelErrorClient(lateHeaders: true);
      final transport = HttpKcwikiReportTransport(
        client: client,
        baseUri: Uri.parse('https://example.test'),
        timeout: const Duration(seconds: 8),
      );
      KcwikiTransportResult? result;
      transport.send(_request()).then((value) => result = value);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 6));
      client.headers.complete(http.StreamedResponse(client.body.stream, 200));
      clock.flushMicrotasks();
      client.body.add([1]);
      clock.elapse(const Duration(seconds: 3));
      expect(result?.failure, KcwikiTransportFailure.timeout);
      expect(client.cancels, 1);
      transport.close();
    });
  });

  test('review: header errors arriving after deadline are consumed', () {
    fakeAsync((clock) {
      final client = _CancelErrorClient(lateHeaders: true);
      final transport = HttpKcwikiReportTransport(
        client: client,
        baseUri: Uri.parse('https://example.test'),
        timeout: const Duration(seconds: 1),
      );
      final results = <KcwikiTransportResult>[];
      transport.send(_request()).then(results.add);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 2));
      client.headers.completeError(StateError('headers failed late'));
      clock.flushMicrotasks();
      expect(results, hasLength(1));
      expect(results.single.failure, KcwikiTransportFailure.timeout);
      expect(clock.nonPeriodicTimerCount, 0);
      transport.close();
    });
  });

  test(
    'review: old audio support result cannot suppress a supported replacement',
    () async {
      final old = _LateSupportAudioPort();
      final controller = await GameAudioController.load(_RollbackGateStore());
      addTearDown(controller.dispose);
      final first = controller.attachPort(old);
      await old.started.future;
      final replacement = _AudioPort();
      final second = controller.attachPort(replacement);
      old.supported.complete(false);
      await Future.wait([first, second]);
      expect(controller.availability, GameAudioAvailability.available);
      expect(controller.errorMessage, isNull);
    },
  );
}

class _RollbackGateStore implements ScreenAwakeStore, GameAudioStore {
  bool saved = false;
  int writes = 0;
  final rollbackStarted = Completer<void>();
  final rollbackRelease = Completer<void>();
  @override
  Future<bool?> readEnabled() async => saved;
  @override
  Future<bool?> readMuted() async => false;
  @override
  Future<bool?> readBackgroundPlaybackEnabled() async => saved;
  @override
  Future<void> writeMuted(bool value) async {}
  @override
  Future<void> writeBackgroundPlaybackEnabled(bool value) =>
      writeEnabled(value);
  @override
  Future<void> writeEnabled(bool value) async {
    writes++;
    if (writes == 1) throw StateError('initial persistence failed');
    if (writes == 2) {
      rollbackStarted.complete();
      await rollbackRelease.future;
    }
    saved = value;
  }
}

class _AwakePort implements ScreenAwakePort {
  bool value = false;
  @override
  Future<bool> isEnabled() async => value;
  @override
  Future<void> setEnabled(bool enabled) async => value = enabled;
}

class _AudioPort implements GameAudioPort {
  bool value = false;
  @override
  Future<bool> isSupported() async => true;
  @override
  Future<void> setMuted(bool muted) async => value = muted;
}

class _LateSupportAudioPort extends _AudioPort {
  final started = Completer<void>();
  final supported = Completer<bool>();
  @override
  Future<bool> isSupported() {
    started.complete();
    return supported.future;
  }
}

KcwikiReportRequest _request() =>
    KcwikiReportRequest.form(KcwikiReportModule.quest, {});

class _CancelErrorClient extends http.BaseClient {
  _CancelErrorClient({required this.lateHeaders}) {
    body = StreamController<List<int>>(
      onCancel: () async {
        cancels++;
        throw StateError('cancellation failed');
      },
    );
  }
  final bool lateHeaders;
  int cancels = 0;
  final headers = Completer<http.StreamedResponse>();
  late final StreamController<List<int>> body;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      lateHeaders ? headers.future : http.StreamedResponse(body.stream, 200);
}
