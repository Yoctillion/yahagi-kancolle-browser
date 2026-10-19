import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_models.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/logbook/logbook_database.dart';
import 'package:yahagi_kancolle_browser/src/logbook/logbook_page.dart';

void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('logbook preserves names matching UI labels in $locale', (
      tester,
    ) async {
      final database = await LogbookDatabase.openForTesting();
      final controller = BattleController(gameState: () => GameState.empty);
      addTearDown(database.close);
      addTearDown(controller.dispose);
      await database.insertConstructionRecord(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        constructionType: '普通建造',
        shipId: 1,
        shipName: '联合舰队',
        shipType: '驱逐舰',
        fuel: 30,
        ammo: 30,
        steel: 30,
        bauxite: 30,
        developmentMaterial: 1,
        secretaryName: '演习',
      );
      await database.insertDevelopmentRecord(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        success: true,
        equipmentId: 1,
        equipmentName: '鱼雷',
        equipmentType: '主炮',
        equipmentIconId: 1,
        fuel: 10,
        ammo: 10,
        steel: 10,
        bauxite: 10,
        secretaryName: '演习',
      );
      await tester.pumpWidget(_app(locale, controller, database, 2));
      await tester.pumpAndSettle();
      expect(find.text('联合舰队'), findsOneWidget);
      expect(find.text('演习'), findsOneWidget);

      await tester.tap(find.byKey(const Key('logbook-filter-button')));
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('logbook-filter-field-secretary'));
      final dropdown = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: field,
          matching: find.byType(DropdownButton<String>),
        ),
      );
      final namedOption = dropdown.items!.singleWhere(
        (item) => item.value == '演习',
      );
      expect((namedOption.child as Text).data, '演习');
      final allOption = dropdown.items!.first;
      if (locale.languageCode != 'zh') {
        expect((allOption.child as Text).data, isNot('全部秘书舰'));
      }
      expect(dropdown.value, '全部秘书舰');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      final rows = await database.getConstructionRecords();
      expect(rows.single['ship_name'], '联合舰队');
      expect(rows.single['secretary_name'], '演习');
      await tester.pumpWidget(_app(locale, controller, database, 3));
      await tester.pumpAndSettle();
      expect(find.text('鱼雷'), findsOneWidget);
      expect(find.text('演习'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'logbook localizes material labels and keeps unknown names in $locale',
      (tester) async {
        final database = await LogbookDatabase.openForTesting();
        final controller = BattleController(gameState: () => GameState.empty);
        addTearDown(database.close);
        addTearDown(controller.dispose);
        await database.insertMapResourceRecord(
          MapResourceLogEntry(
            eventKey: 'five-language-reward',
            timestamp: DateTime.now(),
            mapArea: 1,
            mapNo: 1,
            mapName: '原始海域名',
            node: 1,
            rewardItems: const [
              BattleRewardItem(
                kind: BattleRewardKind.item,
                id: 1,
                name: '高速修复材',
                count: 2,
              ),
              BattleRewardItem(
                kind: BattleRewardKind.item,
                id: 999,
                name: '全部',
                count: 3,
              ),
            ],
          ),
        );
        await tester.pumpWidget(_app(locale, controller, database, 0));
        await tester.pumpAndSettle();
        final material = switch (locale.languageCode) {
          'en' => 'Instant repair material',
          'ja' => '高速修復材',
          'ko' => '고속수복재',
          _ => locale.scriptCode == 'Hant' ? '高速修復材' : '高速修复材',
        };
        expect(find.text('$material ×2　全部 ×3'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

Widget _app(
  Locale locale,
  BattleController controller,
  LogbookDatabase database,
  int tab,
) => MaterialApp(
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: Scaffold(
    body: LogbookPage(
      battleController: controller,
      database: database,
      selectedTabIndex: tab,
    ),
  ),
);
