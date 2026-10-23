import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/settings/display_mode_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/display_mode_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/screen_settings_page.dart';
import 'package:yahagi_kancolle_browser/src/theme/app_theme.dart';
import 'package:yahagi_kancolle_browser/src/theme/app_palette.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test(
    'missing and invalid themes keep the original dark appearance',
    () async {
      for (final saved in <Object?>[null, '', 'unknown', 'sand', 42]) {
        SharedPreferences.setMockInitialValues(
          saved == null ? <String, Object>{} : {'app_theme_mode': saved},
        );
        final controller = await LayoutSettingsController.load(
          SharedPreferencesLayoutSettingsStore(),
        );
        expect(controller.appThemeMode, AppThemeMode.dark);
        controller.dispose();
      }
    },
  );

  test(
    'all themes persist without changing layout or language preferences',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'layout_locale_code': 'ja',
        'layout_game_area_ratio': .61,
        'layout_information_panel_on_left': true,
        'layout_auto_zoom': false,
        'layout_ui_locked': true,
        'layout_workspace_menu_position': 'bottom',
      });
      final controller = await LayoutSettingsController.load(
        SharedPreferencesLayoutSettingsStore(),
      );
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);

      for (final mode in [
        AppThemeMode.seaSalt,
        AppThemeMode.skyBlue,
        AppThemeMode.dark,
      ]) {
        await controller.setAppThemeMode(mode);
        final restored = await LayoutSettingsController.load(
          SharedPreferencesLayoutSettingsStore(),
        );
        expect(restored.appThemeMode, mode);
        expect(restored.localeCode, 'ja');
        expect(restored.gameAreaRatio, .61);
        expect(restored.informationPanelOnLeft, isTrue);
        expect(restored.autoZoom, isFalse);
        expect(restored.uiLocked, isTrue);
        expect(restored.workspaceMenuPosition, 'bottom');
        restored.dispose();
      }
      expect(notifications, 3);
      await controller.setAppThemeMode(AppThemeMode.dark);
      expect(notifications, 3);
    },
  );

  testWidgets('settings offer one theme dropdown with three colors', (
    tester,
  ) async {
    final controller = await LayoutSettingsController.load(
      SharedPreferencesLayoutSettingsStore(),
    );
    final display = await DisplayModeController.load(MemoryDisplayModeStore());
    addTearDown(controller.dispose);
    addTearDown(display.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScreenSettingsPage(
          layoutSettingsController: controller,
          displayModeController: display,
        ),
      ),
    );

    final dropdown = find.byKey(const Key('settings-app-theme-dropdown'));
    expect(dropdown, findsOneWidget);
    expect(find.text('主题色'), findsOneWidget);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    expect(find.text('原版暗色').last, findsOneWidget);
    expect(find.text('海盐青').last, findsOneWidget);
    expect(find.text('晴空蓝').last, findsOneWidget);
    await tester.tap(find.text('海盐青').last);
    await tester.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getString('app_theme_mode'),
      'seaSalt',
    );
    expect(controller.appThemeMode, AppThemeMode.seaSalt);
    expect(
      tester.widget<DropdownButton<AppThemeMode>>(dropdown).value,
      AppThemeMode.seaSalt,
    );
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('晴空蓝').last);
    await tester.pumpAndSettle();
    expect(controller.appThemeMode, AppThemeMode.skyBlue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'settings colors change while the existing rows keep their size',
    (tester) async {
      final controller = await LayoutSettingsController.load(
        SharedPreferencesLayoutSettingsStore(),
      );
      final display = await DisplayModeController.load(
        MemoryDisplayModeStore(),
      );
      addTearDown(controller.dispose);
      addTearDown(display.dispose);
      Rect? languageBounds;
      Rect? themeBounds;
      Rect? sizeBounds;
      for (final mode in AppThemeMode.values) {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            theme: createAppTheme(mode: mode),
            themeAnimationDuration: Duration.zero,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ScreenSettingsPage(
              layoutSettingsController: controller,
              displayModeController: display,
            ),
          ),
        );
        final language = tester.getRect(
          find.byKey(const Key('settings-language-label')),
        );
        final theme = tester.getRect(
          find.byKey(const Key('settings-app-theme-row')),
        );
        final size = tester.getRect(
          find.byKey(const Key('settings-ui-display-size-row')),
        );
        languageBounds ??= language;
        themeBounds ??= theme;
        sizeBounds ??= size;
        expect(language, languageBounds);
        expect(theme, themeBounds);
        expect(size, sizeBounds);
        final background = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(ScreenSettingsPage),
                matching: find.byType(Container),
              )
              .first,
        );
        expect(
          background.color,
          AppPalette(mode).color(const Color(0xff0d1a26)),
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
}
