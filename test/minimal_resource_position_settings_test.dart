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
  testWidgets('resource position setting only shows for minimal size', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final layout = await LayoutSettingsController.load(
      SharedPreferencesLayoutSettingsStore(),
    );
    final display = await DisplayModeController.load(MemoryDisplayModeStore());
    addTearDown(layout.dispose);
    addTearDown(display.dispose);
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
    final row = find.byKey(const Key('settings-minimal-resource-position'));
    expect(row, findsNothing);

    await layout.setUiDisplaySize(UiDisplaySize.compact);
    await tester.pumpAndSettle();
    expect(row, findsNothing);

    await layout.setUiDisplaySize(UiDisplaySize.minimal);
    await tester.pumpAndSettle();
    await tester.ensureVisible(row);
    expect(row, findsOneWidget);
    expect(find.text('资源位置'), findsOneWidget);
    // 紧跟在界面大小下拉框之后。
    expect(
      tester.getTopLeft(row).dy,
      greaterThan(
        tester
            .getTopLeft(find.byKey(const Key('settings-ui-display-size-row')))
            .dy,
      ),
    );

    final dropdown = find.descendant(
      of: row,
      matching: find.byType(DropdownButton<MinimalResourcePosition>),
    );
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('顶部横栏').last);
    await tester.pumpAndSettle();

    expect(layout.minimalResourcePosition, MinimalResourcePosition.topBar);
    expect(tester.takeException(), isNull);
  });
}
