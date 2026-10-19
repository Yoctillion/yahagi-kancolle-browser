import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/theme/custom_font_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '120 distinct cancelled previews never register an engine font',
    () async {
      final port = _Port();
      var loads = 0;
      final controller = await CustomFontController.load(
        store: _Store(),
        port: port,
        loader: (_) async => loads++,
      );
      addTearDown(controller.dispose);

      for (var index = 0; index < 120; index++) {
        port.next = _font(index);
        await controller.importForPreview();
        await controller.discardPreview();
      }

      expect(loads, 0);
      expect(port.removed, hasLength(120));
    },
  );

  test(
    'engine registration limit survives default and still permits previews',
    () async {
      final port = _PreviewPort();
      final store = _Store();
      final loaded = <String>[];
      final controller = await CustomFontController.load(
        store: store,
        port: port,
        loader: (font) async => loaded.add(font.id),
      );
      addTearDown(controller.dispose);

      for (var index = 0; index < 8; index++) {
        port.next = _font(index);
        await controller.importForPreview();
        await controller.applyPreview();
      }
      final selected = controller.selectedFont;
      port.next = _font(8);
      await controller.importForPreview();
      await expectLater(
        controller.applyPreview(),
        throwsA(isA<CustomFontLoadLimitException>()),
      );
      expect(controller.selectedFont, selected);
      expect(store.value, selected);
      expect(controller.previewFont, port.next);
      expect(loaded, hasLength(8));
      final png = Uint8List.fromList([137, 80, 78, 71]);
      port.result.complete(png);
      expect(
        await controller.renderPreview(
          text: 'Font',
          width: 640,
          fontSize: 18.0,
          locale: 'en',
          color: 0xff000000,
        ),
        same(png),
      );
      expect(controller.selectedFont, selected);

      await controller.restoreDefault();
      port.next = _font(8);
      await controller.importForPreview();
      await expectLater(
        controller.applyPreview(),
        throwsA(isA<CustomFontLoadLimitException>()),
      );
      expect(controller.selectedFont, isNull);
      expect(controller.previewFont, port.next);
      expect(loaded, hasLength(8));

      port.next = _font(0);
      await controller.importForPreview();
      await controller.applyPreview();
      expect(controller.selectedFont, port.next);
      expect(loaded, hasLength(8));
    },
  );

  test('startup registration consumes one of the eight font slots', () async {
    final store = _Store()..value = _font(0);
    final port = _Port();
    var loads = 0;
    final controller = await CustomFontController.load(
      store: store,
      port: port,
      loader: (_) async => loads++,
    );
    addTearDown(controller.dispose);
    for (var index = 1; index < 8; index++) {
      port.next = _font(index);
      await controller.importForPreview();
      await controller.applyPreview();
    }
    port.next = _font(8);
    await controller.importForPreview();
    await expectLater(controller.applyPreview(), throwsException);
    expect(loads, 8);
  });

  test(
    'PNG preview leaves engine loading, persistence and busy untouched',
    () async {
      final port = _PreviewPort()..next = _font(0);
      final store = _Store();
      var loads = 0;
      final controller = await CustomFontController.load(
        store: store,
        port: port,
        loader: (_) async => loads++,
      );
      addTearDown(controller.dispose);
      await controller.importForPreview();
      var notifications = 0;
      controller.addListener(() => notifications++);

      final rendering = controller.renderPreview(
        text: '艦これ Font',
        width: 640,
        fontSize: 18.0,
        locale: 'ja',
        color: 0xff123456,
      );
      expect(controller.busy, isFalse);
      expect(port.font, port.next);
      expect(port.arguments, ['艦これ Font', 640, 18.0, 'ja', 0xff123456]);
      final png = Uint8List.fromList([137, 80, 78, 71]);
      port.result.complete(png);
      expect(await rendering, same(png));
      expect(controller.selectedFont, isNull);
      expect(controller.previewFont, port.next);
      expect(store.value, isNull);
      expect(notifications, 0);
      expect(loads, 0);
    },
  );

  test('PNG preview reports a missing preview capability', () async {
    final controller = await CustomFontController.load(
      store: _Store(),
      port: _Port()..next = _font(0),
      loader: (_) async {},
    );
    addTearDown(controller.dispose);
    await controller.importForPreview();
    await expectLater(
      controller.renderPreview(
        text: 'Font',
        width: 640,
        fontSize: 18.0,
        locale: 'en',
        color: 0xff000000,
      ),
      throwsUnsupportedError,
    );
  });
}

CustomFontDescriptor _font(int index) => CustomFontDescriptor(
  id: index.toRadixString(16).padLeft(64, '0'),
  name: 'Font $index.ttf',
  path: '/private/font-$index.ttf',
);

final class _Store implements CustomFontStore {
  CustomFontDescriptor? value;

  @override
  Future<CustomFontDescriptor?> load() async => value;

  @override
  Future<void> save(CustomFontDescriptor? font) async => value = font;
}

class _Port implements CustomFontPort {
  CustomFontDescriptor? next;
  final removed = <String>[];

  @override
  Future<CustomFontDescriptor?> importFont() async => next;

  @override
  Future<void> removeFont(String id) async => removed.add(id);
}

final class _PreviewPort extends _Port implements CustomFontPreviewPort {
  final result = Completer<Uint8List>();
  CustomFontDescriptor? font;
  List<Object>? arguments;

  @override
  Future<Uint8List> renderPreview(
    CustomFontDescriptor font, {
    required String text,
    required int width,
    required double fontSize,
    required String locale,
    required int color,
  }) {
    this.font = font;
    arguments = [text, width, fontSize, locale, color];
    return result.future;
  }
}
