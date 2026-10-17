import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/logbook/logbook_database.dart';

void main() {
  for (final category in [
    LogbookChangeCategory.development,
    LogbookChangeCategory.construction,
    LogbookChangeCategory.expedition,
    LogbookChangeCategory.retirement,
  ]) {
    test(
      '$category filters before keyset pagination and catalogs all stored identities',
      () async {
        final database = await LogbookDatabase.openForTesting();
        addTearDown(database.close);
        final db = await database.database;
        final table = '${category.name}_logs';
        for (var i = 1; i <= 151; i++) {
          final match = i <= 101;
          final fields = switch (category) {
            LogbookChangeCategory.development => <String, Object?>{
              'success': match ? 0 : 1,
              'equipment_id': i,
              'equipment_name': 'item$i',
              'equipment_type': match ? "old'type" : 'new type',
              'equipment_icon_id': 1,
              'fuel': 10,
              'ammo': 10,
              'steel': 10,
              'bauxite': 10,
              'secretary_name': 'secretary',
            },
            LogbookChangeCategory.construction => <String, Object?>{
              'construction_type': match ? '大型建造' : '普通建造',
              'ship_name': 'ship$i',
              'ship_type': match ? "old'type" : 'new type',
              'secretary_name': 'secretary',
              'fuel': 10,
              'ammo': 10,
              'steel': 10,
              'bauxite': 10,
              'development_material': 1,
            },
            LogbookChangeCategory.expedition => <String, Object?>{
              'expedition_id': match ? 1 : 2,
              'name': match ? "old'name" : 'new name',
              'result': match ? 2 : 1,
              'item1_count': match ? 1 : 0,
            },
            _ => <String, Object?>{
              'type': match ? '解体' : '改修',
              'ship_type': match ? "old'type" : 'new type',
              'ship_name': 'ship$i',
              'level': 1,
            },
          };
          await db.insert(table, {'timestamp': i, ...fields});
        }
        final query = switch (category) {
          LogbookChangeCategory.development => const OperationRecordQuery(
            success: false,
            equipmentType: "old'type",
            secretaryName: 'secretary',
          ),
          LogbookChangeCategory.construction => const OperationRecordQuery(
            constructionType: '大型建造',
            shipType: "old'type",
            secretaryName: 'secretary',
          ),
          LogbookChangeCategory.expedition => const OperationRecordQuery(
            expeditionResult: 2,
            hasRewardItems: true,
            missions: [(id: 1, name: "old'name")],
          ),
          _ => const OperationRecordQuery(
            retirementType: '解体',
            shipType: "old'type",
          ),
        };
        Future<List<Map<String, dynamic>>> page(
          OperationRecordQuery q, [
          int? before,
        ]) => switch (category) {
          LogbookChangeCategory.development => database.getDevelopmentRecords(
            query: q,
            beforeId: before,
          ),
          LogbookChangeCategory.construction => database.getConstructionRecords(
            query: q,
            beforeId: before,
          ),
          LogbookChangeCategory.expedition => database.getExpeditionRecords(
            query: q,
            beforeId: before,
          ),
          _ => database.getRetirementRecords(query: q, beforeId: before),
        };
        final first = await page(query);
        final second = await page(query, first.last['id'] as int);
        final third = await page(query, second.last['id'] as int);
        expect(first, hasLength(50));
        expect(second, hasLength(50));
        expect(third, hasLength(1));
        expect(
          [...first, ...second, ...third].map((r) => r['id']),
          List.generate(101, (i) => 101 - i),
        );
        expect(await page(query, 1), isEmpty);
        expect(
          await page(const OperationRecordQuery(sinceTimestamp: 1000)),
          isEmpty,
        );
        expect((await page(const OperationRecordQuery())).first['id'], 151);
        final catalog = await database.getOperationFilterCatalog(category);
        expect(catalog, hasLength(2));
        expect(catalog.toString(), contains('old'));
      },
    );
  }
}
