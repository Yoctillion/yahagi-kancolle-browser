import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 信息栏紧挨游戏画面的一侧；极简档下该侧边缘的点按多半是想点游戏。
enum PanelGameEdge { none, left, right }

/// 竖屏时游戏和信息栏上下排布，信息栏没有靠游戏的竖边。
PanelGameEdge panelGameEdgeFor({
  required bool isLandscape,
  required bool infoOnLeft,
}) {
  if (!isLandscape) return PanelGameEdge.none;
  return infoOnLeft ? PanelGameEdge.right : PanelGameEdge.left;
}

/// 从信息栏靠游戏一侧的边缘量起：扁平卡片 6 内边距、1 分隔线之外再留 12dp。
/// 按信息栏而不是按行量，两列格子里靠中缝的单元格边缘才不会被误挡。
const panelGameEdgeDeadZone = 19.0;

/// 标出信息栏的边界，供其中的 [GameEdgeTapGuard] 判定防误触边。
class PanelGameEdgeScope extends SingleChildRenderObjectWidget {
  const PanelGameEdgeScope({
    super.key,
    required this.edge,
    required super.child,
  });

  final PanelGameEdge edge;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPanelGameEdgeScope(edge);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderPanelGameEdgeScope).edge = edge;
  }
}

class _RenderPanelGameEdgeScope extends RenderProxyBox {
  _RenderPanelGameEdgeScope(this.edge);

  // 只在命中测试时读取，布局和绘制都不依赖它，改值无需标脏。
  PanelGameEdge edge;

  bool inDeadZone(Offset position) => switch (edge) {
    PanelGameEdge.left => position.dx < panelGameEdgeDeadZone,
    PanelGameEdge.right => position.dx > size.width - panelGameEdgeDeadZone,
    PanelGameEdge.none => false,
  };
}

/// 防误触边内的点按不命中子树。不用覆盖层吸收点按：覆盖层会挡住从边内
/// 开始的滚动，而这里祖先 Scrollable 仍会被命中，滚动照常。
class GameEdgeTapGuard extends SingleChildRenderObjectWidget {
  const GameEdgeTapGuard({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGameEdgeTapGuard();
}

class _RenderGameEdgeTapGuard extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (size.contains(position)) {
      final scope = _scope();
      if (scope != null &&
          scope.inDeadZone(
            MatrixUtils.transformPoint(getTransformTo(scope), position),
          )) {
        return false;
      }
    }
    return super.hitTest(result, position: position);
  }

  _RenderPanelGameEdgeScope? _scope() {
    for (var node = parent; node != null; node = node.parent) {
      if (node is _RenderPanelGameEdgeScope) return node;
    }
    return null;
  }
}
