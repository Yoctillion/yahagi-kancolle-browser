import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'battle_detail_strings.dart';
import 'battle_models.dart';

// The mark is drawn on a fixed 28-unit grid and scaled to the badge size.
const double _grid = 28;
const Offset _center = Offset(14, 14);
const Offset _bossCenter = Offset(14, 15);

const _enemyArrow = Color(0xffff5d4d);
const _friendArrow = Color(0xff4aa8ff);
const _radarWave = Color(0xffff9800);
const _combinedRing = Color(0xffff8c78);

const _battle = _BadgeFill(Color(0xffa8281f), Color(0xfff1e7e2));
const _night = _BadgeFill(Color(0xff6d4bd8), Color(0xffe3dcff));
const _resource = _BadgeFill(Color(0xff1f7a45), Color(0xffd6f2e2));
const _maelstrom = _BadgeFill(
  Color(0xffd2c6ff),
  Color(0xff6b5b91),
  letter: Color(0xff1a1036),
);
const _route = _BadgeFill(
  Color(0xffffffff),
  Color(0xff8197a5),
  letter: Color(0xff0d1a24),
);
const _quiet = _BadgeFill(Color(0xff0a7d7b), Color(0xffd3efee));
const _neutral = _BadgeFill(
  Color(0xff26343e),
  Color(0xff9db2bf),
  letter: Color(0xffdfe8ee),
);

class _BadgeFill {
  const _BadgeFill(this.fill, this.ring, {this.letter = Colors.white});

  final Color fill;
  final Color ring;
  final Color letter;
}

_BadgeFill _fillOf(BattleNodeKind kind) => switch (kind) {
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

/// A node's letter on a mark that says what kind of node it is, so a narrow
/// panel needs no separate type text. The marks follow the in-game cell icons
/// (red arrow for enemy aircraft, blue for ours) but are redrawn around the
/// letter, which the originals would cover.
class BattleNodeBadge extends StatelessWidget {
  const BattleNodeBadge({
    super.key = const Key('battle-node-badge'),
    required this.nodeContext,
    this.size = _grid,
  });

  final BattleContext nodeContext;
  final double size;

  @override
  Widget build(BuildContext context) {
    final strings = BattleDetailStrings.of(context);
    final kind = nodeContext.nodeKind;
    return Tooltip(
      message: nodeContext.nodeTypeLabels.map(strings.localize).join(' · '),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            CustomPaint(
              key: const Key('battle-node-badge-mark'),
              painter: _NodeMarkPainter(kind, boss: nodeContext.isBossNode),
            ),
            Padding(
              padding: EdgeInsets.all(size * .2),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    nodeContext.nodeBadgeLetter,
                    maxLines: 1,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      color: _fillOf(kind).letter,
                      fontSize: size * .45,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NodeMarkPainter extends CustomPainter {
  const _NodeMarkPainter(this.kind, {required this.boss});

  final BattleNodeKind kind;
  final bool boss;

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
        _disc(canvas, 9.5, fill.fill);
        _arrow(canvas, _enemyArrow);
        _arrow(canvas, _friendArrow, opposite: true);
      case BattleNodeKind.airRaid:
        _disc(canvas, 9.5, fill.fill);
        _arrow(canvas, _enemyArrow);
      case BattleNodeKind.antiSubAir:
        _disc(canvas, 8.4, fill.fill);
        _ring(canvas, _center, 9.9, _friendArrow, 1.8);
        _arrow(canvas, _enemyArrow);
      case BattleNodeKind.radarAmbush:
        _disc(canvas, 9.5, fill.fill);
        _radarRing(canvas);
      case BattleNodeKind.enemyCombined:
        _ring(canvas, _center, 12.2, _combinedRing, 1.4);
        _disc(canvas, 9.6, fill.fill);
        _ring(canvas, _center, 9.6, fill.ring, 1.2);
      case BattleNodeKind.nightToDay:
        _disc(canvas, 11, fill.fill);
        _nightSwirl(canvas, _center);
        _ring(canvas, _center, 11, fill.ring, 1.4);
      default:
        _disc(canvas, 11, fill.fill);
        _ring(canvas, _center, 11, fill.ring, 1.4);
    }
  }

  // The arrows would run into the horns, so a boss shows its fill alone.
  void _paintBoss(Canvas canvas) {
    final horns = Paint()..color = _enemyArrow;
    canvas
      ..drawPath(_triangle(7.2, 7.8, 4.6, 1, 12, 4.2), horns)
      ..drawPath(_triangle(20.8, 7.8, 23.4, 1, 16, 4.2), horns);
    final fill = _fillOf(kind);
    canvas.drawCircle(_bossCenter, 11, Paint()..color = fill.fill);
    if (kind == BattleNodeKind.nightToDay) _nightSwirl(canvas, _bossCenter);
    _ring(canvas, _bossCenter, 11, const Color(0xffffb3a6), 1.4);
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
          ..strokeWidth = 2.2,
      )
      ..drawPath(
        _triangle(3.4, 24.6, 7.6, 20.4, 9.2, 25),
        Paint()..color = color,
      )
      ..restore();
  }

  void _radarRing(Canvas canvas) {
    const dashes = 9;
    final paint = Paint()
      ..color = _radarWave
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    final bounds = Rect.fromCircle(center: _center, radius: 12);
    const step = 2 * math.pi / dashes;
    for (var index = 0; index < dashes; index++) {
      canvas.drawArc(bounds, index * step, step * .55, false, paint);
    }
  }

  void _nightSwirl(Canvas canvas, Offset center) {
    final top = center - const Offset(0, 11);
    final bottom = center + const Offset(0, 11);
    canvas.drawPath(
      Path()
        ..moveTo(top.dx, top.dy)
        ..arcToPoint(
          bottom,
          radius: const Radius.circular(11),
          clockwise: false,
        )
        ..arcToPoint(
          center,
          radius: const Radius.circular(5.5),
          clockwise: false,
        )
        ..arcToPoint(top, radius: const Radius.circular(5.5))
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
      oldDelegate.kind != kind || oldDelegate.boss != boss;
}
