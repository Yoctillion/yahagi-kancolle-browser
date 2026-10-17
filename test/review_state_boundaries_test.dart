import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/src/account/account_session.dart';
import 'package:yahagi_kancolle_browser/src/backup/record_backup.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_store.dart';
import 'package:yahagi_kancolle_browser/src/logbook/logbook_database.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/composition_record_store.dart';

class _OfflinePort implements BackupDocumentPort {
  @override
  Future<bool> hasDirectory() async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected document access: ${invocation.memberName}');
}

class _GatedNormalizeWorker extends BackupArchiveWorker {
  final started = Completer<void>();
  final gate = Completer<void>();

  @override
  Future<BackupArchive> normalize(BackupArchive archive) async {
    started.complete();
    await gate.future;
    return super.normalize(archive);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferences.setMockInitialValues({
      SharedPreferencesRecordBackupEnabledStore.key: true,
    }),
  );

  test(
    'review: nested shared mutations survive an in-flight older write',
    () async {
      final started = Completer<void>();
      final gate = Completer<void>();
      final writes = <Map<String, dynamic>>[];
      final limited = <int>{10};
      final specialShips = <int>{1};
      final type = <int>[1, 2];
      final state = GameState(
        memberId: 1001,
        masterShips: {
          1: MasterShip(
            id: 1,
            name: 'ship',
            shipTypeId: 2,
            limitedEquipmentIdsByType: {3: limited},
          ),
        },
        masterSlotItems: {10: MasterSlotItem(id: 10, name: 'item', type: type)},
        expansionSlotSpecialRules: {
          10: ExpansionSlotSpecialRule(
            equipmentMasterId: 10,
            shipMasterIds: specialShips,
          ),
        },
      );
      final store = GameStateStore(
        saveDelay: const Duration(hours: 1),
        writeString: (prefs, key, value) async {
          if (key == 'game_state.shared.v1') {
            writes.add(jsonDecode(value) as Map<String, dynamic>);
            if (writes.length == 1) {
              started.complete();
              await gate.future;
            }
          }
          return prefs.setString(key, value);
        },
      );
      store.save(state);
      final first = store.flush();
      await started.future;
      limited.add(20);
      specialShips.add(2);
      type[1] = 7;
      store.save(state);
      final second = store.flush();
      gate.complete();
      await Future.wait([first, second]);
      expect(writes, hasLength(2));
      expect(
        writes.first['masterShips']['1']['limitedEquipmentIdsByType']['3'],
        [10],
      );
      expect(writes.first['expansionSlotSpecialRules']['10']['shipMasterIds'], [
        1,
      ]);
      expect(writes.first['masterSlotItems']['10']['type'], [1, 2]);
      final loaded = await store.loadForAccount(1001);
      expect(loaded.masterShips[1]!.limitedEquipmentIdsByType[3], {10, 20});
      expect(loaded.expansionSlotSpecialRules[10]!.shipMasterIds, {1, 2});
      expect(loaded.masterSlotItems[10]!.type, [1, 7]);
    },
  );

  test(
    'review: restore normalization rejects same member in a new generation',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'yahagi-review-normalize-',
      );
      final database = await LogbookDatabase.openForTesting();
      final session = AccountSession(initialMemberId: 1001);
      final worker = _GatedNormalizeWorker();
      final service = RecordBackupService(
        session: session,
        port: _OfflinePort(),
        worker: worker,
        databaseFor: (_) => database,
        compositionStore: FileCompositionRecordStore(
          rootDirectory: () async => directory,
        ),
      );
      var maintenanceStarted = false;
      service.onMaintenanceBegin = () async => maintenanceStarted = true;
      addTearDown(() async {
        if (!worker.gate.isCompleted) worker.gate.complete();
        await service.close();
        session.dispose();
        await database.close();
        await directory.delete(recursive: true);
      });
      final archive = BackupArchive(
        memberId: 1001,
        tables: {
          for (final table in LogbookDatabase.backupTables)
            table: <Map<String, Object?>>[],
        },
        compositions: [],
      );
      final restore = service.restore(archive);
      final rejected = expectLater(
        restore,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Game account changed',
          ),
        ),
      );
      await worker.started.future;
      session.reset();
      session.selectMember(1001);
      worker.gate.complete();
      await rejected;
      expect(maintenanceStarted, isFalse);
      expect(service.maintenanceActive, isFalse);
      expect(await directory.list(recursive: true).toList(), isEmpty);
    },
  );
}
