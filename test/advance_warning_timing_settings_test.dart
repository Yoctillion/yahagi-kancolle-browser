import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/settings/battle_status_effect_settings.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_store.dart';

void main() {
  test('timing values contain all nonempty independent stage selections', () {
    expect(AdvanceWarningTimingSettings.values.toSet(), <
      AdvanceWarningTimingSettings
    >{
      const AdvanceWarningTimingSettings(),
      const AdvanceWarningTimingSettings(postBattle: true),
      const AdvanceWarningTimingSettings(postBattle: true, afterAdvance: false),
    });
    expect(
      AdvanceWarningTimingSettings.values.every((settings) => settings.hasAny),
      isTrue,
    );
    expect(
      AdvanceWarningTimingSettings.advanceOnly.copyWith(postBattle: true),
      AdvanceWarningTimingSettings.battleAndAdvance,
    );
    expect(
      AdvanceWarningTimingSettings.battleAndAdvance.copyWith(
        afterAdvance: false,
      ),
      AdvanceWarningTimingSettings.battleOnly,
    );
    expect(
      AdvanceWarningTimingSettings.battleOnly.copyWith(),
      AdvanceWarningTimingSettings.battleOnly,
    );
    expect(
      AdvanceWarningTimingSettings.advanceOnly.hashCode,
      const AdvanceWarningTimingSettings().hashCode,
    );
    expect(
      AdvanceWarningTimingSettings.battleOnly.toString(),
      contains('postBattle: true, afterAdvance: false'),
    );
    expect(
      const AdvanceWarningTimingSettings(afterAdvance: false).hasAny,
      isFalse,
    );
  });

  test('all five languages explain independent timings and next sortie', () {
    final expectedTranslations = <String, (String, String)>{
      'en': ('Warning timing', 'next sortie'),
      'ja': ('警告のタイミング', '次回の出撃'),
      'ko': ('알림 시점', '다음 출격'),
      'zh': ('提醒时机', '下次出击'),
      'zh-Hant': ('提醒時機', '下次出擊'),
    };
    expect(AppLocalizations.supportedLocales, hasLength(5));
    for (final locale in AppLocalizations.supportedLocales) {
      final localizations = lookupAppLocalizations(locale);
      final expected = expectedTranslations[locale.toLanguageTag()]!;
      expect(localizations.advanceWarningTimingModeTitle, expected.$1);
      expect(
        localizations.advanceWarningTimingModeDescription,
        contains(expected.$2),
      );
      expect(
        localizations.advanceWarningTimingModeDescription,
        isNot(contains('POI')),
      );
      expect(
        localizations.advanceWarningTimingModeDescription,
        isNot(contains('KCA')),
      );
      expect(localizations.advanceWarningPostBattle, isNotEmpty);
      expect(localizations.advanceWarningAfterAdvance, isNotEmpty);
      expect(localizations.advanceWarningTimingRequired, isNotEmpty);
      expect(localizations.advanceWarningPostBattleOnlyWarning, isNotEmpty);
      expect(
        localizations.advanceWarningPostBattle,
        isNot(localizations.advanceWarningAfterAdvance),
      );
    }
  });

  test(
    'unset timings default to advance only and preserve other settings',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'safety.battleWarningMode': 'off',
        'safety.advanceWarningDisplayMode': 'smart',
      });
      final memoryStore = MemorySafetySettingsStore();
      await memoryStore.saveWarningMode(BattleWarningMode.off);
      await memoryStore.saveAdvanceWarningDisplayMode(
        AdvanceWarningDisplayMode.smart,
      );

      for (final store in <SafetySettingsStore>[
        SharedPreferencesSafetySettingsStore(),
        memoryStore,
      ]) {
        final controller = await SafetySettingsController.load(store);
        addTearDown(controller.dispose);
        expect(
          controller.advanceWarningTimings,
          AdvanceWarningTimingSettings.advanceOnly,
        );
        expect(controller.battleWarningMode, BattleWarningMode.off);
        expect(
          controller.advanceWarningDisplayMode,
          AdvanceWarningDisplayMode.smart,
        );
      }
    },
  );

  for (final legacyValue in <Object>[
    'kca',
    'poi',
    '',
    'unknown',
    'POI',
    'KCA',
    'off',
    42,
    false,
    2.5,
    <String>['kca'],
  ]) {
    test(
      'legacy timing $legacyValue migrates only when new key is absent',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'safety.advanceWarningTimingMode': legacyValue,
          'safety.battleWarningMode': 'off',
          'safety.advanceWarningDisplayMode': 'smart',
        });
        final controller = await SafetySettingsController.load(
          SharedPreferencesSafetySettingsStore(),
        );
        addTearDown(controller.dispose);
        expect(
          controller.advanceWarningTimings,
          legacyValue == 'kca'
              ? AdvanceWarningTimingSettings.battleAndAdvance
              : AdvanceWarningTimingSettings.advanceOnly,
        );
        expect(controller.battleWarningMode, BattleWarningMode.off);
        expect(
          controller.advanceWarningDisplayMode,
          AdvanceWarningDisplayMode.smart,
        );
      },
    );
  }

  for (final invalidValue in <Object>[
    '',
    'unknown',
    'kca',
    '{',
    'null',
    'true',
    '42',
    '[]',
    '{}',
    '{"postBattle":true}',
    '{"afterAdvance":true}',
    '{"postBattle":false,"afterAdvance":false}',
    '{"postBattle":"true","afterAdvance":true}',
    '{"postBattle":true,"afterAdvance":1}',
    '{"postBattle":null,"afterAdvance":true}',
    42,
    false,
    2.5,
    <String>['kca'],
  ]) {
    test(
      'invalid new timings $invalidValue ignore legacy KCA and fall back',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'safety.advanceWarningTimings': invalidValue,
          'safety.advanceWarningTimingMode': 'kca',
        });
        final controller = await SafetySettingsController.load(
          SharedPreferencesSafetySettingsStore(),
        );
        addTearDown(controller.dispose);
        expect(
          controller.advanceWarningTimings,
          AdvanceWarningTimingSettings.advanceOnly,
        );
      },
    );
  }

  for (final timings in AdvanceWarningTimingSettings.values) {
    test(
      'saved $timings overrides legacy mode and restores atomically',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'safety.advanceWarningTimingMode': 'kca',
        });
        final store = SharedPreferencesSafetySettingsStore();
        await store.saveAdvanceWarningTimings(timings);
        final preferences = await SharedPreferences.getInstance();
        expect(
          jsonDecode(preferences.getString('safety.advanceWarningTimings')!),
          <String, bool>{
            'postBattle': timings.postBattle,
            'afterAdvance': timings.afterAdvance,
          },
        );
        expect(
          preferences
              .getKeys()
              .where((key) => key.startsWith('safety.advanceWarningTimings'))
              .toSet(),
          <String>{'safety.advanceWarningTimings'},
        );
        final restored = await SafetySettingsController.load(store);
        addTearDown(restored.dispose);
        expect(restored.advanceWarningTimings, timings);
        expect(restored.battleWarningMode, BattleWarningMode.confirm);
        expect(
          restored.advanceWarningDisplayMode,
          AdvanceWarningDisplayMode.alwaysConfirm,
        );
      },
    );
  }

  test(
    'timings persist independently from display, enablement, and effects',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final controller = await SafetySettingsController.load(
        SharedPreferencesSafetySettingsStore(),
      );
      addTearDown(controller.dispose);
      final effects = controller.battleStatusEffects.copyWith(enabled: false);
      await controller.setAdvanceWarningTimings(
        AdvanceWarningTimingSettings.battleOnly,
      );
      await controller.setAdvanceWarningDisplayMode(
        AdvanceWarningDisplayMode.smart,
      );
      await controller.setBattleWarningMode(BattleWarningMode.off);
      await controller.setBattleStatusEffects(effects);

      final restored = await SafetySettingsController.load(
        SharedPreferencesSafetySettingsStore(),
      );
      addTearDown(restored.dispose);
      expect(
        restored.advanceWarningTimings,
        AdvanceWarningTimingSettings.battleOnly,
      );
      expect(
        restored.advanceWarningDisplayMode,
        AdvanceWarningDisplayMode.smart,
      );
      expect(restored.battleWarningMode, BattleWarningMode.off);
      expect(restored.battleStatusEffects, effects);

      await restored.setAdvanceWarningTimings(
        AdvanceWarningTimingSettings.battleAndAdvance,
      );
      expect(
        restored.advanceWarningDisplayMode,
        AdvanceWarningDisplayMode.smart,
      );
      expect(restored.battleWarningMode, BattleWarningMode.off);
      expect(restored.battleStatusEffects, effects);
      await restored.setBattleWarningMode(BattleWarningMode.confirm);
      await restored.setAdvanceWarningDisplayMode(
        AdvanceWarningDisplayMode.alwaysConfirm,
      );
      expect(
        restored.advanceWarningTimings,
        AdvanceWarningTimingSettings.battleAndAdvance,
      );
    },
  );

  test('memory timings notify once per change and survive reloading', () async {
    final store = MemorySafetySettingsStore();
    final controller = await SafetySettingsController.load(store);
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    await controller.setAdvanceWarningTimings(
      AdvanceWarningTimingSettings.advanceOnly,
    );
    expect(notifications, 0);
    await controller.setAdvanceWarningTimings(
      AdvanceWarningTimingSettings.battleOnly,
    );
    await controller.setAdvanceWarningTimings(
      AdvanceWarningTimingSettings.battleOnly,
    );
    expect(notifications, 1);
    expect(
      await store.loadAdvanceWarningTimings(),
      AdvanceWarningTimingSettings.battleOnly,
    );

    final restored = await SafetySettingsController.load(store);
    addTearDown(restored.dispose);
    expect(
      restored.advanceWarningTimings,
      AdvanceWarningTimingSettings.battleOnly,
    );
    expect(restored.battleWarningMode, BattleWarningMode.confirm);
    expect(
      restored.advanceWarningDisplayMode,
      AdvanceWarningDisplayMode.alwaysConfirm,
    );
    await store.saveAdvanceWarningTimings(
      AdvanceWarningTimingSettings.battleAndAdvance,
    );
    await restored.loadSettings();
    expect(
      restored.advanceWarningTimings,
      AdvanceWarningTimingSettings.battleAndAdvance,
    );
  });

  test(
    'empty timing selection is rejected without state or storage changes',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      for (final store in <SafetySettingsStore>[
        MemorySafetySettingsStore(),
        SharedPreferencesSafetySettingsStore(),
      ]) {
        final controller = await SafetySettingsController.load(store);
        addTearDown(controller.dispose);
        await controller.setAdvanceWarningTimings(
          AdvanceWarningTimingSettings.battleOnly,
        );
        var notifications = 0;
        controller.addListener(() => notifications++);
        const empty = AdvanceWarningTimingSettings(afterAdvance: false);
        await expectLater(
          controller.setAdvanceWarningTimings(empty),
          throwsArgumentError,
        );
        await expectLater(
          store.saveAdvanceWarningTimings(empty),
          throwsArgumentError,
        );
        expect(notifications, 0);
        expect(
          controller.advanceWarningTimings,
          AdvanceWarningTimingSettings.battleOnly,
        );
        expect(
          await store.loadAdvanceWarningTimings(),
          AdvanceWarningTimingSettings.battleOnly,
        );
      }
    },
  );

  test('controller normalizes empty timings supplied by a store', () async {
    final controller = await SafetySettingsController.load(_EmptyTimingStore());
    addTearDown(controller.dispose);
    expect(
      controller.advanceWarningTimings,
      AdvanceWarningTimingSettings.advanceOnly,
    );
    expect(controller.battleStatusEffects, const BattleStatusEffectSettings());
  });
}

class _EmptyTimingStore extends MemorySafetySettingsStore {
  @override
  Future<AdvanceWarningTimingSettings> loadAdvanceWarningTimings() async =>
      const AdvanceWarningTimingSettings(afterAdvance: false);
}
