import 'package:flutter/widgets.dart';

enum PanelStyle { card, flat }

class PanelStyleScope extends InheritedWidget {
  const PanelStyleScope({super.key, required this.style, required super.child});
  final PanelStyle style;
  static PanelStyle of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PanelStyleScope>()?.style ??
      PanelStyle.card;
  @override
  bool updateShouldNotify(PanelStyleScope oldWidget) =>
      style != oldWidget.style;
}

/// 信息栏紧挨游戏画面的一侧；极简档下该侧边缘的点按多半是想点游戏。
enum PanelGameEdge { none, left, right }

class PanelGameEdgeScope extends InheritedWidget {
  const PanelGameEdgeScope({
    super.key,
    required this.edge,
    required super.child,
  });
  final PanelGameEdge edge;
  static PanelGameEdge of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PanelGameEdgeScope>()?.edge ??
      PanelGameEdge.none;
  @override
  bool updateShouldNotify(PanelGameEdgeScope oldWidget) =>
      edge != oldWidget.edge;
}
