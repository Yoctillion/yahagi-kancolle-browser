import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/settings/battle_prediction_settings.dart';
import 'package:yahagi_kancolle_browser/src/settings/battle_prediction_settings_section.dart';

void main() {
  testWidgets('enemy preview position can be selected and survives reload', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = SharedPreferencesBattlePredictionSettingsStore();
    final controller = await BattlePredictionSettingsController.load(store);
    addTearDown(controller.dispose);

    Future<void> pumpSettings(BattlePredictionSettingsController settings) =>
        tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: BattlePredictionSettingsSection(controller: settings),
            ),
          ),
        );

    await pumpSettings(controller);
    final position = find.byKey(const Key('battle-enemy-preview-position'));
    expect(position, findsOneWidget);
    expect(find.text('战前敌舰预测位置'), findsOneWidget);
    expect(find.text('上方'), findsOneWidget);

    await tester.tap(position);
    await tester.pumpAndSettle();
    await tester.tap(find.text('下方').last);
    await tester.pumpAndSettle();
    expect(find.text('下方'), findsOneWidget);

    final reloaded = await BattlePredictionSettingsController.load(store);
    addTearDown(reloaded.dispose);
    await pumpSettings(reloaded);
    expect(find.text('下方'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(2));
  });

  testWidgets('shows only POI display options and persists both switches', (
    tester,
  ) async {
    final store = MemoryBattlePredictionSettingsStore();
    final controller = await BattlePredictionSettingsController.load(store);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: BattlePredictionSettingsSection(controller: controller),
        ),
      ),
    );

    expect(find.byType(SegmentedButton), findsNothing);
    expect(find.text('增强模式'), findsNothing);
    expect(find.text('轻量模式'), findsNothing);
    expect(find.byType(Switch), findsNWidgets(2));
    expect(
      tester
          .widget<Switch>(
            find.byKey(const Key('battle-enemy-preview-portraits')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<Switch>(find.byKey(const Key('battle-last-formation-hint')))
          .value,
      isTrue,
    );
    expect(find.text('在未卜先知中显示战前敌方立绘。'), findsOneWidget);

    await tester.tap(find.byKey(const Key('battle-enemy-preview-portraits')));
    await tester.pump();

    expect(controller.enemyPortraitsEnabled, isFalse);
    expect(await store.loadEnemyPortraitsEnabled(), isFalse);

    await tester.tap(find.byKey(const Key('battle-last-formation-hint')));
    await tester.pump();

    expect(controller.lastFormationHintEnabled, isFalse);
    expect(await store.loadLastFormationHintEnabled(), isFalse);
  });
}
