import '../theme/app_palette.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'battle_detail_strings.dart';
import 'battle_ui_text.dart';
import 'fcd_map_geometry.dart';
import 'sortie_map_progress.dart';

const _background = Color(0xff10212e);
const _teal = Color(0xff70c7bc);
const _muted = Color(0xff8fa8b6);
const _edge = Color(0xff506372);
const _gold = Color(0xffffcf67);
const _red = Color(0xffff8c78);

/// An independently controlled section of the live battle card.
///
/// Route IDs are resolved against FCD routes; node letters are never inferred
/// from the numeric IDs supplied by the game.
class SortieMapSection extends StatefulWidget {
  const SortieMapSection({
    super.key,
    required this.progress,
    required this.geometry,
    required this.expanded,
    required this.onToggleExpanded,
    this.currentNodeLabel,
  });

  final SortieMapProgress progress;
  final FcdMapGeometry? geometry;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final String? currentNodeLabel;

  @override
  State<SortieMapSection> createState() => _SortieMapSectionState();
}

class _SortieMapSectionState extends State<SortieMapSection> {
  @override
  Widget build(BuildContext context) {
    final scene = _MapScene(
      widget.progress,
      widget.geometry,
      widget.currentNodeLabel,
      BattleDetailStrings.of(context),
    );
    final expanded = widget.expanded;
    final progress = widget.progress;
    final english = Localizations.localeOf(context).languageCode == 'en';
    final title = BattleUiText(
      scene.strings.sortieMapTitle,
      style: appTextStyle(
        context,
        TextStyle(
          color: appColor(context, _teal),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    return Material(
      key: const Key('sortie-map-section'),
      color: appColor(context, _background),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            expanded: expanded,
            child: TextButton(
              key: const Key('sortie-map-toggle'),
              onPressed: widget.onToggleExpanded,
              style: TextButton.styleFrom(
                foregroundColor: appColor(context, _teal),
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: const RoundedRectangleBorder(),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) => Row(
                  children: [
                    const Icon(Icons.map_outlined, size: 14),
                    const SizedBox(width: 6),
                    if (english)
                      Flexible(flex: 3, child: title)
                    else
                      ConstrainedBox(
                        // Keep short titles intrinsic, but leave summary space
                        // when accessibility text sizes enlarge the title.
                        constraints: BoxConstraints(
                          maxWidth: math.max(0, constraints.maxWidth - 50) * .6,
                        ),
                        child: title,
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: english ? 2 : 1,
                      child: Semantics(
                        liveRegion: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            BattleUiText(
                              scene.summary,
                              textAlign: TextAlign.end,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: appTextStyle(
                                context,
                                TextStyle(
                                  color: appColor(context, _muted),
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            if (!expanded && scene.needsUpdate)
                              BattleUiText(
                                scene.strings.mapUnavailable,
                                textAlign: TextAlign.end,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: appTextStyle(
                                  context,
                                  TextStyle(
                                    color: appColor(context, _gold),
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      color: appColor(context, _muted),
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded)
            Container(
              key: const Key('sortie-map-body'),
              padding: const EdgeInsets.fromLTRB(9, 2, 9, 8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: appColor(context, Color(0xff203746))),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (scene.hasGeometry)
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: LayoutBuilder(
                          builder: (context, constraints) => SizedBox(
                            width: constraints.maxWidth,
                            height: (constraints.maxWidth * .44 + 16).clamp(
                              125.0,
                              175.0,
                            ),
                            child: RepaintBoundary(
                              child: _MapCanvas(
                                key: const Key('sortie-map-canvas'),
                                scene: scene,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: BattleUiText(
                        scene.strings.mapUnavailable,
                        textAlign: TextAlign.center,
                        style: appTextStyle(
                          context,
                          TextStyle(
                            color: appColor(context, _muted),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  if (scene.hasGeometry && scene.needsUpdate)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 5),
                      child: BattleUiText(
                        scene.strings.mapUnavailable,
                        style: appTextStyle(
                          context,
                          TextStyle(
                            color: appColor(context, _gold),
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  if (progress.isPartial)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: BattleUiText(
                        scene.strings.mapPartial,
                        style: appTextStyle(
                          context,
                          TextStyle(
                            color: appColor(context, _muted),
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MapScene {
  _MapScene(this.progress, this.geometry, String? currentLabel, this.strings)
    : current =
          geometry?.routes[progress.currentRouteId]?.to ??
          (currentLabel?.trim().isNotEmpty == true
              ? currentLabel!.trim()
              : null);

  final SortieMapProgress progress;
  final FcdMapGeometry? geometry;
  final BattleDetailStrings strings;
  final String? current;

  // These inputs are immutable. Reuse derived data within this scene across
  // the header, route/node semantics and painting.
  late final bool hasGeometry = _hasGeometry();

  bool _hasGeometry() {
    final map = geometry;
    if (map == null || map.spots.isEmpty || map.routes.isEmpty) return false;
    final xs = map.spots.values.map((spot) => spot.x);
    final ys = map.spots.values.map((spot) => spot.y);
    if (xs.any((x) => !x.isFinite) || ys.any((y) => !y.isFinite)) {
      return false;
    }
    // Finite endpoints can still have an infinite span (e.g. -1e308..1e308).
    // Such optional data must fall back rather than produce NaN paint bounds.
    return (xs.reduce(math.max) - xs.reduce(math.min)).isFinite &&
        (ys.reduce(math.max) - ys.reduce(math.min)).isFinite;
  }

  late final bool needsUpdate =
      !hasGeometry ||
      progress.routeIds.any((id) => !_hasRoute(id)) ||
      (progress.bossRouteId != null && !_hasRoute(progress.bossRouteId!));

  bool _hasRoute(int id) {
    final route = geometry?.routes[id];
    return route != null &&
        geometry!.spots.containsKey(route.to) &&
        (route.from == null || geometry!.spots.containsKey(route.from));
  }

  String? get boss => geometry?.routes[progress.bossRouteId]?.to;
  String get currentDisplay =>
      current ??
      (progress.currentRouteId == null
          ? strings.mapUnknown
          : strings.mapNode(progress.currentRouteId!));
  String get summary =>
      '${progress.mapKey} · ${strings.mapCurrent} $currentDisplay';

  late final Set<int> routeIds = progress.routeIds.toSet();

  late final Set<String> visited = {
    for (final id in progress.routeIds)
      if (geometry?.routes[id] case final route?) ...[
        if (route.from != null) route.from!,
        route.to,
      ],
  };

  String routeLabel(int id) => strings.mapRoute(id);

  String nodeDescription(String label) => [
    label,
    if (geometry?.spots[label]?.type == 'start') strings.mapStart,
    if (label == boss) 'Boss',
    if (label == current) strings.mapCurrent,
    if (visited.contains(label)) strings.mapVisited,
  ].join(' · ');
}

class _MapCanvas extends StatelessWidget {
  const _MapCanvas({super.key, required this.scene});
  final _MapScene scene;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      final projection = _MapProjection(scene.geometry!, size);
      return Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _MapPainter(scene, projection, AppPalette.of(context)),
          ),
          for (final entry in scene.geometry!.routes.entries)
            if (projection.points[entry.value.from] case final from?)
              if (projection.points[entry.value.to] case final to?)
                Positioned.fromRect(
                  rect: Rect.fromPoints(from, to).inflate(3),
                  child: Semantics(
                    container: true,
                    label: [
                      scene.routeLabel(entry.key),
                      '${entry.value.from} → ${entry.value.to}',
                      if (scene.routeIds.contains(entry.key))
                        scene.strings.mapVisited,
                    ].join(' · '),
                    child: const SizedBox.expand(),
                  ),
                ),
          for (final entry in projection.points.entries)
            Positioned.fromRect(
              rect: Rect.fromCircle(center: entry.value, radius: 10),
              child: Semantics(
                container: true,
                label: scene.nodeDescription(entry.key),
                child: const SizedBox.expand(),
              ),
            ),
        ],
      );
    },
  );
}

class _MapProjection {
  _MapProjection(FcdMapGeometry geometry, Size size) {
    final xs = geometry.spots.values.map((spot) => spot.x);
    final ys = geometry.spots.values.map((spot) => spot.y);
    final minX = xs.reduce(math.min);
    final minY = ys.reduce(math.min);
    final rangeX = xs.reduce(math.max) - minX;
    final rangeY = ys.reduce(math.max) - minY;
    final scale = math.min(
      math.max(0, size.width - 52) / math.max(1, rangeX),
      math.max(0, size.height - 52) / math.max(1, rangeY),
    );
    final origin = Offset(
      (size.width - rangeX * scale) / 2,
      (size.height - rangeY * scale) / 2,
    );
    points = {
      for (final entry in geometry.spots.entries)
        entry.key:
            origin + Offset(entry.value.x - minX, entry.value.y - minY) * scale,
    };
  }

  late final Map<String, Offset> points;
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.scene, this.projection, this.palette);
  final _MapScene scene;
  final _MapProjection projection;
  final AppPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = scene.geometry!;
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (final route in geometry.routes.values) {
      final from = projection.points[route.from];
      final to = projection.points[route.to];
      if (from != null && to != null) {
        canvas.drawLine(
          from,
          to,
          paint
            ..color = palette.color(_edge.withValues(alpha: .55))
            ..strokeWidth = 1.1,
        );
      }
    }
    for (final id in scene.progress.routeIds) {
      final route = geometry.routes[id];
      final from = projection.points[route?.from];
      final to = projection.points[route?.to];
      if (from != null && to != null) {
        canvas.drawLine(
          from,
          to,
          paint
            ..color = palette.color(_teal)
            ..strokeWidth = 2.8,
        );
      }
    }
    final visited = scene.visited;
    final labelBounds = <Rect>[];
    final labels = <String, ({TextPainter painter, Rect bounds})>{};
    final labelOrder = [
      ...projection.points.entries.where((entry) => entry.key == scene.current),
      ...projection.points.entries.where((entry) => entry.key != scene.current),
    ];
    // Reserve a clear label for the current node before placing other labels.
    for (final entry in labelOrder) {
      final at = entry.key == scene.current;
      final color = entry.key == scene.boss
          ? _red
          : at
          ? _gold
          : visited.contains(entry.key)
          ? _teal
          : _muted;
      final label = TextPainter(
        text: TextSpan(
          text: entry.key,
          style: TextStyle(
            color: palette.color(at ? _gold : color),
            fontSize: 10,
            fontWeight: at ? FontWeight.w800 : FontWeight.w600,
            shadows: [Shadow(color: palette.color(_background), blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.max(0, size.width - 4));
      final point = entry.value;
      final preferred = _labelBounds(
        point + Offset(-label.width / 2, point.dy < 40 ? 9 : -label.height - 9),
        label.size,
        size,
      );
      final bounds = _avoidLabelBounds(
        point,
        label.size,
        size,
        preferred,
        labelBounds,
      );
      labels[entry.key] = (painter: label, bounds: bounds);
      labelBounds.add(bounds);
    }
    // A displaced label still identifies its source node unambiguously. Paint
    // the short guides underneath every marker and label, including current.
    for (final entry in labels.entries) {
      final point = projection.points[entry.key]!;
      final bounds = entry.value.bounds;
      final nearest = Offset(
        point.dx.clamp(bounds.left, bounds.right),
        point.dy.clamp(bounds.top, bounds.bottom),
      );
      final delta = nearest - point;
      if (delta.distance <= 12) continue;
      final direction = delta / delta.distance;
      final at = entry.key == scene.current;
      canvas.drawLine(
        point + direction * (at ? 9 : 5),
        nearest - direction * 2,
        Paint()
          ..color = palette.color((at ? _gold : _muted).withValues(alpha: .4))
          ..strokeWidth = .6,
      );
    }
    // Keep the captured position above every other marker and label on dense
    // maps without changing any of the source map's node positions.
    final nodes = [
      ...projection.points.entries.where((entry) => entry.key != scene.current),
      ...projection.points.entries.where((entry) => entry.key == scene.current),
    ];
    for (final entry in nodes) {
      final node = entry.key;
      final point = entry.value;
      final at = node == scene.current;
      final boss = node == scene.boss;
      final color = boss
          ? _red
          : at
          ? _gold
          : visited.contains(node)
          ? _teal
          : _muted;
      if (at) {
        canvas.drawCircle(
          point,
          8,
          Paint()..color = palette.color(_gold.withValues(alpha: .13)),
        );
        canvas.drawCircle(
          point,
          8,
          Paint()
            ..color = palette.color(_gold)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
      }
      final fill = Paint()..color = palette.color(color);
      if (boss) {
        canvas.drawPath(
          Path()
            ..moveTo(point.dx, point.dy - 5)
            ..lineTo(point.dx + 5, point.dy)
            ..lineTo(point.dx, point.dy + 5)
            ..lineTo(point.dx - 5, point.dy)
            ..close(),
          fill,
        );
      } else if (geometry.spots[node]!.type == 'start') {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: point, width: 8, height: 8),
            const Radius.circular(1),
          ),
          fill,
        );
      } else {
        canvas.drawCircle(point, at ? 4.5 : 3.2, fill);
      }
      final label = labels[node]!;
      label.painter.paint(canvas, label.bounds.topLeft);
    }
  }

  Rect _labelBounds(Offset offset, Size label, Size canvas) => Rect.fromLTWH(
    offset.dx.clamp(2.0, math.max(2, canvas.width - label.width - 2)),
    offset.dy.clamp(2.0, math.max(2, canvas.height - label.height - 2)),
    label.width,
    label.height,
  );

  Rect _avoidLabelBounds(
    Offset point,
    Size label,
    Size canvas,
    Rect preferred,
    List<Rect> labels,
  ) {
    final obstacles = [
      ...labels.map((rect) => rect.inflate(1)),
      for (final node in projection.points.values)
        Rect.fromCircle(
          center: node,
          radius: node == projection.points[scene.current] ? 9 : 6,
        ),
    ];
    final candidates = [
      preferred,
      for (final y in [
        -label.height - 9,
        9.0,
        -label.height / 2,
        -label.height - 21,
        21.0,
      ])
        for (final x in [0.0, -16.0, 16.0, -32.0, 32.0])
          _labelBounds(point + Offset(-label.width / 2 + x, y), label, canvas),
    ];
    var best = preferred;
    var bestOverlap = double.infinity;
    for (final candidate in candidates) {
      var overlap = 0.0;
      for (final obstacle in obstacles) {
        if (candidate.overlaps(obstacle)) {
          final intersection = candidate.intersect(obstacle);
          overlap += intersection.width * intersection.height;
        }
      }
      if (overlap == 0) return candidate;
      if (overlap < bestOverlap) {
        best = candidate;
        bestOverlap = overlap;
      }
    }
    return best;
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) =>
      oldDelegate.palette.mode != palette.mode ||
      oldDelegate.scene.geometry != scene.geometry ||
      oldDelegate.scene.progress != scene.progress ||
      oldDelegate.scene.current != scene.current;
}
