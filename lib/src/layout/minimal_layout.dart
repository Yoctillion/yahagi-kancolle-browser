import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../settings/ui_display_size.dart';
import 'display_corners.dart';
import 'ui_scale.dart';

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

/// HD 的外壳几何按紧凑档设计，极简只给它扁平样式，所以 HD 下导航栏、顶栏、
/// 胶囊的尺寸都按紧凑档查。
UiDisplaySize chromeDisplaySize(UiDisplaySize size, {required bool hd}) =>
    size.isMinimal && hd ? UiDisplaySize.compact : size;

/// 极简档只在 HD 下放大信息栏内容；手机极简靠更小的外壳尺寸省空间，内容保持原大小。
double minimalContentScale({required bool hd}) => hd ? minimalUiScale : 1.0;

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
