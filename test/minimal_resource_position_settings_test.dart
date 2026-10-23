import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/settings/display_mode_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/display_mode_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/screen_settings_page.dart';
import 'package:yahagi_kancolle_browser/src/settings/ui_display_size.dart';

void main() {
  for (final hdEnabled in [false, true]) {
    for (final size in UiDisplaySize.values) {
      for (final savedPosition in MinimalResourcePosition.values) {
        testWidgets('resource position controls stay absent for ${size.name}, '
            'HD=$hdEnabled, saved=${savedPosition.name}', (tester) async {
          SharedPreferences.setMockInitialValues(<String, Object>{
            'layout_ui_display_size': size.name,
            'layout_minimal_resource_position': savedPosition.name,
          });
          final layout = await LayoutSettingsController.load(
            SharedPreferencesLayoutSettingsStore(),
          );
          final display = await DisplayModeController.load(
            MemoryDisplayModeStore(),
          );
          addTearDown(layout.dispose);
          addTearDown(display.dispose);
          await layout.setHdEnabled(hdEnabled);
          expect(layout.uiDisplaySize, size);
          expect(layout.minimalResourcePosition, savedPosition);

          await tester.pumpWidget(
            MaterialApp(
              locale: const Locale('zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: ScreenSettingsPage(
                layoutSettingsController: layout,
                displayModeController: display,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final row = find.byKey(
            const Key('settings-minimal-resource-position'),
            skipOffstage: false,
          );
          final dropdown = find.byType(
            DropdownButton<MinimalResourcePosition>,
            skipOffstage: false,
          );
          expect(row, findsNothing);
          expect(dropdown, findsNothing);
          expect(find.text('资源位置'), findsNothing);

          final nextPosition =
              MinimalResourcePosition.values[(savedPosition.index + 1) %
                  MinimalResourcePosition.values.length];
          await layout.setMinimalResourcePosition(nextPosition);
          await tester.pumpAndSettle();

          expect(layout.minimalResourcePosition, nextPosition);
          final preferences = await SharedPreferences.getInstance();
          expect(
            preferences.getString('layout_minimal_resource_position'),
            nextPosition.name,
          );
          expect(row, findsNothing);
          expect(dropdown, findsNothing);
          expect(find.text('资源位置'), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
