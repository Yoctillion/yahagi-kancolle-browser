import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_controller.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_port.dart';

void main() {
  group('GameCaptureController', () {
    test('game mode configures the port and forwards valid events', () async {
      final port = _FakeGameCapturePort(supported: true);
      final forwarded = <CapturedApiEvent>[];
      final controller = GameCaptureController(onAcceptedEvent: forwarded.add);
      addTearDown(() async {
        controller.dispose();
        await port.close();
      });

      await controller.attach(port, enabled: true);
      port.emit(_event(sequence: 1));
      await Future<void>.delayed(Duration.zero);

      expect(port.configurations, <bool>[true]);
      expect(controller.state, GameCaptureState.capturing);
      expect(controller.latestEvent?.sequence, 1);
      expect(controller.capturedCount, 1);
      expect(forwarded.single.sequence, 1);
    });

    test('browser-only mode rejects events arriving after disable', () async {
      final port = _FakeGameCapturePort(supported: true);
      final controller = GameCaptureController();
      addTearDown(() async {
        controller.dispose();
        await port.close();
      });

      await controller.attach(port, enabled: true);
      await controller.configure(enabled: false);
      port.emit(_event(sequence: 1));
      await Future<void>.delayed(Duration.zero);

      expect(controller.state, GameCaptureState.disabled);
      expect(controller.latestEvent, isNull);
    });

    test('unsupported platform keeps a stable unsupported state', () async {
      final port = _FakeGameCapturePort(supported: false);
      final controller = GameCaptureController();
      addTearDown(() async {
        controller.dispose();
        await port.close();
      });

      await controller.attach(port, enabled: true);

      expect(controller.state, GameCaptureState.unsupported);
      expect(port.configurations, isEmpty);
    });

    test('repeated configuration is idempotent', () async {
      final port = _FakeGameCapturePort(supported: true);
      final controller = GameCaptureController();
      addTearDown(() async {
        controller.dispose();
        await port.close();
      });

      await controller.attach(port, enabled: true);
      await controller.configure(enabled: true);
      await controller.configure(enabled: false);
      await controller.configure(enabled: false);

      expect(port.configurations, <bool>[true, false]);
    });

    test('forced configuration rebinds a surviving platform port', () async {
      final port = _FakeGameCapturePort(supported: true);
      final controller = GameCaptureController();
      addTearDown(() async {
        controller.dispose();
        await port.close();
      });

      await controller.attach(port, enabled: true, script: 'capture');
      await controller.configure(enabled: true, force: true);
      await controller.configure(enabled: true);
      port.emit(_event(sequence: 2));
      await Future<void>.delayed(Duration.zero);

      expect(port.configurations, <bool>[true, true]);
      expect(controller.latestEvent?.sequence, 2);
      expect(controller.state, GameCaptureState.capturing);
    });

    test(
      'forced same-port rebind proceeds before an old install replies',
      () async {
        final oldReply = Completer<void>();
        final port = _FakeGameCapturePort(
          supported: true,
          configureBlocker: oldReply,
          recordConfigureOnCompletion: true,
        );
        final forwarded = <CapturedApiEvent>[];
        final controller = GameCaptureController(
          onAcceptedEvent: forwarded.add,
        );
        addTearDown(() async {
          controller.dispose();
          if (!oldReply.isCompleted) oldReply.complete();
          await port.close();
        });

        final oldAttach = controller.attach(
          port,
          enabled: true,
          script: 'capture',
        );
        await port.waitForConfigureCalls(1);
        await controller
            .configure(enabled: true, force: true)
            .timeout(const Duration(seconds: 1));
        await oldAttach;
        expect(port.configureCalls, 2);
        expect(controller.state, GameCaptureState.ready);

        port.emit(_event(sequence: 1));
        await Future<void>.delayed(Duration.zero);
        oldReply.complete();
        await Future<void>.delayed(Duration.zero);

        expect(port.configureCalls, 2);
        expect(port.appliedScript, 'capture');
        expect(controller.state, GameCaptureState.capturing);
        expect(controller.latestEvent?.sequence, 1);
        expect(forwarded.map((event) => event.sequence), <int>[1]);
      },
    );

    test(
      'forced disabled mode reaches the port again and rejects events',
      () async {
        final port = _FakeGameCapturePort(supported: true);
        final forwarded = <CapturedApiEvent>[];
        final controller = GameCaptureController(
          onAcceptedEvent: forwarded.add,
        );
        addTearDown(() async {
          controller.dispose();
          await port.close();
        });

        await controller.attach(port, enabled: false, script: 'capture');
        await controller.configure(enabled: false, force: true);
        await controller.configure(enabled: false);
        port.emit(_event(sequence: 1));
        await Future<void>.delayed(Duration.zero);

        expect(port.configurations, <bool>[false, false]);
        expect(port.configurationScripts, <String>['', '']);
        expect(port.appliedEnabled, false);
        expect(controller.state, GameCaptureState.disabled);
        expect(controller.latestEvent, isNull);
        expect(controller.capturedCount, 0);
        expect(forwarded, isEmpty);
      },
    );

    test('failed forced install remains retryable without force', () async {
      final initialReply = Completer<void>()..complete();
      final failedReply = Completer<void>();
      final port = _FakeGameCapturePort(
        supported: true,
        configureBlockers: <Completer<void>>[initialReply, failedReply],
      );
      final forwarded = <CapturedApiEvent>[];
      final controller = GameCaptureController(onAcceptedEvent: forwarded.add);
      addTearDown(() async {
        controller.dispose();
        if (!failedReply.isCompleted) failedReply.complete();
        await port.close();
      });

      await controller.attach(port, enabled: true, script: 'capture');
      final rebind = controller.configure(enabled: true, force: true);
      await port.waitForConfigureCalls(2);
      failedReply.completeError(StateError('replacement WebView disappeared'));
      await rebind;

      expect(controller.state, GameCaptureState.error);
      expect(controller.errorMessage, contains('StateError'));
      await controller.configure(enabled: true);
      expect(port.configureCalls, 3);
      expect(controller.state, GameCaptureState.ready);
      expect(controller.errorMessage, isNull);
      port.emit(_event(sequence: 1));
      await Future<void>.delayed(Duration.zero);
      expect(forwarded.map((event) => event.sequence), <int>[1]);
    });

    test('failed forced disable remains retryable without force', () async {
      final initialReply = Completer<void>()..complete();
      final failedReply = Completer<void>();
      final port = _FakeGameCapturePort(
        supported: true,
        configureBlockers: <Completer<void>>[initialReply, failedReply],
      );
      final controller = GameCaptureController();
      addTearDown(() async {
        controller.dispose();
        if (!failedReply.isCompleted) failedReply.complete();
        await port.close();
      });

      await controller.attach(port, enabled: false, script: 'capture');
      final rebind = controller.configure(enabled: false, force: true);
      await port.waitForConfigureCalls(2);
      failedReply.completeError(StateError('disable command failed'));
      await rebind;
      expect(controller.state, GameCaptureState.error);

      await controller.configure(enabled: false);
      expect(port.configurations, <bool>[false, false, false]);
      expect(controller.state, GameCaptureState.disabled);
      expect(controller.errorMessage, isNull);
    });

    test('late older force cannot cache a newer failed binding', () async {
      final initialReply = Completer<void>()..complete();
      final olderReply = Completer<void>();
      final newerReply = Completer<void>();
      final port = _FakeGameCapturePort(
        supported: true,
        configureBlockers: <Completer<void>>[
          initialReply,
          olderReply,
          newerReply,
        ],
      );
      final controller = GameCaptureController();
      addTearDown(() async {
        controller.dispose();
        if (!olderReply.isCompleted) olderReply.complete();
        if (!newerReply.isCompleted) newerReply.complete();
        await port.close();
      });

      await controller.attach(port, enabled: true, script: 'capture');
      final olderRebind = controller.configure(enabled: true, force: true);
      await port.waitForConfigureCalls(2);
      final newerRebind = controller.configure(enabled: true, force: true);
      await port.waitForConfigureCalls(3);
      newerReply.completeError(StateError('new binding failed'));
      await Future.wait(<Future<void>>[olderRebind, newerRebind]);
      expect(controller.state, GameCaptureState.error);

      olderReply.complete();
      await Future<void>.delayed(Duration.zero);
      expect(controller.state, GameCaptureState.error);
      expect(port.configureCalls, 3);
      await controller.configure(enabled: true);

      expect(port.configureCalls, 4);
      expect(controller.state, GameCaptureState.ready);
      expect(controller.errorMessage, isNull);
    });

    test(
      'dispose completes a forced rebind and ignores its late reply',
      () async {
        final initialReply = Completer<void>()..complete();
        final lateReply = Completer<void>();
        final port = _FakeGameCapturePort(
          supported: true,
          configureBlockers: <Completer<void>>[initialReply, lateReply],
        );
        final forwarded = <CapturedApiEvent>[];
        final controller = GameCaptureController(
          onAcceptedEvent: forwarded.add,
        );
        addTearDown(() async {
          controller.dispose();
          if (!lateReply.isCompleted) lateReply.complete();
          await port.close();
        });

        await controller.attach(port, enabled: true, script: 'capture');
        final rebind = controller.configure(enabled: true, force: true);
        await port.waitForConfigureCalls(2);
        controller.dispose();
        await rebind.timeout(const Duration(seconds: 1));
        lateReply.complete();
        port.emit(_event(sequence: 1));
        await Future<void>.delayed(Duration.zero);

        expect(port.configureCalls, 2);
        expect(forwarded, isEmpty);
        expect(controller.capturedCount, 0);
      },
    );

    test(
      'late forced install replays the newer script on the same port',
      () async {
        final initialReply = Completer<void>()..complete();
        final oldReply = Completer<void>();
        final port = _FakeGameCapturePort(
          supported: true,
          configureBlockers: <Completer<void>>[initialReply, oldReply],
          recordConfigureOnCompletion: true,
        );
        final controller = GameCaptureController();
        addTearDown(() async {
          controller.dispose();
          if (!oldReply.isCompleted) oldReply.complete();
          await port.close();
        });

        await controller.attach(port, enabled: true, script: 'old');
        final oldRebind = controller.configure(enabled: true, force: true);
        await port.waitForConfigureCalls(2);
        await controller.configure(enabled: true, script: 'new');
        await oldRebind;
        expect(port.appliedScript, 'new');

        oldReply.complete();
        await port.waitForConfigureCalls(4);
        await Future<void>.delayed(Duration.zero);

        expect(port.configurationScripts, <String>['old', 'new', 'old', 'new']);
        expect(port.appliedScript, 'new');
        expect(controller.state, GameCaptureState.ready);
        port.emit(_event(sequence: 1));
        await Future<void>.delayed(Duration.zero);
        expect(controller.latestEvent?.sequence, 1);
      },
    );

    test('late forced install cannot restore capture after disable', () async {
      final initialReply = Completer<void>()..complete();
      final oldReply = Completer<void>();
      final port = _FakeGameCapturePort(
        supported: true,
        configureBlockers: <Completer<void>>[initialReply, oldReply],
        recordConfigureOnCompletion: true,
      );
      final forwarded = <CapturedApiEvent>[];
      final controller = GameCaptureController(onAcceptedEvent: forwarded.add);
      addTearDown(() async {
        controller.dispose();
        if (!oldReply.isCompleted) oldReply.complete();
        await port.close();
      });

      await controller.attach(port, enabled: true, script: 'capture');
      final oldRebind = controller.configure(enabled: true, force: true);
      await port.waitForConfigureCalls(2);
      await controller.configure(enabled: false, force: true);
      await oldRebind;
      expect(port.appliedEnabled, false);

      oldReply.complete();
      await port.waitForConfigureCalls(4);
      await Future<void>.delayed(Duration.zero);
      port.emit(_event(sequence: 1));
      await Future<void>.delayed(Duration.zero);

      expect(port.configurations, <bool>[true, false, true, false]);
      expect(port.appliedEnabled, false);
      expect(port.appliedScript, '');
      expect(controller.state, GameCaptureState.disabled);
      expect(controller.latestEvent, isNull);
      expect(forwarded, isEmpty);
    });

    test('late failed forced install cannot poison a newer capture', () async {
      final initialReply = Completer<void>()..complete();
      final oldReply = Completer<void>();
      final port = _FakeGameCapturePort(
        supported: true,
        configureBlockers: <Completer<void>>[initialReply, oldReply],
      );
      final controller = GameCaptureController();
      addTearDown(() async {
        controller.dispose();
        if (!oldReply.isCompleted) oldReply.complete();
        await port.close();
      });

      await controller.attach(port, enabled: true, script: 'old');
      final oldRebind = controller.configure(enabled: true, force: true);
      await port.waitForConfigureCalls(2);
      await controller.configure(enabled: true, script: 'new');
      await oldRebind;
      port.emit(_event(sequence: 1));
      await Future<void>.delayed(Duration.zero);

      oldReply.completeError(StateError('old replacement failed late'));
      await Future<void>.delayed(Duration.zero);

      expect(port.appliedScript, 'new');
      expect(controller.errorMessage, isNull);
      expect(controller.state, GameCaptureState.capturing);
      expect(controller.latestEvent?.sequence, 1);
      expect(controller.capturedCount, 1);
    });

    test('forced rebind preserves events arriving before its reply', () async {
      final initialReply = Completer<void>()..complete();
      final rebindReply = Completer<void>();
      final port = _FakeGameCapturePort(
        supported: true,
        configureBlockers: <Completer<void>>[initialReply, rebindReply],
      );
      final forwarded = <CapturedApiEvent>[];
      final controller = GameCaptureController(onAcceptedEvent: forwarded.add);
      addTearDown(() async {
        controller.dispose();
        if (!rebindReply.isCompleted) rebindReply.complete();
        await port.close();
      });

      await controller.attach(port, enabled: true, script: 'capture');
      port.emit(_event(sequence: 1));
      await Future<void>.delayed(Duration.zero);
      final rebind = controller.configure(enabled: true, force: true);
      await port.waitForConfigureCalls(2);
      port.emit(_event(sequence: 2));
      await Future<void>.delayed(Duration.zero);
      rebindReply.complete();
      await rebind;

      expect(forwarded.map((event) => event.sequence), <int>[1, 2]);
      expect(controller.capturedCount, 2);
      expect(controller.latestEvent?.sequence, 2);
      expect(controller.state, GameCaptureState.capturing);
    });

    for (final force in <bool>[false, true]) {
      test('${force ? 'forced' : 'ordinary'} capture check preserves events '
          'while support reply is pending', () async {
        final initialSupport = Completer<bool>()..complete(true);
        final pendingSupport = Completer<bool>();
        final port = _FakeGameCapturePort(
          supported: true,
          supportBlockers: <Completer<bool>>[initialSupport, pendingSupport],
        );
        final forwarded = <CapturedApiEvent>[];
        final controller = GameCaptureController(
          onAcceptedEvent: forwarded.add,
        );
        addTearDown(() async {
          controller.dispose();
          if (!pendingSupport.isCompleted) pendingSupport.complete(true);
          await port.close();
        });

        await controller.attach(port, enabled: true, script: 'capture');
        port.emit(_event(sequence: 1));
        await Future<void>.delayed(Duration.zero);
        final check = controller.configure(enabled: true, force: force);
        await port.waitForSupportCalls(2);
        port.emit(_event(sequence: 2));
        await Future<void>.delayed(Duration.zero);

        expect(forwarded.map((event) => event.sequence), <int>[1, 2]);
        pendingSupport.complete(true);
        await check;
        expect(controller.latestEvent?.sequence, 2);
        expect(controller.capturedCount, 2);
        expect(port.configureCalls, force ? 2 : 1);
      });
    }

    test(
      'late old-port completion is followed by the latest port mode',
      () async {
        final blocked = Completer<void>();
        final oldPort = _FakeGameCapturePort(
          supported: true,
          configureBlocker: blocked,
        );
        final newPort = _FakeGameCapturePort(supported: true);
        final controller = GameCaptureController();
        addTearDown(() async {
          controller.dispose();
          await oldPort.close();
          await newPort.close();
        });

        final oldAttach = controller.attach(oldPort, enabled: true);
        await Future<void>.delayed(Duration.zero);
        final newAttach = controller.attach(newPort, enabled: false);
        blocked.complete();
        await Future.wait(<Future<void>>[oldAttach, newAttach]);
        for (
          var index = 0;
          index < 5 && newPort.configurations.isEmpty;
          index++
        ) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(oldPort.configurations, <bool>[true]);
        expect(newPort.configurations, <bool>[false]);
        expect(controller.state, GameCaptureState.disabled);
      },
    );

    test('new port proceeds while an old configure never completes', () async {
      final blocked = Completer<void>();
      final oldPort = _FakeGameCapturePort(
        supported: true,
        configureBlocker: blocked,
      );
      final newPort = _FakeGameCapturePort(supported: true);
      final controller = GameCaptureController();
      addTearDown(() async {
        if (!blocked.isCompleted) blocked.complete();
        controller.dispose();
        await oldPort.close();
        await newPort.close();
      });

      final oldAttach = controller.attach(oldPort, enabled: true);
      await Future<void>.delayed(Duration.zero);
      await controller
          .attach(newPort, enabled: false)
          .timeout(const Duration(milliseconds: 100));
      await oldAttach;

      expect(newPort.configurations, <bool>[false]);
      expect(controller.state, GameCaptureState.disabled);
    });

    test(
      'late old side effect replays the final new-port configuration',
      () async {
        final blocked = Completer<void>();
        final oldPort = _FakeGameCapturePort(
          supported: true,
          configureBlocker: blocked,
          recordConfigureOnCompletion: true,
        );
        final newPort = _FakeGameCapturePort(supported: true);
        final controller = GameCaptureController();
        addTearDown(() async {
          if (!blocked.isCompleted) blocked.complete();
          controller.dispose();
          await oldPort.close();
          await newPort.close();
        });

        final oldAttach = controller.attach(oldPort, enabled: true);
        await Future<void>.delayed(Duration.zero);
        await controller.attach(newPort, enabled: false);
        blocked.complete();
        await oldAttach;
        for (
          var index = 0;
          index < 5 && newPort.configurations.length < 2;
          index++
        ) {
          await Future<void>.delayed(Duration.zero);
        }

        expect(oldPort.configurations, <bool>[true]);
        expect(newPort.configurations, <bool>[false, false]);
        expect(controller.state, GameCaptureState.disabled);
      },
    );

    test(
      'multiple stale completions coalesce into one latest repair',
      () async {
        final firstBlocker = Completer<void>();
        final secondBlocker = Completer<void>();
        final oldPort = _FakeGameCapturePort(
          supported: true,
          configureBlockers: <Completer<void>>[firstBlocker, secondBlocker],
          recordConfigureOnCompletion: true,
        );
        final newPort = _FakeGameCapturePort(supported: true);
        final controller = GameCaptureController();
        addTearDown(() async {
          if (!firstBlocker.isCompleted) firstBlocker.complete();
          if (!secondBlocker.isCompleted) secondBlocker.complete();
          controller.dispose();
          await oldPort.close();
          await newPort.close();
        });

        final first = controller.attach(oldPort, enabled: true, script: 'old');
        await Future<void>.delayed(Duration.zero);
        final second = controller.configure(enabled: false);
        await Future<void>.delayed(Duration.zero);
        final latest = controller.attach(newPort, enabled: false);
        await latest;

        firstBlocker.complete();
        secondBlocker.complete();
        await Future.wait(<Future<void>>[first, second]);
        for (
          var index = 0;
          index < 10 && newPort.configurations.length < 2;
          index++
        ) {
          await Future<void>.delayed(Duration.zero);
        }

        expect(oldPort.configurations, <bool>[true, false]);
        expect(newPort.configurations, <bool>[false, false]);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        expect(newPort.configurations, hasLength(2));
        expect(controller.state, GameCaptureState.disabled);
      },
    );

    test(
      'a current never-ending configure times out without hanging',
      () async {
        final blocked = Completer<void>();
        final port = _FakeGameCapturePort(
          supported: true,
          configureBlocker: blocked,
        );
        final controller = GameCaptureController(
          operationTimeout: const Duration(milliseconds: 1),
        );
        addTearDown(() async {
          blocked.complete();
          controller.dispose();
          await port.close();
        });

        await controller.attach(port, enabled: true);

        expect(controller.state, GameCaptureState.error);
        expect(controller.errorMessage, contains('TimeoutException'));
      },
    );

    test(
      'rapid same-port changes replay the latest mode after a late call',
      () async {
        final blocked = Completer<void>();
        final port = _FakeGameCapturePort(
          supported: true,
          configureBlocker: blocked,
        );
        final controller = GameCaptureController();
        addTearDown(() async {
          controller.dispose();
          await port.close();
        });

        final attach = controller.attach(port, enabled: true);
        await Future<void>.delayed(Duration.zero);
        final disable = controller.configure(enabled: false);
        blocked.complete();
        await Future.wait(<Future<void>>[attach, disable]);

        expect(port.configurations, <bool>[true, false]);
        expect(controller.state, GameCaptureState.disabled);
      },
    );

    test(
      'retains only the latest event and exposes a lightweight count',
      () async {
        final port = _FakeGameCapturePort(supported: true);
        final controller = GameCaptureController(maxResponseBytes: 8);
        addTearDown(() async {
          controller.dispose();
          await port.close();
        });

        await controller.attach(port, enabled: true);
        port
          ..emit(_event(sequence: 1, body: '1234'))
          ..emit(_event(sequence: 2, body: '5678'))
          ..emit(_event(sequence: 3, body: 'abc'));
        await Future<void>.delayed(Duration.zero);

        expect(controller.latestEvent?.sequence, 3);
        expect(controller.latestEvent?.responseBody, 'abc');
        expect(controller.capturedCount, 3);
        expect(controller.responseBytes, 3);
      },
    );

    test(
      'separates per-event activity from capture status notifications',
      () async {
        final port = _FakeGameCapturePort(supported: true);
        final controller = GameCaptureController();
        addTearDown(() async {
          controller.dispose();
          await port.close();
        });

        var statusNotifications = 0;
        var eventNotifications = 0;
        controller.addListener(() => statusNotifications++);
        controller.eventActivity.addListener(() => eventNotifications++);

        await controller.attach(port, enabled: true);
        final statusBeforeEvents = statusNotifications;
        port
          ..emit(_event(sequence: 1))
          ..emit(_event(sequence: 2));
        await Future<void>.delayed(Duration.zero);

        expect(statusNotifications - statusBeforeEvents, 1);
        expect(eventNotifications, 2);
        expect(controller.capturedCount, 2);
      },
    );

    test(
      'synchronous event stream listen failure completes attach safely',
      () async {
        final port = _FakeGameCapturePort(
          supported: true,
          eventsFailure: StateError('listen failed'),
        );
        final controller = GameCaptureController();
        addTearDown(controller.dispose);

        await controller.attach(port, enabled: true);

        expect(controller.state, GameCaptureState.error);
        expect(port.configurations, isEmpty);
        expect(controller.errorMessage, contains('StateError'));
      },
    );

    test('event stream errors become a terminal capture error', () async {
      final port = _FakeGameCapturePort(supported: true);
      final controller = GameCaptureController();
      addTearDown(() async {
        controller.dispose();
        await port.close();
      });
      await controller.attach(port, enabled: true);

      port.emitError(StateError('stream failed'));
      await Future<void>.delayed(Duration.zero);

      expect(controller.state, GameCaptureState.error);
      expect(controller.errorMessage, contains('StateError'));
    });

    test('event stream terminal releases an in-flight attach waiter', () async {
      final configureBlocker = Completer<void>();
      final port = _FakeGameCapturePort(
        supported: true,
        configureBlocker: configureBlocker,
      );
      final controller = GameCaptureController();
      addTearDown(() async {
        if (!configureBlocker.isCompleted) configureBlocker.complete();
        controller.dispose();
        await port.close();
      });
      final attach = controller.attach(port, enabled: true);
      await Future<void>.delayed(Duration.zero);

      port.emitError(StateError('stream failed during configure'));
      await attach.timeout(const Duration(milliseconds: 100));

      expect(controller.state, GameCaptureState.error);
      configureBlocker.complete();
    });

    test('event stream completion becomes a terminal capture error', () async {
      final port = _FakeGameCapturePort(supported: true);
      final controller = GameCaptureController();
      addTearDown(controller.dispose);
      await controller.attach(port, enabled: true);

      await port.close();
      await Future<void>.delayed(Duration.zero);

      expect(controller.state, GameCaptureState.error);
      expect(controller.errorMessage, isNotEmpty);
    });
  });
}

CapturedApiEvent _event({required int sequence, String body = '{}'}) {
  return CapturedApiEvent(
    method: 'POST',
    path: '/kcsapi/api_port/port',
    requestParams: const <String, Object?>{},
    responseBody: body,
    statusCode: 200,
    source: CaptureSource.xhr,
    sourceOrigin: 'https://w01y.kancolle-server.com',
    capturedAt: DateTime.utc(2026, 7, 30),
    sequence: sequence,
  );
}

final class _FakeGameCapturePort implements GameCapturePort {
  _FakeGameCapturePort({
    required this.supported,
    this.configureBlocker,
    this.configureBlockers = const <Completer<void>>[],
    this.supportBlockers = const <Completer<bool>>[],
    this.eventsFailure,
    this.recordConfigureOnCompletion = false,
  });

  final bool supported;
  final Completer<void>? configureBlocker;
  final List<Completer<void>> configureBlockers;
  final List<Completer<bool>> supportBlockers;
  final Object? eventsFailure;
  final bool recordConfigureOnCompletion;
  final StreamController<CapturedApiEvent> _events =
      StreamController<CapturedApiEvent>.broadcast();

  final List<bool> configurations = <bool>[];
  final List<String> configurationScripts = <String>[];
  final Map<int, Completer<void>> _configureCallWaiters =
      <int, Completer<void>>{};
  final Map<int, Completer<void>> _supportCallWaiters =
      <int, Completer<void>>{};
  bool? appliedEnabled;
  String? appliedScript;
  int configureCalls = 0;
  int supportCalls = 0;

  @override
  Stream<CapturedApiEvent> get events {
    final failure = eventsFailure;
    if (failure != null) throw failure;
    return _events.stream;
  }

  @override
  Future<void> configure({
    required bool enabled,
    required String script,
  }) async {
    configureCalls += 1;
    _configureCallWaiters.remove(configureCalls)?.complete();
    if (!recordConfigureOnCompletion) {
      configurations.add(enabled);
      configurationScripts.add(script);
    }
    if (configureCalls <= configureBlockers.length) {
      await configureBlockers[configureCalls - 1].future;
    } else if (configureCalls == 1) {
      await configureBlocker?.future;
    }
    if (recordConfigureOnCompletion) {
      configurations.add(enabled);
      configurationScripts.add(script);
    }
    appliedEnabled = enabled;
    appliedScript = script;
  }

  Future<void> waitForConfigureCalls(int count) {
    if (configureCalls >= count) return Future<void>.value();
    return _configureCallWaiters
        .putIfAbsent(count, Completer<void>.new)
        .future
        .timeout(const Duration(seconds: 1));
  }

  @override
  Future<bool> isSupported() async {
    supportCalls += 1;
    _supportCallWaiters.remove(supportCalls)?.complete();
    if (supportCalls <= supportBlockers.length) {
      return supportBlockers[supportCalls - 1].future;
    }
    return supported;
  }

  Future<void> waitForSupportCalls(int count) {
    if (supportCalls >= count) return Future<void>.value();
    return _supportCallWaiters
        .putIfAbsent(count, Completer<void>.new)
        .future
        .timeout(const Duration(seconds: 1));
  }

  @override
  void dispose() {}

  void emit(CapturedApiEvent event) {
    _events.add(event);
  }

  void emitError(Object error) => _events.addError(error);

  Future<void> close() => _events.close();
}
