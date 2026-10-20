import '../settings/ui_display_size.dart';

/// HD 下极简档整体按紧凑档处理，因此游戏页隐藏顶栏只在非 HD 生效。
bool usesMinimalGameShell({
  required UiDisplaySize size,
  required int workspaceIndex,
  required bool isLandscape,
  required bool hd,
}) => size.isMinimal && workspaceIndex == 0 && isLandscape && !hd;

bool usesFlatPanel({required UiDisplaySize size, required bool hd}) =>
    size.isMinimal && !hd;
