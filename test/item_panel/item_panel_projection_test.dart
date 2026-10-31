import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/item_panel/item_panel_projection.dart';
import 'package:yahagi_kancolle_browser/src/item_panel/use_item_catalog.dart';

void main() {
  ItemPanelGroup group(List<ItemPanelGroup> groups, ItemGroup kind) =>
      groups.firstWhere((item) => item.group == kind);

  ItemPanelEntry entry(List<ItemPanelGroup> groups, int id) =>
      groups.expand((item) => item.entries).firstWhere((item) => item.id == id);

  List<int> allIds(List<ItemPanelGroup> groups) => [
    for (final item in groups)
      for (final entry in item.entries) entry.id,
  ];

  test('returns null before useitem data arrives', () {
    expect(projectItemPanel(GameState.empty), isNull);
  });

  test('groups come in spec order', () {
    final groups = projectItemPanel(
      const GameState(useItems: <int, int>{96: 1}, hasUseItemData: true),
    )!;
    expect(
      [for (final item in groups) item.group],
      [
        ItemGroup.reward,
        ItemGroup.improvement,
        ItemGroup.seasonal,
        ItemGroup.consumable,
        ItemGroup.other,
      ],
    );
  });

  test('ordinary items keep a zero entry', () {
    final groups = projectItemPanel(
      const GameState(useItems: <int, int>{57: 43}, hasUseItemData: true),
    )!;
    expect(entry(groups, 57).count, 43);
    expect(entry(groups, 61).count, 0);
  });

  test('seasonal items at zero are dropped', () {
    final groups = projectItemPanel(
      const GameState(useItems: <int, int>{96: 12}, hasUseItemData: true),
    )!;
    expect(
      [for (final item in group(groups, ItemGroup.seasonal).entries) item.id],
      [96],
    );
  });

  test('seasonal group disappears when empty', () {
    final groups = projectItemPanel(
      const GameState(useItems: <int, int>{57: 1}, hasUseItemData: true),
    )!;
    expect([
      for (final item in groups) item.group,
    ], isNot(contains(ItemGroup.seasonal)));
  });

  test('repair items add equipment and pay items', () {
    final groups = projectItemPanel(
      const GameState(
        hasUseItemData: true,
        slotItems: <int, OwnedSlotItem>{
          1: OwnedSlotItem(instanceId: 1, masterSlotItemId: 43),
          2: OwnedSlotItem(instanceId: 2, masterSlotItemId: 43),
          3: OwnedSlotItem(instanceId: 3, masterSlotItemId: 42),
        },
        payItems: <int, int>{14: 3},
        hasPayItemData: true,
      ),
    )!;
    expect(entry(groups, 51).count, 5);
    expect(entry(groups, 50).count, 1);
  });

  test('rations count owned equipment', () {
    final groups = projectItemPanel(
      const GameState(
        hasUseItemData: true,
        slotItems: <int, OwnedSlotItem>{
          1: OwnedSlotItem(instanceId: 1, masterSlotItemId: 145),
          2: OwnedSlotItem(instanceId: 2, masterSlotItemId: 146),
          3: OwnedSlotItem(instanceId: 3, masterSlotItemId: 146),
        },
      ),
    )!;
    expect(entry(groups, 66).count, 1);
    expect(entry(groups, 67).count, 2);
  });

  test('port expansion comes only from pay items', () {
    final groups = projectItemPanel(
      const GameState(
        useItems: <int, int>{53: 9},
        hasUseItemData: true,
        payItems: <int, int>{16: 2},
        hasPayItemData: true,
      ),
    )!;
    expect(entry(groups, 53).count, 2);
  });

  test('unknown ids go to the end of other', () {
    final groups = projectItemPanel(
      const GameState(
        useItems: <int, int>{999: 2, 998: 0},
        hasUseItemData: true,
      ),
    )!;
    final other = group(groups, ItemGroup.other).entries;
    expect(other.last.id, 999);
    expect(other.last.count, 2);
    expect(other.last.assetPath, useItemFallbackAsset);
    expect(allIds(groups), isNot(contains(998)));
  });

  test('resource bar ids are not treated as unknown', () {
    final groups = projectItemPanel(
      const GameState(useItems: <int, int>{44: 5, 1: 3}, hasUseItemData: true),
    )!;
    expect(allIds(groups), isNot(contains(44)));
    expect(allIds(groups), isNot(contains(1)));
  });

  test('entries carry their icon', () {
    final groups = projectItemPanel(const GameState(hasUseItemData: true))!;
    expect(
      entry(groups, 57).assetPath,
      'assets/images/material/useitem_57.png',
    );
  });
}
