enum ItemPanelMode { compact, detailed }

abstract interface class ItemPanelSettingsStore {
  Future<ItemPanelMode> loadItemPanelMode();
  Future<void> saveItemPanelMode(ItemPanelMode mode);
}
