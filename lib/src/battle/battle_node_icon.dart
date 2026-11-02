import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../layout/flat_style.dart';
import 'battle_detail_strings.dart';
import 'battle_models.dart';

// The mark is drawn on a fixed 28-unit grid and scaled to the icon size.
const double _grid = 28;
const Offset _center = Offset(14, 14);
const Offset _bossCenter = Offset(14, 15);
const double _arrowWidth = 3;

const _enemyArrow = Color(0xffff5d4d);
const _friendArrow = Color(0xff4aa8ff);
const _radarWave = Color(0xffff9800);
const _combinedRing = Color(0xffff8c78);
const _bossRing = Color(0xffffb3a6);

const _battle = _IconFill(Color(0xffa8281f), Color(0xfff1e7e2));
const _night = _IconFill(Color(0xff6d4bd8), Color(0xffe3dcff));
const _resource = _IconFill(Color(0xff1f7a45), Color(0xffd6f2e2));
const _maelstrom = _IconFill(Color(0xffd2c6ff), Color(0xff6b5b91));
const _route = _IconFill(Color(0xffffffff), Color(0xff8197a5));
const _quiet = _IconFill(Color(0xff0a7d7b), Color(0xffd3efee));
const _neutral = _IconFill(Color(0xff26343e), Color(0xff9db2bf));

class _IconFill {
  const _IconFill(this.fill, this.ring);

  final Color fill;
  final Color ring;
}

_IconFill _fillOf(BattleNodeKind kind) => switch (kind) {
  BattleNodeKind.battle ||
  BattleNodeKind.nightToDay ||
  BattleNodeKind.airBattle ||
  BattleNodeKind.airRaid ||
  BattleNodeKind.radarAmbush ||
  BattleNodeKind.enemyCombined ||
  BattleNodeKind.antiSubAir => _battle,
  BattleNodeKind.nightBattle => _night,
  BattleNodeKind.resource ||
  BattleNodeKind.transport ||
  BattleNodeKind.escort => _resource,
  BattleNodeKind.maelstrom => _maelstrom,
  BattleNodeKind.routeSelect => _route,
  BattleNodeKind.quiet ||
  BattleNodeKind.anchorage ||
  BattleNodeKind.airRecon => _quiet,
  BattleNodeKind.start || BattleNodeKind.unknown => _neutral,
};

/// A small mark for what kind of node this is, set inline before the node
/// name. The marks follow the in-game cell icons: a red arrow for enemy
/// aircraft, blue for ours, and a blue ring for submarines.
class BattleNodeIcon extends StatelessWidget {
  const BattleNodeIcon({
    super.key = const Key('battle-node-icon'),
    required this.nodeContext,
    this.size = flatNodeIconSize,
  });

  final BattleContext nodeContext;
  final double size;

  @override
  Widget build(BuildContext context) {
    final strings = BattleDetailStrings.of(context);
    return Tooltip(
      message: nodeContext.nodeTypeLabels.map(strings.localize).join(' · '),
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _NodeMarkPainter(
            nodeContext.nodeKind,
            boss: nodeContext.isBossNode,
            submarine: nodeContext.isSubmarineBattle,
          ),
        ),
      ),
    );
  }
}

class _NodeMarkPainter extends CustomPainter {
  const _NodeMarkPainter(
    this.kind, {
    required this.boss,
    required this.submarine,
  });

  final BattleNodeKind kind;
  final bool boss;
  final bool submarine;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _grid);
    if (boss) {
      _paintBoss(canvas);
      return;
    }
    final fill = _fillOf(kind);
    switch (kind) {
      case BattleNodeKind.airBattle:
        _disc(canvas, 8.5, fill.fill);
        _arrow(canvas, _enemyArrow);
        _arrow(canvas, _friendArrow, opposite: true);
      case BattleNodeKind.airRaid:
        _disc(canvas, 8.5, fill.fill);
        _arrow(canvas, _enemyArrow);
      case BattleNodeKind.antiSubAir:
        _submarineMark(canvas, fill.fill);
        _arrow(canvas, _enemyArrow);
      case BattleNodeKind.radarAmbush:
        _disc(canvas, 8.5, fill.fill);
        _radarRing(canvas);
      case BattleNodeKind.enemyCombined:
        _ring(canvas, _center, 12.4, _combinedRing, 2);
        _disc(canvas, 8.8, fill.fill);
      case BattleNodeKind.nightToDay:
        _disc(canvas, 12, fill.fill);
        _nightSwirl(canvas, _center, 12);
      case _ when submarine:
        _submarineMark(canvas, fill.fill);
      default:
        _disc(canvas, 11, fill.fill);
        _ring(canvas, _center, 11, fill.ring, 2);
    }
  }

  // The arrows would run into the horns, so a boss shows its fill alone.
  void _paintBoss(Canvas canvas) {
    final horns = Paint()..color = _enemyArrow;
    canvas
      ..drawPath(_triangle(6.6, 8.4, 3.6, 0.4, 12.4, 4.2), horns)
      ..drawPath(_triangle(21.4, 8.4, 24.4, 0.4, 15.6, 4.2), horns);
    final fill = _fillOf(kind);
    canvas.drawCircle(_bossCenter, 11, Paint()..color = fill.fill);
    if (kind == BattleNodeKind.nightToDay) {
      _nightSwirl(canvas, _bossCenter, 11);
    }
    _ring(canvas, _bossCenter, 11, submarine ? _friendArrow : _bossRing, 2);
  }

  void _submarineMark(Canvas canvas, Color fill) {
    _disc(canvas, 8, fill);
    _ring(canvas, _center, 10.2, _friendArrow, 2.4);
  }

  void _disc(Canvas canvas, double radius, Color color) =>
      canvas.drawCircle(_center, radius, Paint()..color = color);

  void _ring(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double width,
  ) => canvas.drawCircle(
    center,
    radius,
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width,
  );

  /// An arc down the left edge; [opposite] turns it to run up the right edge.
  void _arrow(Canvas canvas, Color color, {bool opposite = false}) {
    canvas.save();
    if (opposite) {
      canvas
        ..translate(_grid, _grid)
        ..rotate(math.pi);
    }
    canvas
      ..drawPath(
        Path()
          ..moveTo(8, 3.6)
          ..arcToPoint(
            const Offset(5.5, 22.5),
            radius: const Radius.circular(12),
            clockwise: false,
          ),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = _arrowWidth,
      )
      ..drawPath(
        _triangle(2.4, 25.6, 8.6, 19.4, 10.2, 26),
        Paint()..color = color,
      )
      ..restore();
  }

  void _radarRing(Canvas canvas) {
    const dashes = 6;
    final paint = Paint()
      ..color = _radarWave
      ..style = PaintingStyle.stroke
      ..strokeWidth = _arrowWidth;
    final bounds = Rect.fromCircle(center: _center, radius: 12);
    const step = 2 * math.pi / dashes;
    for (var index = 0; index < dashes; index++) {
      canvas.drawArc(bounds, index * step, step * .6, false, paint);
    }
  }

  void _nightSwirl(Canvas canvas, Offset center, double radius) {
    final top = center - Offset(0, radius);
    final bottom = center + Offset(0, radius);
    canvas.drawPath(
      Path()
        ..moveTo(top.dx, top.dy)
        ..arcToPoint(bottom, radius: Radius.circular(radius), clockwise: false)
        ..arcToPoint(
          center,
          radius: Radius.circular(radius / 2),
          clockwise: false,
        )
        ..arcToPoint(top, radius: Radius.circular(radius / 2))
        ..close(),
      Paint()..color = _night.fill,
    );
  }

  Path _triangle(
    double ax,
    double ay,
    double bx,
    double by,
    double cx,
    double cy,
  ) => Path()
    ..moveTo(ax, ay)
    ..lineTo(bx, by)
    ..lineTo(cx, cy)
    ..close();

  @override
  bool shouldRepaint(covariant _NodeMarkPainter oldDelegate) =>
      oldDelegate.kind != kind ||
      oldDelegate.boss != boss ||
      oldDelegate.submarine != submarine;
}
