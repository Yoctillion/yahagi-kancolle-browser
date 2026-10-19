import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/settings/display_mode_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/display_mode_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/screen_settings_page.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_settings.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_language.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'actual screen settings expose opt-in and conditional subtitle choices',
    (tester) async {
      final settings = await ShipSubtitleSettingsController.load();
      final layout = await LayoutSettingsController.load(
        SharedPreferencesLayoutSettingsStore(),
      );
      final display = await DisplayModeController.load(
        MemoryDisplayModeStore(),
      );
      addTearDown(settings.dispose);
      addTearDown(layout.dispose);
      addTearDown(display.dispose);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ScreenSettingsPage(
              layoutSettingsController: layout,
              displayModeController: display,
              shipSubtitleSettingsController: settings,
            ),
          ),
        ),
      );
      final toggle = find.byKey(const Key('settings-ship-subtitles'));
      await tester.ensureVisible(toggle);
      expect(tester.widget<Switch>(toggle).value, isFalse);
      expect(
        find.byKey(const Key('settings-ship-subtitle-font-size')),
        findsNothing,
      );
      final language = find.byKey(const Key('settings-ship-subtitle-language'));
      expect(language, findsNothing);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('settings-ship-subtitle-font-size')),
        findsOneWidget,
      );
      await tester.ensureVisible(language);
      await tester.tap(language);
      await tester.pumpAndSettle();
      await tester.tap(find.text('日本語').hitTestable());
      await tester.pumpAndSettle();
      expect(settings.language, ShipSubtitleLanguage.japanese);
      expect(tester.takeException(), isNull);
    },
  );
}
