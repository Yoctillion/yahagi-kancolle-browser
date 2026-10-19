import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// The platform fake exercises the plugin's false persistence result.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:yahagi_kancolle_browser/src/theme/custom_font_controller.dart';

const _first = CustomFontDescriptor(
  id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  name: 'First.ttf',
  path: '/private/fonts/first.ttf',
);
const _second = CustomFontDescriptor(
  id: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  name: 'Second.otf',
  path: '/private/fonts/second.otf',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'import previews without applying or saving and cancel removes it',
    () async {
      final store = _MemoryStore();
      final port = _MemoryPort()..next = _first;
      final loaded = <String>[];
      final controller = await CustomFontController.load(
        store: store,
        port: port,
        loader: (font) async => loaded.add(font.id),
      );
      addTearDown(controller.dispose);

      expect(await controller.importForPreview(), _first);
      expect(loaded, isEmpty);
      expect(controller.previewFont, _first);
      expect(controller.selectedFont, isNull);
      expect(controller.fontFamily, isNull);
      expect(store.saves, isEmpty);

      await controller.discardPreview();
      expect(controller.previewFont, isNull);
      expect(port.removed, [_first.id]);
      expect(store.saves, isEmpty);
    },
  );

  test(
    'applying persists and a fresh controller reloads the saved font',
    () async {
      final store = _MemoryStore()..value = _first;
      final port = _MemoryPort()..next = _second;
      final loaded = <String>[];
      Future<void> loader(CustomFontDescriptor font) async =>
          loaded.add(font.id);
      final controller = await CustomFontController.load(
        store: store,
        port: port,
        loader: loader,
      );
      addTearDown(controller.dispose);
      await controller.importForPreview();
      expect(controller.fontFamily, _first.fontFamily);

      await controller.applyPreview();
      expect(controller.selectedFont, _second);
      expect(controller.fontFamily, _second.fontFamily);
      expect(controller.previewFont, isNull);
      expect(store.value, _second);
      expect(port.removed, [_first.id]);

      final restarted = await CustomFontController.load(
        store: store,
        port: port,
        loader: loader,
      );
      addTearDown(restarted.dispose);
      expect(restarted.selectedFont, _second);
      expect(restarted.fontFamily, _second.fontFamily);
      expect(loaded, [_first.id, _second.id, _second.id]);
    },
  );

  test(
    'failed save keeps the active font and preview available to retry',
    () async {
      final store = _MemoryStore()..value = _first;
      final port = _MemoryPort()..next = _second;
      final loaded = <String>[];
      final controller = await CustomFontController.load(
        store: store,
        port: port,
        loader: (font) async => loaded.add(font.id),
      );
      addTearDown(controller.dispose);
      await controller.importForPreview();
      store.fail = true;

      await expectLater(controller.applyPreview(), throwsStateError);
      expect(controller.selectedFont, _first);
      expect(controller.previewFont, _second);
      expect(controller.busy, isFalse);
      expect(store.value, _first);
      expect(port.removed, isEmpty);
      expect(loaded, [_first.id, _second.id]);

      store.fail = false;
      await controller.applyPreview();
      expect(controller.selectedFont, _second);
      expect(store.value, _second);
      expect(loaded, [_first.id, _second.id]);
    },
  );

  test('selection changes only after persistence completes', () async {
    final gate = Completer<void>();
    final store = _MemoryStore()..saveGate = gate;
    final controller = await CustomFontController.load(
      store: store,
      port: _MemoryPort()..next = _first,
      loader: (_) async {},
    );
    addTearDown(controller.dispose);
    await controller.importForPreview();
    final applying = controller.applyPreview();
    expect(controller.busy, isTrue);
    expect(controller.selectedFont, isNull);
    expect(controller.previewFont, _first);
    gate.complete();
    await applying;
    expect(controller.selectedFont, _first);
    expect(controller.previewFont, isNull);
  });

  test(
    'restore default persists before clearing and cleans selected and preview',
    () async {
      final store = _MemoryStore()..value = _first;
      final port = _MemoryPort()..next = _second;
      final controller = await CustomFontController.load(
        store: store,
        port: port,
        loader: (_) async {},
      );
      addTearDown(controller.dispose);
      await controller.importForPreview();
      store.fail = true;
      await expectLater(controller.restoreDefault(), throwsStateError);
      expect(controller.selectedFont, _first);
      expect(controller.previewFont, _second);
      expect(port.removed, isEmpty);

      store.fail = false;
      await controller.restoreDefault();
      expect(controller.fontFamily, isNull);
      expect(controller.selectedFont, isNull);
      expect(controller.previewFont, isNull);
      expect(store.value, isNull);
      expect(port.removed, unorderedEquals([_first.id, _second.id]));
    },
  );

  test(
    'duplicate imports load once and cancel never deletes the active font',
    () async {
      final store = _MemoryStore()..value = _first;
      final port = _MemoryPort()..next = _first;
      var loads = 0;
      final controller = await CustomFontController.load(
        store: store,
        port: port,
        loader: (_) async => loads++,
      );
      addTearDown(controller.dispose);
      await controller.importForPreview();
      await controller.discardPreview();
      await controller.importForPreview();
      await controller.applyPreview();
      expect(loads, 1);
      expect(port.removed, isEmpty);
      expect(controller.selectedFont, _first);
    },
  );

  test('replacing a preview deletes only the superseded file', () async {
    final port = _MemoryPort()..next = _first;
    final controller = await CustomFontController.load(
      store: _MemoryStore(),
      port: port,
      loader: (_) async {},
    );
    addTearDown(controller.dispose);
    await controller.importForPreview();
    port.next = _second;
    await controller.importForPreview();
    expect(controller.previewFont, _second);
    expect(port.removed, [_first.id]);
    port.next = null;
    expect(await controller.importForPreview(), isNull);
    expect(controller.previewFont, _second);
    expect(port.removed, [_first.id]);
  });

  test(
    'failed apply preserves selection and preview so loading can retry',
    () async {
      final store = _MemoryStore()..value = _first;
      final port = _MemoryPort()..next = _second;
      var fail = true;
      final controller = await CustomFontController.load(
        store: store,
        port: port,
        loader: (font) async {
          if (font.id == _second.id && fail) {
            throw const FormatException('bad font');
          }
        },
      );
      addTearDown(controller.dispose);
      expect(await controller.importForPreview(), _second);
      await expectLater(controller.applyPreview(), throwsFormatException);
      expect(controller.selectedFont, _first);
      expect(controller.previewFont, _second);
      expect(controller.busy, isFalse);
      expect(port.removed, isEmpty);
      expect(store.value, _first);
      expect(store.saves, isEmpty);
      fail = false;
      await controller.applyPreview();
      expect(controller.selectedFont, _second);
    },
  );

  test(
    'cleanup failures do not roll back a saved selection or default',
    () async {
      final store = _MemoryStore()..value = _first;
      final port = _MemoryPort()
        ..next = _second
        ..failRemoval = true;
      final controller = await CustomFontController.load(
        store: store,
        port: port,
        loader: (_) async {},
      );
      addTearDown(controller.dispose);
      await controller.importForPreview();
      await controller.applyPreview();
      expect(controller.selectedFont, _second);
      expect(store.value, _second);
      await controller.restoreDefault();
      expect(controller.selectedFont, isNull);
      expect(store.value, isNull);
      expect(controller.busy, isFalse);
    },
  );

  test('a second concurrent import does not open another picker', () async {
    final gate = Completer<CustomFontDescriptor?>();
    final port = _MemoryPort()..importGate = gate;
    final controller = await CustomFontController.load(
      store: _MemoryStore(),
      port: port,
      loader: (_) async {},
    );
    addTearDown(controller.dispose);
    final importing = controller.importForPreview();
    expect(controller.busy, isTrue);
    expect(await controller.importForPreview(), isNull);
    expect(port.imports, 1);
    gate.complete(_first);
    expect(await importing, _first);
    expect(controller.busy, isFalse);
  });

  test('startup drops a saved font that cannot be loaded', () async {
    final store = _MemoryStore()..value = _first;
    final port = _MemoryPort();
    final controller = await CustomFontController.load(
      store: store,
      port: port,
      loader: (_) async => throw const FormatException('corrupt font'),
    );
    addTearDown(controller.dispose);
    expect(controller.selectedFont, isNull);
    expect(store.value, isNull);
    expect(port.removed, [_first.id]);
  });

  test('default loader rejects missing, invalid and oversized files', () async {
    final directory = await Directory.systemTemp.createTemp(
      'yahagi_font_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final invalid = await File(
      '${directory.path}/invalid.ttf',
    ).writeAsBytes([0, 1, 2, 3]);
    final oversized = File('${directory.path}/oversized.otf');
    final handle = await oversized.open(mode: FileMode.write);
    await handle.truncate(32 * 1024 * 1024 + 1);
    await handle.close();
    for (final path in [
      '${directory.path}/missing.ttf',
      invalid.path,
      oversized.path,
    ]) {
      final font = CustomFontDescriptor(
        id: _first.id,
        name: 'Invalid.ttf',
        path: path,
      );
      final store = _MemoryStore()..value = font;
      final port = _MemoryPort();
      final controller = await CustomFontController.load(
        store: store,
        port: port,
      );
      addTearDown(controller.dispose);
      expect(controller.selectedFont, isNull, reason: path);
      expect(store.value, isNull, reason: path);
      expect(port.removed, [font.id], reason: path);
    }
  });

  test(
    'preferences persist the descriptor independently of locale font settings',
    () async {
      SharedPreferences.setMockInitialValues({
        'font_family': 'HarmonyOS_Sans_SC',
      });
      final store = SharedPreferencesCustomFontStore();
      expect(await store.load(), isNull);
      await store.save(_first);
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString('custom_font_selection_v1')!), {
        'id': _first.id,
        'name': _first.name,
        'path': _first.path,
      });
      final restored = await SharedPreferencesCustomFontStore().load();
      expect(restored?.id, _first.id);
      expect(restored?.name, _first.name);
      expect(restored?.path, _first.path);
      await store.save(null);
      expect(prefs.containsKey('custom_font_selection_v1'), isFalse);
      expect(prefs.getString('font_family'), 'HarmonyOS_Sans_SC');
    },
  );

  test('malformed preference is cleared when the controller starts', () async {
    SharedPreferences.setMockInitialValues({
      'custom_font_selection_v1': '{bad',
    });
    final controller = await CustomFontController.load(
      store: SharedPreferencesCustomFontStore(),
      port: _MemoryPort(),
      loader: (_) async {},
    );
    addTearDown(controller.dispose);
    expect(controller.selectedFont, isNull);
    expect(
      (await SharedPreferences.getInstance()).containsKey(
        'custom_font_selection_v1',
      ),
      isFalse,
    );
  });

  test('preferences report failed writes and removals', () async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesStorePlatform.instance = _FailingPreferences();
    final store = SharedPreferencesCustomFontStore();
    await expectLater(store.save(_first), throwsStateError);
    await expectLater(store.save(null), throwsStateError);
  });

  test(
    'default loader registers a real TrueType font and restores it',
    () async {
      final realFile = File('assets/fonts/HarmonyOS_Sans.ttf');
      final realFont = CustomFontDescriptor(
        id: sha256.convert(await realFile.readAsBytes()).toString(),
        name: 'HarmonyOS_Sans.ttf',
        path: realFile.absolute.path,
      );
      final store = _MemoryStore();
      final port = _MemoryPort()..next = realFont;
      final controller = await CustomFontController.load(
        store: store,
        port: port,
      );
      addTearDown(controller.dispose);
      expect(await controller.importForPreview(), realFont);
      await controller.applyPreview();
      expect(controller.selectedFont, realFont);
      final restarted = await CustomFontController.load(
        store: store,
        port: port,
      );
      addTearDown(restarted.dispose);
      expect(restarted.selectedFont, realFont);
      expect(port.removed, isEmpty);
    },
  );

  test(
    'a platform exception cannot leave an unsaved font in the preference cache',
    () async {
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesStorePlatform.instance = _FailingPreferences(
        values: {
          'flutter.custom_font_selection_v1': jsonEncode(_first.toMap()),
        },
        throwWrites: true,
      );
      final store = SharedPreferencesCustomFontStore();
      expect((await store.load())?.id, _first.id);
      await expectLater(store.save(_second), throwsStateError);
      expect((await store.load())?.id, _first.id);
      await expectLater(store.save(null), throwsStateError);
      expect((await store.load())?.id, _first.id);
    },
  );
}

final class _MemoryStore implements CustomFontStore {
  CustomFontDescriptor? value;
  bool fail = false;
  Completer<void>? saveGate;
  final saves = <CustomFontDescriptor?>[];

  @override
  Future<CustomFontDescriptor?> load() async => value;

  @override
  Future<void> save(CustomFontDescriptor? font) async {
    await saveGate?.future;
    if (fail) throw StateError('save failed');
    saves.add(font);
    value = font;
  }
}

final class _MemoryPort implements CustomFontPort {
  CustomFontDescriptor? next;
  Completer<CustomFontDescriptor?>? importGate;
  int imports = 0;
  bool failRemoval = false;
  final removed = <String>[];

  @override
  Future<CustomFontDescriptor?> importFont() async {
    imports++;
    return importGate == null ? next : await importGate!.future;
  }

  @override
  Future<void> removeFont(String id) async {
    removed.add(id);
    if (failRemoval) throw StateError('cleanup failed');
  }
}

final class _FailingPreferences extends InMemorySharedPreferencesStore {
  _FailingPreferences({Map<String, Object>? values, this.throwWrites = false})
    : super.withData(values ?? {});

  final bool throwWrites;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (throwWrites) throw StateError('platform write failed');
    return false;
  }

  @override
  Future<bool> remove(String key) async {
    if (throwWrites) throw StateError('platform removal failed');
    return false;
  }
}
