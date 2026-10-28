import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/settings/fleet_display_settings_section.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('fleet auto switch defaults on and persists', () async {
    final layout = await LayoutSettingsController.load(
      SharedPreferencesLayoutSettingsStore(),
    );
    expect(layout.fleetAutoSwitch, isTrue);
    await layout.setFleetAutoSwitch(false);

    final reloaded = await LayoutSettingsController.load(
      SharedPreferencesLayoutSettingsStore(),
    );
    expect(reloaded.fleetAutoSwitch, isFalse);
  });

  testWidgets('fleet display settings toggle and reset the auto switch', (
    tester,
  ) async {
    final layout = await tester.runAsync(
      () =>
          LayoutSettingsController.load(SharedPreferencesLayoutSettingsStore()),
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: FleetDisplaySettingsSection(controller: layout!),
          ),
        ),
      ),
    );
    expect(find.text('自动切换当前队伍'), findsOneWidget);

    await tester.tap(find.byKey(const Key('fleet-auto-switch')));
    await tester.pump();
    expect(layout.fleetAutoSwitch, isFalse);

    await tester.tap(find.byKey(const Key('fleet-display-default')));
    await tester.pump();
    expect(layout.fleetAutoSwitch, isTrue);
  });
}
