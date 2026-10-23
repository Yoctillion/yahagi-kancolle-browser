import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/settings/settings_ui_helpers.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_catalog.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_catalog_controller.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_language.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_port.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_runtime_controller.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_settings.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_settings_section.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_strings.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_update_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GameStateController.disableTimerForTest = true;
  });
  tearDown(() => GameStateController.disableTimerForTest = false);

  testWidgets('unsupported subtitles keep opt-in and can recover from retry', (
    tester,
  ) async {
    final f = await _RuntimeFixture.create(supported: false);
    addTearDown(f.dispose);
    await f.runtime.initialize();
    await _pumpRuntimeSection(tester, f);
    expect(find.text('当前 WebView 不支持字幕，请更新系统 WebView 后重新检测。'), findsOneWidget);
    final toggle = find.byKey(const Key('settings-ship-subtitles'));
    expect(tester.widget<Switch>(toggle).value, isTrue);
    f.port.supported = true;
    await tester.tap(find.byKey(const Key('settings-ship-subtitle-retry')));
    await tester.pumpAndSettle();
    expect(f.port.supportChecks, 2);
    expect(f.settings.enabled, isTrue);
    expect(f.runtime.status, ShipSubtitleRuntimeStatus.ready);
    expect(
      find.byKey(const Key('settings-ship-subtitle-runtime-status')),
      findsNothing,
    );
    final reloaded = await ShipSubtitleSettingsController.load();
    addTearDown(reloaded.dispose);
    expect(reloaded.enabled, isTrue);
    f.runtime.dispose();
  });

  testWidgets('support checks show progress and disable repeated retries', (
    tester,
  ) async {
    final f = await _RuntimeFixture.create();
    addTearDown(f.dispose);
    final gate = Completer<bool>();
    f.port.supportGate = gate.future;
    final initialization = f.runtime.initialize();
    await _pumpRuntimeSection(tester, f, settle: false);
    expect(find.text('正在检测字幕支持…'), findsOneWidget);
    final retry = find.byKey(const Key('settings-ship-subtitle-retry'));
    expect(tester.widget<TextButton>(retry).onPressed, isNull);
    gate.complete(true);
    await initialization;
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('settings-ship-subtitle-runtime-status')),
      findsNothing,
    );
    f.runtime.dispose();
  });

  testWidgets('failed subtitle initialization exposes recovery', (
    tester,
  ) async {
    final f = await _RuntimeFixture.create();
    addTearDown(f.dispose);
    f.port.failCatalog = true;
    await f.runtime.initialize();
    await _pumpRuntimeSection(tester, f);
    expect(find.text('字幕初始化失败，请重新检测。'), findsOneWidget);
    f.port.failCatalog = false;
    await tester.tap(find.byKey(const Key('settings-ship-subtitle-retry')));
    await tester.pumpAndSettle();
    expect(f.runtime.status, ShipSubtitleRuntimeStatus.ready);
    expect(f.settings.enabled, isTrue);
    expect(
      find.byKey(const Key('settings-ship-subtitle-runtime-status')),
      findsNothing,
    );
    f.runtime.dispose();
  });

  testWidgets('missing game voice mappings explain how to resume subtitles', (
    tester,
  ) async {
    final f = await _RuntimeFixture.create(hasGameData: false);
    addTearDown(f.dispose);
    await f.runtime.initialize();
    await _pumpRuntimeSection(tester, f);
    expect(find.text('尚未取得舰娘语音资料，请在游戏模式重新载入游戏。'), findsOneWidget);
    expect(find.byKey(const Key('settings-ship-subtitle-retry')), findsNothing);
    f.runtime.dispose();
  });

  testWidgets(
    'disabled subtitles hide runtime failures without changing opt-in',
    (tester) async {
      final f = await _RuntimeFixture.create(supported: false);
      addTearDown(f.dispose);
      await f.runtime.initialize();
      await f.settings.setEnabled(false);
      await _pumpRuntimeSection(tester, f);
      expect(
        find.byKey(const Key('settings-ship-subtitle-runtime-status')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('settings-ship-subtitle-retry')),
        findsNothing,
      );
      f.runtime.dispose();
    },
  );

  for (final entry in <Locale, String>{
    const Locale('zh'): '当前 WebView 不支持字幕，请更新系统 WebView 后重新检测。',
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'):
        '目前 WebView 不支援字幕，請更新系統 WebView 後重新檢測。',
    const Locale('ja'):
        '現在の WebView は字幕に対応していません。システムの WebView を更新して再確認してください。',
    const Locale(
      'en',
    ): 'This WebView does not support subtitles. Update the system WebView, then check again.',
    const Locale('ko'):
        '현재 WebView는 자막을 지원하지 않습니다. 시스템 WebView를 업데이트한 후 다시 확인하세요.',
  }.entries) {
    testWidgets('runtime guidance fits a narrow viewport: ${entry.key}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = await _RuntimeFixture.create(supported: false);
      addTearDown(f.dispose);
      await f.runtime.initialize();
      await _pumpRuntimeSection(tester, f, locale: entry.key);
      expect(find.text(entry.value), findsOneWidget);
      final retry = find.byKey(const Key('settings-ship-subtitle-retry'));
      await tester.ensureVisible(retry);
      expect(tester.getRect(retry).right, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
      f.runtime.dispose();
    });
  }

  testWidgets(
    'Korean subtitles are available independently of interface language',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = await ShipSubtitleSettingsController.load();
      addTearDown(settings.dispose);
      await settings.setEnabled(true);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ShipSubtitleSettingsSection(controller: settings),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('settings-ship-subtitle-language')),
      );
      await tester.pumpAndSettle();
      expect(find.text('한국어').hitTestable(), findsOneWidget);
      await tester.tap(find.text('한국어').hitTestable());
      await tester.pumpAndSettle();
      expect(settings.language.code, 'ko-kr');
      final reloaded = await ShipSubtitleSettingsController.load();
      addTearDown(reloaded.dispose);
      expect(reloaded.language.code, 'ko-kr');
    },
  );

  for (final locale in [
    const Locale('zh'),
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    const Locale('ja'),
    const Locale('en'),
    const Locale('ko'),
  ]) {
    testWidgets(
      'subtitle choices appear only when enabled and persist selections: $locale',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final settings = await ShipSubtitleSettingsController.load();
        addTearDown(settings.dispose);
        final strings = ShipSubtitleStrings(locale);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: ShipSubtitleSettingsSection(controller: settings),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final toggle = find.byKey(const Key('settings-ship-subtitles'));
        final languages = find.byKey(
          const Key('settings-ship-subtitle-language'),
        );
        expect(tester.widget<Switch>(toggle).value, isFalse);
        expect(
          find.byKey(const Key('settings-ship-subtitle-font-size')),
          findsNothing,
        );
        expect(languages, findsNothing);
        final title = tester.widget<Text>(find.text(strings.title));
        expect(title.style?.fontSize, SettingsTileTypography.title.fontSize);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(find.text(strings.fontSize), findsOneWidget);
        expect(find.text(strings.language), findsOneWidget);
        final sizes = find.byKey(const Key('settings-ship-subtitle-font-size'));
        expect(
          find.text(strings.sizeLabel(ShipSubtitleFontSize.medium)),
          findsOneWidget,
        );
        expect(
          find.text(strings.sizeLabel(ShipSubtitleFontSize.small)),
          findsNothing,
        );
        await tester.tap(sizes);
        await tester.pumpAndSettle();
        expect(
          find
              .text(strings.sizeLabel(ShipSubtitleFontSize.small))
              .hitTestable(),
          findsOneWidget,
        );
        await tester.tap(
          find.text(strings.sizeLabel(ShipSubtitleFontSize.large)),
        );
        await tester.pumpAndSettle();
        expect(settings.fontSize, ShipSubtitleFontSize.large);
        expect(
          find.text(strings.sizeLabel(ShipSubtitleFontSize.large)),
          findsOneWidget,
        );
        expect(find.text('简体中文'), findsOneWidget);
        expect(find.text('English'), findsNothing);
        await tester.tap(languages);
        await tester.pumpAndSettle();
        final menuOptions = ShipSubtitleLanguage.values
            .map((language) => find.text(language.label).hitTestable().last)
            .toList();
        for (var index = 0; index < menuOptions.length; index++) {
          expect(menuOptions[index], findsOneWidget);
          if (index > 0) {
            expect(
              tester.getCenter(menuOptions[index]).dy,
              greaterThan(tester.getCenter(menuOptions[index - 1]).dy),
            );
          }
        }
        await tester.tap(find.text('English').hitTestable());
        await tester.pumpAndSettle();
        expect(settings.language, ShipSubtitleLanguage.english);
        expect(find.text('English'), findsOneWidget);
        expect(find.text('日本語'), findsNothing);
        final reloaded = await ShipSubtitleSettingsController.load();
        addTearDown(reloaded.dispose);
        expect(reloaded.fontSize, ShipSubtitleFontSize.large);
        expect(reloaded.language, ShipSubtitleLanguage.english);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('settings-ship-subtitle-font-size')),
          findsNothing,
        );
        expect(languages, findsNothing);
        expect(settings.fontSize, ShipSubtitleFontSize.large);
        expect(settings.language, ShipSubtitleLanguage.english);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('enabled settings fit a narrow viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final settings = await ShipSubtitleSettingsController.load();
    addTearDown(settings.dispose);
    await settings.setEnabled(true);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: ThemeData.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ShipSubtitleSettingsSection(controller: settings),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('settings-ship-subtitle-font-size')),
      findsOneWidget,
    );
    final languages = find.byKey(const Key('settings-ship-subtitle-language'));
    expect(languages, findsOneWidget);
    await tester.tap(languages);
    await tester.pumpAndSettle();
    expect(find.text('English').hitTestable(), findsOneWidget);
    expect(find.text('日本語').hitTestable(), findsOneWidget);
    await tester.tap(find.text('繁體中文').hitTestable());
    await tester.pumpAndSettle();
    expect(settings.language, ShipSubtitleLanguage.traditionalChinese);
    final sizes = find.byKey(const Key('settings-ship-subtitle-font-size'));
    await tester.tap(sizes);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Large').hitTestable());
    await tester.pumpAndSettle();
    expect(settings.fontSize, ShipSubtitleFontSize.large);
    expect(tester.getRect(languages).right, lessThanOrEqualTo(320));
    expect(tester.getRect(sizes).right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpRuntimeSection(
  WidgetTester tester,
  _RuntimeFixture f, {
  Locale locale = const Locale('zh'),
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ShipSubtitleSettingsSection(
            controller: f.settings,
            runtimeController: f.runtime,
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

final class _RuntimeFixture {
  _RuntimeFixture(
    this.settings,
    this.catalog,
    this.layout,
    this.game,
    this.port,
  ) : runtime = ShipSubtitleRuntimeController(
        settings: settings,
        catalog: catalog,
        layout: layout,
        gameState: game,
        port: port,
      );

  final ShipSubtitleSettingsController settings;
  final ShipSubtitleCatalogController catalog;
  final LayoutSettingsController layout;
  final GameStateController game;
  final _RuntimePort port;
  final ShipSubtitleRuntimeController runtime;

  static Future<_RuntimeFixture> create({
    bool supported = true,
    bool hasGameData = true,
  }) async {
    final settings = await ShipSubtitleSettingsController.load();
    await settings.setEnabled(true);
    final catalog = ShipSubtitleCatalogController(
      data: ShipSubtitleCatalog(
        version: '2026101805',
        quotes: {
          '1': {'1': '台词'},
        },
      ),
      updater: _OfflineUpdater(),
    );
    final layout = await LayoutSettingsController.load(
      SharedPreferencesLayoutSettingsStore(),
    );
    final game = GameStateController(
      initialState: GameState(
        masterShips: hasGameData
            ? const {
                1: MasterShip(
                  id: 1,
                  name: '睦月',
                  shipTypeId: 2,
                  portraitFileName: 'voice-file',
                ),
              }
            : const {},
      ),
    );
    return _RuntimeFixture(
      settings,
      catalog,
      layout,
      game,
      _RuntimePort()..supported = supported,
    );
  }

  void dispose() {
    runtime.dispose();
    settings.dispose();
    catalog.dispose();
    layout.dispose();
    game.dispose();
  }
}

final class _RuntimePort implements ShipSubtitlePort {
  bool supported = true;
  bool failCatalog = false;
  int supportChecks = 0;
  Future<bool>? supportGate;

  @override
  void Function(double x, double y)? onPositionChanged;

  @override
  Future<bool> isSupported() async {
    supportChecks++;
    return await supportGate ?? supported;
  }

  @override
  Future<void> configure({
    required bool enabled,
    required ShipSubtitleFontSize fontSize,
    required bool locked,
    required double x,
    required double y,
  }) async {}

  @override
  Future<void> setCatalog(ShipSubtitleCatalog catalog) async {
    if (failCatalog) throw StateError('Subtitle initialization failed');
  }

  @override
  Future<void> setShips(List<Map<String, Object?>> ships) async {}

  @override
  void dispose() {}
}

final class _OfflineUpdater implements ShipSubtitleUpdateClient {
  @override
  Future<ShipSubtitleUpdateResult> checkAndUpdate({
    required ShipSubtitleCatalog current,
  }) async => ShipSubtitleUpToDate(current, sourceHost: '');
}
