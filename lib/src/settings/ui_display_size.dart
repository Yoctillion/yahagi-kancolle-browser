enum UiDisplaySize { normal, compact, minimal }

/// 极简档横屏游戏页的资源放在信息栏顶部、游戏上方的细顶栏，还是屏幕底边的细横栏。
enum MinimalResourcePosition { panel, topBar, bottomBar }

extension UiDisplaySizeX on UiDisplaySize {
  bool get isCompactOrSmaller => this != UiDisplaySize.normal;
  bool get isMinimal => this == UiDisplaySize.minimal;
}

double workspaceNavigationExtent(UiDisplaySize size) => switch (size) {
  UiDisplaySize.normal => 48.0,
  UiDisplaySize.compact || UiDisplaySize.minimal => 41.0,
};

double topHeaderHeight(UiDisplaySize size) => switch (size) {
  UiDisplaySize.normal => 44.0,
  UiDisplaySize.compact || UiDisplaySize.minimal => 36.0,
};

double headerCapsuleHeight(UiDisplaySize size) => switch (size) {
  UiDisplaySize.normal => 30.0,
  UiDisplaySize.compact || UiDisplaySize.minimal => 26.0,
};

double browserToolbarHeight(UiDisplaySize size) => switch (size) {
  UiDisplaySize.normal => 34.0,
  UiDisplaySize.compact => 30.0,
  UiDisplaySize.minimal => 30.0,
};
