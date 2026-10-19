import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/theme/custom_font_port.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.yahagi.kancollebrowser/custom_fonts');
  const port = MethodChannelCustomFontPort();
  const id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  final calls = <MethodCall>[];
  Object? response;

  setUp(() {
    calls.clear();
    response = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'renderPreview') return response;
          return call.method == 'importFont' ? response : null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('picker cancellation returns null', () async {
    expect(await port.importFont(), isNull);
    expect(calls.single.method, 'importFont');
    expect(calls.single.arguments, isNull);
  });

  test('imports the native descriptor and removes fonts by id', () async {
    response = {
      'id': id,
      'name': 'My Font.otf',
      'path': '/private/fonts/$id.otf',
    };
    final font = await port.importFont();
    expect(font?.id, id);
    expect(font?.name, 'My Font.otf');
    expect(font?.path, '/private/fonts/$id.otf');
    expect(font?.fontFamily, 'UserFont_$id');
    await port.removeFont(id);
    expect(calls.last.method, 'removeFont');
    expect(calls.last.arguments, {'id': id});
  });

  test('malformed native descriptors are rejected', () async {
    for (final value in <Object>[
      'not a descriptor',
      <String, Object>{},
      {'id': '../escape', 'name': 'font.ttf', 'path': '/private/font.ttf'},
      {'id': id, 'name': '', 'path': '/private/font.ttf'},
      {'id': id, 'name': 'font.ttf', 'path': 'relative/font.ttf'},
    ]) {
      response = value;
      await expectLater(
        port.importFont(),
        throwsFormatException,
        reason: '$value',
      );
    }
  });

  test(
    'startup maintenance retains only the supplied active font ids',
    () async {
      await port.pruneFonts({id});
      expect(calls.single.method, 'pruneFonts');
      expect(calls.single.arguments, {
        'ids': [id],
      });
      calls.clear();
      await port.pruneFonts({});
      expect(calls.single.arguments, {'ids': <String>[]});
    },
  );

  test(
    'requests a bounded native PNG without transferring the font file',
    () async {
      const font = CustomFontDescriptor(
        id: id,
        name: 'Font.ttf',
        path: '/private/font.ttf',
      );
      response = Uint8List.fromList([137, 80, 78, 71]);
      expect(
        await port.renderPreview(
          font,
          text: 'Sample',
          width: 480,
          fontSize: 36,
          locale: 'en',
          color: 0xffe5eef5,
        ),
        response,
      );
      expect(calls.single.method, 'renderPreview');
      expect(calls.single.arguments, {
        'id': id,
        'text': 'Sample',
        'width': 480,
        'fontSize': 36.0,
        'locale': 'en',
        'color': 0xffe5eef5,
      });
    },
  );

  test('rejects empty or oversized preview responses', () async {
    const font = CustomFontDescriptor(
      id: id,
      name: 'Font.ttf',
      path: '/private/font.ttf',
    );
    for (final value in [null, Uint8List(0), Uint8List(3 * 1024 * 1024 + 1)]) {
      response = value;
      await expectLater(
        port.renderPreview(
          font,
          text: 'Sample',
          width: 480,
          fontSize: 36,
          locale: 'en',
          color: 0xffe5eef5,
        ),
        throwsFormatException,
      );
    }
  });
}
