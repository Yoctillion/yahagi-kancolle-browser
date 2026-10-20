enum UiDisplaySize { normal, compact, minimal }

extension UiDisplaySizeX on UiDisplaySize {
  bool get isCompactOrSmaller => this != UiDisplaySize.normal;
  bool get isMinimal => this == UiDisplaySize.minimal;
}

double workspaceNavigationExtent(UiDisplaySize size) => switch (size) {
  UiDisplaySize.normal => 48.0,
  UiDisplaySize.compact => 41.0,
  UiDisplaySize.minimal => 34.0,
};

double topHeaderHeight(UiDisplaySize size) => switch (size) {
  UiDisplaySize.normal => 44.0,
  UiDisplaySize.compact => 36.0,
  UiDisplaySize.minimal => 28.0,
};

double headerCapsuleHeight(UiDisplaySize size) => switch (size) {
  UiDisplaySize.normal => 30.0,
  UiDisplaySize.compact => 26.0,
  UiDisplaySize.minimal => 22.0,
};

double browserToolbarHeight(UiDisplaySize size) => switch (size) {
  UiDisplaySize.normal => 34.0,
  UiDisplaySize.compact => 30.0,
  UiDisplaySize.minimal => 30.0,
};
