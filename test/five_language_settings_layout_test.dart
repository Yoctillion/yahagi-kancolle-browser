import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/settings/battle_settings_page.dart';
import 'package:yahagi_kancolle_browser/src/settings/battle_status_effect_settings.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_store.dart';

void _expectReadableText(WidgetTester tester, Finder text, Rect bounds) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(
    paragraph.getMaxIntrinsicHeight(paragraph.size.width),
    lessThanOrEqualTo(paragraph.size.height + .1),
  );
  final textBounds = tester.getRect(text);
  expect(textBounds.left, greaterThanOrEqualTo(bounds.left - .1));
  expect(textBounds.right, lessThanOrEqualTo(bounds.right + .1));
  expect(textBounds.top, greaterThanOrEqualTo(bounds.top - .1));
  expect(textBounds.bottom, lessThanOrEqualTo(bounds.bottom + .1));
}

Future<void> _chooseWarningSetting(
  WidgetTester tester, {
  required String selectorKey,
  required String dropdownKey,
  required String currentLabel,
  required String currentDescription,
  required List<(String, String)> options,
  required String selectedKey,
  required String selectedLabel,
  required String selectedDescription,
  required double width,
}) async {
  final selector = find.byKey(Key(selectorKey));
  final dropdown = find.byKey(Key(dropdownKey));
  final selectedBefore = find.descendant(
    of: dropdown,
    matching: find.text(currentLabel),
  );
  expect(selectedBefore, findsOneWidget);
  await tester.ensureVisible(selector);
  await tester.pumpAndSettle();
  _expectReadableText(tester, selectedBefore, tester.getRect(dropdown));
  _expectReadableText(
    tester,
    find.descendant(of: selector, matching: find.text(currentDescription)),
    tester.getRect(selector),
  );
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  for (final (key, label) in options) {
    final option = find.byKey(Key(key)).last;
    await tester.ensureVisible(option);
    await tester.pumpAndSettle();
    final text = find.descendant(of: option, matching: find.text(label));
    expect(text, findsOneWidget);
    _expectReadableText(tester, text, tester.getRect(option));
    _expectReadableText(tester, text, Rect.fromLTWH(0, 0, width, 780));
  }
  final selectedOption = find.byKey(Key(selectedKey)).last;
  await tester.ensureVisible(selectedOption);
  await tester.pumpAndSettle();
  await tester.tap(selectedOption);
  await tester.pumpAndSettle();
  expect(find.byKey(Key(selectedKey)), findsOneWidget);
  final selectedAfter = find.descendant(
    of: dropdown,
    matching: find.text(selectedLabel),
  );
  expect(selectedAfter, findsOneWidget);
  await tester.ensureVisible(selector);
  await tester.pumpAndSettle();
  _expectReadableText(tester, selectedAfter, tester.getRect(dropdown));
  _expectReadableText(
    tester,
    find.descendant(of: selector, matching: find.text(selectedDescription)),
    tester.getRect(selector),
  );
}

void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    for (final width in [320.0, 800.0]) {
      testWidgets(
        'battle warning settings remain readable at $width in $locale',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 780);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final store = MemorySafetySettingsStore();
          final controller = await SafetySettingsController.load(store);
          addTearDown(controller.dispose);
          controller.setBattleEffectDisplayScope(
            BattleEffectDisplayScope.predictionOnly,
          );
          controller.setDamagePulseFilter(DamagePulseFilter.moderateOnly);
          controller.setDamageVibrationFilter(
            DamageVibrationFilter.moderateOnly,
          );
          controller.setMoraleSparkleMode(MoraleSparkleMode.steady);
          await tester.pumpWidget(
            MaterialApp(
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.3)),
                child: child!,
              ),
              home: Scaffold(
                body: BattleSettingsPage(safetySettingsController: controller),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final l10n = lookupAppLocalizations(locale);
          final warningSwitch = find.byKey(
            const Key('battleWarningMasterSwitch'),
          );
          expect(tester.widget<Switch>(warningSwitch).value, isTrue);
          final switchRow = find.byKey(const Key('battleWarningMasterRow'));
          final switchLabel = find.text(l10n.gameSafety);
          _expectReadableText(tester, switchLabel, tester.getRect(switchRow));
          await _chooseWarningSetting(
            tester,
            selectorKey: 'advanceWarningTimingSelector',
            dropdownKey: 'advanceWarningTimingDropdown',
            currentLabel: l10n.advanceWarningAfterAdvance,
            currentDescription: l10n.advanceWarningTimingModeDescription,
            options: [
              (
                'advanceWarningTimingOptionAdvance',
                l10n.advanceWarningAfterAdvance,
              ),
              (
                'advanceWarningTimingOptionBattle',
                l10n.advanceWarningPostBattle,
              ),
              (
                'advanceWarningTimingOptionBoth',
                l10n.advanceWarningBothTimings,
              ),
            ],
            selectedKey: 'advanceWarningTimingOptionBoth',
            selectedLabel: l10n.advanceWarningBothTimings,
            selectedDescription: l10n.advanceWarningTimingModeDescription,
            width: width,
          );
          expect(
            controller.advanceWarningTimings,
            AdvanceWarningTimingSettings.battleAndAdvance,
          );
          expect(
            await store.loadAdvanceWarningTimings(),
            AdvanceWarningTimingSettings.battleAndAdvance,
          );
          await _chooseWarningSetting(
            tester,
            selectorKey: 'advanceWarningDisplayModeSelector',
            dropdownKey: 'advanceWarningDisplayModeDropdown',
            currentLabel: l10n.advanceWarningAlwaysConfirm,
            currentDescription: l10n.advanceWarningAlwaysConfirmDescription,
            options: [
              (
                'advanceWarningDisplayOptionAlways',
                l10n.advanceWarningAlwaysConfirm,
              ),
              ('advanceWarningDisplayOptionSmart', l10n.advanceWarningSmart),
            ],
            selectedKey: 'advanceWarningDisplayOptionSmart',
            selectedLabel: l10n.advanceWarningSmart,
            selectedDescription: l10n.advanceWarningSmartDescription,
            width: width,
          );
          expect(
            controller.advanceWarningDisplayMode,
            AdvanceWarningDisplayMode.smart,
          );
          expect(
            await store.loadAdvanceWarningDisplayMode(),
            AdvanceWarningDisplayMode.smart,
          );
          expect(tester.takeException(), isNull);
          for (final (dropdown, selectedLabel) in [
            (
              find.byKey(const Key('battleEffectScopeDropdown')),
              l10n.battleEffectScopePredictionOnly,
            ),
            (
              find.byKey(const Key('damagePulseFilterDropdown')),
              l10n.battleEffectModerateOnly,
            ),
            (
              find.byKey(const Key('damageVibrationFilterDropdown')),
              l10n.battleEffectModerateOnly,
            ),
            (
              find.byKey(const Key('moraleSparkleModeDropdown')),
              l10n.battleMoraleSparkleSteady,
            ),
          ]) {
            await tester.ensureVisible(dropdown);
            await tester.pumpAndSettle();
            final selected = find.descendant(
              of: dropdown,
              matching: find.text(selectedLabel),
            );
            expect(selected, findsOneWidget);
            _expectReadableText(tester, selected, tester.getRect(dropdown));
            await tester.tap(dropdown);
            await tester.pumpAndSettle();
            final menuOption = find.text(selectedLabel).last;
            _expectReadableText(
              tester,
              menuOption,
              Rect.fromLTWH(0, 0, width, 780),
            );
            expect(tester.takeException(), isNull);
            await tester.tap(menuOption);
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
