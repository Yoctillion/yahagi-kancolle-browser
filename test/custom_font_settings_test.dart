import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/settings/display_mode_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/display_mode_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/custom_font_settings_section.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/screen_settings_page.dart';
import 'package:yahagi_kancolle_browser/src/theme/custom_font_controller.dart';

const _font = CustomFontDescriptor(
  id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  name: 'My Favorite Font.ttf',
  path: '/private/custom_fonts/favorite.ttf',
);

class _Store implements CustomFontStore {
  CustomFontDescriptor? value;
  bool failSave = false;
  Completer<void>? pendingSave;
  @override
  Future<CustomFontDescriptor?> load() async => value;
  @override
  Future<void> save(CustomFontDescriptor? font) async {
    await pendingSave?.future;
    if (failSave) throw StateError('storage unavailable');
    value = font;
  }
}

class _Port implements CustomFontPort, CustomFontPreviewPort {
  Object? error;
  Object? previewError;
  int renders = 0;
  Uint8List? previewBytes;
  Completer<Uint8List>? pendingPreview;
  Completer<CustomFontDescriptor?>? pendingImport;
  final removed = <String>[];
  @override
  Future<CustomFontDescriptor?> importFont() async {
    if (error case final Object error) throw error;
    return pendingImport == null ? _font : await pendingImport!.future;
  }

  @override
  Future<void> removeFont(String id) async => removed.add(id);

  @override
  Future<Uint8List> renderPreview(
    CustomFontDescriptor font, {
    required String text,
    required int width,
    required double fontSize,
    required String locale,
    required int color,
  }) async {
    renders++;
    if (previewError case final Object error) throw error;
    return pendingPreview != null
        ? await pendingPreview!.future
        : previewBytes ?? img.encodePng(img.Image(width: 160, height: 80));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    // Image decoding uses engine callbacks, which need real event-loop turns
    // rather than only advancing the fake clock used for widget animations.
    for (var attempt = 0; attempt < 100; attempt++) {
      if (find
              .byKey(const Key('custom-font-preview-dialog'))
              .evaluate()
              .isEmpty ||
          find
              .byKey(const Key('custom-font-preview-sample'))
              .evaluate()
              .isNotEmpty ||
          find
              .byKey(const Key('custom-font-preview-render-error'))
              .evaluate()
              .isNotEmpty) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<(CustomFontController, LayoutSettingsController, _Store, _Port)>
  setup({bool selected = false, CustomFontLoader? loader}) async {
    final store = _Store()..value = selected ? _font : null;
    final port = _Port();
    final fonts = await CustomFontController.load(
      store: store,
      port: port,
      loader: loader ?? (_) async {},
    );
    final layout = await LayoutSettingsController.load(
      SharedPreferencesLayoutSettingsStore(),
      systemLocaleCode: 'zh',
      customFontController: fonts,
    );
    addTearDown(layout.dispose);
    addTearDown(fonts.dispose);
    return (fonts, layout, store, port);
  }

  Future<void> pumpSettings(
    WidgetTester tester,
    LayoutSettingsController layout, {
    Locale locale = const Locale('zh'),
    bool fontControlsOnly = false,
  }) async {
    final display = await DisplayModeController.load(MemoryDisplayModeStore());
    addTearDown(display.dispose);
    await tester.pumpWidget(
      AnimatedBuilder(
        animation: layout,
        builder: (_, _) => MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            fontFamily: layout.fontFamily,
            fontFamilyFallback: layout.fontFamilyFallback,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(fontControlsOnly ? 1.3 : 1),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: fontControlsOnly
                ? SingleChildScrollView(
                    child: CustomFontSettingsSection(
                      controller: layout.customFontController!,
                      fallbackFonts: [layout.defaultFontFamily],
                    ),
                  )
                : ScreenSettingsPage(
                    layoutSettingsController: layout,
                    displayModeController: display,
                  ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  test(
    'custom font persists across locale changes and resets to locale default',
    () async {
      final (fonts, layout, store, _) = await setup(selected: true);
      var changes = 0;
      layout.addListener(() => changes++);
      expect(layout.fontFamily, _font.fontFamily);
      expect(layout.fontFamilyFallback.first, 'HarmonyOS_Sans_SC');
      await layout.setLocaleCode('zh_Hant');
      expect(layout.fontFamily, _font.fontFamily);
      expect(layout.fontFamilyFallback.first, 'HarmonyOS_Sans_TC');
      await layout.setLocaleCode(null);
      layout.updateSystemLocaleCode('en');
      expect(layout.fontFamily, _font.fontFamily);
      expect(layout.fontFamilyFallback.first, 'HarmonyOS_Sans');
      await fonts.restoreDefault();
      expect(layout.fontFamily, 'HarmonyOS_Sans');
      expect(store.value, isNull);
      expect(changes, greaterThanOrEqualTo(4));
    },
  );

  testWidgets('preview can be cancelled, applied, reloaded, and restored', (
    tester,
  ) async {
    final (fonts, layout, store, port) = await setup();
    await pumpSettings(tester, layout);
    final importButton = find.byKey(const Key('settings-custom-font-import'));
    await tester.ensureVisible(importButton);
    await tester.tap(importButton);
    await settle(tester);
    expect(find.byKey(const Key('custom-font-preview-dialog')), findsOneWidget);
    expect(layout.fontFamily, 'HarmonyOS_Sans_SC');
    expect(store.value, isNull);
    final sample = tester.widget<RawImage>(
      find.byKey(const Key('custom-font-preview-sample')),
    );
    expect(sample.image, isNotNull);
    expect(port.renders, 1);
    await tester.tap(find.byKey(const Key('custom-font-preview-cancel')));
    await settle(tester);
    expect(sample.image!.debugDisposed, isTrue);
    expect(fonts.selectedFont, isNull);
    expect(fonts.previewFont, isNull);
    await tester.tap(importButton);
    await settle(tester);
    await tester.tap(find.byKey(const Key('custom-font-preview-apply')));
    await settle(tester);
    expect(layout.fontFamily, _font.fontFamily);
    expect(store.value?.id, _font.id);
    final reloaded = await CustomFontController.load(
      store: store,
      port: port,
      loader: (_) async {},
    );
    addTearDown(reloaded.dispose);
    expect(reloaded.fontFamily, _font.fontFamily);
    await tester.tap(find.byKey(const Key('settings-custom-font-restore')));
    await settle(tester);
    expect(fonts.selectedFont, isNull);
    expect(layout.fontFamily, 'HarmonyOS_Sans_SC');
    expect(store.value, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled previews dispose images without registering fonts', (
    tester,
  ) async {
    var registrations = 0;
    final (_, layout, _, port) = await setup(
      loader: (_) async => registrations++,
    );
    await pumpSettings(tester, layout, fontControlsOnly: true);
    final cache = PaintingBinding.instance.imageCache;
    final initialLiveImages = cache.liveImageCount;
    final initialCachedImages = cache.currentSize;
    for (var i = 0; i < 20; i++) {
      await tester.tap(find.byKey(const Key('settings-custom-font-import')));
      await settle(tester);
      final image = tester
          .widget<RawImage>(find.byKey(const Key('custom-font-preview-sample')))
          .image!;
      expect(image.debugDisposed, isFalse);
      await tester.pump();
      expect(port.renders, i + 1);
      await tester.tap(find.byKey(const Key('custom-font-preview-cancel')));
      await settle(tester);
      expect(image.debugDisposed, isTrue);
    }
    expect(registrations, 0);
    expect(cache.liveImageCount, initialLiveImages);
    expect(cache.currentSize, initialCachedImages);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview errors allow retry and disable apply until rendered', (
    tester,
  ) async {
    final (_, layout, _, port) = await setup();
    port.previewError = StateError('native preview failed');
    await pumpSettings(tester, layout, fontControlsOnly: true);
    await tester.tap(find.byKey(const Key('settings-custom-font-import')));
    await settle(tester);
    expect(
      find.byKey(const Key('custom-font-preview-render-error')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('custom-font-preview-apply')),
          )
          .onPressed,
      isNull,
    );
    port.previewError = null;
    await tester.tap(find.byKey(const Key('custom-font-preview-retry')));
    await settle(tester);
    expect(find.byKey(const Key('custom-font-preview-sample')), findsOneWidget);
    expect(port.renders, 2);
    await tester.tap(find.byKey(const Key('custom-font-preview-cancel')));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late rendering after cancellation is ignored without caching', (
    tester,
  ) async {
    final (_, layout, _, port) = await setup();
    final pending = Completer<Uint8List>();
    port.pendingPreview = pending;
    await pumpSettings(tester, layout, fontControlsOnly: true);
    final cache = PaintingBinding.instance.imageCache;
    final cached = cache.currentSize;
    await tester.tap(find.byKey(const Key('settings-custom-font-import')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('custom-font-preview-apply')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('custom-font-preview-cancel')));
    await settle(tester);
    pending.complete(img.encodePng(img.Image(width: 160, height: 80)));
    await settle(tester);
    expect(find.byKey(const Key('custom-font-preview-dialog')), findsNothing);
    expect(cache.currentSize, cached);
    expect(tester.takeException(), isNull);
  });

  testWidgets('oversized decoded preview is rejected before display', (
    tester,
  ) async {
    final (_, layout, _, port) = await setup();
    port.previewBytes = img.encodePng(img.Image(width: 1025, height: 513));
    await pumpSettings(tester, layout, fontControlsOnly: true);
    await tester.tap(find.byKey(const Key('settings-custom-font-import')));
    await settle(tester);
    expect(
      find.byKey(const Key('custom-font-preview-render-error')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('custom-font-preview-sample')), findsNothing);
    await tester.tap(find.byKey(const Key('custom-font-preview-cancel')));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'registration limit preserves preview and shows restart guidance',
    (tester) async {
      final (fonts, layout, store, _) = await setup(
        loader: (_) async => throw const CustomFontLoadLimitException(),
      );
      await pumpSettings(tester, layout, fontControlsOnly: true);
      await tester.tap(find.byKey(const Key('settings-custom-font-import')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('custom-font-preview-apply')));
      await settle(tester);
      expect(find.textContaining('请重启应用'), findsOneWidget);
      expect(fonts.previewFont, isNotNull);
      expect(fonts.selectedFont, isNull);
      expect(store.value, isNull);
      await tester.tap(find.byKey(const Key('custom-font-preview-cancel')));
      await settle(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('save failure keeps the preview open and allows retry', (
    tester,
  ) async {
    final (fonts, layout, store, _) = await setup();
    await pumpSettings(tester, layout);
    await tester.tap(find.byKey(const Key('settings-custom-font-import')));
    await settle(tester);
    store.failSave = true;
    await tester.tap(find.byKey(const Key('custom-font-preview-apply')));
    await settle(tester);
    expect(find.byKey(const Key('custom-font-preview-dialog')), findsOneWidget);
    expect(find.byKey(const Key('custom-font-preview-error')), findsOneWidget);
    expect(fonts.selectedFont, isNull);
    store.failSave = false;
    await tester.tap(find.byKey(const Key('custom-font-preview-apply')));
    await settle(tester);
    expect(fonts.selectedFont?.id, _font.id);
    expect(find.byKey(const Key('custom-font-preview-dialog')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving settings during import discards the late preview', (
    tester,
  ) async {
    final (fonts, layout, store, port) = await setup();
    final pending = Completer<CustomFontDescriptor?>();
    port.pendingImport = pending;
    await pumpSettings(tester, layout);
    await tester.tap(find.byKey(const Key('settings-custom-font-import')));
    await tester.pump();
    expect(fonts.busy, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(_font);
    await settle(tester);
    expect(fonts.busy, isFalse);
    expect(fonts.previewFont, isNull);
    expect(fonts.selectedFont, isNull);
    expect(store.value, isNull);
    expect(port.removed, [_font.id]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'system back cancels the preview without changing the saved font',
    (tester) async {
      final (fonts, layout, store, port) = await setup();
      await pumpSettings(tester, layout);
      await tester.tap(find.byKey(const Key('settings-custom-font-import')));
      await settle(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byKey(const Key('custom-font-preview-dialog')), findsNothing);
      expect(fonts.previewFont, isNull);
      expect(fonts.selectedFont, isNull);
      expect(store.value, isNull);
      expect(port.removed, [_font.id]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('saving prevents back dismissal and duplicate application', (
    tester,
  ) async {
    final (fonts, layout, store, _) = await setup();
    final pending = Completer<void>();
    await pumpSettings(tester, layout);
    await tester.tap(find.byKey(const Key('settings-custom-font-import')));
    await settle(tester);
    store.pendingSave = pending;
    final apply = find.byKey(const Key('custom-font-preview-apply'));
    await tester.tap(apply);
    await tester.pump();
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);
    expect(fonts.selectedFont, isNull);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byKey(const Key('custom-font-preview-dialog')), findsOneWidget);
    pending.complete();
    await settle(tester);
    expect(find.byKey(const Key('custom-font-preview-dialog')), findsNothing);
    expect(fonts.selectedFont?.id, _font.id);
    expect(store.value?.id, _font.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'font setting aligns with neighboring rows and uses compact inline actions',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(918, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final (_, layout, _, _) = await setup();
      await pumpSettings(tester, layout);
      final title = find.text('界面字体');
      final current = find.byKey(const Key('settings-custom-font-current'));
      final import = find.byKey(const Key('settings-custom-font-import'));
      final restore = find.byKey(const Key('settings-custom-font-restore'));
      final neighbor = find.byKey(const Key('settings-ui-display-size-label'));
      expect(tester.getTopLeft(title).dx, tester.getTopLeft(neighbor).dx);
      expect(tester.getTopLeft(current).dx, tester.getTopLeft(title).dx);
      expect(tester.getSize(import).height, lessThanOrEqualTo(36));
      expect(tester.getSize(restore).height, lessThanOrEqualTo(36));
      expect(tester.getCenter(import).dy, tester.getCenter(restore).dy);
      expect(
        tester.getCenter(import).dy,
        lessThan(tester.getBottomLeft(current).dy),
      );
      expect(
        tester.getTopLeft(import).dx,
        greaterThan(tester.getTopRight(current).dx),
      );
      expect(
        tester.getCenter(restore).dx,
        lessThan(tester.getCenter(import).dx),
      );
      final restoreButton = tester.widget<OutlinedButton>(restore);
      final importButton = tester.widget<FilledButton>(import);
      expect(restoreButton.style?.shape?.resolve({}), isA<StadiumBorder>());
      expect(importButton.style?.shape?.resolve({}), isA<StadiumBorder>());
      expect(
        importButton.style?.backgroundColor?.resolve({}),
        const Color(0xffd4a85f),
      );
      expect(
        importButton.style?.foregroundColor?.resolve({}),
        const Color(0xff332914),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'import errors preserve the active font and report the size limit',
    (tester) async {
      final (fonts, layout, _, port) = await setup(selected: true);
      port.error = PlatformException(code: 'font_too_large');
      await pumpSettings(tester, layout);
      await tester.tap(find.byKey(const Key('settings-custom-font-import')));
      await settle(tester);
      expect(find.text('字体文件不能超过 32 MB。'), findsOneWidget);
      expect(fonts.selectedFont?.id, _font.id);
      expect(find.byKey(const Key('custom-font-preview-dialog')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('font controls and preview fit a narrow screen in $locale', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final (_, layout, _, _) = await setup();
      await pumpSettings(
        tester,
        layout,
        locale: locale,
        fontControlsOnly: true,
      );
      final importButton = find.byKey(const Key('settings-custom-font-import'));
      await tester.ensureVisible(importButton);
      final current = find.byKey(const Key('settings-custom-font-current'));
      expect(tester.getSize(importButton).height, lessThanOrEqualTo(36));
      final restore = find.byKey(const Key('settings-custom-font-restore'));
      expect(tester.getSize(restore).height, lessThanOrEqualTo(36));
      expect(tester.widget(restore), isA<OutlinedButton>());
      expect(tester.widget(importButton), isA<FilledButton>());
      expect(
        tester.getTopRight(restore).dx,
        lessThan(tester.getTopLeft(importButton).dx),
      );
      expect(
        tester.getCenter(importButton).dy,
        lessThan(tester.getBottomLeft(current).dy),
      );
      await tester.tap(importButton);
      await settle(tester);
      expect(
        find.byKey(const Key('custom-font-preview-dialog')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('custom-font-preview-cancel')));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  }
}
