import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Wraps [children] like a [Wrap] and draws [separator] only between two
/// neighbours on the same line, so a wrapped line never starts or ends with it.
class SeparatedWrap extends MultiChildRenderObjectWidget {
  const SeparatedWrap({
    super.key,
    required this.separator,
    required this.style,
    super.children,
  });

  final String separator;
  final TextStyle style;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderSeparatedWrap(separator, style, Directionality.of(context));

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as RenderSeparatedWrap)
      ..separator = separator
      ..style = style
      ..textDirection = Directionality.of(context);
  }
}

class _Parent extends ContainerBoxParentData<RenderBox> {}

class RenderSeparatedWrap extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _Parent>,
        RenderBoxContainerDefaultsMixin<RenderBox, _Parent> {
  RenderSeparatedWrap(this._separator, this._style, this._textDirection) {
    _rebuildPainter();
  }

  static const _gap = 3.0;

  String _separator;
  TextStyle _style;
  TextDirection _textDirection;
  final TextPainter _painter = TextPainter();
  final List<Offset> _separatorOffsets = [];

  set separator(String value) {
    if (value == _separator) return;
    _separator = value;
    _rebuildPainter();
    markNeedsLayout();
  }

  set style(TextStyle value) {
    if (value == _style) return;
    _style = value;
    _rebuildPainter();
    markNeedsLayout();
  }

  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    _rebuildPainter();
    markNeedsLayout();
  }

  void _rebuildPainter() {
    _painter
      ..text = TextSpan(text: _separator, style: _style)
      ..textDirection = _textDirection
      ..layout();
  }

  /// Rects of the painted separators, for tests.
  @visibleForTesting
  List<Rect> get debugSeparatorRects => [
    for (final at in _separatorOffsets) at & _painter.size,
  ];

  double get _separatorWidth => _painter.width + _gap * 2;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _Parent) child.parentData = _Parent();
  }

  @override
  void performLayout() {
    final maxWidth = constraints.maxWidth;
    final loose = BoxConstraints(maxWidth: maxWidth);
    _separatorOffsets.clear();

    final lines = <List<RenderBox>>[];
    var line = <RenderBox>[];
    var x = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      child.layout(loose, parentUsesSize: true);
      final width = child.size.width;
      if (line.isNotEmpty && x + _separatorWidth + width > maxWidth) {
        lines.add(line);
        line = [];
        x = 0;
      }
      if (line.isNotEmpty) x += _separatorWidth;
      line.add(child);
      x += width;
    }
    if (line.isNotEmpty) lines.add(line);

    var y = 0.0;
    var widest = 0.0;
    for (final items in lines) {
      final height = items.fold<double>(
        0,
        (h, c) => math.max(h, c.size.height),
      );
      var dx = 0.0;
      for (var i = 0; i < items.length; i++) {
        if (i > 0) {
          _separatorOffsets.add(
            Offset(dx + _gap, y + (height - _painter.height) / 2),
          );
          dx += _separatorWidth;
        }
        (items[i].parentData! as _Parent).offset = Offset(
          dx,
          y + (height - items[i].size.height) / 2,
        );
        dx += items[i].size.width;
      }
      widest = math.max(widest, dx);
      y += height;
    }
    size = constraints.constrain(Size(widest, y));
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    var widest = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      widest = math.max(widest, child.getMinIntrinsicWidth(height));
    }
    return widest;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    var total = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if (child != firstChild) total += _separatorWidth;
      total += child.getMaxIntrinsicWidth(height);
    }
    return total;
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      getDryLayout(BoxConstraints(maxWidth: width)).height;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final maxWidth = constraints.maxWidth;
    final loose = BoxConstraints(maxWidth: maxWidth);
    var x = 0.0;
    var widest = 0.0;
    var lineHeight = 0.0;
    var height = 0.0;
    var onLine = 0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final size = child.getDryLayout(loose);
      if (onLine > 0 && x + _separatorWidth + size.width > maxWidth) {
        height += lineHeight;
        widest = math.max(widest, x);
        x = 0;
        lineHeight = 0;
        onLine = 0;
      }
      if (onLine > 0) x += _separatorWidth;
      x += size.width;
      lineHeight = math.max(lineHeight, size.height);
      onLine++;
    }
    height += lineHeight;
    widest = math.max(widest, x);
    return constraints.constrain(Size(widest, height));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
    for (final at in _separatorOffsets) {
      _painter.paint(context.canvas, offset + at);
    }
  }

  @override
  void dispose() {
    _painter.dispose();
    super.dispose();
  }
}
