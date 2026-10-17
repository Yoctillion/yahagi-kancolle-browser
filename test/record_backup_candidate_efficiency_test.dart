import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/backup/record_backup.dart';
import 'package:yahagi_kancolle_browser/src/logbook/logbook_database.dart';

const _owner = 88021;

Uint8List _archive({int memberId = _owner, String writerId = ''}) =>
    BackupArchive(
      memberId: memberId,
      tables: {for (final table in LogbookDatabase.backupTables) table: []},
      compositions: const [],
      writerId: writerId,
    ).encode();

class _CountingWorker extends BackupArchiveWorker {
  int decodes = 0;

  @override
  Future<BackupArchive> decode(
    Uint8List bytes, {
    int maxPlainBytes = 250 * 1024 * 1024,
  }) {
    decodes++;
    return super.decode(bytes, maxPlainBytes: maxPlainBytes);
  }
}

class _Candidates {
  _Candidates(this.slots);

  final Map<String, Uint8List?> slots;
  final calls = <String>[];
  String? unreadableSlot;
  bool corruptPromotion = false;

  Future<Object?> handle(MethodCall call) async {
    final arguments = call.arguments as Map;
    final slot = arguments['slot'] as String;
    calls.add('${call.method}:$slot');
    if (call.method == 'readCandidate') {
      if (slot == unreadableSlot) {
        throw PlatformException(code: 'read_failed');
      }
      // Real platform replies own distinct byte buffers for each document.
      final bytes = slots[slot];
      return bytes == null ? null : Uint8List.fromList(bytes);
    }
    if (call.method == 'promoteCandidate') {
      slots['main'] = corruptPromotion
          ? Uint8List.fromList([0])
          : arguments['bytes'] as Uint8List;
      slots[slot] = null;
      return null;
    }
    throw StateError('Unexpected method ${call.method}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/backup-candidate-efficiency');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void install(_Candidates candidates) {
    messenger.setMockMethodCallHandler(channel, candidates.handle);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }

  test('identical candidates decode and validate once per live read', () async {
    final bytes = _archive();
    final candidates = _Candidates({
      'pending': bytes,
      'main': bytes,
      'previous': bytes,
    });
    install(candidates);
    final worker = _CountingWorker();
    var validations = 0;
    final port = AndroidBackupDocumentPort(
      channel: channel,
      worker: worker,
      validateCandidate: (_) async => validations++,
    );

    expect(await port.readLive(_owner, 'Admiral.yhb'), bytes);
    expect(worker.decodes, 1);
    expect(validations, 1);
    expect(candidates.calls, [
      'readCandidate:pending',
      'readCandidate:main',
      'readCandidate:previous',
      'promoteCandidate:pending',
      'readCandidate:main',
    ]);
  });

  test(
    'older distinct copies retain ownership checks without SQLite work',
    () async {
      final main = _archive(writerId: 'main');
      final candidates = _Candidates({
        'main': main,
        'previous': _archive(writerId: 'previous'),
      });
      install(candidates);
      final worker = _CountingWorker();
      var validations = 0;
      final port = AndroidBackupDocumentPort(
        channel: channel,
        worker: worker,
        validateCandidate: (_) async => validations++,
      );

      expect(await port.readLive(_owner, 'Admiral.yhb'), main);
      expect(worker.decodes, 2);
      expect(validations, 1);
    },
  );

  test(
    'foreign previous copy still prevents promotion of a valid pending',
    () async {
      final candidates = _Candidates({
        'pending': _archive(),
        'main': _archive(),
        'previous': _archive(memberId: _owner + 1),
      });
      install(candidates);
      final port = AndroidBackupDocumentPort(
        channel: channel,
        validateCandidate: (_) async {},
      );

      await expectLater(port.readLive(_owner, 'Admiral.yhb'), throwsStateError);
      expect(
        candidates.calls.where((call) => call.startsWith('promote')),
        isEmpty,
      );
    },
  );

  test('unreadable previous copy still blocks a valid pending', () async {
    final candidates = _Candidates({'pending': _archive()})
      ..unreadableSlot = 'previous';
    install(candidates);
    final port = AndroidBackupDocumentPort(
      channel: channel,
      validateCandidate: (_) async {},
    );

    await expectLater(port.readLive(_owner, 'Admiral.yhb'), throwsStateError);
    expect(
      candidates.calls.where((call) => call.startsWith('promote')),
      isEmpty,
    );
  });

  test(
    'later reads detect new corruption and validate the fallback again',
    () async {
      final main = _archive(writerId: 'main');
      final previous = _archive(writerId: 'previous');
      final candidates = _Candidates({'main': main, 'previous': previous});
      install(candidates);
      final validated = <String>[];
      final port = AndroidBackupDocumentPort(
        channel: channel,
        validateCandidate: (archive) async => validated.add(archive.writerId),
      );

      expect(await port.readLive(_owner, 'Admiral.yhb'), main);
      validated.clear();
      candidates.slots['main'] = Uint8List.fromList([1, 2, 3]);
      expect(await port.readLive(_owner, 'Admiral.yhb'), previous);
      expect(validated, ['previous']);
      candidates.slots['main'] = _archive(memberId: _owner + 1);
      await expectLater(port.readLive(_owner, 'Admiral.yhb'), throwsStateError);
    },
  );

  test('SQLite-invalid pending still falls back to the healthy main', () async {
    final database = await LogbookDatabase.openForTesting();
    addTearDown(database.close);
    final valid = _archive();
    final invalid = BackupArchive(
      memberId: _owner,
      tables: {
        for (final table in LogbookDatabase.backupTables)
          table: table == 'resource_logs'
              ? [
                  <String, Object?>{'id': 1, 'timestamp': 'bad'},
                ]
              : <Map<String, Object?>>[],
      },
      compositions: const [],
    ).encode();
    final candidates = _Candidates({'pending': invalid, 'main': valid});
    install(candidates);
    var validations = 0;
    final port = AndroidBackupDocumentPort(
      channel: channel,
      validateCandidate: (archive) {
        validations++;
        return database.validateBackupSnapshot(archive.tables);
      },
    );

    expect(await port.readLive(_owner, 'Admiral.yhb'), valid);
    expect(validations, 2);
    expect(
      candidates.calls.where((call) => call.startsWith('promote')),
      isEmpty,
    );
  });

  test('recovered bytes are still read back and compared exactly', () async {
    final candidates = _Candidates({'pending': _archive()})
      ..corruptPromotion = true;
    install(candidates);
    final port = AndroidBackupDocumentPort(
      channel: channel,
      validateCandidate: (_) async {},
    );

    await expectLater(port.readLive(_owner, 'Admiral.yhb'), throwsStateError);
    expect(candidates.calls.last, 'readCandidate:main');
  });
}
