import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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

  test(
    'progress channel decodes optional totals without installing a handler',
    () async {
      const channel = MethodChannel('test/game-mods-progress');
      const port = MethodChannelGameModsPort(channel);
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return {
              'operationId': 'native-1',
              'operation': 'scan',
              'phase': 'read',
              'active': true,
              'completedPackages': 3,
              'totalPackages': 20,
              'currentPackage': '伊47',
              'currentFile': 'kcs2/resources/ship/full/0607.png',
              'completedFiles': 4,
              'totalFiles': 8,
              'completedBytes': 512,
              'totalBytes': 1024,
              'elapsedMillis': 1700,
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final snapshot = (await port.operationProgress())!;
      expect(calls, ['operationProgress']);
      expect(snapshot.operationId, 'native-1');
      expect(snapshot.currentPackage, '伊47');
      expect(snapshot.completedPackages, 3);
      expect(snapshot.totalPackages, 20);
      expect(snapshot.elapsedMillis, 1700);
      expect(snapshot.fraction, .5);
      final discovering = GameModsOperationProgress.fromMap({
        'phase': 'discover',
        'completedPackages': 3,
        'totalPackages': 20,
      });
      expect(discovering.fraction, isNull);
      expect(discovering.totalBytes, isNull);
      expect(
        GameModsOperationProgress.fromMap({
          'phase': 'read',
          'completedBytes': 3,
        }).fraction,
        isNull,
      );
    },
  );

  testWidgets(
    'progress polling stays independent of status and ignores inactive restoration',
    (tester) async {
      final port = _ReportingPort()
        ..snapshot = _progress('scan-1', phase: 'validate');
      final controller = GameModsController(port: port);
      await controller.initialize();
      controller.setVisible(true);
      expect(port.progressCalls, 0);
      final task = controller.scanLibrary();
      await tester.pump();
      expect(controller.operationProgress?.operationId, 'scan-1');
      port.snapshot = _progress('old-finished', active: false);
      await tester.pump(const Duration(seconds: 2));
      expect(port.statusCalls, 1);
      expect(port.progressCalls, greaterThan(1));
      expect(controller.operationProgress?.operationId, 'scan-1');
      expect(controller.operationElapsedMillis, greaterThanOrEqualTo(2100));
      port.scanGate.complete(_scan);
      await task;
      expect(controller.operationProgress, isNull);
      final calls = port.progressCalls;
      await tester.pump(const Duration(milliseconds: 600));
      expect(port.progressCalls, calls);
      controller.dispose();
    },
  );

  testWidgets(
    'late progress cannot revive a finished operation or overwrite a new operation',
    (tester) async {
      final firstReply = Completer<GameModsOperationProgress?>();
      final port = _ReportingPort()..reply = firstReply.future;
      final controller = GameModsController(port: port);
      await controller.initialize();
      final scan = controller.scanLibrary();
      await tester.pump();
      port.scanGate.complete(_scan);
      await scan;
      expect(controller.operationProgress, isNull);
      port.reply = null;
      port.snapshot = _progress(
        'import-2',
        operation: 'import',
        phase: 'import',
      );
      final commit = controller.confirmLibraryScan();
      await tester.pump();
      expect(controller.operationProgress?.operationId, 'import-2');
      firstReply.complete(_progress('scan-1'));
      await tester.pump();
      expect(controller.operationProgress?.operationId, 'import-2');
      port.snapshot = _progress('other-import', operation: 'import');
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.operationProgress?.operationId, 'import-2');
      port.commitGate.complete();
      await commit;
      expect(controller.operationProgress, isNull);
      controller.dispose();
    },
  );

  testWidgets(
    'disposing during a slow progress request stops polling and notifications',
    (tester) async {
      final reply = Completer<GameModsOperationProgress?>();
      final port = _ReportingPort()..reply = reply.future;
      final controller = GameModsController(port: port);
      await controller.initialize();
      var notifications = 0;
      controller.addListener(() => notifications++);
      final task = controller.scanLibrary();
      await tester.pump(const Duration(milliseconds: 600));
      expect(port.progressCalls, 1);
      controller.dispose();
      final count = notifications;
      reply.complete(_progress('late'));
      port.scanGate.complete(_scan);
      await task;
      await tester.pump(const Duration(seconds: 1));
      expect(port.progressCalls, 1);
      expect(notifications, count);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scan stays modal until complete, then preserves review and batch import',
    (tester) async {
      final port = _ProgressLibraryPort();
      final controller = GameModsController(port: port);
      await controller.initialize();
      await tester.pumpWidget(_app(controller));
      expect(
        find.byKey(const Key('game-mods-operation-progress')),
        findsNothing,
      );
      await tester.ensureVisible(
        find.byKey(const Key('game-mods-library-scan')),
      );
      await tester.tap(find.byKey(const Key('game-mods-library-scan')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final progress = find.byKey(const Key('game-mods-operation-progress'));
      expect(progress, findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.descendant(
                of: progress,
                matching: find.byType(LinearProgressIndicator),
              ),
            )
            .value,
        isNull,
      );
      expect(find.textContaining('%'), findsNothing);
      await tester.tapAt(const Offset(4, 4));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(progress, findsOneWidget);
      expect(controller.busy, isTrue);

      port.scanGate.complete(_scan);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(progress, findsNothing);
      expect(find.text('扫描结果'), findsOneWidget);
      await tester.tap(find.byKey(const Key('game-mods-library-scan-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(progress, findsOneWidget);
      port.commitGate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(progress, findsNothing);
      expect(controller.libraryScan, isNull);
      expect(port.applyCalls, 0);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'failed ZIP processing closes progress and keeps the page usable',
    (tester) async {
      final port = _ProgressLibraryPort();
      final controller = GameModsController(port: port);
      await controller.initialize();
      await tester.pumpWidget(_app(controller));
      final task = controller.pickArchive();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const Key('game-mods-operation-progress')),
        findsOneWidget,
      );
      port.archiveGate.completeError(PlatformException(code: 'invalid_zip'));
      await task;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const Key('game-mods-operation-progress')),
        findsNothing,
      );
      expect(controller.canEdit, isTrue);
      expect(controller.errorCode, 'invalid_zip');
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  for (final locale in const [
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    Locale('ja'),
    Locale('en'),
    Locale('ko'),
  ]) {
    testWidgets('progress fits a small screen in $locale', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final port = _ReportingPort()
        ..snapshot = _progress(
          'long-names',
          package: List.filled(20, '長い魔改包 Package 名称 ').join(),
          file: List.filled(20, 'kcs2/resources/ship/full/0607/').join(),
        );
      final controller = GameModsController(port: port);
      await controller.initialize();
      await tester.pumpWidget(_app(controller, locale: locale, textScale: 1.6));
      final task = controller.scanLibrary();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const Key('game-mods-operation-progress')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('game-mods-progress-package')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('game-mods-progress-file')), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        .5,
      );
      expect(tester.takeException(), isNull);
      port.scanGate.complete(_scan);
      await task;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }
}

Widget _app(
  GameModsController controller, {
  Locale locale = const Locale('zh'),
  double textScale = 1,
}) => MaterialApp(
  locale: locale,
  supportedLocales: [locale],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(body: GameModsPage(controller: controller)),
);

final _scan = GameModLibraryScan.fromMap({
  'token': 'scan-1',
  'entries': [
    {
      'id': 'new',
      'name': 'New package',
      'kind': 'new',
      'supportedCount': 1,
      'resourceCount': 1,
    },
  ],
});

class _ProgressLibraryPort extends FakeGameModsPort
    implements GameModsLibraryPort {
  _ProgressLibraryPort() {
    current = GameModsStatus.fromMap({
      ...current.toMap(),
      'library': {'configured': true, 'available': true, 'displayName': 'Mods'},
    });
  }
  final scanGate = Completer<GameModLibraryScan>();
  final archiveGate = Completer<GameModsPreflight?>();
  final commitGate = Completer<void>();
  @override
  Future<GameModsPreflight?> pickAndPreflightArchive() => archiveGate.future;
  @override
  Future<bool> chooseLibraryDirectory() async => true;
  @override
  Future<void> openLibraryDirectory() async {}
  @override
  Future<GameModLibraryScan> scanLibrary() => scanGate.future;
  @override
  Future<void> commitLibraryScan(String token) => commitGate.future;
  @override
  Future<void> discardLibraryScan(String token) async {}
}

class _ReportingPort extends _ProgressLibraryPort
    implements GameModsProgressPort {
  int progressCalls = 0;
  GameModsOperationProgress? snapshot;
  Future<GameModsOperationProgress?>? reply;
  @override
  Future<GameModsOperationProgress?> operationProgress() async {
    progressCalls++;
    return reply == null ? snapshot : await reply;
  }
}

GameModsOperationProgress _progress(
  String id, {
  String operation = 'scan',
  String phase = 'read',
  bool active = true,
  String package = 'Package A',
  String file = 'kcs2/resources/ship/full/0607.png',
}) => GameModsOperationProgress(
  operationId: id,
  operation: operation,
  phase: phase,
  active: active,
  completedPackages: 2,
  totalPackages: 10,
  currentPackage: package,
  currentFile: file,
  completedFiles: 3,
  totalFiles: 6,
  completedBytes: 512,
  totalBytes: 1024,
  elapsedMillis: 2100,
);
