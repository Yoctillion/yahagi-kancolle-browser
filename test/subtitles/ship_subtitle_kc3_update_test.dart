import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_catalog_store.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_kc3_bundle.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_kc3_store.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_kc3_update_service.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_update_service.dart';

import 'ship_subtitle_kc3_bundle_test.dart' show kc3Fixture;

const newSha = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

Map<String, dynamic> head({
  String sha = newSha,
  String date = '2026-10-18T03:04:05Z',
}) => {
  'sha': sha,
  'commit': {
    'committer': {'date': date},
  },
};

http.Response resource(http.Request request, {String? brokenPath}) {
  if (request.url.host == 'api.github.com') {
    return http.Response(jsonEncode(head()), 200);
  }
  if (request.url.path.endsWith(brokenPath ?? '/no-such-file')) {
    return http.Response('{}', 200);
  }
  return http.Response(
    jsonEncode(
      request.url.path.endsWith('/quotes.json')
          ? {
              '1': {'Intro': 'Updated!'},
            }
          : request.url.path.endsWith('/items.json')
          ? {'12cm単装砲': 'New Gun'}
          : request.url.path.endsWith('/stype.json')
          ? List.filled(23, 'Ship type')
          : request.url.path.endsWith('/equiptype.json')
          ? List.generate(5, (_) => ['', 'Equipment type'])
          : request.url.path.endsWith('/ships.json')
          ? {'睦月': 'New Mutsuki'}
          : {
              'prefixes': <String, String>{},
              'suffixes': {'改': ' Kai'},
            },
    ),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

final class MemoryKc3Store implements ShipSubtitleKc3Store {
  MemoryKc3Store(this.bundle);
  ShipSubtitleKc3Bundle bundle;
  DateTime? checkedAt;
  bool failSave = false;
  int saves = 0;
  @override
  Future<ShipSubtitleKc3Bundle> loadBestAvailable() async => bundle;
  @override
  Future<void> save(ShipSubtitleKc3Bundle value) async {
    if (failSave) throw const FileSystemException('disk full');
    saves++;
    bundle = value;
  }

  @override
  Future<DateTime?> loadLastCheckedAt() async => checkedAt;
  @override
  Future<void> saveLastCheckedAt(DateTime value) async => checkedAt = value;
}

void main() {
  late ShipSubtitleKc3Bundle current;
  late MemoryKc3Store store;
  setUp(() {
    current = ShipSubtitleKc3Bundle.fromJson(kc3Fixture());
    store = MemoryKc3Store(current);
  });

  test(
    'fetches repository HEAD then exactly 22 files pinned to one SHA',
    () async {
      final requests = <Uri>[];
      final service = ShipSubtitleKc3UpdateService(
        client: MockClient((request) async {
          requests.add(request.url);
          return resource(request);
        }),
        store: store,
      );
      final result = await service.checkAndUpdate(current: current);
      expect(
        result,
        isA<ShipSubtitleKc3Updated>(),
        reason: result is ShipSubtitleKc3UpdateFailed
            ? '${result.error}'
            : null,
      );
      final updated = (result as ShipSubtitleKc3Updated).bundle;
      expect(updated.version, '20261018030405');
      expect(updated.commit, newSha);
      expect(store.saves, 1);
      expect(requests, hasLength(23));
      expect(updated.korean.quotes['1']!['1'], 'Updated!');
      expect(
        requests.first.toString(),
        'https://api.github.com/repos/KC3Kai/kc3-translations/commits/master',
      );
      expect(requests.skip(1).map((uri) => uri.path).toSet(), {
        for (final file in ShipSubtitleKc3Bundle.sourcePaths)
          '/KC3Kai/kc3-translations/$newSha/$file',
      });
      requests.clear();
      expect(
        await service.checkAndUpdate(current: updated),
        isA<ShipSubtitleKc3UpToDate>(),
      );
      expect(requests, hasLength(1));
      expect(store.saves, 1);
    },
  );

  test(
    'a changed commit with equal timestamp refreshes the complete group',
    () async {
      final service = ShipSubtitleKc3UpdateService(
        client: MockClient(
          (request) async => request.url.host == 'api.github.com'
              ? http.Response(
                  jsonEncode(head(date: '2026-10-17T02:31:18Z')),
                  200,
                )
              : resource(request),
        ),
        store: store,
      );
      expect(
        await service.checkAndUpdate(current: current),
        isA<ShipSubtitleKc3Updated>(),
      );
      expect(store.bundle.commit, newSha);
    },
  );

  test('any malformed group member keeps the complete old bundle', () async {
    for (final path in ShipSubtitleKc3Bundle.sourcePaths) {
      store.saves = 0;
      final service = ShipSubtitleKc3UpdateService(
        client: MockClient(
          (request) async => resource(request, brokenPath: '/$path'),
        ),
        store: store,
      );
      final result = await service.checkAndUpdate(current: current);
      expect(result, isA<ShipSubtitleKc3UpdateFailed>(), reason: path);
      expect(
        (result as ShipSubtitleKc3UpdateFailed).kind,
        ShipSubtitleUpdateFailure.validation,
      );
      expect(store.saves, 0);
      expect(store.bundle, same(current));
    }
  });

  test(
    'invalid SHA, impossible dates and older commits never download members',
    () async {
      for (final metadata in [
        head(sha: '../master'),
        head(date: '2026-02-30T03:04:05Z'),
        head(date: '2026-10-18T03:04:05+00:00'),
        head(date: '2026-10-16T03:04:05Z'),
      ]) {
        var requests = 0;
        final service = ShipSubtitleKc3UpdateService(
          client: MockClient((request) async {
            requests++;
            return http.Response(jsonEncode(metadata), 200);
          }),
          store: store,
        );
        expect(
          await service.checkAndUpdate(current: current),
          isA<ShipSubtitleKc3UpdateFailed>(),
        );
        expect(requests, 1);
        expect(store.saves, 0);
      }
    },
  );

  test('storage failure does not publish the candidate bundle', () async {
    store.failSave = true;
    final result = await ShipSubtitleKc3UpdateService(
      client: MockClient((request) async => resource(request)),
      store: store,
    ).checkAndUpdate(current: current);
    expect(result, isA<ShipSubtitleKc3UpdateFailed>());
    expect(
      (result as ShipSubtitleKc3UpdateFailed).kind,
      ShipSubtitleUpdateFailure.storage,
    );
    expect(store.bundle, same(current));
  });

  test('redirects cannot change host, scheme, repository, SHA, path or query', () async {
    for (final target in [
      'https://example.com/quotes.json',
      'http://raw.githubusercontent.com/KC3Kai/kc3-translations/$newSha/data/en/quotes.json',
      'https://raw.githubusercontent.com/other/repo/$newSha/data/en/quotes.json',
      'https://raw.githubusercontent.com/KC3Kai/kc3-translations/master/data/en/quotes.json',
      'https://raw.githubusercontent.com/KC3Kai/kc3-translations/$newSha/data/en/ships.json',
      'https://raw.githubusercontent.com/KC3Kai/kc3-translations/$newSha/data/en/quotes.json?x=1',
    ]) {
      final followed = <Uri>[];
      final service = ShipSubtitleKc3UpdateService(
        client: MockClient((request) async {
          followed.add(request.url);
          return request.url.host == 'api.github.com'
              ? http.Response(jsonEncode(head()), 200)
              : http.Response('', 302, headers: {'location': target});
        }),
        store: store,
      );
      final result = await service.checkAndUpdate(current: current);
      expect(result, isA<ShipSubtitleKc3UpdateFailed>(), reason: target);
      expect(followed, hasLength(2));
    }
  });

  test(
    'enforces declared and streamed body limits and a finite timeout',
    () async {
      for (final client in [
        MockClient((request) async => http.Response('x' * 200, 200)),
        MockClient.streaming(
          (request, body) async =>
              http.StreamedResponse(Stream.value(List.filled(200, 120)), 200),
        ),
        MockClient((request) async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return resource(request);
        }),
      ]) {
        final result = await ShipSubtitleKc3UpdateService(
          client: client,
          store: store,
          maximumMetadataBytes: 100,
          timeout: const Duration(milliseconds: 10),
        ).checkAndUpdate(current: current);
        expect(result, isA<ShipSubtitleKc3UpdateFailed>());
        expect(store.saves, 0);
      }
    },
  );

  test('applies the byte budget to the whole 22 file group', () async {
    final service = ShipSubtitleKc3UpdateService(
      client: MockClient((request) async => resource(request)),
      store: store,
      maximumDataBytes: 100,
    );
    final result = await service.checkAndUpdate(current: current);
    expect(result, isA<ShipSubtitleKc3UpdateFailed>());
    expect(
      (result as ShipSubtitleKc3UpdateFailed).kind,
      ShipSubtitleUpdateFailure.validation,
    );
    expect(store.saves, 0);
  });

  test('decodes UTF-8 BOM Korean source files as valid JSON', () async {
    final result = await ShipSubtitleKc3UpdateService(
      client: MockClient((request) async {
        final response = resource(request);
        return request.url.path.contains('/data/kr/')
            ? http.Response.bytes([
                0xef,
                0xbb,
                0xbf,
                ...response.bodyBytes,
              ], 200)
            : response;
      }),
      store: store,
    ).checkAndUpdate(current: current);
    expect(result, isA<ShipSubtitleKc3Updated>());
    expect(store.saves, 1);
  });

  test('the total download deadline spans HEAD and every member', () async {
    var requests = 0;
    final service = ShipSubtitleKc3UpdateService(
      client: MockClient((request) async {
        requests++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return resource(request);
      }),
      store: store,
      timeout: const Duration(seconds: 1),
      maximumDownloadDuration: const Duration(milliseconds: 70),
    );
    final result = await service.checkAndUpdate(current: current);
    expect(result, isA<ShipSubtitleKc3UpdateFailed>());
    expect(
      (result as ShipSubtitleKc3UpdateFailed).error,
      isA<TimeoutException>(),
    );
    expect(requests, lessThan(8));
    expect(store.saves, 0);
  });

  test(
    'an interrupted member stream cancels and keeps the old bundle',
    () async {
      var cancelled = false;
      final stream = StreamController<List<int>>();
      stream.onCancel = () => cancelled = true;
      final client = MockClient.streaming((request, body) async {
        if (request.url.host == 'api.github.com') {
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode(head()))),
            200,
          );
        }
        stream.add(utf8.encode('{"1":'));
        stream.addError(const SocketException('connection reset'));
        return http.StreamedResponse(stream.stream, 200);
      });
      final result = await ShipSubtitleKc3UpdateService(
        client: client,
        store: store,
      ).checkAndUpdate(current: current);
      expect(result, isA<ShipSubtitleKc3UpdateFailed>());
      expect(
        (result as ShipSubtitleKc3UpdateFailed).kind,
        ShipSubtitleUpdateFailure.network,
      );
      expect(cancelled, isTrue);
      expect(store.saves, 0);
      await stream.close();
    },
  );

  test('redirect loops stop after five hops and cancel every body', () async {
    var requests = 0;
    final service = ShipSubtitleKc3UpdateService(
      client: MockClient((request) async {
        requests++;
        return http.Response(
          '',
          302,
          headers: {'location': request.url.toString()},
        );
      }),
      store: store,
    );
    final result = await service.checkAndUpdate(current: current);
    expect(result, isA<ShipSubtitleKc3UpdateFailed>());
    expect(requests, 6);
    expect(store.saves, 0);
  });

  group('KC3 whole bundle disk cache', () {
    late Directory directory;
    late FileShipSubtitleKc3Store disk;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('kc3-bundle-');
      disk = FileShipSubtitleKc3Store.inDirectory(
        directory,
        bundledReader: () async => jsonEncode(kc3Fixture()),
      );
    });
    tearDown(() async => directory.delete(recursive: true));

    test(
      'recovers a torn cache as one group and ignores older cached bundles',
      () async {
        await disk.cacheFile.writeAsString('{torn');
        await File('${disk.cacheFile.path}.bak').writeAsString(
          jsonEncode(kc3Fixture(version: '20261018030405', commit: newSha)),
        );
        expect((await disk.loadBestAvailable()).commit, newSha);
        await disk.cacheFile.writeAsString(
          jsonEncode(kc3Fixture(version: '20261016000000')),
        );
        expect((await disk.loadBestAvailable()).version, current.version);
      },
    );

    test(
      'saves names and both KC3 catalogs without touching the kcwiki cache',
      () async {
        final legacy = FileShipSubtitleCatalogStore.inDirectory(directory);
        await legacy.cacheFile.writeAsString('sentinel');
        final newer = ShipSubtitleKc3Bundle.fromJson(
          kc3Fixture(version: '20261018030405', commit: newSha),
        );
        await disk.save(newer);
        expect((await disk.loadBestAvailable()).commit, newSha);
        expect(
          (await disk.loadBestAvailable()).korean.quotes,
          newer.korean.quotes,
        );
        expect(await legacy.cacheFile.readAsString(), 'sentinel');
        final at = DateTime.utc(2026, 10, 18, 4);
        await disk.saveLastCheckedAt(at);
        expect(await disk.loadLastCheckedAt(), at);
        expect(await legacy.loadLastCheckedAt(), isNull);
        expect(await File('${disk.cacheFile.path}.tmp').exists(), isFalse);
      },
    );

    test('schema 1 cache cannot hide bundled Korean at the same SHA', () async {
      final previous = kc3Fixture()
        ..['schema'] = 1
        ..remove('korean');
      (previous['names'] as Map).remove('ko-kr');
      await disk.cacheFile.writeAsString(jsonEncode(previous));
      final loaded = await disk.loadBestAvailable();
      expect(loaded.commit, current.commit);
      expect(loaded.korean.quotes['1']!['1'], '안녕하세요!');
      expect(loaded.names.keys, hasLength(4));
    });

    test(
      'schema 2 cache at the same SHA falls back to complete name resources',
      () async {
        final previous = kc3Fixture()
          ..['schema'] = 2
          ..remove('entityNames');
        await disk.cacheFile.writeAsString(jsonEncode(previous));
        final loaded = await disk.loadBestAvailable();
        expect(loaded.commit, current.commit);
        expect(loaded.entityNames, hasLength(4));
        var requests = 0;
        final updater = ShipSubtitleKc3UpdateService(
          client: MockClient((request) async {
            requests++;
            return http.Response(
              jsonEncode(
                head(sha: current.commit, date: '2026-10-17T02:31:18Z'),
              ),
              200,
            );
          }),
          store: disk,
        );
        final result = await updater.checkAndUpdate(current: loaded);
        expect(result, isA<ShipSubtitleKc3UpToDate>());
        expect(requests, 1);
        expect(
          (result as ShipSubtitleKc3UpToDate).bundle.entityNames,
          hasLength(4),
        );
      },
    );

    test(
      'newer schema 2 cache cannot shadow bundled complete resources',
      () async {
        final previous = kc3Fixture(version: '20261018030405', commit: newSha)
          ..['schema'] = 2
          ..remove('entityNames');
        await disk.cacheFile.writeAsString(jsonEncode(previous));
        final loaded = await disk.loadBestAvailable();
        expect(loaded.commit, current.commit);
        expect(loaded.entityNames, hasLength(4));
      },
    );

    test(
      'even newer schema 1 caches fall back to a complete bundled group',
      () async {
        final previous = kc3Fixture(version: '20261018030405', commit: newSha)
          ..['schema'] = 1
          ..remove('korean');
        (previous['names'] as Map).remove('ko-kr');
        await disk.cacheFile.writeAsString(jsonEncode(previous));
        final loaded = await disk.loadBestAvailable();
        expect(loaded.commit, current.commit);
        expect(loaded.korean.quotes['1']!['1'], '안녕하세요!');
      },
    );

    test(
      'a failed temporary write leaves the old whole bundle readable',
      () async {
        await disk.save(current);
        final before = await disk.cacheFile.readAsString();
        await Directory('${disk.cacheFile.path}.tmp').create();
        final newer = ShipSubtitleKc3Bundle.fromJson(
          kc3Fixture(version: '20261018030405', commit: newSha),
        );
        await expectLater(
          disk.save(newer),
          throwsA(isA<FileSystemException>()),
        );
        expect(await disk.cacheFile.readAsString(), before);
        expect((await disk.loadBestAvailable()).commit, current.commit);
      },
    );

    test(
      'a broken check timestamp falls back to its recoverable state backup',
      () async {
        final state = File('${disk.cacheFile.path}.state');
        await state.writeAsString('{torn');
        await File('${state.path}.bak').writeAsString(
          jsonEncode({'lastCheckedAt': '2026-10-18T09:00:00+09:00'}),
        );
        expect(await disk.loadLastCheckedAt(), DateTime.utc(2026, 10, 18));
      },
    );
  });
}
