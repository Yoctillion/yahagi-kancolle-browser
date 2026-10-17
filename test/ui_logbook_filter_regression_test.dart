import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/logbook/logbook_database.dart';
import 'package:yahagi_kancolle_browser/src/logbook/logbook_page.dart';
import 'package:yahagi_kancolle_browser/src/widgets/frozen_data_table.dart';

void main() {
  testWidgets(
    'filter reaches older development records beyond the first page',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(844, 600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final db = await LogbookDatabase.openForTesting();
      addTearDown(db.close);
      for (var i = 0; i < 51; i++) {
        await db.insertDevelopmentRecord(
          timestamp: i,
          success: i > 0,
          equipmentId: i,
          equipmentName: 'offline$i',
          equipmentType: i == 0 ? '旧式主炮' : '主炮',
          equipmentIconId: 1,
          fuel: 10,
          ammo: 10,
          steel: 10,
          bauxite: 10,
          secretaryName: 'offline',
        );
      }
      final controller = BattleController(gameState: () => GameState.empty);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LogbookPage(
              battleController: controller,
              database: db,
              selectedTabIndex: 3,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FrozenDataTable>(
              find.byKey(const Key('logbook-table-development')),
            )
            .rowHeights,
        hasLength(50),
      );
      await tester.tap(find.byKey(const Key('logbook-filter-button')));
      await tester.pumpAndSettle();
      final dropdown = find.descendant(
        of: find.byKey(const Key('logbook-filter-field-result')),
        matching: find.byType(DropdownButton<String>),
      );
      tester.widget<DropdownButton<String>>(dropdown).onChanged!('失败');
      await tester.pump();
      await tester.tap(find.byKey(const Key('logbook-filter-apply')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FrozenDataTable>(
              find.byKey(const Key('logbook-table-development')),
            )
            .rowHeights,
        hasLength(1),
      );
      final list = tester.widget<ListView>(
        find.byKey(const Key('logbook-development-body-scroll')),
      );
      expect(list.controller!.position.maxScrollExtent, 0);
      await tester.drag(
        find.byKey(const Key('logbook-development-body-scroll')),
        const Offset(0, -1000),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FrozenDataTable>(
              find.byKey(const Key('logbook-table-development')),
            )
            .rowHeights,
        hasLength(1),
      );
      await tester.tap(find.byKey(const Key('logbook-filter-button')));
      await tester.pumpAndSettle();
      final types = find.descendant(
        of: find.byKey(const Key('logbook-filter-field-equipmentType')),
        matching: find.byType(DropdownButton<String>),
      );
      final typeDropdown = tester.widget<DropdownButton<String>>(types);
      expect(typeDropdown.items!.map((item) => item.value), contains('旧式主炮'));
      typeDropdown.onChanged!('主炮');
      await tester.pump();
      await tester.tap(find.byKey(const Key('logbook-filter-apply')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FrozenDataTable>(
              find.byKey(const Key('logbook-table-development')),
            )
            .rowHeights,
        isEmpty,
      );
      await tester.tap(find.byKey(const Key('logbook-filter-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('logbook-filter-reset')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('logbook-filter-apply')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FrozenDataTable>(
              find.byKey(const Key('logbook-table-development')),
            )
            .rowHeights,
        hasLength(50),
      );
    },
  );
}
