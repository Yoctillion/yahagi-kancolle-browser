import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_toolbar_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/background_game_retention_controller.dart';

void main() {
  test(
    'rapid settings writes cannot persist older intent after newer intent',
    () async {
      final store = _ScheduledRetentionStore();
      fakeAsync((clock) {
        final controller = _loadController(store, clock);
        unawaited(controller.setEnabled(false));
        unawaited(controller.setEnabled(true));
        clock.flushMicrotasks();
        store.completeLast();
        clock.flushMicrotasks();
        store.completeFirst();
        clock.flushMicrotasks();

        expect(controller.enabled, isTrue);
        expect(store.value, isTrue);
        controller.dispose();
      });
    },
  );

  test(
    'an older write failure cannot roll back newer settings intent',
    () async {
      final store = _ScheduledRetentionStore();
      fakeAsync((clock) {
        final controller = _loadController(store, clock);
        unawaited(controller.setEnabled(false));
        unawaited(controller.setEnabled(true));
        unawaited(controller.setEnabled(false));
        clock.flushMicrotasks();
        store.completeFirst(fail: true);
        clock.flushMicrotasks();

        expect(controller.enabled, isFalse);
        expect(controller.errorMessage, isNull);
        store.finish(clock);
        expect(store.value, isFalse);
        controller.dispose();
      });
    },
  );

  test('latest write failure restores the last persisted value', () async {
    final store = _ScheduledRetentionStore();
    fakeAsync((clock) {
      final controller = _loadController(store, clock);
      unawaited(controller.setEnabled(false));
      clock.flushMicrotasks();
      store.completeFirst();
      clock.flushMicrotasks();
      unawaited(controller.setEnabled(true));
      unawaited(controller.setEnabled(false));
      clock.flushMicrotasks();
      store.completeFirst(fail: true);
      clock.flushMicrotasks();
      store.completeFirst(fail: true);
      clock.flushMicrotasks();

      expect(store.value, isFalse);
      expect(controller.enabled, isFalse);
      expect(controller.errorMessage, contains('write rejected'));
      controller.dispose();
    });
  });

  test('late setting failure cannot notify disposed controller', () async {
    final store = _ScheduledRetentionStore();
    fakeAsync((clock) {
      final controller = _loadController(store, clock);
      unawaited(controller.setEnabled(false));
      clock.flushMicrotasks();
      controller.dispose();
      store.completeFirst(fail: true);
      clock.flushMicrotasks();
      controller.reportSyncError('late native failure');
      unawaited(controller.setEnabled(true));
      clock.flushMicrotasks();

      expect(store.pending, isEmpty);
      expect(store.requests, <bool>[false]);
    });
  });

  test('a stale failed enable with a late effect cannot undo disable', () {
    fakeAsync((clock) {
      final store = _ScheduledRetentionStore();
      final controller = _loadController(store, clock);
      final toolbar = GameToolbarController();
      final port = _ScheduledRetentionPort();
      final coordinator = BackgroundGameRetentionCoordinator(
        controller: controller,
        toolbarController: toolbar,
        port: port,
      );
      clock.flushMicrotasks();
      port.reply(port.commands[0]);
      clock.flushMicrotasks();
      toolbar.onStageChanged(GameSurfaceStage.game);
      clock.flushMicrotasks();
      toolbar.onStageChanged(GameSurfaceStage.login);
      clock.flushMicrotasks();
      port.reply(port.commands[2]);
      clock.flushMicrotasks();
      expect(port.applied, isFalse);
      port.apply(port.commands[1]);
      port.reply(port.commands[1], fail: true);
      port.succeedNewCommands = true;
      clock.flushMicrotasks();

      expect(port.applied, isFalse);
      expect(port.commands.map((command) => command.value), <bool>[
        false,
        true,
        false,
        false,
      ]);
      final calls = port.commands.length;
      clock.elapse(const Duration(minutes: 1));
      expect(port.commands, hasLength(calls));
      coordinator.dispose();
      controller.dispose();
      toolbar.dispose();
      clock.flushMicrotasks();
    });
  });

  test('2000 deterministic schedules converge after faults are drained', () {
    const scenarios = 2000;
    var totalCommands = 0;
    var maxCommands = 0;
    for (var seed = 0; seed < scenarios; seed++) {
      fakeAsync((clock) {
        final random = Random(seed);
        final trace = <String>[];
        final store = _ScheduledRetentionStore();
        final controller = _loadController(store, clock);
        final toolbar = GameToolbarController();
        final port = _ScheduledRetentionPort();
        final coordinator = BackgroundGameRetentionCoordinator(
          controller: controller,
          toolbarController: toolbar,
          port: port,
          operationTimeout: const Duration(milliseconds: 10),
          retryDelay: const Duration(milliseconds: 1),
        );
        var expectedEnabled = true;
        var expectedPersisted = true;
        var settingRevision = 0;
        var detached = false;
        var disposed = false;
        final writes = <({bool value, int revision})>[];

        void check(bool condition, String message) {
          expect(
            condition,
            isTrue,
            reason: 'seed=$seed $message\n${trace.join('\n')}',
          );
        }

        void completeWrite({required bool fail}) {
          if (writes.isEmpty) return;
          check(store.pending.isNotEmpty, 'settings queue stalled');
          final write = writes.removeAt(0);
          check(
            store.pending.first.value == write.value,
            'write order changed',
          );
          trace.add('store ${write.value} ${fail ? "error" : "ok"}');
          store.completeFirst(fail: fail);
          if (fail) {
            if (write.revision == settingRevision) {
              expectedEnabled = expectedPersisted;
            }
          } else {
            expectedPersisted = write.value;
          }
          clock.flushMicrotasks();
        }

        clock.flushMicrotasks();
        for (var step = 0; step < 50; step++) {
          final action = random.nextInt(10);
          switch (action) {
            case 0 || 1:
              final value = random.nextBool();
              trace.add('setting $value');
              if (value != expectedEnabled) {
                expectedEnabled = value;
                writes.add((value: value, revision: ++settingRevision));
              }
              unawaited(controller.setEnabled(value));
            case 2:
              final stage = GameSurfaceStage.values[random.nextInt(3)];
              trace.add('stage ${stage.name}');
              toolbar.onStageChanged(stage);
            case 3:
              final state = AppLifecycleState.values[random.nextInt(5)];
              trace.add('lifecycle ${state.name}');
              if (state == AppLifecycleState.resumed) detached = false;
              if (state == AppLifecycleState.detached) detached = true;
              unawaited(coordinator.handleLifecycleState(state));
            case 4:
              completeWrite(fail: random.nextBool());
            case 5:
              if (port.pending.isNotEmpty) {
                final command =
                    port.pending[random.nextInt(port.pending.length)];
                trace.add('effect #${command.id} ${command.value}');
                port.apply(command);
              }
            case 6 || 7:
              if (port.pending.isNotEmpty) {
                final command =
                    port.pending[random.nextInt(port.pending.length)];
                final fail = random.nextInt(4) == 0;
                trace.add('ack #${command.id} ${fail ? "error" : "ok"}');
                port.reply(command, fail: fail);
              }
            case 8:
              final elapsed = random.nextInt(15);
              trace.add('elapse $elapsed ms');
              clock.elapse(Duration(milliseconds: elapsed));
            case 9:
              if (port.commands.isNotEmpty) {
                final command =
                    port.commands[random.nextInt(port.commands.length)];
                if (command.receipt.isCompleted) {
                  trace.add('duplicate ack #${command.id}');
                  port.reply(command);
                }
              }
          }
          clock.flushMicrotasks();
          check(controller.enabled == expectedEnabled, 'optimistic setting');
          check(store.value == expectedPersisted, 'persisted setting');
          check(port.commands.length < 300, 'unbounded native retry queue');
        }

        while (writes.isNotEmpty) {
          completeWrite(fail: false);
        }
        if (seed.isOdd) {
          trace.add('dispose');
          disposed = true;
          coordinator.dispose();
          controller.dispose();
          toolbar.dispose();
        }
        port.succeedNewCommands = true;
        if (!disposed) {
          trace.add('return to resumed game');
          detached = false;
          toolbar.onStageChanged(GameSurfaceStage.game);
          unawaited(
            coordinator.handleLifecycleState(AppLifecycleState.resumed),
          );
          clock.flushMicrotasks();
        }
        for (var step = 0; step < 500 && port.pending.isNotEmpty; step++) {
          final command = port.pending[random.nextInt(port.pending.length)];
          trace.add('drain #${command.id}');
          port.reply(command);
          clock.flushMicrotasks();
        }
        clock.elapse(const Duration(milliseconds: 50));
        clock.flushMicrotasks();
        final expectedTarget =
            !disposed &&
            !detached &&
            expectedEnabled &&
            toolbar.stage == GameSurfaceStage.game;
        check(port.pending.isEmpty, 'native receipts not drained');
        check(port.applied == expectedTarget, 'native effect != latest target');
        var settled = false;
        unawaited(coordinator.settle().then((_) => settled = true));
        clock.flushMicrotasks();
        check(settled, 'settle did not finish after receipts drained');
        final calls = port.commands.length;
        totalCommands += calls;
        maxCommands = max(maxCommands, calls);
        clock.elapse(const Duration(seconds: 1));
        check(port.commands.length == calls, 'idle native polling');
        if (!disposed) {
          coordinator.dispose();
          controller.dispose();
          toolbar.dispose();
          clock.flushMicrotasks();
        }
      });
    }
    debugPrint(
      'retention stress: seeds=0..${scenarios - 1}, actions=${scenarios * 50}, '
      'nativeCommands=$totalCommands, maxCommandsPerScenario=$maxCommands',
    );
  });
}

BackgroundGameRetentionController _loadController(
  BackgroundGameRetentionStore store,
  FakeAsync clock,
) {
  BackgroundGameRetentionController? controller;
  unawaited(
    BackgroundGameRetentionController.load(store).then((value) {
      controller = value;
    }),
  );
  clock.flushMicrotasks();
  return controller!;
}

final class _ScheduledRetentionStore implements BackgroundGameRetentionStore {
  bool value = true;
  final List<bool> requests = <bool>[];
  final List<({bool value, Completer<void> receipt})> pending = [];

  @override
  Future<bool?> readEnabled() async => value;

  @override
  Future<void> writeEnabled(bool enabled) {
    requests.add(enabled);
    final receipt = Completer<void>();
    pending.add((value: enabled, receipt: receipt));
    return receipt.future;
  }

  void completeFirst({bool fail = false}) => _complete(0, fail: fail);

  void completeLast({bool fail = false}) =>
      _complete(pending.length - 1, fail: fail);

  void _complete(int index, {required bool fail}) {
    final request = pending.removeAt(index);
    if (fail) {
      request.receipt.completeError(StateError('write rejected'));
    } else {
      value = request.value;
      request.receipt.complete();
    }
  }

  void finish(FakeAsync clock) {
    for (var step = 0; step < 100 && pending.isNotEmpty; step++) {
      completeFirst();
      clock.flushMicrotasks();
    }
    expect(pending, isEmpty);
  }
}

final class _NativeCommand {
  _NativeCommand(this.id, this.value);

  final int id;
  final bool value;
  final Completer<void> receipt = Completer<void>();
  bool applied = false;
}

final class _ScheduledRetentionPort implements BackgroundGameRetentionPort {
  final List<_NativeCommand> commands = [];
  bool applied = false;
  bool succeedNewCommands = false;

  List<_NativeCommand> get pending =>
      commands.where((command) => !command.receipt.isCompleted).toList();

  @override
  Future<void> setRetaining(bool retaining) {
    final command = _NativeCommand(commands.length, retaining);
    commands.add(command);
    if (succeedNewCommands) reply(command);
    return command.receipt.future;
  }

  void apply(_NativeCommand command) {
    if (command.applied || command.receipt.isCompleted) return;
    command.applied = true;
    applied = command.value;
  }

  void reply(_NativeCommand command, {bool fail = false}) {
    if (command.receipt.isCompleted) return;
    if (fail) {
      command.receipt.completeError(StateError('native rejected'));
    } else {
      apply(command);
      command.receipt.complete();
    }
  }
}
