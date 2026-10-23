import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../settings/ui_display_size.dart';
import 'display_corners.dart';

/// HD 保留自己的分栏外壳，极简面板样式可在两种外壳中使用。
bool usesMinimalShell({
  required UiDisplaySize size,
  required bool isLandscape,
  required bool hd,
}) => size.isMinimal && isLandscape && !hd;

bool usesFlatPanel({required UiDisplaySize size, required bool hd}) =>
    size.isMinimal;

UiDisplaySize effectiveUiDisplaySize(UiDisplaySize size, {required bool hd}) =>
    size;

/// 极简横屏下竖向导航栏位于顶栏下方，只需避让底角与手势条。横向导航栏只在
/// 贴着屏幕底边时才需要（游戏页的「上方」位置也排在游戏列下面），所以只看底部两角；
/// 这里不含手势条，贴底横栏的底部安全区由调用方按栏的位置另加。
EdgeInsets minimalNavigationInsets({
  required CornerRadii corners,
  required double bottomSafeArea,
  required bool horizontal,
  required bool onRight,
  bool leftAtEdge = true,
  bool rightAtEdge = true,
}) {
  if (horizontal) {
    return EdgeInsets.only(
      left: leftAtEdge ? cornerInset(corners.bottomLeft) : 0,
      right: rightAtEdge ? cornerInset(corners.bottomRight) : 0,
    );
  }
  return EdgeInsets.only(
    bottom: math.max(
      cornerInset(onRight ? corners.bottomRight : corners.bottomLeft),
      bottomSafeArea,
    ),
  );
}
