import 'package:flutter/widgets.dart';

import '../localization/ui_locale.dart';
import 'use_item_strings.dart';

enum ItemGroup { reward, improvement, seasonal, consumable, other }

/// Where one item's count comes from. Some items never appear in the useitem
/// response: repair items and rations are equipment, and repair items may also
/// be sold as pay items (KC3 adds both together).
class UseItemSpec {
  const UseItemSpec(
    this.id,
    this.group, {
    this.slotMasterId,
    this.payItemId,
    this.fromUseItem = true,
  });

  final int id;
  final ItemGroup group;
  final int? slotMasterId;
  final int? payItemId;
  final bool fromUseItem;
}

const useItemFallbackAsset = 'assets/images/material/useitem_0.png';

/// Already shown by the resource bar, so they are neither listed nor treated
/// as unknown items when a response carries them.
const useItemIdsOnResourceBar = <int>{1, 2, 3, 4, 5, 31, 32, 33, 34, 44};

/// Display order within each group.
const useItemCatalog = <UseItemSpec>[
  UseItemSpec(57, ItemGroup.reward),
  UseItemSpec(61, ItemGroup.reward),
  UseItemSpec(58, ItemGroup.reward),
  UseItemSpec(65, ItemGroup.reward),
  UseItemSpec(74, ItemGroup.reward),
  UseItemSpec(78, ItemGroup.reward),
  UseItemSpec(70, ItemGroup.reward),
  UseItemSpec(101, ItemGroup.reward),
  UseItemSpec(98, ItemGroup.reward),
  UseItemSpec(99, ItemGroup.reward),
  UseItemSpec(75, ItemGroup.improvement),
  UseItemSpec(77, ItemGroup.improvement),
  UseItemSpec(94, ItemGroup.improvement),
  UseItemSpec(92, ItemGroup.improvement),
  UseItemSpec(91, ItemGroup.improvement),
  UseItemSpec(104, ItemGroup.improvement),
  UseItemSpec(100, ItemGroup.improvement),
  UseItemSpec(95, ItemGroup.improvement),
  UseItemSpec(71, ItemGroup.improvement),
  UseItemSpec(96, ItemGroup.seasonal),
  UseItemSpec(68, ItemGroup.seasonal),
  UseItemSpec(93, ItemGroup.seasonal),
  UseItemSpec(62, ItemGroup.seasonal),
  UseItemSpec(90, ItemGroup.seasonal),
  UseItemSpec(56, ItemGroup.seasonal),
  UseItemSpec(60, ItemGroup.seasonal),
  UseItemSpec(80, ItemGroup.seasonal),
  UseItemSpec(85, ItemGroup.seasonal),
  UseItemSpec(86, ItemGroup.seasonal),
  UseItemSpec(87, ItemGroup.seasonal),
  UseItemSpec(88, ItemGroup.seasonal),
  UseItemSpec(89, ItemGroup.seasonal),
  UseItemSpec(97, ItemGroup.seasonal),
  UseItemSpec(72, ItemGroup.seasonal),
  UseItemSpec(79, ItemGroup.seasonal),
  UseItemSpec(81, ItemGroup.seasonal),
  UseItemSpec(82, ItemGroup.seasonal),
  UseItemSpec(83, ItemGroup.seasonal),
  UseItemSpec(84, ItemGroup.seasonal),
  UseItemSpec(54, ItemGroup.consumable),
  UseItemSpec(59, ItemGroup.consumable),
  UseItemSpec(52, ItemGroup.consumable),
  UseItemSpec(
    51,
    ItemGroup.consumable,
    slotMasterId: 43,
    payItemId: 14,
    fromUseItem: false,
  ),
  UseItemSpec(
    50,
    ItemGroup.consumable,
    slotMasterId: 42,
    payItemId: 11,
    fromUseItem: false,
  ),
  UseItemSpec(67, ItemGroup.consumable, slotMasterId: 146, fromUseItem: false),
  UseItemSpec(66, ItemGroup.consumable, slotMasterId: 145, fromUseItem: false),
  UseItemSpec(76, ItemGroup.consumable, slotMasterId: 241, fromUseItem: false),
  UseItemSpec(69, ItemGroup.consumable, slotMasterId: 150, fromUseItem: false),
  UseItemSpec(102, ItemGroup.consumable),
  UseItemSpec(73, ItemGroup.consumable),
  UseItemSpec(64, ItemGroup.consumable),
  UseItemSpec(63, ItemGroup.consumable),
  UseItemSpec(10, ItemGroup.other),
  UseItemSpec(11, ItemGroup.other),
  UseItemSpec(12, ItemGroup.other),
  UseItemSpec(49, ItemGroup.other),
  UseItemSpec(103, ItemGroup.other),
  UseItemSpec(53, ItemGroup.other, payItemId: 16, fromUseItem: false),
  UseItemSpec(105, ItemGroup.other),
  UseItemSpec(55, ItemGroup.other),
];

String useItemAssetPath(int id) => const {10, 11, 12}.contains(id)
    ? 'assets/images/material/$id.png'
    : 'assets/images/material/useitem_$id.png';

String useItemName(Locale? locale, int id) {
  final names = useItemStrings[id];
  if (names == null) return '#$id';
  return switch (uiLocaleStorageCode(locale)) {
    'zh_Hant' => names.$2,
    'ja' => names.$3,
    'ko' => names.$4,
    'en' => names.$5,
    _ => names.$1,
  };
}
