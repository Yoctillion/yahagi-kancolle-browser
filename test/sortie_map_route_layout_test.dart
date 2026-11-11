import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/battle/fcd_map_geometry.dart';
import 'package:yahagi_kancolle_browser/src/battle/sortie_map_route_layout.dart';

void main() {
  const canvas = Size(100, 100);

  test('unobstructed routes retain their original straight segment', () {
    const points = {
      'A': Offset(10, 50),
      'B': Offset(90, 50),
      'C': Offset(50, 80),
    };
    final paths = layoutSortieMapRoutes(
      routes: const {7: FcdMapRoute(from: 'A', to: 'B')},
      points: points,
      canvas: canvas,
    );

    expect(paths.keys, [7]);
    expect(paths[7], [points['A'], points['B']]);
    _expectClearPath(paths[7]!, points, 'A', 'B', canvas);
  });

  test(
    'blocked routes detour without moving endpoints or crossing markers',
    () {
      const points = {
        'A': Offset(10, 50),
        'B': Offset(90, 50),
        'C': Offset(50, 50),
      };
      final paths = layoutSortieMapRoutes(
        routes: const {7: FcdMapRoute(from: 'A', to: 'B')},
        points: points,
        canvas: canvas,
      );

      expect(paths[7]!.length, greaterThan(2));
      _expectClearPath(paths[7]!, points, 'A', 'B', canvas);
    },
  );

  test('duplicate endpoints reuse a path and reverse routes reverse it', () {
    const points = {
      'A': Offset(10, 50),
      'B': Offset(90, 50),
      'C': Offset(50, 50),
    };
    final paths = layoutSortieMapRoutes(
      routes: const {
        3: FcdMapRoute(from: 'A', to: 'B'),
        7: FcdMapRoute(from: 'A', to: 'B'),
        11: FcdMapRoute(from: 'B', to: 'A'),
      },
      points: points,
      canvas: canvas,
    );

    expect(paths.keys, [3, 7, 11]);
    expect(identical(paths[3], paths[7]), isTrue);
    expect(paths[11], orderedEquals(paths[3]!.reversed));
    _expectClearPath(paths[3]!, points, 'A', 'B', canvas);
    _expectClearPath(paths[11]!, points, 'B', 'A', canvas);
  });

  test('detours avoid additional obstacles outside the original segment', () {
    const points = {
      'A': Offset(10, 50),
      'B': Offset(90, 50),
      'C': Offset(50, 50),
      'D': Offset(50, 40),
      'E': Offset(50, 60),
    };
    // D and E do not obstruct A-B, but they block a short detour around C.
    // A valid route therefore needs to account for more than the first blocker.
    for (final label in ['D', 'E']) {
      expect(
        _distanceToSegment(points[label]!, points['A']!, points['B']!),
        greaterThan(6.6),
      );
    }
    final paths = layoutSortieMapRoutes(
      routes: const {7: FcdMapRoute(from: 'A', to: 'B')},
      points: points,
      canvas: canvas,
    );

    expect(paths[7]!.length, greaterThan(2));
    _expectClearPath(paths[7]!, points, 'A', 'B', canvas);
  });

  test('null sources and missing endpoint positions do not create paths', () {
    const points = {'A': Offset(10, 50), 'B': Offset(90, 50)};
    final paths = layoutSortieMapRoutes(
      routes: const {
        0: FcdMapRoute(from: null, to: 'A'),
        1: FcdMapRoute(from: 'missing', to: 'B'),
        2: FcdMapRoute(from: 'A', to: 'missing'),
        3: FcdMapRoute(from: 'A', to: 'B'),
      },
      points: points,
      canvas: canvas,
    );

    expect(paths.keys, [3]);
    expect(paths[3], [points['A'], points['B']]);
  });

  test(
    'an unavoidable marker covering an endpoint safely retains endpoints',
    () {
      const points = {
        'A': Offset(10, 50),
        'B': Offset(90, 50),
        'C': Offset(10, 50),
      };
      final paths = layoutSortieMapRoutes(
        routes: const {7: FcdMapRoute(from: 'A', to: 'B')},
        points: points,
        canvas: canvas,
      );

      expect(paths[7], [points['A'], points['B']]);
      expect(paths[7]!.every((point) => point.isFinite), isTrue);
    },
  );

  test('coincident route endpoints safely retain their finite positions', () {
    const points = {
      'A': Offset(10, 50),
      'B': Offset(10, 50),
      'C': Offset(90, 50),
    };
    final paths = layoutSortieMapRoutes(
      routes: const {7: FcdMapRoute(from: 'A', to: 'B')},
      points: points,
      canvas: canvas,
    );

    expect(paths[7], [points['A'], points['B']]);
    expect(paths[7]!.every((point) => point.isFinite), isTrue);
  });

  test('an empty canvas safely retains finite route endpoints', () {
    const points = {
      'A': Offset(10, 50),
      'B': Offset(90, 50),
      'C': Offset(50, 50),
    };
    final paths = layoutSortieMapRoutes(
      routes: const {7: FcdMapRoute(from: 'A', to: 'B')},
      points: points,
      canvas: Size.zero,
    );

    expect(paths[7], [points['A'], points['B']]);
    expect(paths[7]!.every((point) => point.isFinite), isTrue);
  });
}

void _expectClearPath(
  List<Offset> path,
  Map<String, Offset> points,
  String from,
  String to,
  Size canvas,
) {
  expect(path.length, greaterThanOrEqualTo(2));
  expect(path.first, points[from]);
  expect(path.last, points[to]);
  for (final vertex in path) {
    expect(vertex.isFinite, isTrue);
    expect(vertex.dx, inInclusiveRange(0, canvas.width));
    expect(vertex.dy, inInclusiveRange(0, canvas.height));
  }
  for (var index = 1; index < path.length; index++) {
    for (final entry in points.entries) {
      if (entry.key == from || entry.key == to) continue;
      expect(
        _distanceToSegment(entry.value, path[index - 1], path[index]),
        greaterThanOrEqualTo(6.6 - 1e-8),
        reason: '$from-$to segment $index must clear ${entry.key}',
      );
    }
  }
}

double _distanceToSegment(Offset point, Offset from, Offset to) {
  final delta = to - from;
  final relative = point - from;
  final dot = relative.dx * delta.dx + relative.dy * delta.dy;
  if (dot <= 0 || delta.distanceSquared == 0) return relative.distance;
  if (dot >= delta.distanceSquared) return (point - to).distance;
  return (relative.dx * delta.dy - relative.dy * delta.dx).abs() /
      delta.distance;
}
