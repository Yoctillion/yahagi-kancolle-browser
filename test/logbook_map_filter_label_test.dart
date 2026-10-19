import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_models.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/logbook/logbook_database.dart';
import 'package:yahagi_kancolle_browser/src/logbook/logbook_page.dart';
import 'package:yahagi_kancolle_browser/src/widgets/frozen_data_table.dart';

void main() {
  testWidgets(
    'map filter prefixes only displayed numbers and retains label identities',
    (tester) async {
      final database = await _showLogbook(tester, const [
        (area: 1, map: 5, name: 'B湾/作戦(甲)', difficulty: 0),
        (area: 6, map: 4, name: 'A湾/作戦(乙)', difficulty: 0),
        (area: 2, map: 3, name: 'B湾/作戦(甲)', difficulty: 0),
      ]);
      final stored = await database.getSortieRecords();
      expect(stored.map((row) => row['map_name']), contains('B湾/作戦(甲)'));
      expect(find.text('B湾/作戦(甲) (1-5)'), findsOneWidget);

      await _openFilter(tester);
      final dropdown = _mapDropdown(tester);
      expect(dropdown.value, '全部海域');
      expect(dropdown.items!.map((item) => item.value), [
        '全部海域',
        'A湾/作戦(乙) (6-4)',
        'B湾/作戦(甲) (1-5)',
        'B湾/作戦(甲) (2-3)',
      ]);
      expect(dropdown.items!.map((item) => (item.child as Text).data), [
        '全部海域',
        '(6-4) A湾/作戦(乙)',
        '(1-5) B湾/作戦(甲)',
        '(2-3) B湾/作戦(甲)',
      ]);
      final dateDropdown = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.byKey(const Key('logbook-filter-field-date')),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(dateDropdown.items!.map((item) => (item.child as Text).data), [
        '全部日期',
        '最近 7 天',
        '最近 30 天',
      ]);

      await tester.tap(find.byKey(const Key('logbook-filter-field-map')));
      await tester.pumpAndSettle();
      expect(find.text('(1-5) B湾/作戦(甲)').last, findsOneWidget);
      await tester.tap(find.text('(1-5) B湾/作戦(甲)').last);
      await tester.pumpAndSettle();
      expect(_mapDropdown(tester).value, 'B湾/作戦(甲) (1-5)');
      expect(
        find.descendant(
          of: find.byKey(const Key('logbook-filter-field-map')),
          matching: find.text('(1-5) B湾/作戦(甲)').hitTestable(),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('logbook-filter-apply')));
      await tester.pumpAndSettle();
      expect(find.text('B湾/作戦(甲) (1-5)'), findsOneWidget);
      expect(find.text('B湾/作戦(甲) (2-3)'), findsNothing);
      expect(find.text('A湾/作戦(乙) (6-4)'), findsNothing);
      expect(
        tester
            .widget<FrozenDataTable>(
              find.byKey(const Key('logbook-table-sortie')),
            )
            .rowHeights,
        hasLength(1),
      );
      await _openFilter(tester);
      expect(_mapDropdown(tester).value, 'B湾/作戦(甲) (1-5)');
      expect(find.text('(1-5) B湾/作戦(甲)').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'map filter retains event names difficulty practice and unnamed fallback',
    (tester) async {
      await _showLogbook(tester, const [
        (area: 62, map: 2, name: '南沙諸島沖/オルモック沖 (作戦名)', difficulty: 3),
        (area: 7, map: 3, name: '', difficulty: 0),
        (area: 0, map: 0, name: '演习', difficulty: 0),
      ]);
      expect(find.text('南沙諸島沖/オルモッ… (62-2 乙)'), findsOneWidget);
      expect(find.text('7-3'), findsOneWidget);
      expect(find.text('演习'), findsOneWidget);

      await _openFilter(tester);
      final dropdown = _mapDropdown(tester);
      expect(dropdown.items!.map((item) => item.value), [
        '全部海域',
        '7-3',
        '南沙諸島沖/オルモック沖 (作戦名) (62-2 乙)',
        '演习',
      ]);
      expect(dropdown.items!.map((item) => (item.child as Text).data), [
        '全部海域',
        '7-3',
        '(62-2 乙) 南沙諸島沖/オルモック沖 (作戦名)',
        '演习',
      ]);
      await tester.tap(find.byKey(const Key('logbook-filter-field-map')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('(62-2 乙) 南沙諸島沖/オルモック沖 (作戦名)').last);
      await tester.pumpAndSettle();
      expect(_mapDropdown(tester).value, '南沙諸島沖/オルモック沖 (作戦名) (62-2 乙)');
      expect(
        find.text('(62-2 乙) 南沙諸島沖/オルモック沖 (作戦名)').hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('logbook-filter-apply')));
      await tester.pumpAndSettle();
      expect(find.text('南沙諸島沖/オルモッ… (62-2 乙)'), findsOneWidget);
      expect(find.text('7-3'), findsNothing);
      expect(find.text('演习'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<LogbookDatabase> _showLogbook(
  WidgetTester tester,
  List<({int area, int map, String name, int difficulty})> maps,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 700);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final database = await LogbookDatabase.openForTesting();
  addTearDown(database.close);
  for (var i = 0; i < maps.length; i++) {
    final map = maps[i];
    await database.insertBattleRecord(
      BattleRecord(
        battle: LiveBattle(
          context: BattleContext(
            mapAreaId: map.area,
            mapInfoNo: map.map,
            node: 1,
          ),
          rank: BattleRank.s,
        ),
        completedAt: DateTime.utc(2026, 10, 17, 0, i),
      ),
      mapName: map.name,
      mapDifficulty: map.difficulty,
    );
  }
  final controller = BattleController(gameState: () => GameState.empty);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: LogbookPage(battleController: controller, database: database),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return database;
}

Future<void> _openFilter(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('logbook-filter-button')));
  await tester.pumpAndSettle();
}

DropdownButton<String> _mapDropdown(WidgetTester tester) =>
    tester.widget<DropdownButton<String>>(
      find.descendant(
        of: find.byKey(const Key('logbook-filter-field-map')),
        matching: find.byType(DropdownButton<String>),
      ),
    );
