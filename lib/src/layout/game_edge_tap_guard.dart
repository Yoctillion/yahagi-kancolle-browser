import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'panel_style.dart';

const gameEdgeTapGuardWidth = 12.0;

/// 靠游戏一侧的边缘条带不参与命中测试。不用覆盖层吸收点按：覆盖层会挡住
/// 从条带内开始的滚动，而这里祖先 Scrollable 仍会被命中，滚动照常。
class GameEdgeTapGuard extends StatelessWidget {
  const GameEdgeTapGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final edge = PanelGameEdgeScope.of(context);
    if (edge == PanelGameEdge.none) return child;
    return _GameEdgeHitBlock(edge: edge, child: child);
  }
}

class _GameEdgeHitBlock extends SingleChildRenderObjectWidget {
  const _GameEdgeHitBlock({required this.edge, super.child});

  final PanelGameEdge edge;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGameEdgeHitBlock(edge);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderGameEdgeHitBlock renderObject,
  ) {
    renderObject.edge = edge;
  }
}

class _RenderGameEdgeHitBlock extends RenderProxyBox {
  _RenderGameEdgeHitBlock(this._edge);

  PanelGameEdge _edge;
  set edge(PanelGameEdge value) {
    _edge = value;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final inStrip = switch (_edge) {
      PanelGameEdge.left => position.dx < gameEdgeTapGuardWidth,
      PanelGameEdge.right => position.dx > size.width - gameEdgeTapGuardWidth,
      PanelGameEdge.none => false,
    };
    if (inStrip) return false;
    return super.hitTest(result, position: position);
  }
}
