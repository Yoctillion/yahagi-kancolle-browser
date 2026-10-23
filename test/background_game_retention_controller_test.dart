import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_toolbar_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/background_game_retention_controller.dart';

void main() {
  test('defaults enabled when no value was saved', () async {
    final controller = await BackgroundGameRetentionController.load(
      _MemoryBackgroundGameRetentionStore(),
    );

    expect(controller.enabled, isTrue);
  });

  test('restores a persisted disabled value', () async {
    final store = _MemoryBackgroundGameRetentionStore()..value = false;

    final controller = await BackgroundGameRetentionController.load(store);

    expect(controller.enabled, isFalse);
  });

  test('rolls setting back when persistence fails', () async {
    final store = _MemoryBackgroundGameRetentionStore()..failWrites = true;
    final controller = await BackgroundGameRetentionController.load(store);

    await controller.setEnabled(false);

    expect(controller.enabled, isTrue);
    expect(controller.errorMessage, isNotNull);
  });

  test(
    'starts retention before leaving the game and keeps it on resume',
    () async {
      final controller = await BackgroundGameRetentionController.load(
        _MemoryBackgroundGameRetentionStore(),
      );
      final toolbar = GameToolbarController();
      final port = _RecordingBackgroundGameRetentionPort();
      final coordinator = BackgroundGameRetentionCoordinator(
        controller: controller,
        toolbarController: toolbar,
        port: port,
      );
      await coordinator.settle();

      toolbar.onStageChanged(GameSurfaceStage.game);
      await coordinator.settle();
      expect(port.values.last, isTrue);
      final countBeforeBackground = port.values.length;
      await coordinator.handleLifecycleState(AppLifecycleState.paused);
      await coordinator.settle();

      expect(port.values.last, isTrue);
      expect(port.values.length, countBeforeBackground);

      await coordinator.handleLifecycleState(AppLifecycleState.resumed);
      await coordinator.settle();

      expect(port.values.last, isTrue);
      expect(port.values.length, countBeforeBackground);
      coordinator.dispose();
      toolbar.dispose();
      controller.dispose();
    },
  );

  test('inactive does not flicker retention and detached stops it', () async {
    final controller = await BackgroundGameRetentionController.load(
      _MemoryBackgroundGameRetentionStore(),
    );
    final toolbar = GameToolbarController()
      ..onStageChanged(GameSurfaceStage.game);
    final port = _RecordingBackgroundGameRetentionPort();
    final coordinator = BackgroundGameRetentionCoordinator(
      controller: controller,
      toolbarController: toolbar,
      port: port,
    );

    await coordinator.handleLifecycleState(AppLifecycleState.paused);
    await coordinator.settle();
    final afterPause = List<bool>.of(port.values);

    await coordinator.handleLifecycleState(AppLifecycleState.inactive);
    await coordinator.settle();
    expect(port.values, afterPause);

    await coordinator.handleLifecycleState(AppLifecycleState.detached);
    await coordinator.settle();
    expect(port.values.last, isFalse);
  });

  test('leaving game or disabling setting stops retention', () async {
    final controller = await BackgroundGameRetentionController.load(
      _MemoryBackgroundGameRetentionStore(),
    );
    final toolbar = GameToolbarController()
      ..onStageChanged(GameSurfaceStage.game);
    final port = _RecordingBackgroundGameRetentionPort();
    final coordinator = BackgroundGameRetentionCoordinator(
      controller: controller,
      toolbarController: toolbar,
      port: port,
    );

    await coordinator.handleLifecycleState(AppLifecycleState.paused);
    await coordinator.settle();
    toolbar.onStageChanged(GameSurfaceStage.login);
    await coordinator.settle();
    expect(port.values.last, isFalse);

    toolbar.onStageChanged(GameSurfaceStage.game);
    await coordinator.settle();
    expect(port.values.last, isTrue);
    await controller.setEnabled(false);
    await coordinator.settle();
    expect(port.values.last, isFalse);
  });

  test('rapid transitions finish at the newest requested state', () async {
    final controller = await BackgroundGameRetentionController.load(
      _MemoryBackgroundGameRetentionStore(),
    );
    final toolbar = GameToolbarController()
      ..onStageChanged(GameSurfaceStage.game);
    final port = _RecordingBackgroundGameRetentionPort()..block = true;
    final coordinator = BackgroundGameRetentionCoordinator(
      controller: controller,
      toolbarController: toolbar,
      port: port,
    );

    await coordinator.handleLifecycleState(AppLifecycleState.paused);
    await coordinator.handleLifecycleState(AppLifecycleState.resumed);
    toolbar.onStageChanged(GameSurfaceStage.login);
    port.release();
    await coordinator.settle();

    expect(port.values.last, isFalse);
  });

  test('foreground service failure is visible and can recover', () async {
    final controller = await BackgroundGameRetentionController.load(
      _MemoryBackgroundGameRetentionStore(),
    );
    final toolbar = GameToolbarController();
    final port = _RecordingBackgroundGameRetentionPort()..failuresRemaining = 3;
    final failures = <Object>[];
    final coordinator = BackgroundGameRetentionCoordinator(
      controller: controller,
      toolbarController: toolbar,
      port: port,
      onFailure: failures.add,
      retryDelay: Duration.zero,
    );
    await coordinator.settle();

    toolbar.onStageChanged(GameSurfaceStage.game);
    await coordinator.settle();
    expect(controller.errorMessage, contains('foreground denied'));
    expect(failures, hasLength(1));

    toolbar.onStageChanged(GameSurfaceStage.login);
    await coordinator.settle();
    toolbar.onStageChanged(GameSurfaceStage.game);
    await coordinator.settle();
    expect(controller.errorMessage, isNull);
    expect(port.values.last, isTrue);
  });

  test('retries a transient start failure without another input', () async {
    final controller = await BackgroundGameRetentionController.load(
      _MemoryBackgroundGameRetentionStore(),
    );
    final toolbar = GameToolbarController()
      ..onStageChanged(GameSurfaceStage.game);
    final port = _ControlledBackgroundGameRetentionPort(
      onSet: (_, attempt) async {
        if (attempt == 1) throw StateError('temporary service failure');
      },
    );

    fakeAsync((clock) {
      final coordinator = BackgroundGameRetentionCoordinator(
        controller: controller,
        toolbarController: toolbar,
        port: port,
      );
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 2));

      expect(port.applied, isTrue);
      expect(port.requests, <bool>[true, true]);
      expect(controller.errorMessage, isNull);
      coordinator.dispose();
      clock.flushMicrotasks();
    });
    toolbar.dispose();
    controller.dispose();
  });

  test('a hung enable cannot hold a newer disable in the queue', () async {
    final controller = await BackgroundGameRetentionController.load(
      _MemoryBackgroundGameRetentionStore(),
    );
    final toolbar = GameToolbarController()
      ..onStageChanged(GameSurfaceStage.game);
    late Completer<void> first;
    final port = _ControlledBackgroundGameRetentionPort(
      onSet: (_, attempt) => attempt == 1 ? first.future : Future<void>.value(),
    );

    fakeAsync((clock) {
      first = Completer<void>();
      final coordinator = BackgroundGameRetentionCoordinator(
        controller: controller,
        toolbarController: toolbar,
        port: port,
      );
      clock.flushMicrotasks();
      unawaited(controller.setEnabled(false));
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 6));

      expect(port.applied, isFalse);
      expect(port.requests.last, isFalse);
      first.complete();
      clock.flushMicrotasks();
      coordinator.dispose();
      clock.flushMicrotasks();
    });
    toolbar.dispose();
    controller.dispose();
  });

  test(
    'a late enable is corrected after the newer disable completed',
    () async {
      final controller = await BackgroundGameRetentionController.load(
        _MemoryBackgroundGameRetentionStore(),
      );
      final toolbar = GameToolbarController()
        ..onStageChanged(GameSurfaceStage.game);
      late Completer<void> first;
      final port = _ControlledBackgroundGameRetentionPort(
        onSet: (_, attempt) =>
            attempt == 1 ? first.future : Future<void>.value(),
      );

      fakeAsync((clock) {
        first = Completer<void>();
        final coordinator = BackgroundGameRetentionCoordinator(
          controller: controller,
          toolbarController: toolbar,
          port: port,
        );
        clock.flushMicrotasks();
        unawaited(controller.setEnabled(false));
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 6));
        first.complete();
        clock.flushMicrotasks();

        expect(port.requests, <bool>[true, false, false]);
        expect(port.applied, isFalse);
        final calls = port.requests.length;
        clock.elapse(const Duration(minutes: 1));
        expect(port.requests, hasLength(calls));
        coordinator.dispose();
        clock.flushMicrotasks();
      });
      toolbar.dispose();
      controller.dispose();
    },
  );

  test('permanent failures have a finite retry budget', () async {
    final controller = await BackgroundGameRetentionController.load(
      _MemoryBackgroundGameRetentionStore(),
    );
    final toolbar = GameToolbarController()
      ..onStageChanged(GameSurfaceStage.game);
    final failures = <Object>[];
    final port = _ControlledBackgroundGameRetentionPort(
      onSet: (_, _) async => throw StateError('foreground denied'),
    );

    fakeAsync((clock) {
      final coordinator = BackgroundGameRetentionCoordinator(
        controller: controller,
        toolbarController: toolbar,
        port: port,
        onFailure: failures.add,
      );
      clock.flushMicrotasks();
      clock.elapse(const Duration(minutes: 1));

      expect(port.requests, <bool>[true, true, true]);
      expect(controller.errorMessage, contains('foreground denied'));
      expect(failures, hasLength(1));
      var settled = false;
      unawaited(coordinator.settle().then((_) => settled = true));
      clock.flushMicrotasks();
      expect(settled, isTrue);
      coordinator.dispose();
      clock.elapse(const Duration(minutes: 1));
    });
    toolbar.dispose();
    controller.dispose();
  });

  test('hung service calls exhaust their budget and settle', () async {
    final controller = await BackgroundGameRetentionController.load(
      _MemoryBackgroundGameRetentionStore(),
    );
    final toolbar = GameToolbarController()
      ..onStageChanged(GameSurfaceStage.game);
    final port = _ControlledBackgroundGameRetentionPort(
      onSet: (_, _) => Completer<void>().future,
    );

    fakeAsync((clock) {
      final coordinator = BackgroundGameRetentionCoordinator(
        controller: controller,
        toolbarController: toolbar,
        port: port,
      );
      var settled = false;
      unawaited(coordinator.settle().then((_) => settled = true));
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 32));

      expect(port.requests, <bool>[true, true, true]);
      expect(settled, isTrue);
      expect(controller.errorMessage, contains('TimeoutException'));
      coordinator.dispose();
      clock.elapse(const Duration(seconds: 32));
    });
    toolbar.dispose();
    controller.dispose();
  });

  test('new disable interrupts a failed enable retry delay', () async {
    final controller = await BackgroundGameRetentionController.load(
      _MemoryBackgroundGameRetentionStore(),
    );
    final toolbar = GameToolbarController()
      ..onStageChanged(GameSurfaceStage.game);
    final port = _ControlledBackgroundGameRetentionPort(
      onSet: (retaining, _) async {
        if (retaining) throw StateError('temporary service failure');
      },
    );

    fakeAsync((clock) {
      final coordinator = BackgroundGameRetentionCoordinator(
        controller: controller,
        toolbarController: toolbar,
        port: port,
      );
      clock.flushMicrotasks();
      unawaited(controller.setEnabled(false));
      clock.flushMicrotasks();

      expect(port.requests, <bool>[true, false]);
      expect(port.applied, isFalse);
      clock.elapse(const Duration(minutes: 1));
      expect(port.requests, <bool>[true, false]);
      coordinator.dispose();
      clock.flushMicrotasks();
    });
    toolbar.dispose();
    controller.dispose();
  });

  test(
    'an enable receipt arriving after timeout cannot undo disable',
    () async {
      final controller = await BackgroundGameRetentionController.load(
        _MemoryBackgroundGameRetentionStore(),
      );
      final toolbar = GameToolbarController()
        ..onStageChanged(GameSurfaceStage.game);

      fakeAsync((clock) {
        final first = Completer<void>();
        final port = _ControlledBackgroundGameRetentionPort(
          onSet: (_, attempt) =>
              attempt == 1 ? first.future : Future<void>.value(),
        );
        final coordinator = BackgroundGameRetentionCoordinator(
          controller: controller,
          toolbarController: toolbar,
          port: port,
        );
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 11));
        expect(port.applied, isTrue);
        unawaited(controller.setEnabled(false));
        clock.flushMicrotasks();
        expect(port.applied, isFalse);
        first.complete();
        clock.flushMicrotasks();

        expect(port.requests, <bool>[true, true, false, false]);
        expect(port.applied, isFalse);
        expect(controller.errorMessage, isNull);
        coordinator.dispose();
        clock.flushMicrotasks();
      });
      toolbar.dispose();
      controller.dispose();
    },
  );

  test('late timeout errors do not replace a successful retry state', () async {
    final controller = await BackgroundGameRetentionController.load(
      _MemoryBackgroundGameRetentionStore(),
    );
    final toolbar = GameToolbarController()
      ..onStageChanged(GameSurfaceStage.game);
    final failures = <Object>[];

    fakeAsync((clock) {
      final first = Completer<void>();
      final port = _ControlledBackgroundGameRetentionPort(
        onSet: (_, attempt) =>
            attempt == 1 ? first.future : Future<void>.value(),
      );
      final coordinator = BackgroundGameRetentionCoordinator(
        controller: controller,
        toolbarController: toolbar,
        port: port,
        onFailure: failures.add,
      );
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 11));
      first.completeError(StateError('late receipt error'));
      clock.flushMicrotasks();

      expect(port.requests, <bool>[true, true]);
      expect(port.applied, isTrue);
      expect(controller.errorMessage, isNull);
      expect(failures, isEmpty);
      coordinator.dispose();
      clock.flushMicrotasks();
    });
    toolbar.dispose();
    controller.dispose();
  });

  test('dispose contains failed releases after controller disposal', () async {
    final controller = await BackgroundGameRetentionController.load(
      _MemoryBackgroundGameRetentionStore(),
    );
    final toolbar = GameToolbarController()
      ..onStageChanged(GameSurfaceStage.game);
    final failures = <Object>[];
    final port = _ControlledBackgroundGameRetentionPort(
      onSet: (retaining, _) async {
        if (!retaining) throw StateError('release failed');
      },
    );

    fakeAsync((clock) {
      final coordinator = BackgroundGameRetentionCoordinator(
        controller: controller,
        toolbarController: toolbar,
        port: port,
        onFailure: failures.add,
      );
      clock.flushMicrotasks();
      coordinator.dispose();
      toolbar.dispose();
      controller.dispose();
      clock.elapse(const Duration(seconds: 2));

      expect(port.requests, <bool>[true, false, false, false]);
      expect(coordinator.errorMessage, contains('release failed'));
      expect(failures, isEmpty);
      final calls = port.requests.length;
      clock.elapse(const Duration(minutes: 1));
      expect(port.requests, hasLength(calls));
    });
  });

  test('pending enable invalidates the previous disable receipt', () async {
    final controller = await BackgroundGameRetentionController.load(
      _MemoryBackgroundGameRetentionStore(),
    );
    final toolbar = GameToolbarController();
    late Completer<void> enableReceipt;
    late _ControlledBackgroundGameRetentionPort port;
    port = _ControlledBackgroundGameRetentionPort(
      onSet: (retaining, attempt) {
        if (retaining && attempt == 2) {
          port.applied = true;
          return enableReceipt.future;
        }
        return Future<void>.value();
      },
    );

    fakeAsync((clock) {
      enableReceipt = Completer<void>();
      final coordinator = BackgroundGameRetentionCoordinator(
        controller: controller,
        toolbarController: toolbar,
        port: port,
      );
      clock.flushMicrotasks();
      toolbar.onStageChanged(GameSurfaceStage.game);
      clock.flushMicrotasks();
      expect(port.applied, isTrue);
      toolbar.onStageChanged(GameSurfaceStage.login);
      clock.flushMicrotasks();

      expect(port.requests, <bool>[false, true, false]);
      expect(port.applied, isFalse);
      enableReceipt.complete();
      clock.flushMicrotasks();
      expect(port.applied, isFalse);
      coordinator.dispose();
      clock.flushMicrotasks();
    });
    toolbar.dispose();
    controller.dispose();
  });

  test(
    'stale same-target receipt cannot acknowledge a newer request',
    () async {
      final controller = await BackgroundGameRetentionController.load(
        _MemoryBackgroundGameRetentionStore(),
      );
      final toolbar = GameToolbarController()
        ..onStageChanged(GameSurfaceStage.game);

      fakeAsync((clock) {
        final port = _ReceiptBackgroundGameRetentionPort();
        final coordinator = BackgroundGameRetentionCoordinator(
          controller: controller,
          toolbarController: toolbar,
          port: port,
        );
        clock.flushMicrotasks();
        toolbar.onStageChanged(GameSurfaceStage.login);
        clock.flushMicrotasks();
        expect(port.requests, <bool>[true, false]);
        expect(port.applied, isFalse);

        toolbar.onStageChanged(GameSurfaceStage.game);
        port.receipts.first.complete();
        clock.flushMicrotasks();

        expect(port.requests, <bool>[true, false, true]);
        expect(port.applied, isTrue);
        coordinator.dispose();
        clock.flushMicrotasks();
        for (var index = 1; index < port.receipts.length; index++) {
          port.receipts[index].complete();
          clock.flushMicrotasks();
        }
      });
      toolbar.dispose();
      controller.dispose();
    },
  );

  test(
    'stale enable receipt cannot cancel a failed newer enable retry',
    () async {
      final controller = await BackgroundGameRetentionController.load(
        _MemoryBackgroundGameRetentionStore(),
      );
      final toolbar = GameToolbarController()
        ..onStageChanged(GameSurfaceStage.game);

      fakeAsync((clock) {
        final port = _ReceiptBackgroundGameRetentionPort(failAttempt: 3);
        final coordinator = BackgroundGameRetentionCoordinator(
          controller: controller,
          toolbarController: toolbar,
          port: port,
          retryDelay: const Duration(milliseconds: 100),
        );
        clock.flushMicrotasks();
        toolbar.onStageChanged(GameSurfaceStage.login);
        clock.flushMicrotasks();
        port.receipts[1].complete();
        clock.flushMicrotasks();
        expect(port.applied, isFalse);

        toolbar.onStageChanged(GameSurfaceStage.game);
        clock.flushMicrotasks();
        expect(port.requests, <bool>[true, false, true]);
        port.receipts.first.complete();
        clock.flushMicrotasks();
        clock.elapse(const Duration(milliseconds: 150));

        expect(port.requests, <bool>[true, false, true, true]);
        expect(port.applied, isTrue);
        port.receipts[2].complete();
        clock.flushMicrotasks();
        expect(controller.errorMessage, isNull);
        coordinator.dispose();
        clock.flushMicrotasks();
        port.receipts[3].complete();
        clock.flushMicrotasks();
      });
      toolbar.dispose();
      controller.dispose();
    },
  );

  test(
    'dispose releases a hung enable without notifying disposed state',
    () async {
      final controller = await BackgroundGameRetentionController.load(
        _MemoryBackgroundGameRetentionStore(),
      );
      final toolbar = GameToolbarController()
        ..onStageChanged(GameSurfaceStage.game);
      late Completer<void> first;
      final port = _ControlledBackgroundGameRetentionPort(
        onSet: (_, attempt) =>
            attempt == 1 ? first.future : Future<void>.value(),
      );

      fakeAsync((clock) {
        first = Completer<void>();
        final coordinator = BackgroundGameRetentionCoordinator(
          controller: controller,
          toolbarController: toolbar,
          port: port,
        );
        clock.flushMicrotasks();
        coordinator.dispose();
        toolbar.dispose();
        controller.dispose();
        clock.elapse(const Duration(seconds: 6));

        expect(port.applied, isFalse);
        first.complete();
        clock.flushMicrotasks();
        expect(port.applied, isFalse);
        expect(port.requests, <bool>[true, false, false]);
        final calls = port.requests.length;
        clock.elapse(const Duration(minutes: 1));
        expect(port.requests, hasLength(calls));
      });
    },
  );
}

final class _ControlledBackgroundGameRetentionPort
    implements BackgroundGameRetentionPort {
  _ControlledBackgroundGameRetentionPort({required this.onSet});

  final Future<void> Function(bool retaining, int attempt) onSet;
  final List<bool> requests = <bool>[];
  bool? applied;

  @override
  Future<void> setRetaining(bool retaining) async {
    requests.add(retaining);
    await onSet(retaining, requests.length);
    applied = retaining;
  }
}

final class _ReceiptBackgroundGameRetentionPort
    implements BackgroundGameRetentionPort {
  _ReceiptBackgroundGameRetentionPort({this.failAttempt});

  final int? failAttempt;
  final List<bool> requests = <bool>[];
  final List<Completer<void>> receipts = <Completer<void>>[];
  bool? applied;

  @override
  Future<void> setRetaining(bool retaining) {
    requests.add(retaining);
    if (requests.length == failAttempt) {
      return Future<void>.error(StateError('service rejected before applying'));
    }
    applied = retaining;
    final receipt = Completer<void>();
    receipts.add(receipt);
    return receipt.future;
  }
}

final class _MemoryBackgroundGameRetentionStore
    implements BackgroundGameRetentionStore {
  bool? value;
  bool failWrites = false;

  @override
  Future<bool?> readEnabled() async => value;

  @override
  Future<void> writeEnabled(bool enabled) async {
    if (failWrites) throw StateError('write failed');
    value = enabled;
  }
}

final class _RecordingBackgroundGameRetentionPort
    implements BackgroundGameRetentionPort {
  final List<bool> values = <bool>[];
  bool block = false;
  int failuresRemaining = 0;
  Completer<void>? _gate;

  @override
  Future<void> setRetaining(bool retaining) async {
    if (failuresRemaining > 0 && retaining) {
      failuresRemaining--;
      throw StateError('foreground denied');
    }
    values.add(retaining);
    if (block) {
      _gate ??= Completer<void>();
      await _gate!.future;
      block = false;
    }
  }

  void release() => _gate?.complete();
}
