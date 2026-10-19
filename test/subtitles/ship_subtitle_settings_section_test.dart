import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/settings/settings_ui_helpers.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_language.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_settings.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_settings_section.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_strings.dart';

void main() {
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
