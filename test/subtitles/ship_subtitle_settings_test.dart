import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Use the platform seam to verify failed writes also restore the Dart cache.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_language.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults are opt-in, medium, and bottom centered', () async {
    final settings = await ShipSubtitleSettingsController.load();
    addTearDown(settings.dispose);
    expect(settings.enabled, isFalse);
    expect(settings.fontSize, ShipSubtitleFontSize.medium);
    expect(settings.language, ShipSubtitleLanguage.simplifiedChinese);
    expect(settings.x, .5);
    expect(settings.y, .9);
    expect(settings.saving, isFalse);
    expect(settings.saveFailed, isFalse);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.containsKey(ShipSubtitleSettingsController.preferenceKey),
      isFalse,
    );
  });

  test('new saves record the default subtitle language', () async {
    final settings = await ShipSubtitleSettingsController.load();
    addTearDown(settings.dispose);
    await settings.setEnabled(true);
    final preferences = await SharedPreferences.getInstance();
    final saved =
        jsonDecode(
              preferences.getString(
                ShipSubtitleSettingsController.preferenceKey,
              )!,
            )
            as Map<String, dynamic>;
    expect(saved['language'], 'zh-cn');
  });

  test(
    'legacy settings retain all choices and default to Simplified Chinese',
    () async {
      final legacy = jsonEncode({
        'enabled': true,
        'fontSize': 'large',
        'x': .2,
        'y': .3,
      });
      SharedPreferences.setMockInitialValues({
        ShipSubtitleSettingsController.preferenceKey: legacy,
      });
      final settings = await ShipSubtitleSettingsController.load();
      addTearDown(settings.dispose);
      expect(settings.enabled, isTrue);
      expect(settings.fontSize, ShipSubtitleFontSize.large);
      expect(settings.language, ShipSubtitleLanguage.simplifiedChinese);
      expect((settings.x, settings.y), (.2, .3));
      expect(
        (await SharedPreferences.getInstance()).getString(
          ShipSubtitleSettingsController.preferenceKey,
        ),
        legacy,
      );
      await settings.setLanguage(ShipSubtitleLanguage.japanese);
      final migrated = await ShipSubtitleSettingsController.load();
      addTearDown(migrated.dispose);
      expect(migrated.language, ShipSubtitleLanguage.japanese);
      expect(migrated.enabled, isTrue);
      expect(migrated.fontSize, ShipSubtitleFontSize.large);
      expect((migrated.x, migrated.y), (.2, .3));
    },
  );

  test(
    'all subtitle languages survive a platform reload independently of other choices',
    () async {
      final settings = await ShipSubtitleSettingsController.load();
      addTearDown(settings.dispose);
      await settings.setFontSize(ShipSubtitleFontSize.small);
      await settings.setPosition(.25, .75);
      for (final language in ShipSubtitleLanguage.values) {
        await settings.setLanguage(language);
        final preferences = await SharedPreferences.getInstance();
        expect(
          (jsonDecode(
                preferences.getString(
                  ShipSubtitleSettingsController.preferenceKey,
                )!,
              )
              as Map<String, dynamic>)['language'],
          language.code,
        );
        await preferences.reload();
        final reloaded = await ShipSubtitleSettingsController.load();
        addTearDown(reloaded.dispose);
        expect(reloaded.language, language);
        expect(reloaded.enabled, isFalse);
        expect(reloaded.fontSize, ShipSubtitleFontSize.small);
        expect((reloaded.x, reloaded.y), (.25, .75));
      }
    },
  );

  test(
    'subtitle languages have stable codes, labels, assets, and safe parsing',
    () {
      expect(ShipSubtitleLanguage.values.map((language) => language.code), [
        'zh-cn',
        'zh-tw',
        'ja-jp',
        'en-us',
        'ko-kr',
      ]);
      expect(ShipSubtitleLanguage.values.map((language) => language.label), [
        '简体中文',
        '繁體中文',
        '日本語',
        'English',
        '한국어',
      ]);
      for (final language in ShipSubtitleLanguage.values) {
        expect(ShipSubtitleLanguage.fromStoredValue(language.code), language);
        expect(
          language.bundledAsset,
          'assets/data/subtitles/${language.code}.json',
        );
      }
      for (final invalid in [null, 'de-de', 'english', 4, true, <String>[]]) {
        expect(
          ShipSubtitleLanguage.fromStoredValue(invalid),
          ShipSubtitleLanguage.simplifiedChinese,
        );
      }
    },
  );

  test('enabled and all three font sizes survive a platform reload', () async {
    final settings = await ShipSubtitleSettingsController.load();
    addTearDown(settings.dispose);
    await settings.setEnabled(true);
    for (final size in ShipSubtitleFontSize.values) {
      await settings.setFontSize(size);
      await (await SharedPreferences.getInstance()).reload();
      final reloaded = await ShipSubtitleSettingsController.load();
      addTearDown(reloaded.dispose);
      expect(reloaded.enabled, isTrue);
      expect(reloaded.fontSize, size);
    }
    await settings.setEnabled(false);
    final disabled = await ShipSubtitleSettingsController.load();
    addTearDown(disabled.dispose);
    expect(disabled.enabled, isFalse);
    expect(disabled.fontSize, ShipSubtitleFontSize.large);
  });

  test(
    'position clamps to the game bounds and rejects nonfinite input',
    () async {
      final settings = await ShipSubtitleSettingsController.load();
      addTearDown(settings.dispose);
      await settings.setPosition(-.5, 1.4);
      expect((settings.x, settings.y), (0, 1));
      await settings.setPosition(double.nan, .5);
      await settings.setPosition(.5, double.infinity);
      expect((settings.x, settings.y), (0, 1));
      await (await SharedPreferences.getInstance()).reload();
      final reloaded = await ShipSubtitleSettingsController.load();
      addTearDown(reloaded.dispose);
      expect((reloaded.x, reloaded.y), (0, 1));
    },
  );

  test('unknown or malformed persisted settings fall back safely', () async {
    for (final value in [
      'broken json',
      '[]',
      jsonEncode({
        'enabled': 'true',
        'fontSize': 'huge',
        'language': 'de-de',
        'x': 'NaN',
        'y': null,
      }),
    ]) {
      SharedPreferences.setMockInitialValues({
        ShipSubtitleSettingsController.preferenceKey: value,
      });
      final settings = await ShipSubtitleSettingsController.load();
      addTearDown(settings.dispose);
      expect(settings.enabled, isFalse);
      expect(settings.fontSize, ShipSubtitleFontSize.medium);
      expect(settings.language, ShipSubtitleLanguage.simplifiedChinese);
      expect((settings.x, settings.y), (.5, .9));
    }
  });

  for (final throwsOnWrite in [false, true]) {
    test(
      'failed writes preserve settings and preference cache ($throwsOnWrite)',
      () async {
        final platform = _ControlledPreferencesStore({});
        SharedPreferencesStorePlatform.instance = platform;
        final settings = await ShipSubtitleSettingsController.load();
        addTearDown(settings.dispose);
        await settings.setEnabled(true);
        await settings.setFontSize(ShipSubtitleFontSize.small);
        await settings.setLanguage(ShipSubtitleLanguage.traditionalChinese);
        await settings.setPosition(.2, .3);
        platform
          ..failWrites = true
          ..throwsOnWrite = throwsOnWrite;
        await settings.setEnabled(false);
        await settings.setFontSize(ShipSubtitleFontSize.large);
        await settings.setLanguage(ShipSubtitleLanguage.english);
        await settings.setPosition(.8, .7);
        expect(settings.enabled, isTrue);
        expect(settings.fontSize, ShipSubtitleFontSize.small);
        expect(settings.language, ShipSubtitleLanguage.traditionalChinese);
        expect((settings.x, settings.y), (.2, .3));
        expect(settings.saveFailed, isTrue);
        expect(settings.saving, isFalse);
        final reloaded = await ShipSubtitleSettingsController.load();
        addTearDown(reloaded.dispose);
        expect(reloaded.enabled, isTrue);
        expect(reloaded.fontSize, ShipSubtitleFontSize.small);
        expect(reloaded.language, ShipSubtitleLanguage.traditionalChinese);
        expect((reloaded.x, reloaded.y), (.2, .3));
        platform.failWrites = false;
        await settings.setEnabled(false);
        await settings.setLanguage(ShipSubtitleLanguage.english);
        expect(settings.enabled, isFalse);
        expect(settings.language, ShipSubtitleLanguage.english);
        expect(settings.saveFailed, isFalse);
      },
    );
  }

  test(
    'queued updates retain the last dragged position and other choices',
    () async {
      final platform = _ControlledPreferencesStore({})
        ..writeGate = Completer<bool>();
      SharedPreferencesStorePlatform.instance = platform;
      final settings = await ShipSubtitleSettingsController.load();
      addTearDown(settings.dispose);
      final pending = <Future<void>>[
        settings.setPosition(.1, .2),
        settings.setFontSize(ShipSubtitleFontSize.large),
        settings.setLanguage(ShipSubtitleLanguage.japanese),
        settings.setPosition(.3, .4),
        settings.setEnabled(true),
        settings.setPosition(.7, .8),
        settings.setLanguage(ShipSubtitleLanguage.english),
      ];
      expect(settings.saving, isTrue);
      platform.writeGate!.complete(true);
      await Future.wait(pending);
      expect(settings.saving, isFalse);
      await (await SharedPreferences.getInstance()).reload();
      final reloaded = await ShipSubtitleSettingsController.load();
      addTearDown(reloaded.dispose);
      expect(reloaded.enabled, isTrue);
      expect(reloaded.fontSize, ShipSubtitleFontSize.large);
      expect(reloaded.language, ShipSubtitleLanguage.english);
      expect((reloaded.x, reloaded.y), (.7, .8));
    },
  );
}

class _ControlledPreferencesStore extends InMemorySharedPreferencesStore {
  _ControlledPreferencesStore(super.data) : super.withData();
  bool failWrites = false;
  bool throwsOnWrite = false;
  Completer<bool>? writeGate;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (failWrites) {
      if (throwsOnWrite) throw StateError('Disk write failed');
      return false;
    }
    if (writeGate != null && !await writeGate!.future) return false;
    return super.setValue(valueType, key, value);
  }
}
