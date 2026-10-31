import '../game_state/game_state.dart';
import 'use_item_catalog.dart';

class ItemPanelEntry {
  const ItemPanelEntry({
    required this.id,
    required this.assetPath,
    required this.count,
  });

  final int id;
  final String assetPath;
  final int count;
}

class ItemPanelGroup {
  const ItemPanelGroup({required this.group, required this.entries});

  final ItemGroup group;
  final List<ItemPanelEntry> entries;
}

/// Returns null until the first useitem response, so the panel can show a
/// waiting state instead of a wall of zeros. Names are left to the view so a
/// language change does not need a new projection.
List<ItemPanelGroup>? projectItemPanel(GameState state) {
  if (!state.hasUseItemData) return null;

  final ownedSlotItems = <int, int>{};
  for (final item in state.slotItems.values) {
    ownedSlotItems.update(
      item.masterSlotItemId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }

  int countOf(UseItemSpec spec) =>
      (spec.fromUseItem ? state.useItems[spec.id] ?? 0 : 0) +
      (ownedSlotItems[spec.slotMasterId] ?? 0) +
      (spec.payItemId == null ? 0 : state.payItemCount(spec.payItemId!));

  final entries = <ItemGroup, List<ItemPanelEntry>>{
    for (final group in ItemGroup.values) group: <ItemPanelEntry>[],
  };
  final known = <int>{};
  for (final spec in useItemCatalog) {
    known.add(spec.id);
    final count = countOf(spec);
    // Seasonal items are mutually exclusive, so zeros would only be noise.
    if (spec.group == ItemGroup.seasonal && count == 0) continue;
    entries[spec.group]!.add(
      ItemPanelEntry(
        id: spec.id,
        assetPath: useItemAssetPath(spec.id),
        count: count,
      ),
    );
  }

  final unknown = [
    for (final item in state.useItems.entries)
      if (item.value > 0 &&
          !known.contains(item.key) &&
          !useItemIdsOnResourceBar.contains(item.key))
        item,
  ]..sort((left, right) => left.key.compareTo(right.key));
  for (final item in unknown) {
    entries[ItemGroup.other]!.add(
      ItemPanelEntry(
        id: item.key,
        assetPath: useItemFallbackAsset,
        count: item.value,
      ),
    );
  }

  return [
    for (final group in ItemGroup.values)
      if (entries[group]!.isNotEmpty)
        ItemPanelGroup(group: group, entries: entries[group]!),
  ];
}
