import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/backup/record_backup.dart';
import 'package:yahagi_kancolle_browser/src/logbook/logbook_database.dart';

Map<String, List<Map<String, Object?>>> _tables(int count, {int fuel = 7}) => {
  for (final name in LogbookDatabase.backupTables)
    name: name == 'resource_logs'
        ? [
            for (var i = 1; i <= count; i++) {'id': i, 'fuel': i * fuel},
          ]
        : [],
};

void main() {
  const worker = BackupArchiveWorker();
  test(
    'worker message owns a detached snapshot before later mutations',
    () async {
      final tables = _tables(2);
      final task = worker.mergeAndEncode(
        memberId: 1001,
        existing: null,
        tables: tables,
        compositions: [],
        writerId: 'test',
        deletedCompositions: {},
      );
      tables['resource_logs']!.first['fuel'] = 999;
      tables['resource_logs']!.clear();
      final result = await task;
      expect(result.archive.tables['resource_logs'], hasLength(2));
      expect(result.archive.tables['resource_logs']!.first['fuel'], 7);
    },
  );

  test('worker preserves merge row mappings and codec bytes', () async {
    final old = BackupArchive(
      memberId: 1001,
      tables: _tables(2),
      compositions: [],
      writerId: 'old',
    );
    final current = _tables(3, fuel: 9);
    final expected = old.merge(current, [], writerId: 'new');
    final actual = await worker.mergeAndEncode(
      memberId: 1001,
      existing: old.encode(),
      tables: current,
      compositions: [],
      writerId: 'new',
      deletedCompositions: {},
    );
    expect(actual.bytes, expected.encode());
    expect(actual.archive.tables, expected.tables);
    expect(actual.archive.rowIds, expected.rowIds);
    expect(await worker.verify(1001, actual.bytes, actual.bytes), isTrue);
    expect(await worker.verify(2002, actual.bytes, actual.bytes), isFalse);
  });

  test(
    'worker yields while merging and encoding 50000 synthetic rows',
    () async {
      var heartbeat = false;
      Timer.run(() => heartbeat = true);
      final actual = await worker.mergeAndEncode(
        memberId: 1001,
        existing: null,
        tables: _tables(50000),
        compositions: [],
        writerId: 'synthetic',
        deletedCompositions: {},
      );
      expect(heartbeat, isTrue);
      expect(actual.archive.tables['resource_logs'], hasLength(50000));
      final decoded = await worker.decode(actual.bytes);
      expect(decoded.tables, actual.archive.tables);
    },
  );

  test(
    'worker rejects wrong owners, checksum corruption and inflated limits',
    () async {
      final archive = BackupArchive(
        memberId: 1001,
        tables: _tables(2),
        compositions: [],
      );
      final bytes = archive.encode();
      await expectLater(
        worker.mergeAndEncode(
          memberId: 2002,
          existing: bytes,
          tables: _tables(1),
          compositions: [],
          writerId: 'new',
          deletedCompositions: {},
        ),
        throwsStateError,
      );
      await expectLater(worker.validateOwner(2002, bytes), throwsStateError);
      await expectLater(
        worker.decode(bytes, maxPlainBytes: 10),
        throwsFormatException,
      );
      final outer = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      outer['sha256'] = 'bad';
      await expectLater(
        worker.decode(Uint8List.fromList(utf8.encode(jsonEncode(outer)))),
        throwsFormatException,
      );
      // A failed task does not poison later worker invocations.
      expect((await worker.decode(bytes)).memberId, 1001);
    },
  );

  test(
    'worker reads the committed v12 fixture and round trips restore journals',
    () async {
      final bytes = await File(
        'test/fixtures/record_backup_v12_empty.yhb',
      ).readAsBytes();
      final expected = BackupArchive.decode(bytes);
      final archive = await worker.decode(bytes);
      expect(archive.tables, expected.tables);
      expect(await worker.encode(archive), archive.encode());
      final journal = BackupRestoreJournal(
        archive: archive,
        requiresExternal: true,
      );
      final encoded = await worker.encodeJournal(journal);
      expect(encoded, journal.encode());
      final restored = await worker.decodeJournal(encoded);
      expect(restored.requiresExternal, isTrue);
      expect(restored.archive.tables, archive.tables);
    },
  );
}
