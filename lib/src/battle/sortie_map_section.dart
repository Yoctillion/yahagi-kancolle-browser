import '../theme/app_palette.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../layout/flat_style.dart';
import '../layout/panel_style.dart';
import 'battle_detail_strings.dart';
import 'battle_ui_text.dart';
import 'fcd_map_geometry.dart';
import 'sortie_map_label_layout.dart';
import 'sortie_map_route_layout.dart';
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
    this.showCurrentNode = true,
  });

  final SortieMapProgress progress;
  final FcdMapGeometry? geometry;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final String? currentNodeLabel;

  /// False when a header outside the section already names the current node.
  final bool showCurrentNode;

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
    final flat = PanelStyleScope.isFlat(context);
    final summary = widget.showCurrentNode ? scene.summary : progress.mapKey;
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
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          expanded: expanded,
          child: TextButton(
            key: const Key('sortie-map-toggle'),
            onPressed: widget.onToggleExpanded,
            style: TextButton.styleFrom(
              foregroundColor: appColor(context, _teal),
              minimumSize: Size(0, flat ? 22 : 44),
              padding: flat
                  ? const EdgeInsets.symmetric(vertical: 2)
                  : const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: const RoundedRectangleBorder(),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                children: [
                  Icon(Icons.map_outlined, size: flat ? 13 : 14),
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
                            summary,
                            textAlign: TextAlign.end,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: appTextStyle(
                              context,
                              TextStyle(
                                color: appColor(context, _muted),
                                fontSize: flat ? flatSmallFontSize : 10,
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
                    size: flat ? 15 : 18,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (expanded)
          Container(
            key: const Key('sortie-map-body'),
            padding: flat
                ? const EdgeInsets.fromLTRB(0, 2, 0, 4)
                : const EdgeInsets.fromLTRB(9, 2, 9, 8),
            decoration: flat
                ? null
                : BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: appColor(context, const Color(0xff203746)),
                      ),
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
                          height: _MapProjection.canvasHeight(
                            scene.geometry!,
                            constraints.maxWidth,
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
    );
    if (flat) {
      // Still a Material so the toggle's ink has a surface to paint on.
      return Material(
        key: const Key('sortie-map-section'),
        type: MaterialType.transparency,
        child: content,
      );
    }
    return Material(
      key: const Key('sortie-map-section'),
      color: appColor(context, _background),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: content,
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
            painter: _MapPainter(
              scene,
              projection,
              AppPalette.of(context),
              Theme.of(context).textTheme.bodyMedium?.fontFamily,
            ),
          ),
          for (final entry in scene.geometry!.routes.entries)
            if (projection.routePaths[entry.key] case final path?)
              Positioned.fromRect(
                rect: path
                    .skip(1)
                    .fold<Rect>(
                      Rect.fromPoints(path.first, path.first),
                      (bounds, point) =>
                          bounds.expandToInclude(Rect.fromPoints(point, point)),
                    )
                    .inflate(3),
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
  static double canvasHeight(FcdMapGeometry geometry, double width) {
    final compact = (width * .44 + 16).clamp(125.0, 175.0);
    final nodes = geometry.spots.length;
    if (nodes <= 10) return compact;
    if (nodes >= 45 && width < 300) return width < 240 ? 320.0 : 280.0;
    return math.max(
      compact,
      nodes >= 30
          ? 240.0
          : nodes >= 18
          ? 210.0
          : 180.0,
    );
  }

  _MapProjection(FcdMapGeometry geometry, Size size) {
    final xs = geometry.spots.values.map((spot) => spot.x);
    final ys = geometry.spots.values.map((spot) => spot.y);
    final minX = xs.reduce(math.min);
    final minY = ys.reduce(math.min);
    final rangeX = xs.reduce(math.max) - minX;
    final rangeY = ys.reduce(math.max) - minY;
    // Use the available height on dense maps as well as the available width.
    // Each axis preserves the source ordering; no nodes or routes are invented.
    final scaleX = math.max(0, size.width - 40) / math.max(1, rangeX);
    final scaleY = math.max(0, size.height - 40) / math.max(1, rangeY);
    final origin = Offset(
      (size.width - rangeX * scaleX) / 2,
      (size.height - rangeY * scaleY) / 2,
    );
    points = {
      for (final entry in geometry.spots.entries)
        entry.key:
            origin +
            Offset(
              (entry.value.x - minX) * scaleX,
              (entry.value.y - minY) * scaleY,
            ),
    };
    routePaths = layoutSortieMapRoutes(
      routes: geometry.routes,
      points: points,
      canvas: size,
    );
    segments = [
      for (final path in routePaths.values)
        for (var index = 1; index < path.length; index++)
          (path[index - 1], path[index]),
    ];
  }

  late final Map<String, Offset> points;
  late final Map<int, List<Offset>> routePaths;
  late final List<(Offset, Offset)> segments;
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.scene, this.projection, this.palette, this.fontFamily);
  final _MapScene scene;
  final _MapProjection projection;
  final AppPalette palette;
  final String? fontFamily;

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = scene.geometry!;
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (final path in projection.routePaths.values) {
      for (var index = 1; index < path.length; index++) {
        canvas.drawLine(
          path[index - 1],
          path[index],
          paint
            ..color = palette.color(_edge.withValues(alpha: .55))
            ..strokeWidth = 1.1,
        );
      }
    }
    for (final id in scene.progress.routeIds) {
      final path = projection.routePaths[id];
      if (path == null) continue;
      for (var index = 1; index < path.length; index++) {
        canvas.drawLine(
          path[index - 1],
          path[index],
          paint
            ..color = palette.color(_teal)
            ..strokeWidth = 2.8,
        );
      }
    }
    final visited = scene.visited;
    final labels = <String, TextPainter>{};
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
            fontFamily: fontFamily,
            fontSize: 10,
            fontWeight: at ? FontWeight.w800 : FontWeight.w600,
            shadows: [Shadow(color: palette.color(_background), blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.max(0, size.width - 4));
      labels[entry.key] = label;
    }
    final labelBounds = layoutSortieMapLabels(
      points: projection.points,
      labelSizes: {
        for (final entry in labels.entries) entry.key: entry.value.size,
      },
      routes: projection.segments,
      canvas: size,
      current: scene.current,
      markerClearances: {
        for (final entry in geometry.spots.entries)
          entry.key: entry.key == scene.current
              ? 9.0
              : entry.key == scene.boss || entry.value.type == 'start'
              ? 5.5
              : 4.5,
      },
    );
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
      labels[node]!.paint(canvas, labelBounds[node]!.topLeft);
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) =>
      oldDelegate.fontFamily != fontFamily ||
      oldDelegate.palette.mode != palette.mode ||
      oldDelegate.scene.geometry != scene.geometry ||
      oldDelegate.scene.progress != scene.progress ||
      oldDelegate.scene.current != scene.current;
}
