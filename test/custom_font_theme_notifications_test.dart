import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/theme/custom_font_controller.dart';

const _first = CustomFontDescriptor(
  id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  name: 'First.ttf',
  path: '/private/fonts/first.ttf',
);
const _second = CustomFontDescriptor(
  id: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  name: 'Second.ttf',
  path: '/private/fonts/second.ttf',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<_Fixture> setup({CustomFontDescriptor? selected}) async {
    final store = _FontStore()..value = selected;
    final port = _FontPort();
    final fonts = await CustomFontController.load(
      store: store,
      port: port,
      loader: (_) async {},
    );
    final layout = await LayoutSettingsController.load(
      SharedPreferencesLayoutSettingsStore(),
      systemLocaleCode: 'zh',
      customFontController: fonts,
    );
    final fixture = _Fixture(fonts, layout, store, port);
    addTearDown(fixture.dispose);
    return fixture;
  }

  test(
    'import, preview replacement and discard only notify font controls',
    () async {
      final fixture = await setup();
      final gate = Completer<CustomFontDescriptor?>();
      fixture.port.pendingImport = gate;
      var layoutChanges = 0;
      var fontChanges = 0;
      fixture.layout.addListener(() => layoutChanges++);
      fixture.fonts.addListener(() => fontChanges++);

      final importing = fixture.fonts.importForPreview();
      expect(fixture.fonts.busy, isTrue);
      expect(fontChanges, greaterThan(0));
      expect(layoutChanges, 0, reason: 'Busy is local to the font controls');
      gate.complete(_first);
      await importing;
      expect(fixture.fonts.previewFont, _first);
      expect(fixture.fonts.busy, isFalse);
      expect(layoutChanges, 0);

      fixture.port.pendingImport = null;
      fixture.port.next = _second;
      await fixture.fonts.importForPreview();
      expect(fixture.fonts.previewFont, _second);
      expect(layoutChanges, 0);
      await fixture.fonts.discardPreview();
      expect(fixture.fonts.previewFont, isNull);
      expect(fixture.fonts.selectedFont, isNull);
      expect(layoutChanges, 0);
      expect(fontChanges, greaterThan(1));
    },
  );

  test(
    'cancelling the file picker leaves the application theme untouched',
    () async {
      final fixture = await setup(selected: _first);
      fixture.port.next = null;
      var changes = 0;
      fixture.layout.addListener(() => changes++);

      expect(await fixture.fonts.importForPreview(), isNull);

      expect(fixture.fonts.fontFamily, _first.fontFamily);
      expect(fixture.fonts.busy, isFalse);
      expect(changes, 0);
    },
  );

  test(
    'applying a new family notifies the application theme once after save',
    () async {
      final fixture = await setup();
      await fixture.fonts.importForPreview();
      final gate = Completer<void>();
      fixture.store.pendingSave = gate;
      var changes = 0;
      fixture.layout.addListener(() => changes++);

      final applying = fixture.fonts.applyPreview();
      expect(fixture.fonts.busy, isTrue);
      expect(changes, 0, reason: 'The selection has not been persisted yet');
      gate.complete();
      await applying;

      expect(fixture.layout.fontFamily, _first.fontFamily);
      expect(fixture.store.value, _first);
      expect(fixture.fonts.busy, isFalse);
      expect(changes, 1);
    },
  );

  test(
    'a loaded selection and another file name for its ID keep the same theme',
    () async {
      final fixture = await setup(selected: _first);
      final renamed = CustomFontDescriptor(
        id: _first.id,
        name: 'Renamed.ttf',
        path: _first.path,
      );
      fixture.port.next = renamed;
      var changes = 0;
      fixture.layout.addListener(() => changes++);

      await fixture.fonts.importForPreview();
      await fixture.fonts.applyPreview();

      expect(fixture.fonts.selectedFont?.name, renamed.name);
      expect(fixture.layout.fontFamily, _first.fontFamily);
      expect(changes, 0);
    },
  );

  test(
    'restoring the default font notifies the application theme once',
    () async {
      final fixture = await setup(selected: _first);
      var changes = 0;
      fixture.layout.addListener(() => changes++);

      await fixture.fonts.restoreDefault();

      expect(fixture.layout.fontFamily, fixture.layout.defaultFontFamily);
      expect(changes, 1);
      await fixture.fonts.restoreDefault();
      expect(changes, 1, reason: 'An unchanged default needs no theme update');
    },
  );

  test(
    'a failed save does not notify or replace the application theme',
    () async {
      final fixture = await setup(selected: _first);
      fixture.port.next = _second;
      await fixture.fonts.importForPreview();
      fixture.store.failSave = true;
      var changes = 0;
      fixture.layout.addListener(() => changes++);

      await expectLater(fixture.fonts.applyPreview(), throwsStateError);
      await expectLater(fixture.fonts.restoreDefault(), throwsStateError);

      expect(fixture.layout.fontFamily, _first.fontFamily);
      expect(fixture.fonts.busy, isFalse);
      expect(changes, 0);
    },
  );

  test('disposing layout removes the font listener and forwarding', () async {
    final fixture = await setup();
    var changes = 0;
    fixture.layout.addListener(() => changes++);
    final errors = <FlutterErrorDetails>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = originalOnError);

    fixture.disposeLayout();
    await fixture.fonts.importForPreview();
    await fixture.fonts.applyPreview();

    expect(errors, isEmpty, reason: 'Fonts must not notify a disposed layout');
    expect(changes, 0);
  });

  test('locale changes still notify when a custom font is selected', () async {
    final fixture = await setup(selected: _first);
    var changes = 0;
    fixture.layout.addListener(() => changes++);

    await fixture.layout.setLocaleCode('en');
    expect(changes, 1);
    expect(fixture.layout.fontFamily, _first.fontFamily);
    expect(fixture.layout.fontFamilyFallback.first, 'HarmonyOS_Sans');
    await fixture.layout.setLocaleCode(null);
    fixture.layout.updateSystemLocaleCode('ko');
    expect(changes, 3);
    expect(fixture.layout.fontFamily, _first.fontFamily);
    expect(fixture.layout.fontFamilyFallback.first, 'HarmonyOS_Sans');
  });
}

final class _Fixture {
  _Fixture(this.fonts, this.layout, this.store, this.port);

  final CustomFontController fonts;
  final LayoutSettingsController layout;
  final _FontStore store;
  final _FontPort port;
  bool _layoutDisposed = false;

  void disposeLayout() {
    if (_layoutDisposed) return;
    _layoutDisposed = true;
    layout.dispose();
  }

  void dispose() {
    disposeLayout();
    fonts.dispose();
  }
}

final class _FontStore implements CustomFontStore {
  CustomFontDescriptor? value;
  bool failSave = false;
  Completer<void>? pendingSave;

  @override
  Future<CustomFontDescriptor?> load() async => value;

  @override
  Future<void> save(CustomFontDescriptor? font) async {
    await pendingSave?.future;
    if (failSave) throw StateError('Font save failed');
    value = font;
  }
}

final class _FontPort implements CustomFontPort {
  CustomFontDescriptor? next = _first;
  Completer<CustomFontDescriptor?>? pendingImport;

  @override
  Future<CustomFontDescriptor?> importFont() async =>
      pendingImport == null ? next : await pendingImport!.future;

  @override
  Future<void> removeFont(String id) async {}
}
