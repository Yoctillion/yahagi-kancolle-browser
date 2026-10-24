import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_controller.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_library.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_models.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_page.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_port.dart';

import 'game_mods_controller_test.dart' show FakeGameModsPort;
import 'support/game_mod_portrait_platform_mock.dart';

void main() {
  setUp(mockGameModPortraitPlatform);
  tearDown(clearGameModPortraitPlatformMock);

  testWidgets(
    'background lifecycle stops progress UI work without stopping scan',
    (tester) async {
      final port = _ProgressPort();
      await _withController(port, (controller) async {
        var notifications = 0;
        controller.addListener(() => notifications++);
        final task = controller.scanLibrary();
        await tester.pump();
        expect(controller.operationProgress?.operationId, 'scan-active');
        await tester.pump(const Duration(milliseconds: 200));
        expect(port.progressCalls, greaterThan(1));

        for (final state in [
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.detached,
        ]) {
          controller.didChangeAppLifecycleState(state);
          final calls = port.progressCalls;
          final count = notifications;
          await tester.pump(const Duration(seconds: 1));
          expect(
            port.progressCalls,
            calls,
            reason: '$state must not poll progress',
          );
          expect(
            notifications,
            count,
            reason: '$state must not redraw progress',
          );
          expect(controller.busy, isTrue);
          expect(port.scanGate.isCompleted, isFalse);
          expect(port.discardedScans, isEmpty);
        }

        port.snapshot = _progress(completedFiles: 9, elapsedMillis: 6000);
        final beforeResume = port.progressCalls;
        controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await tester.pump();
        expect(port.progressCalls, beforeResume + 1);
        expect(controller.operationProgress?.completedFiles, 9);
        expect(controller.operationElapsedMillis, greaterThanOrEqualTo(6000));
        port.scanGate.complete(_scan);
        await task;
        expect(controller.libraryScan?.token, _scan.token);
      });
    },
  );

  testWidgets('hidden page stops progress work and catches up when shown', (
    tester,
  ) async {
    final port = _ProgressPort();
    await _withController(port, (controller) async {
      var notifications = 0;
      controller.addListener(() => notifications++);
      final task = controller.scanLibrary();
      await tester.pump();
      controller.setVisible(false);
      final hiddenCalls = port.progressCalls;
      final hiddenNotifications = notifications;
      await tester.pump(const Duration(seconds: 1));
      expect(port.progressCalls, hiddenCalls);
      expect(notifications, hiddenNotifications);
      expect(controller.busy, isTrue);
      expect(port.discardedScans, isEmpty);

      port.snapshot = _progress(completedFiles: 7, elapsedMillis: 3000);
      controller.setVisible(true);
      await tester.pump();
      expect(port.progressCalls, hiddenCalls + 1);
      expect(controller.operationProgress?.completedFiles, 7);
      controller.setVisible(true);
      await tester.pump();
      expect(port.progressCalls, hiddenCalls + 1);
      await tester.pump(const Duration(milliseconds: 200));
      expect(port.progressCalls, hiddenCalls + 2);
      port.scanGate.complete(_scan);
      await task;
    });
  });

  testWidgets(
    'visible inactive progress remains live and catches up from hidden',
    (tester) async {
      final port = _ProgressPort();
      await _withController(port, (controller) async {
        final task = controller.scanLibrary();
        await tester.pump();
        controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
        await tester.pump();
        final inactiveCalls = port.progressCalls;
        final statusCalls = port.statusCalls;
        port.snapshot = _progress(completedFiles: 4, elapsedMillis: 2000);
        await tester.pump(const Duration(milliseconds: 200));
        expect(port.progressCalls, inactiveCalls + 1);
        expect(controller.operationProgress?.completedFiles, 4);
        expect(port.statusCalls, statusCalls);

        controller.didChangeAppLifecycleState(AppLifecycleState.hidden);
        final hiddenCalls = port.progressCalls;
        await tester.pump(const Duration(seconds: 1));
        expect(port.progressCalls, hiddenCalls);
        port.snapshot = _progress(completedFiles: 8, elapsedMillis: 4000);
        controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
        await tester.pump();
        expect(port.progressCalls, hiddenCalls + 1);
        expect(controller.operationProgress?.completedFiles, 8);
        port.scanGate.complete(_scan);
        await task;
      });
    },
  );

  testWidgets('hidden scan completion preserves its review and cancellation', (
    tester,
  ) async {
    final port = _ProgressPort();
    await _withController(port, (controller) async {
      final task = controller.scanLibrary();
      await tester.pump();
      controller.setVisible(false);
      port.scanGate.complete(_scan);
      await task;
      expect(controller.busy, isFalse);
      expect(controller.operationProgress, isNull);
      expect(controller.libraryScan?.token, _scan.token);
      expect(port.discardedScans, isEmpty);

      final completedCalls = port.progressCalls;
      controller.setVisible(true);
      await tester.pump(const Duration(milliseconds: 600));
      expect(port.progressCalls, completedCalls);
      await controller.cancelLibraryScan();
      expect(port.discardedScans, [_scan.token]);
      expect(controller.libraryScan, isNull);
    });
  });

  for (final fail in [false, true]) {
    testWidgets(
      'background picker ${fail ? 'error' : 'cancellation'} finishes without progress revival',
      (tester) async {
        final port = _ProgressPort();
        await _withController(port, (controller) async {
          final picker = Completer<GameModsPreflight?>();
          port.pickerGate = picker;
          port.snapshot = _progress(operation: 'import');
          final task = controller.pickArchive();
          await tester.pump();
          controller.setAppResumed(false);
          if (fail) {
            picker.completeError(PlatformException(code: 'storage_error'));
          } else {
            picker.complete(null);
          }
          await task;
          expect(controller.busy, isFalse);
          expect(controller.preflight, isNull);
          expect(controller.operationProgress, isNull);
          expect(controller.errorCode, fail ? 'storage_error' : isNull);
          expect(port.discarded, isEmpty);
          final calls = port.progressCalls;
          controller.setAppResumed(true);
          await tester.pump(const Duration(milliseconds: 600));
          expect(port.progressCalls, calls);
        });
      },
    );
  }

  testWidgets(
    'resume does not duplicate a progress request already in flight',
    (tester) async {
      final reply = Completer<GameModsOperationProgress?>();
      final port = _ProgressPort()..reply = reply.future;
      await _withController(port, (controller) async {
        final task = controller.scanLibrary();
        await tester.pump();
        expect(port.progressCalls, 1);
        controller.setAppResumed(false);
        await tester.pump(const Duration(seconds: 1));
        controller.setAppResumed(true);
        await tester.pump();
        expect(port.progressCalls, 1);
        reply.complete(_progress());
        await tester.pump();
        port.reply = null;
        port.snapshot = _progress(completedFiles: 8, elapsedMillis: 4000);
        await tester.pump(const Duration(milliseconds: 200));
        expect(port.progressCalls, 2);
        expect(controller.operationProgress?.completedFiles, 8);
        port.scanGate.complete(_scan);
        await task;
      });
    },
  );

  testWidgets('visible host rebuild catches up a real progress modal safely', (
    tester,
  ) async {
    final port = _ProgressPort();
    await _withController(port, (controller) async {
      final visible = ValueNotifier(true);
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<bool>(
                valueListenable: visible,
                builder: (context, value, _) =>
                    GameModsPage(controller: controller, visible: value),
              ),
            ),
          ),
        );
        final pageState = tester.state(find.byType(GameModsPage));
        final task = controller.scanLibrary();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final modal = find.byKey(const Key('game-mods-operation-progress'));
        expect(modal, findsOneWidget);

        visible.value = false;
        await tester.pump();
        final hiddenCalls = port.progressCalls;
        port.snapshot = _progress(completedFiles: 9, elapsedMillis: 6000);
        visible.value = true;
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(port.progressCalls, hiddenCalls + 1);
        expect(controller.operationProgress?.completedFiles, 9);
        expect(modal, findsOneWidget);
        expect(
          tester.state(find.byType(GameModsPage, skipOffstage: false)),
          same(pageState),
        );

        port.scanGate.complete(_scan);
        await task;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(modal, findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        visible.dispose();
      }
    });
  });

  testWidgets('rapid visibility changes retire queued catch-up callbacks', (
    tester,
  ) async {
    final port = _ProgressPort();
    await _withController(port, (controller) async {
      final task = controller.scanLibrary();
      await tester.pump();
      controller.setVisible(false);
      final calls = port.progressCalls;
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.setVisible(true);
      controller.setVisible(false);
      controller.setVisible(true);
      controller.setVisible(false);
      await tester.pump();
      expect(port.progressCalls, calls);
      expect(notifications, 0);

      controller.setVisible(true);
      controller.setVisible(false);
      controller.setVisible(true);
      await tester.pump();
      expect(port.progressCalls, calls + 1);
      expect(notifications, 2, reason: 'one catch-up plus its fresh snapshot');
      port.scanGate.complete(_scan);
      await task;
    });
  });

  for (final finishesInBackground in [false, true]) {
    testWidgets(
      'Mods page reentry ${finishesInBackground ? 'retains a controller task result' : 'reattaches to a running controller task'}',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final port = _ProgressPort();
        await _withController(port, (controller) async {
          final showPage = ValueNotifier(true);
          try {
            await tester.pumpWidget(_pageMountHost(controller, showPage));
            final task = controller.scanLibrary();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            final modal = find.byKey(const Key('game-mods-operation-progress'));
            expect(modal, findsOneWidget);

            showPage.value = false;
            await tester.pump();
            await tester.pump();
            expect(
              find.byType(GameModsPage, skipOffstage: false),
              findsNothing,
            );
            expect(modal, findsNothing);
            final hiddenReads = port.progressCalls;
            await tester.pump(const Duration(milliseconds: 600));
            expect(port.progressCalls, hiddenReads);
            expect(controller.busy, isTrue);
            expect(port.discardedScans, isEmpty);

            if (finishesInBackground) {
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.hidden,
              );
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.paused,
              );
              port.scanGate.complete(_scan);
              await task;
              expect(controller.busy, isFalse);
              expect(controller.operationProgress, isNull);
              expect(controller.libraryScan?.token, _scan.token);
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.resumed,
              );
            } else {
              port.snapshot = _progress(completedFiles: 8, elapsedMillis: 4000);
            }

            showPage.value = true;
            await tester.pump();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(port.scanCalls, 1, reason: 'reentry must not restart IO');
            expect(tester.takeException(), isNull);
            if (finishesInBackground) {
              expect(modal, findsNothing);
              expect(port.progressCalls, hiddenReads);
            } else {
              expect(modal, findsOneWidget);
              expect(controller.operationProgress?.completedFiles, 8);
              expect(port.scanGate.isCompleted, isFalse);
              port.scanGate.complete(_scan);
              await task;
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 400));
              expect(modal, findsNothing);
            }
            expect(controller.libraryScan?.token, _scan.token);
            expect(port.discardedScans, isEmpty);
            // A controller task owns its result, while the page's scan action
            // owns the review dialog. Reopen that existing preview through UI.
            final scanButton = find.byKey(const Key('game-mods-library-scan'));
            await tester.ensureVisible(scanButton);
            await tester.tap(scanButton);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(
              find.byKey(const Key('game-mods-library-scan-confirm')),
              findsOneWidget,
            );
            expect(
              port.scanCalls,
              1,
              reason: 'review must reuse the saved scan',
            );
            expect(port.discardedScans, isEmpty);
            await tester.tap(
              find.byKey(const Key('game-mods-library-scan-cancel')),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(controller.libraryScan, isNull);
            expect(port.discardedScans, [_scan.token]);
          } finally {
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
            await tester.pumpWidget(const SizedBox.shrink());
            showPage.dispose();
          }
        });
      },
    );
  }

  testWidgets('page-started scan cancels an orphaned review after unmount', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final port = _ProgressPort();
    await _withController(port, (controller) async {
      final showPage = ValueNotifier(true);
      try {
        await tester.pumpWidget(_pageMountHost(controller, showPage));
        final scanButton = find.byKey(const Key('game-mods-library-scan'));
        await tester.ensureVisible(scanButton);
        await tester.tap(scanButton);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final modal = find.byKey(const Key('game-mods-operation-progress'));
        expect(modal, findsOneWidget);
        expect(controller.busy, isTrue);
        expect(port.scanCalls, 1);

        showPage.value = false;
        await tester.pump();
        await tester.pump();
        expect(modal, findsNothing);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        port.scanGate.complete(_scan);
        await tester.pump();
        expect(controller.busy, isFalse);
        expect(controller.libraryScan, isNull);
        expect(controller.operationProgress, isNull);
        expect(port.discardedScans, [_scan.token]);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        showPage.value = true;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(modal, findsNothing);
        expect(
          find.byKey(const Key('game-mods-library-scan-confirm')),
          findsNothing,
        );
        expect(port.scanCalls, 1);
        expect(controller.canEdit, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        showPage.dispose();
      }
    });
  });
}

Widget _pageMountHost(
  GameModsController controller,
  ValueNotifier<bool> showPage,
) => MaterialApp(
  home: Scaffold(
    body: ValueListenableBuilder<bool>(
      valueListenable: showPage,
      builder: (context, mounted, _) => mounted
          ? GameModsPage(controller: controller)
          : const Text('other workspace'),
    ),
  ),
);

Future<void> _withController(
  _ProgressPort port,
  Future<void> Function(GameModsController controller) body,
) async {
  final controller = GameModsController(port: port);
  try {
    await controller.initialize();
    controller.setAppResumed(true);
    controller.setVisible(true);
    await body(controller);
  } finally {
    controller.dispose();
  }
}

final _scan = GameModLibraryScan.fromMap({
  'token': 'scan-review',
  'entries': [
    {
      'id': 'new',
      'name': 'Package',
      'kind': 'new',
      'supportedCount': 1,
      'resourceCount': 1,
    },
  ],
});

class _ProgressPort extends FakeGameModsPort
    implements GameModsLibraryPort, GameModsProgressPort {
  _ProgressPort() {
    current = GameModsStatus.fromMap({
      ...current.toMap(),
      'library': {'configured': true, 'available': true},
    });
  }

  final scanGate = Completer<GameModLibraryScan>();
  final discardedScans = <String>[];
  int progressCalls = 0;
  int scanCalls = 0;
  GameModsOperationProgress snapshot = _progress();
  Future<GameModsOperationProgress?>? reply;

  @override
  Future<GameModsOperationProgress?> operationProgress() async {
    progressCalls++;
    return reply == null ? snapshot : await reply;
  }

  @override
  Future<bool> chooseLibraryDirectory() async => true;

  @override
  Future<void> openLibraryDirectory() async {}

  @override
  Future<GameModLibraryScan> scanLibrary() {
    scanCalls++;
    return scanGate.future;
  }

  @override
  Future<void> commitLibraryScan(String token) async {}

  @override
  Future<void> discardLibraryScan(String token) async {
    discardedScans.add(token);
  }
}

GameModsOperationProgress _progress({
  String operation = 'scan',
  int completedFiles = 1,
  int elapsedMillis = 1000,
}) => GameModsOperationProgress(
  operationId: 'scan-active',
  operation: operation,
  phase: 'read',
  active: true,
  completedFiles: completedFiles,
  totalFiles: 10,
  elapsedMillis: elapsedMillis,
);
