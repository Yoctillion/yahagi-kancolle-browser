import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yahagi_kancolle_browser/src/battle/fcd_map_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/fcd_map_dataset.dart';
import 'package:yahagi_kancolle_browser/src/battle/fcd_map_store.dart';
import 'package:yahagi_kancolle_browser/src/battle/fcd_map_update_service.dart';

void main() {
  final bundled = File('assets/data/fcd/map.json').readAsStringSync();
  final source = jsonDecode(bundled) as Map<String, dynamic>;
  final sourceMaps = source['data'] as Map<String, dynamic>;
  final sourceVersion = FcdMapVersion.parse(
    (source['meta'] as Map<String, dynamic>)['version'] as String,
  );
  final remoteVersion = sourceVersion.toString().replaceRange(11, 13, '99');

  for (final removeAll in [false, true]) {
    test(
      'controller retains all bundled maps after ${removeAll ? 'all maps lose' : '2-5 loses'} geometry and accepts a repaired update',
      () async {
        final current = FcdMapDataset.parse(bundled);
        final oldGeometry = current.geometryFor(mapAreaId: 2, mapInfoNo: 5)!;
        final updated = jsonDecode(bundled) as Map<String, dynamic>;
        (updated['meta'] as Map<String, dynamic>)['version'] = remoteVersion;
        final repaired = jsonEncode(updated);
        for (final entry in (updated['data'] as Map<String, dynamic>).entries) {
          if (removeAll || entry.key == '2-5') {
            (entry.value as Map<String, dynamic>).remove('spots');
          }
        }
        final incomplete = jsonEncode(updated);
        final storage = _MemoryStorage(bundled);
        final store = FcdMapStore(storage);
        final requests = <Uri>[];
        var upstreamRepaired = false;
        final client = MockClient((request) async {
          requests.add(request.url);
          if (request.url.path.endsWith('/meta.json')) {
            return http.Response(
              jsonEncode([
                {'name': 'map', 'version': remoteVersion},
              ]),
              200,
            );
          }
          return http.Response(upstreamRepaired ? repaired : incomplete, 200);
        });
        addTearDown(client.close);
        final controller = FcdMapController(
          dataset: current,
          updater: FcdMapUpdateService(client: client, store: store),
        );
        addTearDown(controller.dispose);

        final rejected = await controller.checkForUpdates();
        expect(rejected, isA<FcdMapUpdateFailed>());
        expect(
          (rejected as FcdMapUpdateFailed).kind,
          FcdMapUpdateFailure.validation,
        );
        expect(controller.version, sourceVersion);
        expect(
          controller.geometryFor(mapAreaId: 2, mapInfoNo: 5),
          same(oldGeometry),
        );
        expect(storage.cached, bundled);
        expect(storage.writes, 0);
        expect(controller.isChecking, isFalse);

        final restarted = await store.loadBestAvailable();
        expect(restarted.dataset.version, sourceVersion);
        _expectAllSourceMaps(restarted.dataset, sourceMaps);
        for (final key in sourceMaps.keys) {
          final ids = key.split('-').map(int.parse).toList();
          expect(
            controller.geometryFor(mapAreaId: ids[0], mapInfoNo: ids[1]),
            isNotNull,
            reason: 'live controller retains $key',
          );
        }

        upstreamRepaired = true;
        expect(await controller.checkForUpdates(), isA<FcdMapUpdated>());
        expect(controller.version.toString(), remoteVersion);
        expect(storage.cached, repaired);
        expect(storage.writes, 1);
        _expectAllSourceMaps(
          (await store.loadBestAvailable()).dataset,
          sourceMaps,
        );
        expect(
          controller.resolve(mapAreaId: 2, mapInfoNo: 5, internalNodeId: 3),
          current.resolve(mapAreaId: 2, mapInfoNo: 5, internalNodeId: 3),
        );

        final beforeHealthyCheck = requests.length;
        expect(await controller.checkForUpdates(), isA<FcdMapUpToDate>());
        expect(requests.length, beforeHealthyCheck + 1);
        expect(requests.last.path, endsWith('/meta.json'));
        expect(storage.writes, 1);
      },
    );
  }
}

void _expectAllSourceMaps(
  FcdMapDataset dataset,
  Map<String, dynamic> sourceMaps,
) {
  for (final entry in sourceMaps.entries) {
    final ids = entry.key.split('-').map(int.parse).toList();
    final geometry = dataset.geometryFor(mapAreaId: ids[0], mapInfoNo: ids[1]);
    expect(geometry, isNotNull, reason: '${entry.key} survives restart');
    final sourceMap = entry.value as Map<String, dynamic>;
    expect(
      geometry!.spots.keys.toSet(),
      (sourceMap['spots'] as Map).keys.toSet(),
    );
    for (final route in (sourceMap['route'] as Map).entries) {
      expect(
        dataset.resolve(
          mapAreaId: ids[0],
          mapInfoNo: ids[1],
          internalNodeId: int.parse(route.key as String),
        ),
        (route.value as List)[1],
      );
    }
  }
}

final class _MemoryStorage implements FcdMapStorage {
  _MemoryStorage(this.bundled) : cached = bundled;

  final String bundled;
  String? cached;
  var writes = 0;

  @override
  Future<String> readBundled() async => bundled;

  @override
  Future<String?> readCached() async => cached;

  @override
  Future<void> writeCached(String rawJson) async {
    writes++;
    cached = rawJson;
  }
}
