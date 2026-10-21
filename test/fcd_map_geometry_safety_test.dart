import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yahagi_kancolle_browser/src/battle/fcd_map_dataset.dart';
import 'package:yahagi_kancolle_browser/src/battle/fcd_map_store.dart';
import 'package:yahagi_kancolle_browser/src/battle/fcd_map_update_service.dart';

const _oldVersion = '2026/07/28/02';
const _newVersion = '2026/10/20/01';

Map<String, dynamic> _geometry({String destination = 'Y', int x = 300}) => {
  'route': {
    '0': [null, '1'],
    '42': ['1', destination],
  },
  'spots': {
    '1': [100, 200, 'start'],
    destination: [x, 400, ''],
  },
};

String _map({String version = _oldVersion, Map<String, dynamic>? maps}) =>
    jsonEncode({
      'meta': {'name': 'map', 'version': version},
      'data': maps ?? {'1-1': _geometry(), '5-6': _geometry()},
    });

String _metadata(String version) => jsonEncode([
  {'name': 'map', 'version': version},
]);

String _revise(
  String original, {
  String version = _newVersion,
  void Function(Map<String, dynamic> maps)? change,
}) {
  final decoded = jsonDecode(original) as Map<String, dynamic>;
  (decoded['meta'] as Map<String, dynamic>)['version'] = version;
  change?.call(decoded['data'] as Map<String, dynamic>);
  return jsonEncode(decoded);
}

FcdMapDataset _parse(String raw) =>
    FcdMapDataset.parse(raw, minimumMapCount: 1);

FcdMapUpdateService _service(
  _MemoryStorage storage,
  Future<http.Response> Function(http.Request) respond,
) => FcdMapUpdateService(
  client: MockClient(respond),
  store: FcdMapStore(storage, minimumMapCount: 1),
  minimumMapCount: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final removeAll in [false, true]) {
    test(
      'rejects bundled snapshot geometry loss (all maps: $removeAll)',
      () async {
        final original = await rootBundle.loadString(
          'assets/data/fcd/map.json',
        );
        final current = _parse(original);
        final maps =
            (jsonDecode(original) as Map<String, dynamic>)['data']
                as Map<String, dynamic>;
        expect(maps, hasLength(136));
        for (final key in maps.keys) {
          final ids = key.split('-').map(int.parse).toList();
          expect(
            current.geometryFor(mapAreaId: ids[0], mapInfoNo: ids[1]),
            isNotNull,
            reason: key,
          );
        }
        final damaged = _revise(
          original,
          change: (maps) {
            for (final entry in maps.entries) {
              if (removeAll || entry.key == '2-5') {
                (entry.value as Map<String, dynamic>).remove('spots');
              }
            }
          },
        );
        final storage = _MemoryStorage(original, cached: original);
        final service = _service(
          storage,
          (request) async => http.Response(
            request.url.path.endsWith('/meta.json')
                ? _metadata(_newVersion)
                : damaged,
            200,
          ),
        );

        final result = await service.checkAndUpdate(current: current);

        expect(result, isA<FcdMapUpdateFailed>());
        expect(
          (result as FcdMapUpdateFailed).kind,
          FcdMapUpdateFailure.validation,
        );
        expect(storage.cached, original);
        expect(storage.writeCount, 0);
        expect(current.geometryFor(mapAreaId: 2, mapInfoNo: 5), isNotNull);
      },
    );
  }

  final damage = <String, void Function(Map<String, dynamic>)>{
    'missing map': (maps) => maps.remove('5-6'),
    'map identity swap': (maps) => maps['9-1'] = maps.remove('5-6'),
    'missing spots': (maps) => (maps['5-6'] as Map).remove('spots'),
    'invalid coordinate': (maps) =>
        ((maps['5-6'] as Map)['spots'] as Map)['Y'] = ['bad', 400, ''],
    'missing endpoint': (maps) =>
        ((maps['5-6'] as Map)['spots'] as Map).remove('Y'),
    'unknown source endpoint': (maps) =>
        ((maps['5-6'] as Map)['route'] as Map)['42'] = ['missing', 'Y'],
    'infinite horizontal span': (maps) {
      final spots = (maps['5-6'] as Map)['spots'] as Map;
      spots['1'] = [-1e308, 200, 'start'];
      spots['Y'] = [1e308, 400, ''];
    },
    'infinite vertical span': (maps) {
      final spots = (maps['5-6'] as Map)['spots'] as Map;
      spots['1'] = [100, -1e308, 'start'];
      spots['Y'] = [300, 1e308, ''];
    },
  };
  for (final entry in damage.entries) {
    test('rejects ${entry.key} before cache replacement', () async {
      final original = _map();
      final damaged = _revise(original, change: entry.value);
      final storage = _MemoryStorage(original, cached: original);
      final service = _service(
        storage,
        (request) async => http.Response(
          request.url.path.endsWith('/meta.json')
              ? _metadata(_newVersion)
              : damaged,
          200,
        ),
      );

      final result = await service.checkAndUpdate(current: _parse(original));

      expect(result, isA<FcdMapUpdateFailed>());
      expect(
        (result as FcdMapUpdateFailed).kind,
        FcdMapUpdateFailure.validation,
      );
      expect(storage.cached, original);
      expect(storage.writeCount, 0);
    });
  }

  test(
    'uses a complete fallback source after rejecting geometry loss',
    () async {
      final original = _map();
      final damaged = _revise(original, change: damage['missing spots']);
      final repaired = _map(
        version: _newVersion,
        maps: {
          '1-1': _geometry(),
          '5-6': _geometry(destination: 'Z', x: 900),
        },
      );
      final storage = _MemoryStorage(original, cached: original);
      final hosts = <String>[];
      final service = _service(storage, (request) async {
        hosts.add(request.url.host);
        return http.Response(
          request.url.path.endsWith('/meta.json')
              ? _metadata(_newVersion)
              : request.url.host == 'raw.githubusercontent.com'
              ? damaged
              : repaired,
          200,
        );
      });

      final result = await service.checkAndUpdate(current: _parse(original));

      expect(result, isA<FcdMapUpdated>());
      final dataset = (result as FcdMapUpdated).dataset;
      expect(
        dataset.resolve(mapAreaId: 5, mapInfoNo: 6, internalNodeId: 42),
        'Z',
      );
      expect(
        dataset.geometryFor(mapAreaId: 5, mapInfoNo: 6)!.spots['Z']!.x,
        900,
      );
      expect(
        dataset.geometryFor(mapAreaId: 5, mapInfoNo: 6)!.spots['Y'],
        isNull,
      );
      expect(storage.cached, repaired);
      expect(storage.writeCount, 1);
      expect(hosts, [
        'raw.githubusercontent.com',
        'raw.githubusercontent.com',
        'cdn.jsdelivr.net',
        'cdn.jsdelivr.net',
      ]);
    },
  );

  test(
    'accepts a new map without geometry while protecting existing maps',
    () async {
      final original = _map();
      final candidate = _revise(
        original,
        change: (maps) {
          maps['9-1'] = {
            'route': {
              '1': ['A', 'B'],
            },
          };
        },
      );
      final storage = _MemoryStorage(original);
      final service = _service(
        storage,
        (request) async => http.Response(
          request.url.path.endsWith('/meta.json')
              ? _metadata(_newVersion)
              : candidate,
          200,
        ),
      );

      final result = await service.checkAndUpdate(current: _parse(original));

      expect(result, isA<FcdMapUpdated>());
      final dataset = (result as FcdMapUpdated).dataset;
      expect(dataset.geometryFor(mapAreaId: 5, mapInfoNo: 6), isNotNull);
      expect(dataset.geometryFor(mapAreaId: 9, mapInfoNo: 1), isNull);
      expect(
        dataset.resolve(mapAreaId: 9, mapInfoNo: 1, internalNodeId: 1),
        'B',
      );
    },
  );

  test('keeps equal-version healthy geometry checks metadata-only', () async {
    final original = _map();
    final storage = _MemoryStorage(original);
    var requests = 0;
    final service = _service(storage, (request) async {
      requests++;
      expect(request.url.path, endsWith('/meta.json'));
      return http.Response(_metadata(_oldVersion), 200);
    });

    expect(
      await service.checkAndUpdate(current: _parse(original)),
      isA<FcdMapUpToDate>(),
    );
    expect(requests, 1);
    expect(storage.writeCount, 0);
  });

  test(
    'keeps legacy labels-only updates and equal-version checks valid',
    () async {
      final original = _map(
        maps: {
          '5-6': {
            'route': {
              '42': ['X', 'Y'],
            },
          },
        },
      );
      final candidate = _revise(original);
      final storage = _MemoryStorage(original);
      var requests = 0;
      final service = _service(storage, (request) async {
        requests++;
        return http.Response(
          request.url.path.endsWith('/meta.json')
              ? _metadata(_newVersion)
              : candidate,
          200,
        );
      });

      final updated = await service.checkAndUpdate(current: _parse(original));
      expect(updated, isA<FcdMapUpdated>());
      final dataset = (updated as FcdMapUpdated).dataset;
      expect(dataset.geometryFor(mapAreaId: 5, mapInfoNo: 6), isNull);
      expect(
        await service.checkAndUpdate(current: dataset),
        isA<FcdMapUpToDate>(),
      );
      expect(requests, 3);
    },
  );

  for (final version in [_oldVersion, _newVersion]) {
    test(
      'falls back from a geometry-losing cache at version $version',
      () async {
        final original = _map();
        final damaged = _revise(
          original,
          version: version,
          change: damage['missing spots'],
        );
        final storage = _MemoryStorage(original, cached: damaged);

        final loaded = await FcdMapStore(
          storage,
          minimumMapCount: 1,
        ).loadBestAvailable();

        expect(loaded.source, FcdMapSource.bundled);
        expect(loaded.dataset.rawJson, original);
        expect(loaded.diagnosticError, contains('cache'));
        expect(storage.cached, damaged);
        expect(storage.writeCount, 0);
      },
    );
  }

  test(
    'restart recovers bad newer cache and replaces it with repaired remote',
    () async {
      final original = await rootBundle.loadString('assets/data/fcd/map.json');
      final damaged = _revise(
        original,
        change: (maps) {
          for (final value in maps.values) {
            (value as Map).remove('spots');
          }
        },
      );
      final repaired = _revise(original);
      final storage = _MemoryStorage(original, cached: damaged);
      final store = FcdMapStore(storage);
      final loaded = await store.loadBestAvailable();
      expect(loaded.source, FcdMapSource.bundled);
      final service = _service(
        storage,
        (request) async => http.Response(
          request.url.path.endsWith('/meta.json')
              ? _metadata(_newVersion)
              : repaired,
          200,
        ),
      );

      final result = await service.checkAndUpdate(current: loaded.dataset);

      expect(result, isA<FcdMapUpdated>());
      expect(storage.cached, repaired);
      final reloaded = await store.loadBestAvailable();
      expect(reloaded.source, FcdMapSource.cache);
      expect(
        reloaded.dataset.geometryFor(mapAreaId: 2, mapInfoNo: 5),
        isNotNull,
      );
      expect(reloaded.dataset.version.toString(), _newVersion);
    },
  );

  test(
    'repairs an already active degraded dataset at the same remote version',
    () async {
      final original = _map();
      final damaged = _revise(original, change: damage['missing spots']);
      final repaired = _revise(original);
      final storage = _MemoryStorage(original, cached: damaged);
      var requests = 0;
      final service = _service(storage, (request) async {
        requests++;
        return http.Response(
          request.url.path.endsWith('/meta.json')
              ? _metadata(_newVersion)
              : repaired,
          200,
        );
      });

      final result = await service.checkAndUpdate(current: _parse(damaged));

      expect(result, isA<FcdMapUpdated>());
      expect(
        (result as FcdMapUpdated).dataset.geometryFor(
          mapAreaId: 5,
          mapInfoNo: 6,
        ),
        isNotNull,
      );
      expect(storage.cached, repaired);
      expect(requests, 2);
      expect(
        await service.checkAndUpdate(current: result.dataset),
        isA<FcdMapUpToDate>(),
      );
      expect(requests, 3);
    },
  );

  test(
    'rejects same-version repair that still loses bundled geometry',
    () async {
      final original = _map();
      final damaged = _revise(original, change: damage['missing spots']);
      final storage = _MemoryStorage(original, cached: damaged);
      final service = _service(
        storage,
        (request) async => http.Response(
          request.url.path.endsWith('/meta.json')
              ? _metadata(_newVersion)
              : damaged,
          200,
        ),
      );

      final result = await service.checkAndUpdate(current: _parse(damaged));

      expect(result, isA<FcdMapUpdateFailed>());
      expect(
        (result as FcdMapUpdateFailed).kind,
        FcdMapUpdateFailure.validation,
      );
      expect(storage.cached, damaged);
      expect(storage.writeCount, 0);
    },
  );

  test(
    'same-version repair must also retain maps introduced since the bundle',
    () async {
      final original = _map();
      final damaged = _revise(
        original,
        change: (maps) {
          damage['missing spots']!(maps);
          maps['9-1'] = _geometry();
        },
      );
      final storage = _MemoryStorage(original, cached: damaged);
      final service = _service(
        storage,
        (request) async => http.Response(
          request.url.path.endsWith('/meta.json')
              ? _metadata(_newVersion)
              : _revise(original),
          200,
        ),
      );

      expect(
        await service.checkAndUpdate(current: _parse(damaged)),
        isA<FcdMapUpdateFailed>(),
      );
      expect(storage.cached, damaged);
    },
  );

  test(
    'a repair cannot downgrade an already active degraded dataset',
    () async {
      final original = _map();
      final damaged = _revise(original, change: damage['missing spots']);
      final storage = _MemoryStorage(original, cached: damaged);
      var requests = 0;
      final service = _service(storage, (request) async {
        requests++;
        expect(request.url.path, endsWith('/meta.json'));
        return http.Response(_metadata(_oldVersion), 200);
      });

      expect(
        await service.checkAndUpdate(current: _parse(damaged)),
        isA<FcdMapUpdateFailed>(),
      );
      expect(requests, 2);
      expect(storage.cached, damaged);
    },
  );

  test(
    'a broken bundle does not block updates protected by current geometry',
    () async {
      final original = _map();
      final candidate = _revise(original);
      final storage = _MemoryStorage('{broken', cached: original);
      final service = _service(
        storage,
        (request) async => http.Response(
          request.url.path.endsWith('/meta.json')
              ? _metadata(_newVersion)
              : candidate,
          200,
        ),
      );

      expect(
        await service.checkAndUpdate(current: _parse(original)),
        isA<FcdMapUpdated>(),
      );
      expect(storage.cached, candidate);
    },
  );

  test(
    'protects every bundled map identity when its geometry alone is lost',
    () async {
      final original = await rootBundle.loadString('assets/data/fcd/map.json');
      final current = _parse(original);
      final maps =
          (jsonDecode(original) as Map<String, dynamic>)['data'] as Map;
      expect(maps, hasLength(136));
      for (final key in maps.keys.cast<String>()) {
        final damaged = _revise(
          original,
          change: (maps) {
            (maps[key] as Map).remove('spots');
          },
        );
        final storage = _MemoryStorage(original, cached: original);
        final service = _service(
          storage,
          (request) async => http.Response(
            request.url.path.endsWith('/meta.json')
                ? _metadata(_newVersion)
                : damaged,
            200,
          ),
        );

        final result = await service.checkAndUpdate(current: current);

        expect(result, isA<FcdMapUpdateFailed>(), reason: key);
        expect(storage.cached, original, reason: key);
        expect(storage.writeCount, 0, reason: key);
      }
    },
  );
}

final class _MemoryStorage implements FcdMapStorage {
  _MemoryStorage(this.bundled, {this.cached});

  final String bundled;
  String? cached;
  int writeCount = 0;

  @override
  Future<String> readBundled() async => bundled;

  @override
  Future<String?> readCached() async => cached;

  @override
  Future<void> writeCached(String rawJson) async {
    writeCount++;
    cached = rawJson;
  }
}
