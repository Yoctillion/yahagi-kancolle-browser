import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/settings/item_panel_settings.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/module_display_settings.dart';

void main() {
  const compactChip = Key('item-panel-mode-compact');
  const detailedChip = Key('item-panel-mode-detailed');

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<LayoutSettingsController> loadLayout() =>
      LayoutSettingsController.load(SharedPreferencesLayoutSettingsStore());

  Future<void> openSettings(
    WidgetTester tester,
    LayoutSettingsController layout,
    String module,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModuleDisplaySettings(context, layout, module),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  test('defaults to compact', () async {
    expect((await loadLayout()).itemPanelMode, ItemPanelMode.compact);
  });

  test('setting persists', () async {
    final layout = await loadLayout();
    await layout.setItemPanelMode(ItemPanelMode.detailed);

    expect((await loadLayout()).itemPanelMode, ItemPanelMode.detailed);
  });

  test('an unknown saved value falls back to compact', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'item_panel_mode': 'x',
    });

    expect((await loadLayout()).itemPanelMode, ItemPanelMode.compact);
  });

  for (final (first, second) in const [
    ('items', 'smart'),
    ('smart', 'items'),
  ]) {
    testWidgets('$first settings change the mode $second also shows', (
      tester,
    ) async {
      final layout = (await tester.runAsync(loadLayout))!;

      await openSettings(tester, layout, first);
      await tester.ensureVisible(find.byKey(detailedChip));
      await tester.tap(find.byKey(detailedChip));
      await tester.pump();
      expect(layout.itemPanelMode, ItemPanelMode.detailed);

      await openSettings(tester, layout, second);
      await tester.ensureVisible(find.byKey(detailedChip));
      final chip = tester.widget<ChoiceChip>(find.byKey(detailedChip));
      expect(chip.selected, isTrue);
    });
  }

  for (final module in const ['items', 'smart']) {
    testWidgets('$module reset restores compact', (tester) async {
      final layout = (await tester.runAsync(loadLayout))!;
      await tester.runAsync(
        () => layout.setItemPanelMode(ItemPanelMode.detailed),
      );

      await openSettings(tester, layout, module);
      await tester.tap(find.byKey(Key('$module-display-reset')));
      await tester.pump();

      expect(layout.itemPanelMode, ItemPanelMode.compact);
    });
  }

  testWidgets('other modules show no item mode chips', (tester) async {
    final layout = (await tester.runAsync(loadLayout))!;

    await openSettings(tester, layout, 'repair');

    expect(find.byKey(compactChip), findsNothing);
    expect(find.byKey(detailedChip), findsNothing);
  });
}
