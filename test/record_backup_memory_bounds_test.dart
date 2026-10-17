import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/backup/record_backup.dart';
import 'package:yahagi_kancolle_browser/src/logbook/logbook_database.dart';

BackupArchive _archive(String text) => BackupArchive(
  memberId: 1001,
  tables: {
    for (final table in LogbookDatabase.backupTables)
      table: table == 'resource_logs'
          ? [
              {'id': 1, 'note': text},
            ]
          : [],
  },
  compositions: const [],
);

Uint8List _wrap(List<int> plain) {
  final compressed = gzip.encode(plain);
  return Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'format': 'yahagi-record-backup',
        'version': 1,
        'sha256': sha256.convert(compressed).toString(),
        'payload': base64Encode(compressed),
      }),
    ),
  );
}

void main() {
  test(
    'encoding rejects oversized plain content before producing an archive',
    () {
      // A compressible snapshot can exceed the restored-size limit while its
      // output file is tiny. Limits must apply to plain UTF-8, not gzip size.
      final archive = _archive('艦' * 10000);
      expect(() => archive.encode(maxPlainBytes: 1024), throwsFormatException);
    },
  );

  test(
    'plain byte limit has the same exact boundary for encode and decode',
    () {
      final archive = _archive('雪風 🚢 \\ "\n' * 400);
      final initial = archive.encode();
      final envelope = jsonDecode(utf8.decode(initial)) as Map;
      final plainSize = gzip
          .decode(base64Decode(envelope['payload'] as String))
          .length;
      final exact = archive.encode(maxPlainBytes: plainSize);
      expect(
        BackupArchive.decode(
          exact,
          maxPlainBytes: plainSize,
        ).tables['resource_logs']!.single['note'],
        archive.tables['resource_logs']!.single['note'],
      );
      expect(
        () => archive.encode(maxPlainBytes: plainSize - 1),
        throwsFormatException,
      );
      expect(
        () => BackupArchive.decode(exact, maxPlainBytes: plainSize - 1),
        throwsFormatException,
      );
    },
  );

  test('streamed decode still rejects malformed and trailing plain data', () {
    final encoded = _archive('響').encode();
    final envelope = jsonDecode(utf8.decode(encoded)) as Map;
    final plain = gzip.decode(base64Decode(envelope['payload'] as String));
    for (final suffix in [
      utf8.encode('{}'),
      [0xff],
      [0xe8, 0x89],
    ]) {
      expect(
        () => BackupArchive.decode(_wrap([...plain, ...suffix])),
        throwsFormatException,
      );
    }
  });

  test(
    'chunked strings and escaped content round trip without changing format',
    () {
      final archive = _archive('艦娘 🚢 \\ "\n\t' * 5000);
      final encoded = archive.encode();
      final envelope = jsonDecode(utf8.decode(encoded)) as Map;
      expect(envelope['format'], 'yahagi-record-backup');
      expect(envelope['version'], 1);
      expect(BackupArchive.decode(encoded).tables, archive.tables);
      // Verify byte-for-byte compatibility with the original whole-buffer codec.
      expect(
        encoded,
        _wrap(
          utf8.encode(
            jsonEncode({
              'memberId': archive.memberId,
              'logbookSchema': BackupArchive.logbookArchiveSchema,
              'tables': archive.tables,
              'compositions': [],
              'writerId': archive.writerId,
              'rowIds': archive.rowIds,
            }),
          ),
        ),
      );
    },
  );

  test('encoded size is bounded as well as expanded size', () {
    final archive = _archive('synthetic data');
    final size = archive.encode().length;
    expect(archive.encode(maxEncodedBytes: size), hasLength(size));
    expect(
      () => archive.encode(maxEncodedBytes: size - 1),
      throwsFormatException,
    );
  });

  test('restore journal cannot exceed its own recovery size limit', () {
    final journal = BackupRestoreJournal(
      archive: _archive('synthetic data'),
      requiresExternal: true,
    );
    final bytes = journal.encode();
    expect(journal.encode(maxEncodedBytes: bytes.length), bytes);
    expect(
      () => journal.encode(maxEncodedBytes: bytes.length - 1),
      throwsFormatException,
    );
    expect(
      BackupRestoreJournal.decode(bytes).archive.tables,
      journal.archive.tables,
    );
  });
}
