import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

const minimalUiScale = 1.1;

/// Scales Flutter UI and its allocated space without changing [MediaQuery].
///
/// Keep this wrapper in the tree when changing its factor so stateful children
/// retain their identity. Game surfaces and platform WebViews belong outside it.
/// [scale] is an absolute factor: nested wrappers with the same factor do not
/// enlarge the UI twice. Overlay feedback can copy [of] into its own wrapper.
class UiScale extends StatelessWidget {
  const UiScale({super.key, this.scale = 1, required this.child})
    : assert(scale > 0 && scale < double.infinity);

  final double scale;
  final Widget child;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_UiScaleScope>()?.scale ?? 1;

  @override
  Widget build(BuildContext context) => _UiScaleScope(
    scale: scale,
    child: _UiScaleBox(scale: scale / of(context), child: child),
  );
}

class _UiScaleScope extends InheritedWidget {
  const _UiScaleScope({required this.scale, required super.child});
  final double scale;

  @override
  bool updateShouldNotify(_UiScaleScope oldWidget) => scale != oldWidget.scale;
}

class _UiScaleBox extends SingleChildRenderObjectWidget {
  const _UiScaleBox({required this.scale, required super.child});

  final double scale;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderUiScale(scale);

  @override
  void updateRenderObject(BuildContext context, _RenderUiScale renderObject) {
    renderObject.scale = scale;
  }
}

class _RenderUiScale extends RenderProxyBox {
  _RenderUiScale(this._scale);

  double _scale;

  set scale(double value) {
    assert(value > 0 && value.isFinite);
    if (_scale == value) return;
    _scale = value;
    markNeedsLayout();
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  Matrix4 get _transform => Matrix4.diagonal3Values(_scale, _scale, 1);

  BoxConstraints _childConstraints(BoxConstraints outer) => BoxConstraints(
    minWidth: outer.minWidth / _scale,
    maxWidth: outer.maxWidth / _scale,
    minHeight: outer.minHeight / _scale,
    maxHeight: outer.maxHeight / _scale,
  );

  @override
  double computeMinIntrinsicWidth(double height) =>
      (child?.getMinIntrinsicWidth(height / _scale) ?? 0) * _scale;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      (child?.getMaxIntrinsicWidth(height / _scale) ?? 0) * _scale;

  @override
  double computeMinIntrinsicHeight(double width) =>
      (child?.getMinIntrinsicHeight(width / _scale) ?? 0) * _scale;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      (child?.getMaxIntrinsicHeight(width / _scale) ?? 0) * _scale;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final childSize = child?.getDryLayout(_childConstraints(constraints));
    return childSize == null
        ? constraints.smallest
        : constraints.constrain(childSize * _scale);
  }

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final distance = child?.getDryBaseline(
      _childConstraints(constraints),
      baseline,
    );
    return distance == null ? null : distance * _scale;
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final distance = child?.getDistanceToActualBaseline(baseline);
    return distance == null ? null : distance * _scale;
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_childConstraints(constraints), parentUsesSize: true);
    size = constraints.constrain(child.size * _scale);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (_scale == 1) return super.hitTestChildren(result, position: position);
    return result.addWithPaintTransform(
      transform: _transform,
      position: position,
      hitTest: (result, position) =>
          super.hitTestChildren(result, position: position),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || _scale == 1) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      _transform,
      super.paint,
      oldLayer: layer is TransformLayer ? layer as TransformLayer : null,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_transform);
  }
}
