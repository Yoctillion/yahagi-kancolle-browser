/// dropdown = 标题下拉 + 左右翻页（默认），tabs = 文字标签条，icons = 图标条。
enum SmartPanelHeaderStyle { dropdown, tabs, icons }

abstract interface class SmartPanelSettingsStore {
  Future<bool> loadSmartPanelAutoSwitch();
  Future<void> saveSmartPanelAutoSwitch(bool enabled);
  Future<SmartPanelHeaderStyle> loadSmartPanelHeaderStyle();
  Future<void> saveSmartPanelHeaderStyle(SmartPanelHeaderStyle style);
}
