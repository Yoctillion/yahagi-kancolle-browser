import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_resource_cache_channel.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_resource_cache_controller.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_resource_cache_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'saved off startup waits for native configure before allowing navigation',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        SharedPreferencesGameResourceCacheStore.preferenceKey: 'none',
      });
      final port = FakePort()..configureGate = Completer<void>();
      final controller = GameResourceCacheController(
        store: SharedPreferencesGameResourceCacheStore(),
        port: port,
      );
      var mayNavigate = false;
      final startup = controller
          .initialize(loadStatus: false)
          .then((_) => mayNavigate = true);
      await Future<void>.delayed(Duration.zero);
      expect(port.configured, <GameResourceCacheMode>[
        GameResourceCacheMode.none,
      ]);
      expect(mayNavigate, isFalse);
      port.configureGate!.complete();
      await startup;
      expect(mayNavigate, isTrue);
      expect(port.nativeMode, GameResourceCacheMode.none);
      expect(port.statusCalls, 0);
      controller.dispose();
    },
  );
  test('startup can apply saved mode without waiting for status', () async {
    final port = FakePort()..statusGate = Completer<void>();
    final controller = GameResourceCacheController(
      store: MemoryStore(GameResourceCacheMode.none),
      port: port,
    );
    await controller.initialize(loadStatus: false);
    expect(controller.initialized, isTrue);
    expect(controller.mode, GameResourceCacheMode.none);
    expect(port.nativeMode, GameResourceCacheMode.none);
    expect(port.statusCalls, 0);
    port.statusGate!.complete();
    await controller.refresh();
    expect(port.statusCalls, 1);
    controller.dispose();
  });

  test(
    'status captured before a mode change cannot notify stale data',
    () async {
      final port = FakePort();
      final controller = GameResourceCacheController(
        store: MemoryStore(),
        port: port,
      );
      await controller.initialize(loadStatus: false);
      port.statusGate = Completer<void>();
      port.statusEntered = Completer<void>();
      port.nextStatus = GameResourceCacheStatus.fromMap(<Object?, Object?>{
        'mode': 'full',
        'cachedBytes': 777,
      });
      final observedBytes = <int>[];
      controller.addListener(
        () => observedBytes.add(controller.status.cachedBytes),
      );
      final stale = controller.refresh();
      await port.statusEntered!.future;
      final change = controller.setMode(GameResourceCacheMode.temporary);
      await Future<void>.delayed(Duration.zero);
      port.nextStatus = GameResourceCacheStatus.empty;
      port.statusGate!.complete();
      await stale;
      await change;
      expect(observedBytes, isNot(contains(777)));
      expect(controller.mode, GameResourceCacheMode.temporary);
      controller.dispose();
    },
  );

  test(
    'saved off mode is never replaced by temporary after configure rejection',
    () async {
      final port = FakePort()..configureResult = false;
      final controller = GameResourceCacheController(
        store: MemoryStore(),
        port: port,
      );
      await controller.initialize();
      expect(controller.mode, GameResourceCacheMode.none);
      expect(port.configured, <GameResourceCacheMode>[
        GameResourceCacheMode.none,
      ]);
      controller.dispose();
    },
  );

  test('late initialize result cannot notify after disposal', () async {
    final port = FakePort()..configureGate = Completer<void>();
    final controller = GameResourceCacheController(
      store: MemoryStore(),
      port: port,
    );
    final pending = controller.initialize();
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    port.configureGate!.complete();
    await expectLater(pending, completes);
    expect(port.statusCalls, 0);
  });

  test('formats completeness as one capacity line', () {
    expect(formatCacheCompleteness(6840000000, 8120000000), '6.84 GB');
  });

  test(
    'does not show the cache capacity as an unknown manifest size',
    () async {
      final port = FakePort()
        ..nextStatus = const GameResourceCacheStatus(
          mode: GameResourceCacheMode.full,
          state: GameResourceCacheState.idle,
          cachedBytes: 0,
          maxBytes: 10000000000,
          targetBytes: 0,
          downloadedBytes: 0,
          bytesPerSecond: 0,
          remainingSeconds: null,
          missingCount: 0,
          damagedCount: 0,
          fileCount: 0,
          capacityBlocked: false,
        );
      final controller = GameResourceCacheController(
        store: MemoryStore(),
        port: port,
      );
      await controller.initialize();

      expect(controller.completenessLine, '0.00 GB');
      controller.dispose();
    },
  );

  test(
    'changing mode configures native cache without clearing files',
    () async {
      final store = MemoryStore();
      final port = FakePort();
      final controller = GameResourceCacheController(store: store, port: port);
      await controller.initialize();

      await controller.setMode(GameResourceCacheMode.full);
      await controller.setMode(GameResourceCacheMode.none);

      expect(store.mode, GameResourceCacheMode.none);
      expect(port.configured, <GameResourceCacheMode>[
        GameResourceCacheMode.none,
        GameResourceCacheMode.full,
        GameResourceCacheMode.none,
      ]);
      expect(port.clearCalls, 0);
      controller.dispose();
    },
  );

  test(
    'maps native progress and uses manifest target in capacity line',
    () async {
      final port = FakePort()
        ..nextStatus = const GameResourceCacheStatus(
          mode: GameResourceCacheMode.full,
          state: GameResourceCacheState.downloading,
          cachedBytes: 6840000000,
          maxBytes: 10000000000,
          targetBytes: 8120000000,
          downloadedBytes: 100,
          bytesPerSecond: 20,
          remainingSeconds: 50,
          missingCount: 3,
          damagedCount: 1,
          fileCount: 1284,
          capacityBlocked: false,
        );
      final controller = GameResourceCacheController(
        store: MemoryStore(GameResourceCacheMode.full),
        port: port,
      );

      await controller.initialize();

      expect(controller.status.state, GameResourceCacheState.downloading);
      expect(controller.completenessLine, '6.84 GB');
      controller.dispose();
    },
  );

  test('overlapping status refreshes are coalesced', () async {
    final port = FakePort();
    final controller = GameResourceCacheController(
      store: MemoryStore(),
      port: port,
    );
    await controller.initialize();
    port.statusGate = Completer<void>();
    port.statusEntered = Completer<void>();

    final first = controller.refresh();
    await port.statusEntered!.future;
    final second = controller.refresh();
    await Future<void>.delayed(Duration.zero);

    expect(port.statusCalls, 2);
    port.statusGate!.complete();
    await Future.wait(<Future<void>>[first, second]);
    expect(port.statusCalls, 3);
    controller.dispose();
  });

  test(
    'rejected native mode change leaves persisted and visible mode intact',
    () async {
      final store = MemoryStore();
      final port = FakePort();
      final controller = GameResourceCacheController(store: store, port: port);
      await controller.initialize();
      port.configureResult = false;
      port.configureResults.addAll(<bool>[false, true]);

      expect(await controller.setMode(GameResourceCacheMode.full), isFalse);
      expect(store.mode, GameResourceCacheMode.none);
      expect(controller.mode, GameResourceCacheMode.none);
      expect(port.nativeMode, GameResourceCacheMode.none);
      controller.dispose();
    },
  );

  test(
    'initial full mode rejection returns to a usable temporary mode',
    () async {
      final store = MemoryStore(GameResourceCacheMode.full);
      final port = FakePort()..configureResults.addAll(<bool>[false, true]);
      final controller = GameResourceCacheController(store: store, port: port);

      await controller.initialize();

      expect(controller.initialized, isTrue);
      expect(controller.mode, GameResourceCacheMode.temporary);
      expect(store.mode, GameResourceCacheMode.temporary);
      expect(port.nativeMode, GameResourceCacheMode.temporary);
      controller.dispose();
    },
  );

  test(
    'optional cache initialization failure does not block startup',
    () async {
      final store = MemoryStore(GameResourceCacheMode.full);
      final port = FakePort()..configureResults.addAll(<bool>[false, false]);
      final controller = GameResourceCacheController(store: store, port: port);

      await controller.initialize();

      expect(controller.initialized, isFalse);
      expect(controller.mode, GameResourceCacheMode.temporary);
      expect(port.statusCalls, 0);
      controller.dispose();
    },
  );

  test('rapid mode changes configure native in request order', () async {
    final store = MemoryStore();
    final port = FakePort();
    final controller = GameResourceCacheController(store: store, port: port);
    await controller.initialize();
    port.configureGate = Completer<void>();
    final first = controller.setMode(GameResourceCacheMode.full);
    final second = controller.setMode(GameResourceCacheMode.temporary);
    await Future<void>.delayed(Duration.zero);
    expect(port.configured, <GameResourceCacheMode>[
      GameResourceCacheMode.none,
      GameResourceCacheMode.full,
    ]);
    port.configureGate!.complete();
    await Future.wait<bool>(<Future<bool>>[first, second]);
    expect(store.mode, GameResourceCacheMode.temporary);
    expect(controller.mode, GameResourceCacheMode.temporary);
    expect(port.configured.last, GameResourceCacheMode.temporary);
    controller.dispose();
  });

  test('failed preference write restores the previous native mode', () async {
    final store = MemoryStore();
    final port = FakePort();
    final controller = GameResourceCacheController(store: store, port: port);
    await controller.initialize();
    store.failSave = true;

    expect(await controller.setMode(GameResourceCacheMode.full), isFalse);
    expect(store.mode, GameResourceCacheMode.none);
    expect(controller.mode, GameResourceCacheMode.none);
    expect(port.configured, <GameResourceCacheMode>[
      GameResourceCacheMode.none,
      GameResourceCacheMode.full,
      GameResourceCacheMode.none,
    ]);
    controller.dispose();
  });

  test('failed native rollback disables cache controls', () async {
    final store = MemoryStore();
    final port = FakePort();
    final controller = GameResourceCacheController(store: store, port: port);
    await controller.initialize();
    store.failSave = true;
    port.configureResults.addAll(<bool>[true, false]);

    expect(await controller.setMode(GameResourceCacheMode.full), isFalse);
    expect(controller.initialized, isFalse);
    expect(store.mode, GameResourceCacheMode.none);
    expect(controller.mode, GameResourceCacheMode.none);
    controller.dispose();
  });
}

final class MemoryStore implements GameResourceCacheStore {
  MemoryStore([this.mode = GameResourceCacheMode.none]);
  GameResourceCacheMode mode;
  bool failSave = false;

  @override
  Future<GameResourceCacheMode> load() async => mode;

  @override
  Future<void> save(GameResourceCacheMode value) async {
    if (failSave) throw StateError('write failed');
    mode = value;
  }
}

final class FakePort implements GameResourceCachePort {
  final List<GameResourceCacheMode> configured = <GameResourceCacheMode>[];
  int clearCalls = 0;
  int statusCalls = 0;
  Completer<void>? statusGate;
  Completer<void>? statusEntered;
  Completer<void>? configureGate;
  bool configureResult = true;
  final List<bool> configureResults = <bool>[];
  GameResourceCacheMode nativeMode = GameResourceCacheMode.temporary;
  GameResourceCacheStatus nextStatus = GameResourceCacheStatus.empty;

  @override
  Future<bool> configure(GameResourceCacheMode mode) async {
    configured.add(mode);
    nativeMode = mode;
    await configureGate?.future;
    final result = configureResults.isEmpty
        ? configureResult
        : configureResults.removeAt(0);
    return result;
  }

  @override
  Future<GameResourceCacheStatus> status() async {
    statusCalls++;
    final response = nextStatus;
    final gate = statusGate;
    if (gate != null) {
      final entered = statusEntered;
      if (entered != null && !entered.isCompleted) entered.complete();
      await gate.future;
    }
    return response;
  }

  @override
  Future<bool> setManifest(
    GameResourceManifest manifest, {
    bool Function()? shouldContinue,
  }) async => shouldContinue?.call() ?? true;

  @override
  Future<bool> startDownload({bool allowMetered = false}) async => true;

  @override
  Future<bool> pauseDownload() async => true;

  @override
  Future<GameResourceCacheStatus> checkIntegrity() async => nextStatus;

  @override
  Future<bool> repair({bool allowMetered = false}) async => true;

  @override
  Future<bool> clear() async {
    clearCalls++;
    return true;
  }
}
