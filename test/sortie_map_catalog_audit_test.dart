import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/battle/fcd_map_dataset.dart';
import 'package:yahagi_kancolle_browser/src/battle/fcd_map_geometry.dart';

// Override these when auditing an exported installed dataset. The default also
// verifies Flutter's bundled asset, so stale or missing asset packaging fails.
const _sourcePath = String.fromEnvironment(
  'FCD_MAP_AUDIT_PATH',
  defaultValue: 'assets/data/fcd/map.json',
);
const _reportPath = String.fromEnvironment('FCD_MAP_AUDIT_REPORT');
const _bundledPath = 'assets/data/fcd/map.json';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final raw = File(_sourcePath).readAsStringSync();
  final source = _object(jsonDecode(raw));
  final sourceMaps = _object(source['data']);
  final dataset = FcdMapDataset.parse(raw);
  final BattleMapGeometryResolver geometries = dataset;
  final mapIds = sourceMaps.keys.toList()..sort(_compareMapIds);

  test('map and route totals include every source record', () {
    final routes = sourceMaps.values.fold<int>(
      0,
      (total, map) => total + _object(_object(map)['route']).length,
    );
    expect(dataset.mapCount, sourceMaps.length);
    expect(dataset.routeCount, routes);
    expect(dataset.labels, hasLength(routes));
    expect(dataset.version.toString(), _object(source['meta'])['version']);
    expect(utf8.encode(raw).length, lessThanOrEqualTo(1024 * 1024));
  });

  if (_sourcePath == _bundledPath) {
    test('packaged map asset equals the audited source file', () async {
      expect(await rootBundle.loadString(_bundledPath), raw);
    });
  }

  test('every regular map in the bundled query catalog has geometry', () {
    final catalog = _object(
      jsonDecode(
        File('assets/data/sortie_map_catalog.json').readAsStringSync(),
      ),
    );
    final catalogMaps = catalog['maps'] as List;
    expect(catalogMaps, isNotEmpty);
    for (final rawMap in catalogMaps) {
      final id = _object(rawMap)['id'] as String;
      final (area, map) = _parseMapId(id);
      expect(sourceMaps, contains(id), reason: 'catalog map $id');
      expect(
        geometries.geometryFor(mapAreaId: area, mapInfoNo: map),
        isNotNull,
        reason: 'catalog map $id',
      );
    }
  });

  group('every source map preserves all geometry and route labels', () {
    for (final id in mapIds) {
      test(id, () {
        expect(id, matches(RegExp(r'^[1-9]\d*-[1-9]\d*$')));
        final (area, map) = _parseMapId(id);
        final sourceMap = _object(sourceMaps[id]);
        final rawSpots = _object(sourceMap['spots']);
        final rawRoutes = _object(sourceMap['route']);
        final geometry = geometries.geometryFor(
          mapAreaId: area,
          mapInfoNo: map,
        );
        expect(geometry, isNotNull, reason: '$id geometry was dropped');
        final actual = geometry!;
        expect(actual.spots.keys, unorderedEquals(rawSpots.keys));
        expect(
          actual.routes.keys,
          unorderedEquals(rawRoutes.keys.map(int.parse)),
        );

        for (final entry in rawSpots.entries) {
          final tuple = entry.value as List;
          expect(tuple, hasLength(3), reason: '$id spot ${entry.key}');
          final spot = actual.spots[entry.key]!;
          expect(spot.x, (tuple[0] as num).toDouble());
          expect(spot.y, (tuple[1] as num).toDouble());
          expect(spot.type, tuple[2]);
          expect(spot.x.isFinite && spot.y.isFinite, isTrue);
        }
        final xs = actual.spots.values.map((spot) => spot.x);
        final ys = actual.spots.values.map((spot) => spot.y);
        expect(xs.reduce(math.max) - xs.reduce(math.min), greaterThan(0));
        expect(ys.reduce(math.max) - ys.reduce(math.min), greaterThan(0));

        for (final entry in rawRoutes.entries) {
          final routeId = int.parse(entry.key);
          final endpoints = entry.value as List;
          final route = actual.routes[routeId]!;
          final reason = '$id route $routeId';
          expect(route.from, endpoints[0], reason: reason);
          expect(route.to, endpoints[1], reason: reason);
          expect(
            dataset.resolve(
              mapAreaId: area,
              mapInfoNo: map,
              internalNodeId: routeId,
            ),
            endpoints[1],
            reason: reason,
          );
          expect(actual.spots, contains(route.to), reason: reason);
          if (route.from case final from?) {
            expect(actual.spots, contains(from), reason: reason);
            final fromSpot = actual.spots[from]!;
            final toSpot = actual.spots[route.to]!;
            expect(
              fromSpot.x != toSpot.x || fromSpot.y != toSpot.y,
              isTrue,
              reason: '$reason has zero drawing length',
            );
          }
        }

        // A bounded graph traversal allows directed cycles, multiple roots and
        // repeated destinations, while detecting unconnected source geometry.
        final roots = actual.routes.values
            .where((route) => route.from == null)
            .map((route) => route.to)
            .toSet();
        expect(roots, isNotEmpty, reason: '$id has no starting route');
        final reached = _reachable(actual, roots);
        expect(
          actual.spots.keys.where((spot) => !reached.contains(spot)),
          isEmpty,
          reason: '$id contains nodes unreachable from any starting route',
        );
        expect(actual.routes[0]?.from, isNull);
        expect(actual.routes, contains(0));

        final absentRoute = actual.routes.keys.reduce(math.max) + 1;
        expect(
          dataset.resolve(
            mapAreaId: area,
            mapInfoNo: map,
            internalNodeId: absentRoute,
          ),
          isNull,
        );
      });
    }
  });

  test(
    'unknown map identifiers never borrow another map geometry or label',
    () {
      final futureArea =
          mapIds.map((id) => _parseMapId(id).$1).reduce(math.max) + 1;
      for (final (area, map) in <(int, int)>[
        (0, 1),
        (1, 0),
        (-1, 1),
        (futureArea, 1),
        (1, 999),
      ]) {
        expect(geometries.geometryFor(mapAreaId: area, mapInfoNo: map), isNull);
        expect(
          dataset.resolve(mapAreaId: area, mapInfoNo: map, internalNodeId: 1),
          isNull,
        );
      }
    },
  );

  test(
    'numeric, multiletter and Unicode names retain their literal meaning',
    () {
      final fixture = FcdMapDataset.parse(
        jsonEncode({
          'meta': {'name': 'map', 'version': '2026/10/18/01'},
          'data': {
            '63-1': {
              'spots': {
                '1': [0, 0, 'start'],
                '2': [0, 10, 'start'],
                'AA': [10, 0, ''],
                'ZII': [20, 10, ''],
                '\u03b1\u4e8c': [30, 0, ''],
              },
              'route': {
                '0': [null, '1'],
                '1': ['1', 'AA'],
                '2': ['AA', 'ZII'],
                '3': ['ZII', 'AA'],
                '4': ['ZII', '\u03b1\u4e8c'],
                '5': [null, '2'],
                '6': ['2', '\u03b1\u4e8c'],
              },
            },
          },
        }),
        minimumMapCount: 1,
      );
      final geometry = fixture.geometryFor(mapAreaId: 63, mapInfoNo: 1)!;
      expect(
        geometry.spots.keys,
        unorderedEquals(['1', '2', 'AA', 'ZII', '\u03b1\u4e8c']),
      );
      expect(geometry.routes[2]!.from, 'AA');
      expect(geometry.routes[2]!.to, 'ZII');
      expect(geometry.routes[3]!.from, 'ZII');
      expect(geometry.routes[3]!.to, 'AA');
      expect(geometry.routes[0]!.to, '1');
      expect(geometry.routes[5]!.to, '2');
      for (final routeId in [4, 6]) {
        expect(
          fixture.resolve(mapAreaId: 63, mapInfoNo: 1, internalNodeId: routeId),
          '\u03b1\u4e8c',
        );
      }
      expect(_reachable(geometry, {'1', '2'}), geometry.spots.keys.toSet());
    },
  );

  test('catalog audit records graph features and source marker anomalies', () {
    final report = _auditReport(dataset, sourceMaps, raw);
    if (_reportPath.isNotEmpty) {
      final reportFile = File(_reportPath);
      reportFile.parent.createSync(recursive: true);
      reportFile.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
    }
    expect(report['resolvedMaps'], sourceMaps.length);
  });
}

Map<String, dynamic> _object(Object? value) => value as Map<String, dynamic>;

(int, int) _parseMapId(String id) {
  final parts = id.split('-');
  return (int.parse(parts[0]), int.parse(parts[1]));
}

int _compareMapIds(String left, String right) {
  final a = _parseMapId(left);
  final b = _parseMapId(right);
  return a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2);
}

Set<String> _reachable(FcdMapGeometry geometry, Set<String> roots) {
  final adjacency = <String, List<String>>{};
  for (final route in geometry.routes.values) {
    if (route.from case final from?) {
      adjacency.putIfAbsent(from, () => []).add(route.to);
    }
  }
  final reached = <String>{};
  final pending = roots.toList();
  while (pending.isNotEmpty) {
    final node = pending.removeLast();
    if (reached.add(node)) pending.addAll(adjacency[node] ?? const []);
  }
  return reached;
}

bool _hasDirectedCycle(FcdMapGeometry geometry) {
  final adjacency = <String, List<String>>{};
  for (final route in geometry.routes.values) {
    if (route.from case final from?) {
      adjacency.putIfAbsent(from, () => []).add(route.to);
    }
  }
  final visiting = <String>{};
  final finished = <String>{};
  bool visit(String node) {
    if (finished.contains(node)) return false;
    if (!visiting.add(node)) return true;
    for (final to in adjacency[node] ?? const <String>[]) {
      if (visit(to)) return true;
    }
    visiting.remove(node);
    finished.add(node);
    return false;
  }

  return geometry.spots.keys.any(visit);
}

Map<String, Object?> _auditReport(
  FcdMapDataset dataset,
  Map<String, dynamic> sourceMaps,
  String raw,
) {
  var resolvedMaps = 0;
  var spotCount = 0;
  var startRouteCount = 0;
  final areas = <String, int>{};
  final mapIdsByArea = <String, List<String>>{};
  final features = <String, Map<String, Object?>>{
    'multipleStarts': {},
    'directedCycles': {},
    'reverseRoutePairs': {},
    'duplicateDirectedEdges': {},
    'repeatedDestinations': {},
    'multicharNames': {},
    'multiletterNames': {},
    'unicodeNames': {},
    'unreachableNodes': {},
    'startMarkerMismatch': {},
    'zeroLengthEdges': {},
  };
  for (final entry in sourceMaps.entries) {
    final id = entry.key;
    final (area, map) = _parseMapId(id);
    areas.update('$area', (value) => value + 1, ifAbsent: () => 1);
    mapIdsByArea.putIfAbsent('$area', () => []).add(id);
    final geometry = dataset.geometryFor(mapAreaId: area, mapInfoNo: map);
    if (geometry == null) continue;
    resolvedMaps++;
    spotCount += geometry.spots.length;
    final roots = <String>{};
    final starts = <String, String>{};
    final incoming = <String, List<int>>{};
    final byEndpoints = <(String?, String), List<int>>{};
    final zeroLength = <int>[];
    for (final edge in geometry.routes.entries) {
      final route = edge.value;
      incoming.putIfAbsent(route.to, () => []).add(edge.key);
      byEndpoints.putIfAbsent((route.from, route.to), () => []).add(edge.key);
      if (route.from == null) {
        starts['${edge.key}'] = route.to;
        roots.add(route.to);
      } else {
        final from = geometry.spots[route.from]!;
        final to = geometry.spots[route.to]!;
        if (from.x == to.x && from.y == to.y) zeroLength.add(edge.key);
      }
    }
    startRouteCount += starts.length;
    if (starts.length > 1) features['multipleStarts']![id] = starts;
    if (_hasDirectedCycle(geometry)) features['directedCycles']![id] = true;
    final reversePairs = <Map<String, Object?>>[];
    final duplicateEdges = <Map<String, Object?>>[];
    for (final edge in byEndpoints.entries) {
      final (from, to) = edge.key;
      if (edge.value.length > 1) {
        duplicateEdges.add({'from': from, 'to': to, 'routes': edge.value});
      }
      if (from == null) continue;
      final reverse = byEndpoints[(to, from)];
      if (from.compareTo(to) < 0 && reverse != null) {
        reversePairs.add({
          'from': from,
          'to': to,
          'forwardRoutes': edge.value,
          'reverseRoutes': reverse,
        });
      }
    }
    if (reversePairs.isNotEmpty) {
      features['reverseRoutePairs']![id] = reversePairs;
    }
    if (duplicateEdges.isNotEmpty) {
      features['duplicateDirectedEdges']![id] = duplicateEdges;
    }
    final repeated = Map<String, List<int>>.fromEntries(
      incoming.entries.where((entry) => entry.value.length > 1),
    );
    if (repeated.isNotEmpty) features['repeatedDestinations']![id] = repeated;
    final multichar = geometry.spots.keys
        .where((name) => name.length > 1)
        .toList();
    if (multichar.isNotEmpty) features['multicharNames']![id] = multichar;
    final multiletter = geometry.spots.keys
        .where((name) => RegExp(r'^[A-Za-z]{2,}$').hasMatch(name))
        .toList();
    if (multiletter.isNotEmpty) features['multiletterNames']![id] = multiletter;
    final unicode = geometry.spots.keys
        .where((name) => name.runes.any((rune) => rune > 127))
        .toList();
    if (unicode.isNotEmpty) features['unicodeNames']![id] = unicode;
    final reached = _reachable(geometry, roots);
    final unreachable = geometry.spots.keys
        .where((name) => !reached.contains(name))
        .toList();
    if (unreachable.isNotEmpty) features['unreachableNodes']![id] = unreachable;
    final typedStarts = geometry.spots.entries
        .where((entry) => entry.value.type == 'start')
        .map((entry) => entry.key)
        .toSet();
    if (roots.difference(typedStarts).isNotEmpty ||
        typedStarts.difference(roots).isNotEmpty) {
      features['startMarkerMismatch']![id] = {
        'nullSourceRouteDestinations': roots.toList(),
        'spotsTypedStart': typedStarts.toList(),
      };
    }
    if (zeroLength.isNotEmpty) features['zeroLengthEdges']![id] = zeroLength;
  }
  return {
    'source': _sourcePath,
    'sourceSha256': sha256.convert(utf8.encode(raw)).toString(),
    'version': dataset.version.toString(),
    'utf8Bytes': utf8.encode(raw).length,
    'sourceMaps': sourceMaps.length,
    'resolvedMaps': resolvedMaps,
    'routes': dataset.routeCount,
    'spots': spotCount,
    'nullSourceStartingRoutes': startRouteCount,
    'areas': areas,
    'mapIdsByArea': mapIdsByArea,
    'featureMapCounts': {
      for (final entry in features.entries) entry.key: entry.value.length,
    },
    'features': features,
    'scope':
        'Offline source/parser audit; does not establish live game map availability or actual sortie correctness.',
  };
}
