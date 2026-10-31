import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/item_panel/use_item_catalog.dart';

void main() {
  List<int> ids(ItemGroup group) => [
    for (final item in useItemCatalog)
      if (item.group == group) item.id,
  ];

  UseItemSpec spec(int id) =>
      useItemCatalog.firstWhere((item) => item.id == id);

  test('catalog follows the spec order', () {
    expect(ids(ItemGroup.reward), [57, 61, 58, 65, 74, 78, 70, 101, 98, 99]);
    expect(ids(ItemGroup.improvement), [75, 77, 94, 92, 91, 104, 100, 95, 71]);
    expect(ids(ItemGroup.seasonal), [
      96,
      68,
      93,
      62,
      90,
      56,
      60,
      80,
      85,
      86,
      87,
      88,
      89,
      97,
      72,
      79,
      81,
      82,
      83,
      84,
    ]);
    expect(ids(ItemGroup.consumable), [
      54,
      59,
      52,
      51,
      50,
      67,
      66,
      76,
      69,
      102,
      73,
      64,
      63,
    ]);
    expect(ids(ItemGroup.other), [10, 11, 12, 49, 103, 53, 105, 55]);
  });

  test('catalog ids are unique', () {
    final all = [for (final item in useItemCatalog) item.id];
    expect(all.toSet(), hasLength(all.length));
  });

  test('every catalog icon and the fallback exist', () {
    for (final item in useItemCatalog) {
      expect(
        File(useItemAssetPath(item.id)).existsSync(),
        isTrue,
        reason: useItemAssetPath(item.id),
      );
    }
    expect(File(useItemFallbackAsset).existsSync(), isTrue);
  });

  test('furniture boxes reuse the existing icons', () {
    expect(useItemAssetPath(10), 'assets/images/material/10.png');
    expect(useItemAssetPath(57), 'assets/images/material/useitem_57.png');
  });

  test('names resolve per locale', () {
    expect(useItemName(const Locale('en'), 57), 'Medals');
    expect(useItemName(const Locale('zh'), 57), '勋章');
    expect(useItemName(const Locale('ja'), 57), '勲章');
    for (final locale in const [Locale('zh', 'TW'), Locale('ko')]) {
      final name = useItemName(locale, 57);
      expect(name, isNotEmpty);
      expect(name, isNot(startsWith('#')));
    }
    expect(useItemName(const Locale('zh'), 999), '#999');
  });

  test('catalog entries have a name in every locale', () {
    const locales = [
      Locale('zh'),
      Locale('zh', 'TW'),
      Locale('ja'),
      Locale('ko'),
      Locale('en'),
    ];
    for (final item in useItemCatalog) {
      for (final locale in locales) {
        expect(
          useItemName(locale, item.id),
          isNot(startsWith('#')),
          reason: '${item.id} $locale',
        );
      }
    }
  });

  test('count sources follow KC3', () {
    expect(spec(50).slotMasterId, 42);
    expect(spec(50).payItemId, 11);
    expect(spec(50).fromUseItem, isFalse);
    expect(spec(51).slotMasterId, 43);
    expect(spec(51).payItemId, 14);
    expect(spec(51).fromUseItem, isFalse);
    expect(spec(53).payItemId, 16);
    expect(spec(53).slotMasterId, isNull);
    expect(spec(53).fromUseItem, isFalse);
    expect(spec(66).slotMasterId, 145);
    expect(spec(67).slotMasterId, 146);
    expect(spec(69).slotMasterId, 150);
    expect(spec(76).slotMasterId, 241);
    expect(spec(66).fromUseItem, isFalse);
    expect(spec(57).fromUseItem, isTrue);
  });
}
