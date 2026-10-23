import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_catalog.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_catalog_controller.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_catalog_dataset.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_catalog_merger.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_catalog_store.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_catalog_update_service.dart';

void main() {
  test(
    'merge resolves relation codes by shared game id in both directions',
    () {
      final raw = mergeQuestCatalogJson(
        japaneseJson: jsonEncode({
          '901': {'code': 'L2606A1', 'name': 'first', 'desc': ''},
          '902': {'code': 'L2606C1', 'name': 'second', 'desc': ''},
          '903': {'code': 'C3', 'name': 'third', 'desc': ''},
        }),
        relationJson: jsonEncode({
          '901': {'code': '2606Am1'},
          '902': {
            'code': '2606Cm1',
            'pre': ['2606Am1'],
          },
          '903': {
            'code': 'C3',
            'pre': ['L2606C1', 'missing'],
          },
        }),
      );
      final catalog = _parse(raw).catalog;
      expect(catalog.prerequisitesOf(902).map((e) => e.gameId), [901]);
      expect(catalog.prerequisitesOf(903).map((e) => e.gameId), [902]);
      expect(catalog.successorsOf(901).map((e) => e.gameId), [902]);
      expect(catalog.byGameId(901)!.code, 'L2606A1');
      expect(catalog.byGameId(903)!.prerequisites, contains('missing'));
    },
  );

  test('ambiguous relation codes cannot invent a prerequisite', () {
    final raw = mergeQuestCatalogJson(
      japaneseJson: jsonEncode({
        '901': {'code': 'A1', 'name': 'first', 'desc': ''},
        '902': {'code': 'A2', 'name': 'second', 'desc': ''},
        '903': {'code': 'A3', 'name': 'third', 'desc': ''},
      }),
      relationJson: jsonEncode({
        '901': {'code': 'ambiguous'},
        '902': {'code': 'ambiguous'},
        '903': {
          'code': 'A3',
          'pre': ['ambiguous'],
        },
      }),
    );
    final catalog = _parse(raw).catalog;
    expect(catalog.prerequisitesOf(903), isEmpty);
    expect(catalog.byGameId(903)!.prerequisites, ['ambiguous']);
  });

  test('rejects a relation alias colliding with another Japanese code', () {
    expect(
      () => mergeQuestCatalogJson(
        japaneseJson: jsonEncode({
          '901': {'code': 'A1', 'name': 'first', 'desc': ''},
          '902': {'code': 'A2', 'name': 'second', 'desc': ''},
          '903': {'code': 'A3', 'name': 'third', 'desc': ''},
        }),
        relationJson: jsonEncode({
          '901': {'code': 'A2'},
          '902': {'code': 'other'},
          '903': {
            'code': 'A3',
            'pre': ['A2'],
          },
        }),
      ),
      throwsFormatException,
    );
  });

  test('rejects duplicate relation codes that collide with Japanese codes', () {
    expect(
      () => mergeQuestCatalogJson(
        japaneseJson: jsonEncode({
          '901': {'code': 'A1', 'name': 'first', 'desc': ''},
          '902': {'code': 'A2', 'name': 'second', 'desc': ''},
          '903': {'code': 'A3', 'name': 'third', 'desc': ''},
        }),
        relationJson: jsonEncode({
          '901': {'code': 'A1'},
          '902': {'code': 'A1'},
          '903': {
            'code': 'A3',
            'pre': ['A1'],
          },
        }),
      ),
      throwsFormatException,
    );
  });

  test(
    'a parent missing in Japanese data cannot reuse another Japanese code',
    () {
      expect(
        () => mergeQuestCatalogJson(
          japaneseJson: jsonEncode({
            '901': {'code': 'A1', 'name': 'other parent', 'desc': ''},
            '903': {'code': 'A3', 'name': 'child', 'desc': ''},
          }),
          relationJson: jsonEncode({
            '900': {'code': 'A1'},
            '901': {'code': 'other'},
            '903': {
              'code': 'A3',
              'pre': ['A1'],
            },
          }),
        ),
        throwsFormatException,
      );
    },
  );

  test('a missing parent still makes a shared relation code ambiguous', () {
    final raw = mergeQuestCatalogJson(
      japaneseJson: jsonEncode({
        '901': {'code': 'A1', 'name': 'present parent', 'desc': ''},
        '903': {'code': 'A3', 'name': 'child', 'desc': ''},
      }),
      relationJson: jsonEncode({
        '900': {'code': 'shared'},
        '901': {'code': 'shared'},
        '903': {
          'code': 'A3',
          'pre': ['shared'],
        },
      }),
    );
    final catalog = _parse(raw).catalog;
    expect(catalog.prerequisitesOf(903), isEmpty);
    expect(catalog.unresolvedPrerequisitesOf(903), ['shared']);
    expect(catalog.successorsOf(901), isEmpty);
  });

  for (final shared in [true, false]) {
    test(
      'merge rejects ${shared ? 'an ambiguous' : 'a missing-parent'} reference '
      'that a bundled alias would resolve',
      () {
        expect(
          () => mergeQuestCatalogJson(
            japaneseJson: jsonEncode({
              '382': {'code': 'L2606C1', 'name': 'legacy parent', 'desc': ''},
              '901': {'code': 'B1', 'name': 'child', 'desc': ''},
            }),
            relationJson: jsonEncode({
              '382': {'code': shared ? '2606Cm1' : 'other'},
              '900': {'code': '2606Cm1'},
              '901': {
                'code': 'B1',
                'pre': ['2606Cm1'],
              },
            }),
          ),
          throwsFormatException,
        );
      },
    );
  }

  test(
    'merge rejects an absent relation owner that a bundled alias would resolve',
    () {
      expect(
        () => mergeQuestCatalogJson(
          japaneseJson: jsonEncode({
            '382': {'code': 'L2606C1', 'name': 'legacy parent', 'desc': ''},
            '901': {'code': 'B1', 'name': 'child', 'desc': ''},
          }),
          relationJson: jsonEncode({
            '901': {
              'code': 'B1',
              'pre': ['2606Cm1'],
            },
          }),
        ),
        throwsFormatException,
      );
    },
  );

  test('an inactive bundled alias leaves the original reference unknown', () {
    final raw = mergeQuestCatalogJson(
      japaneseJson: jsonEncode({
        '382': {'code': 'C1', 'name': 'changed parent code', 'desc': ''},
        '901': {'code': 'B1', 'name': 'child', 'desc': ''},
      }),
      relationJson: jsonEncode({
        '382': {'code': '2606Cm1'},
        '900': {'code': '2606Cm1'},
        '901': {
          'code': 'B1',
          'pre': ['2606Cm1'],
        },
      }),
    );
    final catalog = _parse(raw).catalog;
    expect(catalog.prerequisitesOf(901), isEmpty);
    expect(catalog.unresolvedPrerequisitesOf(901), ['2606Cm1']);
    expect(catalog.byGameId(901)!.prerequisites, ['2606Cm1']);
  });

  test('an explicit Japanese code takes precedence over a bundled alias', () {
    final raw = mergeQuestCatalogJson(
      japaneseJson: jsonEncode({
        '382': {'code': 'L2606C1', 'name': 'legacy parent', 'desc': ''},
        '900': {'code': '2606Cm1', 'name': 'explicit parent', 'desc': ''},
        '901': {'code': 'B1', 'name': 'child', 'desc': ''},
      }),
      relationJson: jsonEncode({
        '901': {
          'code': 'B1',
          'pre': ['2606Cm1'],
        },
      }),
    );
    final catalog = _parse(raw).catalog;
    expect(catalog.prerequisitesOf(901).map((e) => e.gameId), [900]);
    expect(catalog.successorsOf(382), isEmpty);
    expect(catalog.unresolvedPrerequisitesOf(901), isEmpty);
  });

  test(
    'bundled namespace aliases repair only five source-verified edges',
    () async {
      final raw = await File('assets/data/quests-scn.json').readAsString();
      final version = QuestCatalogVersion.fromJson(
        await File('assets/data/quests-meta.json').readAsString(),
      );
      final dataset = QuestCatalogDataset.parse(rawJson: raw, version: version);
      final catalog = dataset.catalog;
      for (final pair in <(int, int)>[
        (383, 382),
        (1048, 382),
        (1049, 1048),
        (1032, 1150),
        (1150, 1031),
      ]) {
        expect(
          catalog.prerequisitesOf(pair.$1).map((e) => e.gameId),
          contains(pair.$2),
          reason: '${pair.$1} -> ${pair.$2}',
        );
        expect(
          catalog.successorsOf(pair.$2).map((e) => e.gameId),
          contains(pair.$1),
        );
      }
      // These references cannot be verified by game id in the pinned source.
      final unresolved = <int, List<String>>{
        382: ['22606Am1'],
        652: ['C2'],
        1017: ['2409B1'],
        1031: ['2605Bw1'],
        1032: ['2605Bw2'],
        1036: ['2507C1'],
        1143: ['2409B1'],
        1155: ['2508B1'],
        1158: ['2412B5'],
      };
      for (final item in unresolved.entries) {
        expect(catalog.unresolvedPrerequisitesOf(item.key), item.value);
        expect(
          catalog.byGameId(item.key)!.prerequisites,
          containsAll(item.value),
        );
      }
      expect(
        () => catalog.unresolvedPrerequisitesOf(382).add('invented'),
        throwsUnsupportedError,
      );
      expect(dataset.rawJson, raw);
      expect(dataset.version.sha256, _hash(raw));
    },
  );

  test('incomplete ancestry cannot infer absent terminal task complete', () {
    final catalog = QuestCatalog([
      _entry(901, 'A1'),
      _entry(902, 'A2', ['A1', 'missing']),
      _entry(903, 'A3', ['A2']),
    ]);
    final projection = catalog.project(
      const <int, GameQuest>{},
      confirmedCompleted: {901},
    );
    expect(projection.byGameId(903).status, QuestStatus.unknown);
    expect(catalog.unresolvedPrerequisitesOf(902), ['missing']);
    expect(catalog.unresolvedPrerequisitesOf(901), isEmpty);
  });

  test('complete known ancestry still infers terminal completion', () {
    final catalog = QuestCatalog([
      _entry(901, 'A1'),
      _entry(902, 'A2', ['A1']),
    ]);
    expect(
      catalog
          .project(const <int, GameQuest>{}, confirmedCompleted: {901})
          .byGameId(902)
          .status,
      QuestStatus.completed,
    );
  });

  test(
    'hot update and restart share bundled display fallbacks and raw hash',
    () async {
      final bundled = _dataset('bundled', 1, translated: true);
      final storage = _MemoryStorage(bundled);
      final store = QuestCatalogStore(storage, minimumQuestCount: 1);
      final client = MockClient((request) async {
        if (request.url.host == 'api.github.com') {
          return http.Response(
            jsonEncode([
              {
                'sha': 'b' * 40,
                'commit': {
                  'committer': {'date': '2026-08-09T00:00:00Z'},
                },
              },
            ]),
            200,
          );
        }
        return http.Response.bytes(
          utf8.encode(
            request.url.path.contains('antest1') ? _raw('new Japanese') : '{}',
          ),
          200,
        );
      });
      addTearDown(client.close);
      final controller = QuestCatalogController(
        dataset: bundled,
        updater: QuestCatalogUpdateService(
          client: client,
          store: store,
          minimumQuestCount: 1,
        ),
      );
      addTearDown(controller.dispose);
      final result = await controller.checkForUpdates();
      expect(result, isA<QuestCatalogUpdated>());
      final restarted = (await store.loadBestAvailable()).dataset;
      for (final dataset in [
        controller.dataset,
        (result as QuestCatalogUpdated).dataset,
        restarted,
      ]) {
        final entry = dataset.catalog.byGameId(901)!;
        expect(entry.name, 'new Japanese');
        expect(entry.translatedName, '中文任务');
        expect(entry.translatedDescription, '中文说明');
        expect(entry.memo, '完成条件备注');
        expect(dataset.rawJson, storage.cached!.rawJson);
        expect(dataset.version.sha256, _hash(dataset.rawJson));
        expect((jsonDecode(dataset.rawJson) as Map)['901']['nameZh'], isNull);
      }
    },
  );

  test(
    'controller also retains display fallback from an existing cache',
    () async {
      final current = _dataset('current', 2, translated: true);
      final next = _dataset('new', 3);
      final controller = QuestCatalogController(
        dataset: current,
        updater: _Updater(next),
      );
      addTearDown(controller.dispose);
      await controller.checkForUpdates();
      expect(controller.catalog.byGameId(901)!.translatedName, '中文任务');
      expect(controller.catalog.byGameId(901)!.memo, '完成条件备注');
      expect(controller.dataset.rawJson, next.rawJson);
    },
  );

  group('cache pair recovery', () {
    late Directory root;
    late File data;
    late File metadata;
    late QuestCatalogDataset bundled;
    late QuestCatalogDataset old;
    late QuestCatalogDataset newer;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('quest-audit-cache-');
      data = File('${root.path}/data.json');
      metadata = File('${root.path}/meta.json');
      bundled = _dataset('bundled', 1);
      old = _dataset('previous cache', 2);
      newer = _dataset('new cache', 3);
    });
    tearDown(() async => root.delete(recursive: true));

    ApplicationQuestCatalogStorage storage({File? dataFile}) =>
        ApplicationQuestCatalogStorage(
          bundledDataReader: () async => bundled.rawJson,
          bundledMetadataReader: () async => bundled.version.toJson(),
          cacheDataFile: dataFile ?? data,
          cacheMetadataFile: metadata,
          stateFile: File('${root.path}/state.json'),
          minimumQuestCount: 1,
        );

    Future<void> writePair(
      QuestCatalogDataset value, {
      String suffix = '',
    }) async {
      await File('${data.path}$suffix').writeAsString(value.rawJson);
      await File(
        '${metadata.path}$suffix',
      ).writeAsString(value.version.toJson());
    }

    Future<void> expectLoaded(QuestCatalogDataset expected) async {
      final loaded = await QuestCatalogStore(
        storage(),
        minimumQuestCount: 1,
      ).loadBestAvailable();
      expect(loaded.source, QuestCatalogSource.cache);
      expect(loaded.dataset.rawJson, expected.rawJson);
      expect(loaded.dataset.version.toJson(), expected.version.toJson());
    }

    test(
      'metadata staging failure preserves the previous valid cache',
      () async {
        final store = QuestCatalogStore(storage(), minimumQuestCount: 1);
        await store.save(old);
        await Directory('${metadata.path}.tmp').create();
        await expectLater(
          store.save(newer),
          throwsA(isA<FileSystemException>()),
        );
        await expectLoaded(old);
      },
    );

    test('rejects a forged dataset before touching the valid cache', () async {
      final store = QuestCatalogStore(storage(), minimumQuestCount: 1);
      await store.save(old);
      final forged = QuestCatalogDataset(
        catalog: newer.catalog,
        version: old.version,
        rawJson: newer.rawJson,
      );
      await expectLater(store.save(forged), throwsFormatException);
      await expectLoaded(old);
    });

    test(
      'rejects invalid revision metadata before replacing the cache',
      () async {
        final store = QuestCatalogStore(storage(), minimumQuestCount: 1);
        await store.save(old);
        final forged = QuestCatalogDataset(
          catalog: newer.catalog,
          rawJson: newer.rawJson,
          version: QuestCatalogVersion(
            committedAt: newer.version.committedAt,
            commitSha: 'bad',
            sha256: newer.version.sha256,
          ),
        );
        await expectLater(store.save(forged), throwsFormatException);
        await expectLoaded(old);
      },
    );

    test('migrates an intact legacy data and metadata pair', () async {
      await writePair(old);
      await expectLoaded(old);
      await QuestCatalogStore(storage(), minimumQuestCount: 1).save(newer);
      await expectLoaded(newer);
    });

    test('recovers old pair after new data replaces only one half', () async {
      await writePair(old, suffix: '.bak');
      await data.writeAsString(newer.rawJson);
      await metadata.writeAsString(old.version.toJson());
      await expectLoaded(old);
      // Recovery is durable across fresh storage objects.
      await expectLoaded(old);
    });

    test('recovers split old pair after first backup rename', () async {
      await File('${data.path}.bak').writeAsString(old.rawJson);
      await metadata.writeAsString(old.version.toJson());
      await expectLoaded(old);
    });

    test('invalid primary cannot delete an intact valid backup pair', () async {
      await writePair(old, suffix: '.bak');
      await data.writeAsString('{broken');
      await metadata.writeAsString(newer.version.toJson());
      await expectLoaded(old);
    });

    test('invalid metadata fields still allow valid backup recovery', () async {
      await writePair(old, suffix: '.bak');
      await data.writeAsString(newer.rawJson);
      await metadata.writeAsString(
        jsonEncode({
          ...jsonDecode(newer.version.toJson()) as Map<String, dynamic>,
          'committedAt': 20260803,
        }),
      );
      await expectLoaded(old);
    });

    test(
      'unreadable primary still falls back to a readable valid pair',
      () async {
        await writePair(newer);
        await writePair(old, suffix: '.bak');
        final loaded = await QuestCatalogStore(
          storage(dataFile: _FaultyFile(data, failRead: true)),
          minimumQuestCount: 1,
        ).loadBestAvailable();
        expect(loaded.source, QuestCatalogSource.cache);
        expect(loaded.dataset.rawJson, old.rawJson);
      },
    );

    test(
      'failed disk repair still returns the validated backup in memory',
      () async {
        await writePair(old, suffix: '.bak');
        await data.writeAsString('{broken');
        await metadata.writeAsString(newer.version.toJson());
        final loaded = await QuestCatalogStore(
          storage(dataFile: _FaultyFile(data, failDelete: true)),
          minimumQuestCount: 1,
        ).loadBestAvailable();
        expect(loaded.source, QuestCatalogSource.cache);
        expect(loaded.dataset.rawJson, old.rawJson);
        expect(await File('${data.path}.bak').readAsString(), old.rawJson);
        expect(
          await File('${metadata.path}.bak').readAsString(),
          old.version.toJson(),
        );
      },
    );

    test(
      'failed repair blocks writes that would consume the only valid backup',
      () async {
        await writePair(old, suffix: '.bak');
        await data.writeAsString('{broken');
        await metadata.writeAsString(newer.version.toJson());
        final files = storage(dataFile: _FaultyFile(data, failDelete: true));
        await expectLater(
          files.writeCached(newer),
          throwsA(isA<FileSystemException>()),
        );
        expect(await File('${data.path}.bak').readAsString(), old.rawJson);
        expect(
          await File('${metadata.path}.bak').readAsString(),
          old.version.toJson(),
        );
      },
    );

    test(
      'complete new primary wins after interruption before cleanup',
      () async {
        await writePair(old, suffix: '.bak');
        await writePair(newer);
        await expectLoaded(newer);
      },
    );

    test(
      'uncommitted staged pair cannot displace last committed pair',
      () async {
        await writePair(old);
        await writePair(newer, suffix: '.tmp');
        await expectLoaded(old);
      },
    );

    test('never mixes unrelated data and metadata on recovery', () async {
      await data.writeAsString(newer.rawJson);
      await metadata.writeAsString(old.version.toJson());
      final loaded = await QuestCatalogStore(
        storage(),
        minimumQuestCount: 1,
      ).loadBestAvailable();
      expect(loaded.source, QuestCatalogSource.bundled);
      expect(loaded.dataset.rawJson, bundled.rawJson);
    });

    test(
      'reads queued during replacement receive a complete new generation',
      () async {
        final files = storage();
        await files.writeCached(old);
        final writing = files.writeCached(newer);
        final reading = files.readCachedPair();
        await writing;
        final loaded = await reading;
        expect(loaded!.rawJson, newer.rawJson);
        expect(loaded.version.toJson(), newer.version.toJson());
        expect(_hash(loaded.rawJson), loaded.version.sha256);
        expect(await File('${data.path}.bak').exists(), isFalse);
        expect(await File('${metadata.path}.bak').exists(), isFalse);
        expect(await File('${data.path}.tmp').exists(), isFalse);
        expect(await File('${metadata.path}.tmp').exists(), isFalse);
      },
    );
  });
}

QuestCatalogEntry _entry(int id, String code, [List<String> pre = const []]) =>
    QuestCatalogEntry(
      gameId: id,
      code: code,
      name: code,
      description: '',
      prerequisites: pre,
    );

String _hash(String raw) => sha256.convert(utf8.encode(raw)).toString();

String _raw(String name, {bool translated = false}) => jsonEncode({
  '901': {
    'code': 'B1',
    'name': name,
    'desc': 'Japanese description',
    if (translated) ...{'nameZh': '中文任务', 'descZh': '中文说明', 'memo2': '完成条件备注'},
  },
});

QuestCatalogDataset _parse(String raw, [int day = 1]) =>
    QuestCatalogDataset.parse(
      rawJson: raw,
      minimumQuestCount: 1,
      version: QuestCatalogVersion(
        committedAt: DateTime.utc(2026, 8, day),
        commitSha: day.toRadixString(16).padLeft(40, '0'),
        sha256: _hash(raw),
      ),
    );

QuestCatalogDataset _dataset(String name, int day, {bool translated = false}) =>
    _parse(_raw(name, translated: translated), day);

final class _MemoryStorage implements QuestCatalogStorage {
  _MemoryStorage(this.bundled);
  final QuestCatalogDataset bundled;
  QuestCatalogDataset? cached;
  @override
  Future<String> readBundledData() async => bundled.rawJson;
  @override
  Future<String> readBundledMetadata() async => bundled.version.toJson();
  @override
  Future<String?> readCachedData() async => cached?.rawJson;
  @override
  Future<String?> readCachedMetadata() async => cached?.version.toJson();
  @override
  Future<void> writeCached(QuestCatalogDataset dataset) async =>
      cached = dataset;
}

final class _Updater implements QuestCatalogUpdateClient {
  _Updater(this.next);
  final QuestCatalogDataset next;
  @override
  Future<QuestCatalogUpdateResult> checkAndUpdate({
    required QuestCatalogDataset current,
  }) async => QuestCatalogUpdated(next);
}

/// Real disk contents with a deterministic I/O failure at one file boundary.
final class _FaultyFile implements File {
  _FaultyFile(this.delegate, {this.failRead = false, this.failDelete = false});
  final File delegate;
  final bool failRead;
  final bool failDelete;
  @override
  String get path => delegate.path;
  @override
  Directory get parent => delegate.parent;
  @override
  Future<bool> exists() => delegate.exists();
  @override
  Future<String> readAsString({Encoding encoding = utf8}) async {
    if (failRead) throw FileSystemException('Injected read failure', path);
    return delegate.readAsString(encoding: encoding);
  }

  @override
  Future<File> delete({bool recursive = false}) async {
    if (failDelete) throw FileSystemException('Injected repair failure', path);
    await delegate.delete(recursive: recursive);
    return delegate;
  }

  @override
  Future<File> rename(String newPath) => delegate.rename(newPath);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
