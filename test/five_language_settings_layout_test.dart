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
          final controller = await SafetySettingsController.load(
            MemorySafetySettingsStore(),
          );
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
          expect(find.text(l10n.blockSortieTitle), findsOneWidget);
          expect(tester.takeException(), isNull);
          for (final (dropdown, selectedLabel) in [
            (
              find.byType(DropdownButton<BattleWarningMode>),
              l10n.battleWarningConfirm,
            ),
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
