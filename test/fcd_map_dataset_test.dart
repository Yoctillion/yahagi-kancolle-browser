import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/battle/fcd_map_dataset.dart';
import 'package:yahagi_kancolle_browser/src/battle/fcd_map_geometry.dart';

String _datasetJson({
  String version = '2026/07/28/02',
  Map<String, Object?>? data,
}) => jsonEncode(<String, Object?>{
  'meta': <String, Object?>{'name': 'map', 'version': version},
  'data':
      data ??
      <String, Object?>{
        '5-6': <String, Object?>{
          'route': <String, Object?>{
            '42': <Object?>['X', 'Y'],
            '43': <Object?>['Y', 'A1'],
            '44': <Object?>['A1', 'AA'],
            '45': <Object?>['AA', 'ZZ'],
          },
        },
      },
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled POI snapshot parses and resolves a real route', () async {
    final raw = await rootBundle.loadString('assets/data/fcd/map.json');
    final dataset = FcdMapDataset.parse(raw);

    expect(dataset.version.toString(), '2026/07/28/02');
    expect(dataset.mapCount, greaterThan(50));
    expect(dataset.routeCount, greaterThan(1000));
    expect(
      dataset.resolve(mapAreaId: 5, mapInfoNo: 6, internalNodeId: 42),
      'Y',
    );
  });

  test(
    'bundled POI geometry retains real 2-5 routes and numeric start',
    () async {
      final raw = await rootBundle.loadString('assets/data/fcd/map.json');
      final dataset = FcdMapDataset.parse(raw);
      final BattleMapGeometryResolver resolver = dataset;
      final geometry = resolver.geometryFor(mapAreaId: 2, mapInfoNo: 5);
      expect(geometry, isNotNull);
      expect(geometry!.spots, hasLength(16));
      expect(geometry.routes, hasLength(21));
      expect(geometry.routes[15]!.from, 'I');
      expect(geometry.routes[15]!.to, 'O');
      expect(geometry.routes[0]!.from, isNull);
      expect(geometry.routes[0]!.to, '1');
      expect(geometry.spots['1']!.type, 'start');
      expect(geometry.spots['1']!.x, 178.0);
      expect(geometry.spots['1']!.y, 384.0);
      expect(geometry.spots['O']!.x, 1031.0);
      expect(geometry.spots['O']!.y, 288.0);
      expect(() => geometry.routes.clear(), throwsUnsupportedError);
      expect(() => geometry.spots.clear(), throwsUnsupportedError);
      expect(dataset.geometryFor(mapAreaId: 999, mapInfoNo: 1), isNull);
    },
  );

  test('labels-only fixtures remain usable without fabricated geometry', () {
    final dataset = FcdMapDataset.parse(_datasetJson(), minimumMapCount: 1);

    expect(dataset.geometryFor(mapAreaId: 5, mapInfoNo: 6), isNull);
    expect(
      dataset.resolve(mapAreaId: 5, mapInfoNo: 6, internalNodeId: 42),
      'Y',
    );
  });

  test('invalid geometry disables only that map and preserves its labels', () {
    final invalidMaps = <String, Map<String, Object?>>{
      'missing spots': _geometryMap()..remove('spots'),
      'non-object spots': _geometryMap()..['spots'] = <Object?>[],
      'empty spots': _geometryMap()..['spots'] = <String, Object?>{},
      'invalid spot tuple': _geometryMap()
        ..['spots'] = <String, Object?>{
          '1': <Object?>[100, 200, 'start'],
          'Y': <Object?>[300, 400],
        },
      'string coordinate': _geometryMap()
        ..['spots'] = <String, Object?>{
          '1': <Object?>[100, 200, 'start'],
          'Y': <Object?>['300', 400, ''],
        },
      'null coordinate': _geometryMap()
        ..['spots'] = <String, Object?>{
          '1': <Object?>[100, 200, 'start'],
          'Y': <Object?>[300, null, ''],
        },
      'invalid spot type': _geometryMap()
        ..['spots'] = <String, Object?>{
          '1': <Object?>[100, 200, 'start'],
          'Y': <Object?>[300, 400, 9],
        },
      'missing endpoint': _geometryMap()
        ..['spots'] = <String, Object?>{
          '1': <Object?>[100, 200, 'start'],
        },
      'invalid route source': _geometryMap()
        ..['route'] = <String, Object?>{
          '42': <Object?>[false, 'Y'],
        },
      'unknown route source': _geometryMap()
        ..['route'] = <String, Object?>{
          '42': <Object?>['unknown', 'Y'],
        },
    };

    for (final invalid in invalidMaps.entries) {
      final dataset = FcdMapDataset.parse(
        _datasetJson(
          data: <String, Object?>{'5-6': invalid.value, '1-1': _geometryMap()},
        ),
        minimumMapCount: 1,
      );
      expect(
        dataset.geometryFor(mapAreaId: 5, mapInfoNo: 6),
        isNull,
        reason: invalid.key,
      );
      expect(
        dataset.resolve(mapAreaId: 5, mapInfoNo: 6, internalNodeId: 42),
        'Y',
        reason: invalid.key,
      );
      expect(
        dataset.geometryFor(mapAreaId: 1, mapInfoNo: 1),
        isNotNull,
        reason: invalid.key,
      );
    }
  });

  test('non-finite coordinates preserve labels without map geometry', () {
    final raw = _datasetJson(
      data: <String, Object?>{'5-6': _geometryMap()},
    ).replaceFirst('300', '1e400');
    final dataset = FcdMapDataset.parse(raw, minimumMapCount: 1);

    expect(dataset.geometryFor(mapAreaId: 5, mapInfoNo: 6), isNull);
    expect(
      dataset.resolve(mapAreaId: 5, mapInfoNo: 6, internalNodeId: 42),
      'Y',
    );
  });

  test('finite coordinates with infinite spans preserve only labels', () {
    for (final axis in [0, 1]) {
      final map = _geometryMap();
      final spots = map['spots']! as Map<String, Object?>;
      (spots['1']! as List<Object?>)[axis] = -1e308;
      (spots['Y']! as List<Object?>)[axis] = 1e308;
      final dataset = FcdMapDataset.parse(
        _datasetJson(data: {'5-6': map}),
        minimumMapCount: 1,
      );

      expect(dataset.geometryFor(mapAreaId: 5, mapInfoNo: 6), isNull);
      expect(
        dataset.resolve(mapAreaId: 5, mapInfoNo: 6, internalNodeId: 42),
        'Y',
      );
    }
  });

  test('compares validated FCD versions by numeric segments', () {
    final older = FcdMapVersion.parse('2026/07/28/02');
    final newerRevision = FcdMapVersion.parse('2026/07/28/10');
    final newerDay = FcdMapVersion.parse('2026/07/29/01');

    expect(older.toString(), '2026/07/28/02');
    expect(older.compareTo(newerRevision), lessThan(0));
    expect(newerRevision.compareTo(newerDay), lessThan(0));
    expect(() => FcdMapVersion.parse('2026/02/30/01'), throwsFormatException);
    expect(() => FcdMapVersion.parse('v2026/07/28/02'), throwsFormatException);
  });

  test('resolves route destinations instead of alphabetizing internal ids', () {
    final dataset = FcdMapDataset.parse(_datasetJson(), minimumMapCount: 1);

    expect(dataset.version.toString(), '2026/07/28/02');
    expect(
      dataset.resolve(mapAreaId: 5, mapInfoNo: 6, internalNodeId: 42),
      'Y',
    );
    expect(
      dataset.resolve(mapAreaId: 5, mapInfoNo: 6, internalNodeId: 43),
      'A1',
    );
    expect(
      dataset.resolve(mapAreaId: 5, mapInfoNo: 6, internalNodeId: 44),
      'AA',
    );
    expect(
      dataset.resolve(mapAreaId: 5, mapInfoNo: 6, internalNodeId: 45),
      'ZZ',
    );
    expect(
      dataset.resolve(mapAreaId: 5, mapInfoNo: 6, internalNodeId: 99),
      isNull,
    );
  });

  test('rejects malformed or unsafe FCD datasets', () {
    final cases = <String>[
      '{}',
      jsonEncode(<String, Object?>{
        'meta': <String, Object?>{
          'name': 'shiptag',
          'version': '2026/07/28/02',
        },
        'data': <String, Object?>{},
      }),
      _datasetJson(data: <String, Object?>{}),
      _datasetJson(
        data: <String, Object?>{
          'bad-map-key': <String, Object?>{
            'route': <String, Object?>{
              '1': <Object?>['A', 'B'],
            },
          },
        },
      ),
      _datasetJson(
        data: <String, Object?>{
          '5-6': <String, Object?>{
            'route': <String, Object?>{
              '42': <Object?>['X'],
            },
          },
        },
      ),
      _datasetJson(
        data: <String, Object?>{
          '5-6': <String, Object?>{
            'route': <String, Object?>{
              '42': <Object?>['X', ''],
            },
          },
        },
      ),
    ];

    for (final raw in cases) {
      expect(
        () => FcdMapDataset.parse(raw, minimumMapCount: 1),
        throwsFormatException,
        reason: raw,
      );
    }
  });

  test('rejects a response larger than the configured limit', () {
    final raw = _datasetJson();
    expect(
      () => FcdMapDataset.parse(
        raw,
        maxBytes: utf8.encode(raw).length - 1,
        minimumMapCount: 1,
      ),
      throwsFormatException,
    );
  });

  test('rejects severely incomplete or route-empty update datasets', () {
    expect(() => FcdMapDataset.parse(_datasetJson()), throwsFormatException);
    final emptyRoutes = <String, Object?>{
      for (var index = 1; index <= 50; index++)
        '1-$index': <String, Object?>{'route': <String, Object?>{}},
    };
    expect(
      () => FcdMapDataset.parse(_datasetJson(data: emptyRoutes)),
      throwsFormatException,
    );
  });
}

Map<String, Object?> _geometryMap() => <String, Object?>{
  'route': <String, Object?>{
    '0': <Object?>[null, '1'],
    '42': <Object?>['1', 'Y'],
  },
  'spots': <String, Object?>{
    '1': <Object?>[100, 200, 'start'],
    'Y': <Object?>[300, 400, ''],
  },
};
