import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../settings/ui_display_size.dart';
import 'display_corners.dart';

/// HD 下极简档整体按紧凑档处理，因此游戏页隐藏顶栏只在非 HD 生效。
bool usesMinimalGameShell({
  required UiDisplaySize size,
  required int workspaceIndex,
  required bool isLandscape,
  required bool hd,
}) => size.isMinimal && workspaceIndex == 0 && isLandscape && !hd;

bool usesFlatPanel({required UiDisplaySize size, required bool hd}) =>
    size.isMinimal && !hd;

UiDisplaySize effectiveUiDisplaySize(UiDisplaySize size, {required bool hd}) =>
    size.isMinimal && hd ? UiDisplaySize.compact : size;

/// 极简横屏下竖向导航栏占满整高，两端直接贴到屏幕角。横向导航栏只在贴着屏幕
/// 底边时才需要（游戏页的「上方」位置也排在游戏列下面），所以只看底部两角；
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
    top: cornerInset(onRight ? corners.topRight : corners.topLeft),
    bottom: math.max(
      cornerInset(onRight ? corners.bottomRight : corners.bottomLeft),
      bottomSafeArea,
    ),
  );
}
