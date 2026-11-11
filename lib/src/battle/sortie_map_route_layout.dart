import 'dart:math' as math;
import 'dart:ui';

import 'fcd_map_geometry.dart';

/// Keeps source endpoints while routing around unrelated node markers.
///
/// Straight routes stay straight. The returned vertices are shared by route
/// painting, label placement and geometry audits, so none infer extra edges.
Map<int, List<Offset>> layoutSortieMapRoutes({
  required Map<int, FcdMapRoute> routes,
  required Map<String, Offset> points,
  required Size canvas,
  double clearance = 6.6,
}) {
  final paths = <int, List<Offset>>{};
  final cache = <(String, String), List<Offset>>{};
  for (final entry in routes.entries) {
    final route = entry.value;
    final source = route.from;
    final destination = route.to;
    if (source == null) continue;
    final reverse = source.compareTo(destination) > 0;
    final key = reverse ? (destination, source) : (source, destination);
    var path = cache[key];
    if (path == null) {
      final from = points[key.$1];
      final to = points[key.$2];
      if (from == null || to == null) continue;
      final obstacles = [
        for (final point in points.entries)
          if (point.key != key.$1 &&
              point.key != key.$2 &&
              point.value.isFinite)
            point.value,
      ];
      path = List<Offset>.unmodifiable(
        _routePath(from, to, obstacles, canvas, clearance),
      );
      cache[key] = path;
    }
    paths[entry.key] = reverse
        ? List<Offset>.unmodifiable(path.reversed)
        : path;
  }
  return Map<int, List<Offset>>.unmodifiable(paths);
}

List<Offset> _routePath(
  Offset from,
  Offset to,
  List<Offset> obstacles,
  Size canvas,
  double clearance,
) {
  final straight = [from, to];
  if (!from.isFinite ||
      !to.isFinite ||
      from == to ||
      !canvas.isFinite ||
      canvas.width <= 0 ||
      canvas.height <= 0 ||
      !clearance.isFinite ||
      clearance <= 0) {
    return straight;
  }
  final radiusSquared = clearance * clearance;
  final blocking = [
    for (final point in obstacles)
      if (_segmentDistanceSquared(point, from, to) < radiusSquared) point,
  ];
  if (blocking.isEmpty) return straight;

  // Coincident or tightly overlapping markers can enclose a source endpoint.
  // No path can clear that marker without moving the endpoint itself.
  if (obstacles.any(
    (point) =>
        (point - from).distanceSquared < radiusSquared ||
        (point - to).distanceSquared < radiusSquared,
  )) {
    return straight;
  }
  final local = _shortestPath(from, to, blocking, obstacles, canvas, clearance);
  if (local != null) return local;
  // A detour may meet a marker that did not block the original straight line.
  // Expand the graph only for these uncommon crowded routes.
  if (blocking.length != obstacles.length) {
    final expanded = _shortestPath(
      from,
      to,
      obstacles,
      obstacles,
      canvas,
      clearance,
    );
    if (expanded != null) return expanded;
  }
  return straight;
}

List<Offset>? _shortestPath(
  Offset from,
  Offset to,
  List<Offset> detours,
  List<Offset> obstacles,
  Size canvas,
  double clearance,
) {
  final radiusSquared = clearance * clearance;
  // Square corners have clearance along their connecting sides as well as at
  // their vertices. The extra margin avoids unstable floating-point tangents.
  final radius = clearance + .25;
  final vertices = <Offset>[from, to];
  final seen = <Offset>{from, to};
  for (final obstacle in detours) {
    for (final dx in [-radius, radius]) {
      for (final dy in [-radius, radius]) {
        final point = obstacle + Offset(dx, dy);
        if (point.dx < 0 ||
            point.dy < 0 ||
            point.dx > canvas.width ||
            point.dy > canvas.height ||
            seen.contains(point) ||
            obstacles.any(
              (other) => (other - point).distanceSquared < radiusSquared,
            )) {
          continue;
        }
        seen.add(point);
        vertices.add(point);
      }
    }
  }
  final distances = List<double>.filled(vertices.length, double.infinity);
  final previous = List<int>.filled(vertices.length, -1);
  final visited = List<bool>.filled(vertices.length, false);
  distances[0] = 0;
  for (var step = 0; step < vertices.length; step++) {
    var nearest = -1;
    for (var index = 0; index < vertices.length; index++) {
      if (!visited[index] &&
          distances[index].isFinite &&
          (nearest == -1 || distances[index] < distances[nearest])) {
        nearest = index;
      }
    }
    if (nearest == -1) return null;
    if (nearest == 1) {
      final path = <Offset>[];
      for (var index = 1; index != -1; index = previous[index]) {
        path.add(vertices[index]);
      }
      return path.reversed.toList();
    }
    visited[nearest] = true;
    final start = vertices[nearest];
    for (var index = 0; index < vertices.length; index++) {
      if (visited[index]) continue;
      final end = vertices[index];
      final distance = distances[nearest] + (end - start).distance;
      if (distance >= distances[index]) continue;
      if (obstacles.any(
        (point) => _segmentDistanceSquared(point, start, end) < radiusSquared,
      )) {
        continue;
      }
      distances[index] = distance;
      previous[index] = nearest;
    }
  }
  return null;
}

double _segmentDistanceSquared(Offset point, Offset from, Offset to) {
  final delta = to - from;
  final lengthSquared = delta.distanceSquared;
  if (lengthSquared == 0) return (point - from).distanceSquared;
  final relative = point - from;
  final fraction =
      ((relative.dx * delta.dx + relative.dy * delta.dy) / lengthSquared).clamp(
        0.0,
        1.0,
      );
  final nearest = from + delta * fraction;
  final distance = (point - nearest).distanceSquared;
  return math.max(0, distance);
}
