import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_controller.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_models.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_port.dart';

import 'support/game_mod_portrait_platform_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(mockGameModPortraitPlatform);
  tearDown(clearGameModPortraitPlatformMock);

  test('master off preserves resource and package selections', () async {
    final port = FakeGameModsPort();
    final controller = GameModsController(port: port);
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.setMaster(false);
    await controller.flushDraft();
    expect(controller.status.draft.master, isFalse);
    expect(controller.status.draft.enabledPackages, {'a', 'b'});
    expect(controller.status.draft.enabledResources, {'a1', 'a2', 'b1'});
    expect(port.applyCalls, 0);
    expect(controller.status.pending, isTrue);
  });

  test(
    'saves serialize and apply waits for the latest saved selection',
    () async {
      final port = FakeGameModsPort()..saveGate = Completer<void>();
      final controller = GameModsController(port: port);
      addTearDown(controller.dispose);
      await controller.initialize();
      controller.setMaster(false);
      controller.setPackageEnabled('b', false);
      final applying = controller.apply();
      await Future<void>.delayed(Duration.zero);
      expect(port.applyCalls, 0);
      expect(port.maxConcurrentSaves, 1);
      port.saveGate!.complete();
      await applying;
      expect(port.saved.last.enabledPackages, {'a'});
      expect(port.applyCalls, 1);
      expect(controller.lastApplyResult, GameModsApplyResult.noGame);
    },
  );

  test('late status response cannot replace newer choices', () async {
    final port = FakeGameModsPort();
    final controller = GameModsController(port: port);
    addTearDown(controller.dispose);
    await controller.initialize();
    port.statusGate = Completer<GameModsStatus>();
    final refreshing = controller.refresh();
    controller.setPackageEnabled('a', false);
    await controller.flushDraft();
    port.statusGate!.complete(fixtureStatus());
    await refreshing;
    expect(controller.status.draft.enabledPackages, {'b'});
  });

  test(
    'atlas pair changes together and higher package wins conflicts',
    () async {
      final controller = GameModsController(port: FakeGameModsPort());
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.status.winners['kcs2/img/bg.png'], 'a1');
      controller.movePackage('b', -1);
      expect(controller.status.winners['kcs2/img/bg.png'], 'b1');
      controller.setResourceEnabled('a1', false);
      expect(controller.status.draft.enabledResources.contains('a2'), isFalse);
      await controller.flushDraft();
    },
  );

  testWidgets('polling runs only while visible and resumed', (tester) async {
    final port = FakeGameModsPort();
    final controller = GameModsController(port: port);
    await controller.initialize();
    controller.setVisible(true);
    await tester.pump(const Duration(seconds: 1));
    final visibleCalls = port.statusCalls;
    expect(visibleCalls, greaterThan(1));
    controller.setVisible(false);
    await tester.pump(const Duration(seconds: 3));
    expect(port.statusCalls, visibleCalls);
    controller.setVisible(true);
    controller.setAppResumed(false);
    await tester.pump(const Duration(seconds: 3));
    expect(port.statusCalls, visibleCalls);
    controller.dispose();
  });
  testWidgets('repeated visibility updates do not postpone status polling', (
    tester,
  ) async {
    final port = FakeGameModsPort();
    final controller = GameModsController(port: port);
    await controller.initialize();
    controller.setVisible(true);
    await tester.pump(const Duration(milliseconds: 500));
    controller.setVisible(true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(port.statusCalls, 2);
    controller.dispose();
  });

  test('cancelled picker and preflight cancellation never import', () async {
    final port = FakeGameModsPort();
    final controller = GameModsController(port: port);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.pickArchive();
    expect(controller.preflight, isNull);
    expect(controller.busy, isFalse);
    port.candidate = GameModsPreflight.fromMap({
      'token': 'temporary',
      'name': 'cache.zip',
      'resourceCount': 2,
      'supportedCount': 1,
      'unsupportedCount': 1,
    });
    await controller.pickArchive();
    await controller.cancelImport();
    expect(port.discarded, ['temporary']);
    expect(port.commitCalls, 0);
  });

  test(
    'package deletion and delete all stage files until explicit apply',
    () async {
      final port = FakeGameModsPort();
      final controller = GameModsController(port: port);
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.removePackage('a');
      expect(port.removed, ['a']);
      expect(port.applyCalls, 0);
      expect(controller.status.packages.first.pendingRemoval, isTrue);
      await controller.resetAll();
      expect(port.resetCalls, 1);
      expect(port.applyCalls, 0);
      expect(controller.status.packages.every((p) => p.pendingRemoval), isTrue);
      expect(controller.status.pending, isTrue);
      await controller.apply();
      expect(port.applyCalls, 1);
      expect(controller.status.packages, isEmpty);
      expect(controller.status.draft.master, isFalse);
    },
  );

  test(
    'cancel restores deleted packages, switches, resources, and order',
    () async {
      final port = FakeGameModsPort();
      final controller = GameModsController(port: port);
      addTearDown(controller.dispose);
      await controller.initialize();
      controller.setMaster(false);
      controller.setPackageEnabled('b', false);
      controller.setResourceEnabled('a1', false);
      controller.movePackage('b', -1);
      await controller.removePackage('a');
      controller.lastApplyResult = GameModsApplyResult.blocked;
      expect(controller.status.pending, isTrue);

      await controller.cancelChanges();

      expect(port.cancelCalls, 1);
      expect(port.applyCalls, 0);
      expect(controller.status.draft.sameAs(fixtureStatus().applied), isTrue);
      expect(controller.status.pending, isFalse);
      expect(controller.status.packages.any((p) => p.pendingRemoval), isFalse);
      expect(controller.status.activeWinners, fixtureStatus().activeWinners);
      expect(controller.status.winners, fixtureStatus().winners);
      expect(controller.status.sessionId, fixtureStatus().sessionId);
      expect(controller.lastApplyResult, isNull);
      expect(controller.errorCode, isNull);
    },
  );

  test('cancel retains newly imported files as disabled packages', () async {
    final port = FakeGameModsPort();
    port.current = GameModsStatus.fromMap({
      ...port.current.toMap(),
      'packages': [
        ...port.current.packages.map((p) => p.toMap()),
        {'id': 'c', 'name': 'New import', 'resources': <Object>[]},
      ],
      'draft': {
        ...port.current.draft.toMap(),
        'order': ['c', 'b', 'a'],
        'enabledPackages': ['a', 'b', 'c'],
      },
      'pending': true,
    });
    final controller = GameModsController(port: port);
    addTearDown(controller.dispose);
    await controller.initialize();

    await controller.cancelChanges();

    expect(controller.status.packages.map((p) => p.id), ['a', 'b', 'c']);
    expect(controller.status.draft.order, ['a', 'b', 'c']);
    expect(controller.status.draft.enabledPackages, {'a', 'b'});
    expect(port.removed, isEmpty);
    expect(port.applyCalls, 0);
    expect(
      controller.status.withDraft(controller.status.draft).pending,
      isFalse,
    );
    expect(controller.status.withRuntimeFrom(port.current).pending, isFalse);
    controller.setPackageEnabled('c', true);
    await controller.flushDraft();
    expect(controller.status.pending, isTrue);
    controller.setPackageEnabled('c', false);
    await controller.flushDraft();
    expect(controller.status.pending, isFalse);
  });

  test(
    'disabled imported order is normalized when comparing applied choices',
    () {
      final baseline = fixtureStatus();
      final status = GameModsStatus.fromMap({
        ...baseline.toMap(),
        'packages': [
          ...baseline.packages.map((p) => p.toMap()),
          {'id': 'c', 'name': 'New import', 'resources': <Object>[]},
        ],
        'draft': baseline.applied.copyWith(order: ['a', 'b', 'c']).toMap(),
      });
      expect(status.withDraft(status.draft).pending, isFalse);
      expect(status.withRuntimeFrom(status).pending, isFalse);
      expect(
        status.withDraft(status.draft.copyWith(order: ['b', 'a', 'c'])).pending,
        isTrue,
      );
    },
  );

  test('cancel recovers unsaved edits even after draft saving fails', () async {
    final port = FakeGameModsPort()..failSave = true;
    final controller = GameModsController(port: port);
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.setMaster(false);
    await controller.flushDraft();
    expect(controller.saveFailed, isTrue);

    await controller.cancelChanges();

    expect(port.cancelCalls, 1);
    expect(controller.saveFailed, isFalse);
    expect(controller.status.draft.master, isTrue);
    expect(controller.status.pending, isFalse);
    expect(controller.errorCode, isNull);
    expect(port.applyCalls, 0);
  });

  test(
    'cancel waits for saves and blocks concurrent editing or cancellation',
    () async {
      final port = FakeGameModsPort()
        ..saveGate = Completer<void>()
        ..cancelGate = Completer<void>();
      final controller = GameModsController(port: port);
      addTearDown(controller.dispose);
      await controller.initialize();
      controller.setMaster(false);
      final cancelling = controller.cancelChanges();
      await Future<void>.delayed(Duration.zero);
      expect(controller.busy, isTrue);
      expect(port.cancelCalls, 0);
      controller.setPackageEnabled('b', false);
      await controller.cancelChanges();
      expect(controller.status.draft.enabledPackages, {'a', 'b'});
      port.saveGate!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(port.cancelCalls, 1);
      expect(controller.busy, isTrue);
      await controller.apply();
      expect(port.applyCalls, 0);
      port.cancelGate!.complete();
      await cancelling;
      expect(controller.busy, isFalse);
      expect(controller.status.pending, isFalse);
    },
  );

  test(
    'a status response started before cancel cannot restore a deletion',
    () async {
      final port = FakeGameModsPort();
      final controller = GameModsController(port: port);
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.removePackage('a');
      final stale = port.current;
      final response = Completer<GameModsStatus>();
      port.statusGate = response;
      final polling = controller.refresh();
      port.statusGate = null;

      await controller.cancelChanges();
      response.complete(stale);
      await polling;

      expect(controller.status.pending, isFalse);
      expect(controller.status.packages.first.pendingRemoval, isFalse);
      expect(port.cancelCalls, 1);
    },
  );

  test(
    'a failed status request started before cancel cannot add a stale error',
    () async {
      final port = FakeGameModsPort();
      final controller = GameModsController(port: port);
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.removePackage('a');
      final response = Completer<GameModsStatus>();
      port.statusGate = response;
      final polling = controller.refresh();
      port.statusGate = null;

      await controller.cancelChanges();
      response.completeError(PlatformException(code: 'stale_status_error'));
      await polling;

      expect(controller.status.pending, isFalse);
      expect(controller.errorCode, isNull);
    },
  );

  test(
    'failed cancellation preserves pending deletion and allows retry',
    () async {
      final port = FakeGameModsPort()..failCancel = true;
      final controller = GameModsController(port: port);
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.removePackage('a');

      await controller.cancelChanges();

      expect(controller.status.pending, isTrue);
      expect(controller.status.packages.first.pendingRemoval, isTrue);
      expect(controller.errorCode, 'storage_error');
      expect(controller.busy, isFalse);
      port.failCancel = false;
      await controller.cancelChanges();
      expect(controller.status.pending, isFalse);
      expect(controller.errorCode, isNull);
      expect(port.cancelCalls, 2);
      expect(port.applyCalls, 0);
    },
  );

  test('cancel does nothing when there is nothing to discard', () async {
    final port = FakeGameModsPort();
    final controller = GameModsController(port: port);
    addTearDown(controller.dispose);
    await controller.initialize();

    await controller.cancelChanges();

    expect(port.cancelCalls, 0);
    expect(controller.busy, isFalse);
  });

  test('missing plugin is a stable unsupported capability', () async {
    final port = FakeGameModsPort()..missing = true;
    final controller = GameModsController(port: port);
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.setVisible(true);
    await controller.refresh();
    expect(controller.supported, isFalse);
    expect(controller.errorCode, 'unsupported');
    expect(port.statusCalls, 0);
  });
  test(
    'native unsupported_platform becomes a stable unsupported state',
    () async {
      final port = FakeGameModsPort()..unsupportedPlatform = true;
      final controller = GameModsController(port: port);
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.supported, isFalse);
      expect(controller.errorCode, 'unsupported');
      expect(port.statusCalls, 0);
    },
  );

  test(
    'failed save keeps choices and prevents applying stale native config',
    () async {
      final port = FakeGameModsPort()..failSave = true;
      final controller = GameModsController(port: port);
      addTearDown(controller.dispose);
      await controller.initialize();
      controller.setMaster(false);
      await controller.flushDraft();
      await controller.refresh();
      expect(controller.status.draft.master, isFalse);
      await controller.apply();
      expect(port.applyCalls, 0);
      port.failSave = false;
      await controller.retrySave();
      await controller.apply();
      expect(port.applyCalls, 1);
    },
  );

  test(
    'status requested before apply cannot revert new session telemetry',
    () async {
      final port = FakeGameModsPort();
      final controller = GameModsController(port: port);
      addTearDown(controller.dispose);
      await controller.initialize();
      final oldResponse = Completer<GameModsStatus>();
      port.statusGate = oldResponse;
      final polling = controller.refresh();
      port.statusGate = null;
      controller.setMaster(false);
      await controller.apply();
      oldResponse.complete(fixtureStatus());
      await polling;
      expect(controller.status.applied.master, isFalse);
    },
  );

  test(
    'independent images in one ship group remain individually selectable',
    () async {
      final port = FakeGameModsPort();
      port.current = GameModsStatus.fromMap({
        ...fixtureStatus().toMap(),
        'packages': [
          {
            'id': 'a',
            'name': 'Images',
            'resources': [
              {
                'id': 'a1',
                'path': 'kcs2/resources/ship/full/0001.png',
                'kind': 'ship',
                'supported': true,
                'groupId': 'ship:0001',
              },
              {
                'id': 'a2',
                'path': 'kcs2/resources/ship/card/0001.png',
                'kind': 'ship',
                'supported': true,
                'groupId': 'ship:0001',
              },
            ],
          },
        ],
      });
      final controller = GameModsController(port: port);
      addTearDown(controller.dispose);
      await controller.initialize();
      controller.setResourceEnabled('a1', false);
      expect(controller.status.draft.enabledResources.contains('a2'), isTrue);
      await controller.flushDraft();
    },
  );
}

GameModsStatus fixtureStatus() => GameModsStatus.fromMap({
  'packages': [
    {
      'id': 'a',
      'name': 'Ocean',
      'sizeBytes': 1024,
      'resources': [
        {
          'id': 'a1',
          'path': 'kcs2/img/bg.png',
          'label': 'Background',
          'kind': 'image',
          'supported': true,
          'groupId': 'atlas',
        },
        {
          'id': 'a2',
          'path': 'kcs2/img/bg.json',
          'label': 'Coordinates',
          'kind': 'atlas',
          'supported': true,
          'groupId': 'atlas',
        },
      ],
    },
    {
      'id': 'b',
      'name': 'Night',
      'resources': [
        {
          'id': 'b1',
          'path': 'kcs2/img/bg.png',
          'label': 'Night background',
          'kind': 'image',
          'supported': true,
        },
        {
          'id': 'b2',
          'path': 'kcs2/old.swf',
          'kind': 'other',
          'supported': false,
          'reason': 'unsupported_type',
        },
      ],
    },
  ],
  'draft': {
    'master': true,
    'order': ['a', 'b'],
    'enabledPackages': ['a', 'b'],
    'enabledResources': ['a1', 'a2', 'b1'],
  },
  'applied': {
    'master': true,
    'order': ['a', 'b'],
    'enabledPackages': ['a', 'b'],
    'enabledResources': ['a1', 'a2', 'b1'],
  },
  'winners': {'kcs2/img/bg.png': 'a1', 'kcs2/img/bg.json': 'a2'},
  'activeWinners': {'kcs2/img/bg.png': 'a1', 'kcs2/img/bg.json': 'a2'},
  'hits': [],
  'failures': {},
  'pending': false,
  'sessionId': 1,
});

class FakeGameModsPort implements GameModsPort {
  GameModsStatus current = fixtureStatus();
  final saved = <GameModsConfig>[];
  final discarded = <String>[];
  final removed = <String>[];
  Completer<void>? saveGate;
  Completer<void>? cancelGate;
  Completer<GameModsStatus>? statusGate;
  GameModsPreflight? candidate;
  int statusCalls = 0, applyCalls = 0, resetCalls = 0, commitCalls = 0;
  int cancelCalls = 0;
  int concurrentSaves = 0, maxConcurrentSaves = 0;
  bool missing = false;
  bool unsupportedPlatform = false;
  bool failSave = false;
  bool failCancel = false;

  @override
  Future<GameModsCapabilities> capabilities() async {
    if (unsupportedPlatform) {
      throw PlatformException(code: 'unsupported_platform');
    }
    if (missing) throw MissingPluginException();
    return const GameModsCapabilities(supported: true);
  }

  @override
  Future<GameModsStatus> status() async {
    statusCalls++;
    final gate = statusGate;
    return gate == null ? current : gate.future;
  }

  @override
  Future<void> saveDraft(GameModsConfig config) async {
    if (failSave) throw PlatformException(code: 'storage_error');
    concurrentSaves++;
    if (concurrentSaves > maxConcurrentSaves) {
      maxConcurrentSaves = concurrentSaves;
    }
    await saveGate?.future;
    saved.add(config);
    current = current.withDraft(config);
    concurrentSaves--;
  }

  @override
  Future<GameModsApplyResult> applyAndReload() async {
    applyCalls++;
    current = GameModsStatus.fromMap({
      ...current.toMap(),
      'packages': current.packages
          .where((p) => !p.pendingRemoval)
          .map((p) => p.toMap())
          .toList(),
      'applied': current.draft.toMap(),
      'pending': false,
    });
    return GameModsApplyResult.noGame;
  }

  @override
  Future<GameModsPreflight?> pickAndPreflightArchive() async => candidate;
  @override
  Future<void> commitImport(String token) async {
    commitCalls++;
  }

  @override
  Future<void> discardImport(String token) async {
    discarded.add(token);
  }

  @override
  Future<void> removePackage(String id) async {
    removed.add(id);
    current = GameModsStatus.fromMap({
      ...current.toMap(),
      'packages': current.packages
          .map((p) => {...p.toMap(), if (p.id == id) 'pendingRemoval': true})
          .toList(),
      'pending': true,
    });
  }

  @override
  Future<void> resetAll() async {
    resetCalls++;
    current = GameModsStatus.fromMap({
      ...current.toMap(),
      'draft': const GameModsConfig().toMap(),
      'packages': current.packages
          .map((p) => {...p.toMap(), 'pendingRemoval': true})
          .toList(),
      'pending': true,
    });
  }

  @override
  Future<void> cancelChanges() async {
    cancelCalls++;
    await cancelGate?.future;
    if (failCancel) throw PlatformException(code: 'storage_error');
    final existing = current.packages.map((p) => p.id).toSet();
    final order = [
      ...current.applied.order.where(existing.contains),
      ...existing.where((id) => !current.applied.order.contains(id)),
    ];
    final restored = current.applied.copyWith(order: order);
    current = GameModsStatus.fromMap({
      ...current.toMap(),
      'draft': restored.toMap(),
      'packages': current.packages
          .map((p) => {...p.toMap(), 'pendingRemoval': false})
          .toList(),
      'pending': false,
    });
    current = current.withDraft(restored);
  }
}
