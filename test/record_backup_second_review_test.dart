import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/src/account/account_session.dart';
import 'package:yahagi_kancolle_browser/src/backup/record_backup.dart';
import 'package:yahagi_kancolle_browser/src/logbook/logbook_database.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/composition_record_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('failed automatic batch makes the lifecycle flush fail', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    await fixture.write(1);
    fixture.port.failNextWrite = true;

    await expectLater(
      fixture.service.flush(),
      throwsA(isA<FileSystemException>()),
      reason: 'A durability barrier must report an unwritten batch.',
    );
    expect(fixture.service.pending, isTrue);
    expect(fixture.service.lastError, contains('simulated backup failure'));

    await fixture.service.flush();
    expect(fixture.savedRows, hasLength(1));
    expect(fixture.service.pending, isFalse);
    expect(fixture.service.lastError, isNull);
  });

  test(
    'failed automatic batch keeps writes arriving before its failure',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      await fixture.write(1);
      fixture.port.failNextWrite = true;
      fixture.port.beforeWrite = () async {
        fixture.port.beforeWrite = null;
        await fixture.write(2);
      };

      try {
        await fixture.service.flush();
      } on FileSystemException {
        // The first barrier reports the failure. The next one must retry the
        // original snapshot and the write that arrived during the failed pass.
      }
      expect(
        fixture.service.pending,
        isTrue,
        reason: 'An automatic failure cannot acknowledge either dirty write.',
      );

      await fixture.service.flush();
      expect(fixture.savedRows, hasLength(2));
      expect(fixture.service.pending, isFalse);
    },
  );

  test(
    'close reports an automatic batch that could not be persisted',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      await fixture.write(1);
      fixture.port.failNextWrite = true;

      await expectLater(
        fixture.service.close(),
        throwsA(isA<FileSystemException>()),
        reason:
            'Closing cannot report success after discarding the last batch.',
      );
    },
  );

  test(
    'repeated close retries its failed batch and then stays clean',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      await fixture.write(1);
      fixture.port.failNextWrite = true;
      await expectLater(
        fixture.service.close(),
        throwsA(isA<FileSystemException>()),
      );

      await fixture.service.close();
      expect(fixture.savedRows, hasLength(1));
      final mergesAfterRetry = fixture.worker.mergeCalls;
      await fixture.service.close();
      expect(fixture.worker.mergeCalls, mergesAfterRetry);
    },
  );

  test(
    'save export consumes a pending batch without redundant compression',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      await fixture.write(1);
      fixture.worker.mergeCalls = 0;
      fixture.worker.encodeCalls = 0;

      expect(await fixture.service.saveExport(), isTrue);

      expect(
        fixture.worker.mergeCalls,
        1,
        reason: 'The explicit sync should consume its own pending timer batch.',
      );
      expect(
        fixture.worker.encodeCalls,
        0,
        reason:
            'The verified sync result already contains complete export bytes.',
      );
      expect(
        BackupArchive.decode(fixture.port.saved!).tables['retirement_logs'],
        hasLength(1),
      );
      expect(fixture.service.pending, isFalse);
    },
  );

  test(
    'account change cannot discard a batch adopted by a queued export',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final snapshotTaken = Completer<void>();
      final releaseSnapshot = Completer<void>();
      addTearDown(() {
        if (!releaseSnapshot.isCompleted) releaseSnapshot.complete();
      });
      fixture.worker.beforeMerge = () async {
        fixture.worker.beforeMerge = null;
        snapshotTaken.complete();
        await releaseSnapshot.future;
      };
      final olderSync = fixture.service.sync();
      await snapshotTaken.future;
      await fixture.write(1);
      final exporting = fixture.service.saveExport();
      final exportRejected = expectLater(exporting, throwsStateError);
      // Let the export join the queue and adopt the account's batching timer.
      await Future<void>.delayed(Duration.zero);
      fixture.session.reset();
      releaseSnapshot.complete();
      await olderSync;
      await exportRejected;

      await fixture.service.flush();

      expect(
        fixture.savedRows,
        hasLength(1),
        reason:
            'Rejecting a stale export must retain its adopted backup batch.',
      );
      expect(fixture.port.saved, isNull);
    },
  );

  test(
    'successful restore acknowledges the previous automatic sync failure',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final restored = BackupArchive.decode(fixture.port.live!);
      await fixture.write(1);
      fixture.port.failNextWrite = true;
      await expectLater(
        fixture.service.flush(),
        throwsA(isA<FileSystemException>()),
      );

      await fixture.service.restore(restored);

      expect(fixture.service.lastError, isNull);
      expect(
        fixture.service.pending,
        isFalse,
        reason: 'The verified restored archive supersedes the failed batch.',
      );
      fixture.worker.mergeCalls = 0;
      await fixture.service.flush();
      expect(
        fixture.worker.mergeCalls,
        0,
        reason: 'A clean restored archive must not retry an obsolete failure.',
      );
    },
  );
  test('replayed restore clears only the obsolete sync failure', () async {
    var interrupt = true;
    final fixture = await _Fixture.create(
      afterRestoreStage: (stage) async {
        if (stage == 'backup' && interrupt) {
          interrupt = false;
          throw const RestoreInterruptionForTesting();
        }
      },
    );
    addTearDown(fixture.close);
    final restored = BackupArchive.decode(fixture.port.live!);
    await fixture.write(1);
    fixture.port.failNextWrite = true;
    await expectLater(
      fixture.service.flush(),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(
      fixture.service.restore(restored),
      throwsA(isA<RestoreInterruptionForTesting>()),
    );

    await fixture.service.recoverPendingRestores();

    expect(fixture.service.maintenanceActive, isFalse);
    expect(fixture.service.lastError, isNull);
    expect(fixture.service.pending, isFalse);
    fixture.worker.mergeCalls = 0;
    await fixture.service.flush();
    expect(fixture.worker.mergeCalls, 0);
  });
}

final class _Fixture {
  _Fixture(
    this.root,
    this.db,
    this.session,
    this.port,
    this.worker,
    this.service,
  );

  final Directory root;
  final LogbookDatabase db;
  final AccountSession session;
  final _Port port;
  final _CountingWorker worker;
  final RecordBackupService service;

  static Future<_Fixture> create({
    Future<void> Function(String stage)? afterRestoreStage,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('yahagi-second-review-');
    final db = await LogbookDatabase.openForTesting();
    final session = AccountSession(initialMemberId: 1001);
    final port = _Port();
    final worker = _CountingWorker();
    final service = RecordBackupService(
      session: session,
      port: port,
      enabledStore: _EnabledStore(),
      worker: worker,
      compositionStore: FileCompositionRecordStore(
        rootDirectory: () async => root,
      ),
      databaseFor: (_) => db,
      installationId: 'second-review',
      autoSyncDelay: const Duration(days: 1),
      afterRestoreStage: afterRestoreStage,
    );
    await service.sync();
    await service.flush();
    return _Fixture(root, db, session, port, worker, service);
  }

  Future<void> write(int id) => db.insertRetirementRecord(
    timestamp: id,
    type: '解体',
    shipType: '驱逐舰',
    shipName: 'review $id',
    level: 1,
  );

  List<Map<String, Object?>> get savedRows =>
      BackupArchive.decode(port.live!).tables['retirement_logs']!;

  Future<void> close() async {
    port.failNextWrite = false;
    port.beforeWrite = null;
    try {
      await service.close();
    } finally {
      session.dispose();
      await db.close();
      await root.delete(recursive: true);
    }
  }
}

final class _EnabledStore implements RecordBackupEnabledStore {
  @override
  Future<bool> load() async => true;
  @override
  Future<void> save(bool enabled) async {}
}

final class _Port implements BackupDocumentPort {
  Uint8List? live;
  Uint8List? saved;
  bool failNextWrite = false;
  Future<void> Function()? beforeWrite;

  @override
  Future<bool> hasDirectory() async => true;

  @override
  Future<Uint8List?> readLive(int memberId, String suggestedName) async => live;

  @override
  Future<void> writeLive(int memberId, String name, Uint8List bytes) async {
    await beforeWrite?.call();
    if (failNextWrite) {
      failNextWrite = false;
      throw const FileSystemException('simulated backup failure');
    }
    live = Uint8List.fromList(bytes);
  }

  @override
  Future<String?> saveFile(String name, Uint8List bytes) async {
    saved = Uint8List.fromList(bytes);
    return 'saved-token';
  }

  @override
  Future<void> completeSavedFile(String token) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _CountingWorker extends BackupArchiveWorker {
  int mergeCalls = 0;
  int encodeCalls = 0;
  Future<void> Function()? beforeMerge;

  @override
  Future<BackupArchiveResult> mergeAndEncode({
    required int memberId,
    required Uint8List? existing,
    required Map<String, List<Map<String, Object?>>> tables,
    required List<CompositionRecord> compositions,
    required String writerId,
    required Set<String> deletedCompositions,
  }) async {
    mergeCalls++;
    await beforeMerge?.call();
    return super.mergeAndEncode(
      memberId: memberId,
      existing: existing,
      tables: tables,
      compositions: compositions,
      writerId: writerId,
      deletedCompositions: deletedCompositions,
    );
  }

  @override
  Future<Uint8List> encode(BackupArchive archive) {
    encodeCalls++;
    return super.encode(archive);
  }
}
