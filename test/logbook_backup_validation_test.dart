import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
// Exercise Android's actual read-only result type rather than a writable fake.
// ignore: depend_on_referenced_packages
import 'package:sqflite_common/src/collection_utils.dart' show QueryResultSet;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yahagi_kancolle_browser/src/logbook/logbook_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LogbookDatabase backing;
  late Database sql;

  setUp(() async {
    backing = await LogbookDatabase.openForTesting();
    sql = await backing.database;
    await sql.insert('resource_logs', _resourceRow(1));
  });
  tearDown(() => backing.close());

  test(
    'validates read-only Android PRAGMA results for composite indexes',
    () async {
      await sql.execute(
        'CREATE UNIQUE INDEX resource_pair ON resource_logs(timestamp, fuel)',
      );
      final schema = await _SchemaDatabase.capture(sql);
      final database = LogbookDatabase.lazyForTesting(() async => schema);
      final snapshot = await backing.backupSnapshot();

      await database.validateBackupSnapshot(snapshot);

      final duplicate = <String, Object?>{
        ...snapshot['resource_logs']!.single,
        'id': 2,
      };
      snapshot['resource_logs'] = [...snapshot['resource_logs']!, duplicate];
      await expectLater(
        database.validateBackupSnapshot(snapshot),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('snapshot validation yields after reading SQLite metadata', () async {
    var eventLoopRan = false;
    final schema = await _SchemaDatabase.capture(sql);
    schema.afterMetadataRead = () => Timer.run(() => eventLoopRan = true);
    final database = LogbookDatabase.lazyForTesting(() async => schema);
    final snapshot = await backing.backupSnapshot();
    snapshot['resource_logs'] = [
      for (var id = 1; id <= 20000; id++) _resourceRow(id),
    ];

    await database.validateBackupSnapshot(snapshot);

    expect(
      eventLoopRan,
      isTrue,
      reason: 'Archive row validation must release the UI event loop.',
    );
  });

  for (final scenario in <String, Map<String, Object?>>{
    'numeric string': {'fuel': '1'},
    'null required value': {'fuel': null},
    'invalid timestamp': {'timestamp': 8640000000000000},
    'invalid auto increment ID': {'id': 9223372036854775807},
  }.entries) {
    test('background validation rejects ${scenario.key}', () async {
      final snapshot = await backing.backupSnapshot();
      snapshot['resource_logs'] = [
        {...snapshot['resource_logs']!.single, ...scenario.value},
      ];
      await expectLater(
        backing.validateBackupSnapshot(snapshot),
        throwsA(isA<FormatException>()),
      );
    });
  }

  test(
    'validation rejects missing columns and dangling construction references',
    () async {
      final snapshot = await backing.backupSnapshot();
      snapshot['resource_logs'] = [
        {...snapshot['resource_logs']!.single}..remove('fuel'),
      ];
      await expectLater(
        backing.validateBackupSnapshot(snapshot),
        throwsA(isA<FormatException>()),
      );
      snapshot['resource_logs'] = [];
      snapshot['pending_construction_logs'] = [
        {'dock_id': 1, 'record_id': 999},
      ];
      await expectLater(
        backing.validateBackupSnapshot(snapshot),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test(
    'restore rejects invalid snapshots without losing existing records',
    () async {
      final before = await backing.backupSnapshot();
      final invalid = <String, List<Map<String, Object?>>>{...before};
      invalid['resource_logs'] = [
        {...before['resource_logs']!.single, 'fuel': '1'},
      ];
      await expectLater(
        backing.restoreSnapshot(invalid),
        throwsA(isA<FormatException>()),
      );
      expect(await backing.backupSnapshot(), before);
      await backing.restoreSnapshot(before);
      expect(await backing.backupSnapshot(), before);
    },
  );
}

Map<String, Object?> _resourceRow(int id) => {
  'id': id,
  'timestamp': id * 1000,
  'fuel': 100,
  'ammo': 100,
  'steel': 100,
  'bauxite': 100,
  'bucket': 10,
  'blowtorch': 10,
  'devmat': 10,
  'screw': 10,
};

// Sqflite's Android bridge returns QueryResultSet, whose rows and list are
// read-only. Keep metadata futures synchronous so an event-loop yield cannot
// accidentally come from the fixture's SQLite I/O.
final class _SchemaDatabase implements Database {
  _SchemaDatabase(this.results);

  final Map<String, QueryResultSet> results;
  void Function()? afterMetadataRead;

  static Future<_SchemaDatabase> capture(Database sql) async {
    final results = <String, QueryResultSet>{};
    Future<List<Map<String, Object?>>> read(String query) async {
      final rows = await sql.rawQuery(query);
      final columns = rows.isEmpty ? <String>[] : rows.first.keys.toList();
      results[query] = QueryResultSet(columns, [
        for (final row in rows) [for (final column in columns) row[column]],
      ]);
      return rows;
    }

    for (final table in LogbookDatabase.backupTables) {
      await read('PRAGMA table_info($table)');
      final indexes = await read('PRAGMA index_list($table)');
      for (final index in indexes.where((row) => row['unique'] == 1)) {
        final name = (index['name'] as String).replaceAll('"', '""');
        await read('PRAGMA index_info("$name")');
      }
    }
    return _SchemaDatabase(results);
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    if (sql == 'PRAGMA index_list(${LogbookDatabase.backupTables.last})') {
      afterMetadataRead?.call();
    }
    return results[sql] ?? (throw StateError('Unexpected query: $sql'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
