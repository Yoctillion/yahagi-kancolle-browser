import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/theme/custom_font_controller.dart';
import 'package:yahagi_kancolle_browser/src/theme/custom_font_file_loader.dart';

const _auditFont = CustomFontDescriptor(
  id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  name: 'Font.ttf',
  path: '/private/font.ttf',
);
const _auditSecondFont = CustomFontDescriptor(
  id: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  name: 'Other.ttf',
  path: '/private/other.ttf',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'startup drops a saved font whose sfnt directory survives corruption',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'yahagi_font_audit_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final original = await File(
        'assets/fonts/HarmonyOS_Sans.ttf',
      ).readAsBytes();
      final damaged = ByteData(28)
        ..setUint32(0, 0x00010000)
        ..setUint16(4, 1);
      final file = await File(
        '${directory.path}/corrupt.ttf',
      ).writeAsBytes(damaged.buffer.asUint8List());
      final font = CustomFontDescriptor(
        id: sha256.convert(original).toString(),
        name: 'HarmonyOS_Sans.ttf',
        path: file.path,
      );
      final store = _AuditStore()..value = font;
      final port = _AuditPort();
      final controller = await CustomFontController.load(
        store: store,
        port: port,
      );
      addTearDown(controller.dispose);

      expect(controller.selectedFont, isNull);
      expect(store.value, isNull);
      expect(port.removed, [font.id]);
    },
  );

  test(
    'disposing during import removes the returned unselected file',
    () async {
      const font = CustomFontDescriptor(
        id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        name: 'Font.ttf',
        path: '/private/font.ttf',
      );
      final gate = Completer<CustomFontDescriptor?>();
      final port = _AuditPort()..gate = gate;
      final controller = await CustomFontController.load(
        store: _AuditStore(),
        port: port,
        loader: (_) async {},
      );
      final importing = controller.importForPreview();
      controller.dispose();
      gate.complete(font);

      expect(await importing, isNull);
      expect(port.removed, [font.id]);
    },
  );

  test(
    'worker reader reads the full font when reads return partial data',
    () async {
      final realFile = File('assets/fonts/HarmonyOS_Sans.ttf');
      final original = await realFile.readAsBytes();
      final reader = _ShortReader(await realFile.open(), original.length ~/ 3);
      final font = CustomFontDescriptor(
        id: sha256.convert(original).toString(),
        name: 'HarmonyOS_Sans.ttf',
        path: realFile.absolute.path,
      );
      final loadedBytes = await IOOverrides.runZoned(
        () => readAndValidateCustomFontFile(font),
        createFile: (_) => _OpenedFile(reader),
      );

      expect(loadedBytes, original);
      expect(reader.reads, greaterThan(1));
      expect(reader.closed, isTrue);
    },
  );

  test(
    'startup prunes unused files while retaining the loaded selection',
    () async {
      final store = _AuditStore()..value = _auditFont;
      final port = _AuditMaintenancePort()..failPrune = true;
      final controller = await CustomFontController.load(
        store: store,
        port: port,
        loader: (_) async {},
      );
      addTearDown(controller.dispose);

      expect(port.retainedIds, [
        <String>{_auditFont.id},
      ]);
      expect(controller.selectedFont, _auditFont);
      expect(store.value, _auditFont);
    },
  );

  test(
    'startup with a persisted default prunes interrupted preview files',
    () async {
      final port = _AuditMaintenancePort();
      final controller = await CustomFontController.load(
        store: _AuditStore(),
        port: port,
        loader: (_) async {},
      );
      addTearDown(controller.dispose);

      expect(port.retainedIds, [<String>{}]);
    },
  );

  test(
    'startup prunes files after clearing an invalid saved selection',
    () async {
      final store = _AuditStore()..value = _auditFont;
      final port = _AuditMaintenancePort();
      final controller = await CustomFontController.load(
        store: store,
        port: port,
        loader: (_) async => throw const FormatException('damaged font'),
      );
      addTearDown(controller.dispose);

      expect(store.value, isNull);
      expect(port.retainedIds, [<String>{}]);
    },
  );

  test(
    'startup prunes files after an unreadable selection is cleared',
    () async {
      final store = _AuditStore()
        ..value = _auditFont
        ..failLoad = true;
      final port = _AuditMaintenancePort();
      final controller = await CustomFontController.load(
        store: store,
        port: port,
        loader: (_) async {},
      );
      addTearDown(controller.dispose);

      expect(store.value, isNull);
      expect(port.retainedIds, [<String>{}]);
    },
  );

  test(
    'startup preserves files when the saved selection cannot be determined',
    () async {
      final store = _AuditStore()
        ..value = _auditFont
        ..failLoad = true
        ..failSave = true;
      final port = _AuditMaintenancePort();
      final controller = await CustomFontController.load(
        store: store,
        port: port,
        loader: (_) async {},
      );
      addTearDown(controller.dispose);

      expect(store.value, _auditFont);
      expect(port.retainedIds, isEmpty);
      expect(port.removed, isEmpty);
    },
  );

  test(
    'startup preserves an unloadable saved font if clearing fails so retry can restore it',
    () async {
      final store = _AuditStore()
        ..value = _auditFont
        ..failSave = true;
      final port = _AuditMaintenancePort();
      final failed = await CustomFontController.load(
        store: store,
        port: port,
        loader: (_) async =>
            throw const FileSystemException('temporary read failure'),
      );
      addTearDown(failed.dispose);

      expect(failed.selectedFont, isNull);
      expect(store.value, _auditFont);
      expect(port.removed, isEmpty);
      expect(port.retainedIds, isEmpty);

      store.failSave = false;
      final retried = await CustomFontController.load(
        store: store,
        port: port,
        loader: (_) async {},
      );
      addTearDown(retried.dispose);

      expect(retried.selectedFont, _auditFont);
      expect(port.removed, isEmpty);
      expect(port.retainedIds, [
        <String>{_auditFont.id},
      ]);
    },
  );

  test(
    'cancelling a preview preserves the saved file after startup clearing failed',
    () async {
      final store = _AuditStore()
        ..value = _auditFont
        ..failSave = true;
      final port = _AuditMaintenancePort()..next = _auditFont;
      var failFirstLoad = true;
      final controller = await CustomFontController.load(
        store: store,
        port: port,
        loader: (_) async {
          if (failFirstLoad) {
            failFirstLoad = false;
            throw const FileSystemException('temporary read failure');
          }
        },
      );
      addTearDown(controller.dispose);

      await controller.importForPreview();
      await controller.discardPreview();

      expect(store.value, _auditFont);
      expect(port.removed, isEmpty);
      expect(port.retainedIds, isEmpty);
    },
  );

  test(
    'failed apply and cancelled previews preserve files while saved selection is unknown',
    () async {
      final store = _AuditStore()
        ..value = _auditFont
        ..failLoad = true
        ..failSave = true;
      final port = _AuditMaintenancePort()..next = _auditFont;
      var failPreviewLoad = true;
      final controller = await CustomFontController.load(
        store: store,
        port: port,
        loader: (_) async {
          if (failPreviewLoad) throw const FormatException('font read failed');
        },
      );
      addTearDown(controller.dispose);

      await controller.importForPreview();
      await expectLater(controller.applyPreview(), throwsFormatException);
      expect(port.removed, isEmpty);
      failPreviewLoad = false;
      await controller.importForPreview();
      await controller.discardPreview();

      expect(store.value, _auditFont);
      expect(port.removed, isEmpty);
      expect(port.retainedIds, isEmpty);
    },
  );

  test(
    'only a successful apply permits cleanup after an unknown startup selection',
    () async {
      final store = _AuditStore()
        ..value = _auditFont
        ..failLoad = true
        ..failSave = true;
      final port = _AuditMaintenancePort()..next = _auditSecondFont;
      final controller = await CustomFontController.load(
        store: store,
        port: port,
        loader: (_) async {},
      );
      addTearDown(controller.dispose);

      await controller.importForPreview();
      await expectLater(controller.applyPreview(), throwsStateError);
      await controller.discardPreview();
      expect(port.removed, isEmpty);
      expect(store.value, _auditFont);

      store.failSave = false;
      await controller.importForPreview();
      await controller.applyPreview();
      expect(store.value, _auditSecondFont);
      port.next = _auditFont;
      await controller.importForPreview();
      await controller.discardPreview();

      expect(port.removed, [_auditFont.id]);
      expect(controller.selectedFont, _auditSecondFont);
    },
  );

  test(
    'only a successful restore permits cleanup after an unknown startup selection',
    () async {
      final store = _AuditStore()
        ..value = _auditFont
        ..failLoad = true
        ..failSave = true;
      final port = _AuditMaintenancePort()..next = _auditFont;
      final controller = await CustomFontController.load(
        store: store,
        port: port,
        loader: (_) async {},
      );
      addTearDown(controller.dispose);

      await controller.importForPreview();
      await expectLater(controller.restoreDefault(), throwsStateError);
      expect(port.removed, isEmpty);
      expect(store.value, _auditFont);

      store.failSave = false;
      await controller.restoreDefault();
      expect(store.value, isNull);
      expect(port.removed, [_auditFont.id]);
      port.next = _auditSecondFont;
      await controller.importForPreview();
      await controller.discardPreview();

      expect(port.removed, [_auditFont.id, _auditSecondFont.id]);
    },
  );
}

final class _AuditStore implements CustomFontStore {
  CustomFontDescriptor? value;
  bool failLoad = false;
  bool failSave = false;

  @override
  Future<CustomFontDescriptor?> load() async {
    if (failLoad) throw StateError('load failed');
    return value;
  }

  @override
  Future<void> save(CustomFontDescriptor? font) async {
    if (failSave) throw StateError('save failed');
    value = font;
  }
}

class _AuditPort implements CustomFontPort {
  CustomFontDescriptor? next;
  Completer<CustomFontDescriptor?>? gate;
  final removed = <String>[];

  @override
  Future<CustomFontDescriptor?> importFont() async =>
      gate == null ? next : await gate!.future;

  @override
  Future<void> removeFont(String id) async => removed.add(id);
}

final class _AuditMaintenancePort extends _AuditPort
    implements CustomFontMaintenancePort {
  final retainedIds = <Set<String>>[];
  bool failPrune = false;

  @override
  Future<void> pruneFonts(Set<String> ids) async {
    retainedIds.add(Set.of(ids));
    if (failPrune) throw StateError('prune failed');
  }
}

final class _OpenedFile implements File {
  _OpenedFile(this.reader);

  final RandomAccessFile reader;

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async =>
      reader;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ShortReader implements RandomAccessFile {
  _ShortReader(this.file, this.chunkSize);

  final RandomAccessFile file;
  final int chunkSize;
  int reads = 0;
  bool closed = false;

  @override
  Future<int> length() => file.length();

  @override
  Future<Uint8List> read(int count) {
    reads++;
    return file.read(count.clamp(0, chunkSize));
  }

  @override
  Future<int> readInto(List<int> buffer, [int start = 0, int? end]) {
    reads++;
    final limit = end ?? buffer.length;
    return file.readInto(
      buffer,
      start,
      (start + chunkSize).clamp(start, limit),
    );
  }

  @override
  Future<RandomAccessFile> close() async {
    await file.close();
    closed = true;
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
