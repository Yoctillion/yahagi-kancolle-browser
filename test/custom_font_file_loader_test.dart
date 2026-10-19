import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/theme/custom_font_descriptor.dart';
import 'package:yahagi_kancolle_browser/src/theme/custom_font_file_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'registered byte budget allows exactly 64 MiB and deduplicates IDs',
    () async {
      final original = await File(
        'assets/fonts/HarmonyOS_Sans.ttf',
      ).readAsBytes();
      final payload = Uint8List(CustomFontFileLoader.maxFontBytes)
        ..setRange(0, original.length, original);
      var reads = 0;
      final sizes = <String, int>{
        _font(0).id: 24 * 1024 * 1024,
        _font(1).id: 24 * 1024 * 1024,
        _font(2).id: 17 * 1024 * 1024,
        _font(3).id: 16 * 1024 * 1024,
      };
      final loader = CustomFontFileLoader(
        readFont: (font) async {
          reads++;
          return Uint8List.sublistView(payload, 0, sizes[font.id]!);
        },
      );

      await loader.load(_font(0));
      await loader.load(_font(0));
      await loader.load(_font(1));
      expect(reads, 2);
      await expectLater(
        loader.load(_font(2)),
        throwsA(isA<CustomFontLoadLimitException>()),
      );
      expect(reads, 3);
      await loader.load(_font(3));
      expect(reads, 4);
      await loader.load(_font(0));
      expect(reads, 4);
      await expectLater(
        loader.load(_font(4)),
        throwsA(isA<CustomFontLoadLimitException>()),
      );
      expect(reads, 4, reason: 'A full budget must stop before another read');
    },
  );

  test('failed reads do not consume registration slots', () async {
    final bytes = await File('assets/fonts/HarmonyOS_Sans.ttf').readAsBytes();
    var fail = true;
    final loader = CustomFontFileLoader(
      readFont: (_) async {
        if (fail) throw const FileSystemException('temporary read failure');
        return bytes;
      },
    );
    await expectLater(
      loader.load(_font(0)),
      throwsA(isA<FileSystemException>()),
    );
    fail = false;
    for (var index = 0; index < 8; index++) {
      await loader.load(_font(index));
    }
    await expectLater(
      loader.load(_font(8)),
      throwsA(isA<CustomFontLoadLimitException>()),
    );
  });

  test(
    'default loader reads and validates outside the caller IO zone',
    () async {
      final file = File('assets/fonts/HarmonyOS_Sans.ttf');
      final font = CustomFontDescriptor(
        id: sha256.convert(await file.readAsBytes()).toString(),
        name: 'HarmonyOS_Sans.ttf',
        path: file.absolute.path,
      );
      await IOOverrides.runZoned(
        () => CustomFontFileLoader().load(font),
        createFile: (_) =>
            throw StateError('File work ran on the caller isolate'),
      );
    },
  );

  test(
    'worker checks remaining budget before reading and always closes',
    () async {
      final reader = _LengthOnlyReader(24 * 1024 * 1024);
      await expectLater(
        IOOverrides.runZoned(
          () => readAndValidateCustomFontFile(
            _font(0),
            remainingBytes: 16 * 1024 * 1024,
          ),
          createFile: (_) => _OpenedFile(reader),
        ),
        throwsA(isA<CustomFontLoadLimitException>()),
      );
      expect(reader.reads, 0);
      expect(reader.closed, isTrue);
    },
  );
}

CustomFontDescriptor _font(int index) => CustomFontDescriptor(
  id: index.toRadixString(16).padLeft(64, '0'),
  name: 'Font $index.ttf',
  path: '/private/font-$index.ttf',
);

final class _OpenedFile implements File {
  _OpenedFile(this.reader);

  final RandomAccessFile reader;

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async =>
      reader;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _LengthOnlyReader implements RandomAccessFile {
  _LengthOnlyReader(this.size);

  final int size;
  int reads = 0;
  bool closed = false;

  @override
  Future<int> length() async => size;

  @override
  Future<int> readInto(List<int> buffer, [int start = 0, int? end]) async {
    reads++;
    throw StateError('A rejected file must not be read');
  }

  @override
  Future<RandomAccessFile> close() async {
    closed = true;
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
