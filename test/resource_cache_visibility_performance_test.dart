import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_resource_cache_channel.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_resource_cache_controller.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_resource_cache_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/game_resource_cache_section.dart';
import 'package:yahagi_kancolle_browser/src/widgets/lazy_indexed_stack.dart';

class _Store implements GameResourceCacheStore {
  @override
  Future<GameResourceCacheMode> load() async => GameResourceCacheMode.temporary;
  @override
  Future<void> save(GameResourceCacheMode mode) async {}
}

class _Port implements GameResourceCachePort {
  int reads = 0;
  int actions = 0;
  GameResourceCacheStatus snapshot = GameResourceCacheStatus.empty;
  Completer<GameResourceCacheStatus>? statusGate;

  @override
  Future<GameResourceCacheStatus> status() async {
    reads++;
    final gate = statusGate;
    return gate == null ? snapshot : await gate.future;
  }

  @override
  Future<bool> configure(GameResourceCacheMode mode) async => true;
  @override
  Future<bool> setManifest(
    GameResourceManifest manifest, {
    bool Function()? shouldContinue,
  }) async => true;
  @override
  Future<bool> startDownload({bool allowMetered = false}) async {
    actions++;
    return true;
  }

  @override
  Future<bool> pauseDownload() async {
    actions++;
    return true;
  }

  @override
  Future<bool> clear() async => true;
  @override
  Future<bool> repair({bool allowMetered = false}) async => true;
  @override
  Future<GameResourceCacheStatus> checkIntegrity() async => snapshot;
}

GameResourceCacheStatus _snapshot({String state = 'idle', int bytes = 0}) =>
    GameResourceCacheStatus.fromMap({
      'mode': 'temporary',
      'state': state,
      'cachedBytes': bytes,
    });

Widget _host(GameResourceCacheController controller, ValueNotifier<int> tab) =>
    MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<int>(
          valueListenable: tab,
          builder: (context, index, _) => LazyIndexedStack(
            index: index,
            children: [
              SingleChildScrollView(
                child: GameResourceCacheSection(controller: controller),
              ),
              const Text('other tab'),
            ],
          ),
        ),
      ),
    );

void main() {
  testWidgets(
    'retained hidden cache tab stops idle reads and refreshes on show',
    (tester) async {
      final port = _Port();
      final controller = GameResourceCacheController(
        store: _Store(),
        port: port,
      );
      final tab = ValueNotifier(0);
      addTearDown(controller.dispose);
      addTearDown(tab.dispose);
      await controller.initialize();
      await tester.pumpWidget(_host(controller, tab));
      await tester.pump(const Duration(seconds: 1));
      tab.value = 1;
      await tester.pump();
      expect(
        find.byType(GameResourceCacheSection, skipOffstage: false),
        findsOneWidget,
      );
      final before = port.reads;
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(port.reads, before);
      port.snapshot = _snapshot(bytes: 1000000000);
      tab.value = 0;
      await tester.pump();
      await tester.pump();
      expect(find.text('已缓存 1.00 GB'), findsOneWidget);
      expect(port.reads, before + 1);
      expect(port.actions, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'idle cache polling pauses in background and keeps inactive live',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final port = _Port();
      final controller = GameResourceCacheController(
        store: _Store(),
        port: port,
      );
      final tab = ValueNotifier(0);
      addTearDown(controller.dispose);
      addTearDown(tab.dispose);
      await controller.initialize();
      await tester.pumpWidget(_host(controller, tab));
      await tester.pump(const Duration(seconds: 1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final before = port.reads;
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(port.reads, before);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      final visibleReads = port.reads;
      await tester.pump(const Duration(seconds: 1));
      expect(port.reads, visibleReads + 1);
      expect(port.actions, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('hidden tab keeps observing real downloads through completion', (
    tester,
  ) async {
    final port = _Port()..snapshot = _snapshot(state: 'downloading');
    final controller = GameResourceCacheController(store: _Store(), port: port);
    final tab = ValueNotifier(0);
    addTearDown(controller.dispose);
    addTearDown(tab.dispose);
    await controller.initialize();
    await tester.pumpWidget(_host(controller, tab));
    tab.value = 1;
    await tester.pump();
    final before = port.reads;
    await tester.pump(const Duration(seconds: 1));
    expect(port.reads, before + 1);
    port.snapshot = _snapshot(state: 'complete', bytes: 1000000000);
    await tester.pump(const Duration(seconds: 1));
    expect(controller.status.state, GameResourceCacheState.complete);
    final completedReads = port.reads;
    await tester.pump(const Duration(seconds: 3));
    expect(port.reads, completedReads);
    expect(port.actions, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('first background mount stays idle and unregisters on removal', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final port = _Port();
    final controller = GameResourceCacheController(store: _Store(), port: port);
    final tab = ValueNotifier(0);
    try {
      await controller.initialize();
      final initialReads = port.reads;
      // Mount a test frame without changing the lifecycle seen by initState.
      tester.binding.scheduleForcedFrame();
      await tester.pumpWidget(_host(controller, tab));
      expect(find.byType(GameResourceCacheSection), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(port.reads, initialReads);

      port.snapshot = _snapshot(bytes: 1000000000);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(port.reads, initialReads + 1);
      expect(find.text('已缓存 1.00 GB'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(port.reads, initialReads + 2);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      final hiddenReads = port.reads;
      await tester.pump(const Duration(seconds: 2));
      expect(port.reads, hiddenReads);
      tester.binding.scheduleForcedFrame();
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 1));
      expect(
        port.reads,
        hiddenReads,
        reason: 'removed observer must stay silent',
      );
      expect(port.actions, 0);
      expect(tester.takeException(), isNull);
    } finally {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      tab.dispose();
    }
  });

  testWidgets(
    'hidden controller replacement ignores old reads and resumes new',
    (tester) async {
      final oldPort = _Port();
      final newPort = _Port();
      final oldController = GameResourceCacheController(
        store: _Store(),
        port: oldPort,
      );
      final newController = GameResourceCacheController(
        store: _Store(),
        port: newPort,
      );
      final active = ValueNotifier(oldController);
      final tab = ValueNotifier(0);
      final lateReply = Completer<GameResourceCacheStatus>();
      try {
        await oldController.initialize();
        await newController.initialize();
        await tester.pumpWidget(
          ValueListenableBuilder<GameResourceCacheController>(
            valueListenable: active,
            builder: (context, controller, _) => _host(controller, tab),
          ),
        );
        final sectionState = tester.state(
          find.byType(GameResourceCacheSection),
        );
        oldPort.statusGate = lateReply;
        final oldRead = oldController.refresh();
        await tester.pump();
        tab.value = 1;
        await tester.pump();
        active.value = newController;
        await tester.pump();
        expect(
          tester.state(
            find.byType(GameResourceCacheSection, skipOffstage: false),
          ),
          same(sectionState),
        );
        final oldReads = oldPort.reads;
        final newReads = newPort.reads;
        oldPort.statusGate = null;
        lateReply.complete(_snapshot(bytes: 1000000000));
        await oldRead;
        await tester.pump(const Duration(seconds: 2));
        expect(oldPort.reads, oldReads);
        expect(newPort.reads, newReads);

        newPort.snapshot = _snapshot(bytes: 2000000000);
        tab.value = 0;
        await tester.pump();
        await tester.pump();
        expect(oldPort.reads, oldReads);
        expect(newPort.reads, newReads + 1);
        expect(find.text('已缓存 2.00 GB'), findsOneWidget);
        expect(oldPort.actions + newPort.actions, 0);
        expect(tester.takeException(), isNull);
      } finally {
        if (!lateReply.isCompleted) {
          lateReply.complete(GameResourceCacheStatus.empty);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        oldController.dispose();
        newController.dispose();
        active.dispose();
        tab.dispose();
      }
    },
  );
}
