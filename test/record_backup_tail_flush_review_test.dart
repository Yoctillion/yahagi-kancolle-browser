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

  test(
    'lifecycle flush includes writes arriving in the last automatic pass',
    () async {
      SharedPreferences.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp('yahagi-tail-flush-');
      final db = await LogbookDatabase.openForTesting();
      final session = AccountSession(initialMemberId: 1001);
      final port = _TailWritePort();
      final service = RecordBackupService(
        session: session,
        port: port,
        enabledStore: _EnabledStore(),
        compositionStore: FileCompositionRecordStore(
          rootDirectory: () async => root,
        ),
        databaseFor: (_) => db,
        installationId: 'tail-flush-test',
        autoSyncDelay: const Duration(days: 1),
      );
      addTearDown(() async {
        port.afterRead = null;
        await service.close();
        session.dispose();
        await db.close();
        await root.delete(recursive: true);
      });
      Future<void> write(int id) => db.insertRetirementRecord(
        timestamp: id,
        type: '解体',
        shipType: '驱逐舰',
        shipName: 'tail $id',
        level: 1,
      );
      await service.sync();
      port.reads = 0;
      await write(1);
      port.afterRead = (read) async {
        // These are verification reads, after each pass captured its snapshot.
        if (read == 2) await write(2);
        if (read == 4) await write(3);
      };

      await service.flush();

      expect(await db.getRetirementRecords(), hasLength(3));
      expect(
        BackupArchive.decode(port.live!).tables['retirement_logs'],
        hasLength(3),
        reason:
            'The lifecycle durability barrier must also drain its last pass.',
      );
      expect(service.pending, isFalse);
    },
  );

  test(
    'close drains a dirty tail from an automatic pass already in flight',
    () async {
      SharedPreferences.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp('yahagi-close-tail-');
      final db = await LogbookDatabase.openForTesting();
      final session = AccountSession(initialMemberId: 1001);
      final port = _TailWritePort();
      final service = RecordBackupService(
        session: session,
        port: port,
        enabledStore: _EnabledStore(),
        compositionStore: FileCompositionRecordStore(
          rootDirectory: () async => root,
        ),
        databaseFor: (_) => db,
        installationId: 'close-tail-test',
        autoSyncDelay: const Duration(days: 1),
      );
      addTearDown(() async {
        port.afterRead = null;
        await service.close();
        session.dispose();
        await db.close();
        await root.delete(recursive: true);
      });
      Future<void> write(int id) => db.insertRetirementRecord(
        timestamp: id,
        type: '解体',
        shipType: '驱逐舰',
        shipName: 'close tail $id',
        level: 1,
      );
      await service.sync();
      port.reads = 0;
      await write(1);
      final secondPassFinishing = Completer<void>();
      final releaseSecondPass = Completer<void>();
      port.afterRead = (read) async {
        if (read == 2) await write(2);
        if (read == 4) {
          await write(3);
          secondPassFinishing.complete();
          await releaseSecondPass.future;
        }
      };
      final flushing = service.flush();
      await secondPassFinishing.future;

      final closing = service.close();
      releaseSecondPass.complete();
      await Future.wait([flushing, closing]);

      expect(
        BackupArchive.decode(port.live!).tables['retirement_logs'],
        hasLength(3),
      );
    },
  );
}

final class _EnabledStore implements RecordBackupEnabledStore {
  @override
  Future<bool> load() async => true;
  @override
  Future<void> save(bool enabled) async {}
}

final class _TailWritePort implements BackupDocumentPort {
  Uint8List? live;
  int reads = 0;
  Future<void> Function(int read)? afterRead;
  @override
  Future<bool> hasDirectory() async => true;
  @override
  Future<Uint8List?> readLive(int memberId, String suggestedName) async {
    await afterRead?.call(++reads);
    return live;
  }

  @override
  Future<void> writeLive(int memberId, String name, Uint8List bytes) async {
    live = Uint8List.fromList(bytes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
