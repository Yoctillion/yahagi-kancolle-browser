// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'quest_catalog_dataset.dart';

enum QuestCatalogSource { bundled, cache }

final class LoadedQuestCatalog {
  const LoadedQuestCatalog({required this.dataset, required this.source});

  final QuestCatalogDataset dataset;
  final QuestCatalogSource source;
}

final class QuestCatalogState {
  const QuestCatalogState({
    required this.version,
    required this.source,
    required this.lastCheckedAt,
    required this.result,
  });

  final QuestCatalogVersion version;
  final String source;
  final DateTime? lastCheckedAt;
  final String result;

  factory QuestCatalogState.fromJson(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] is! Map<String, dynamic> ||
        decoded['source'] is! String ||
        decoded['result'] is! String) {
      throw const FormatException('Quest catalog state is invalid');
    }
    return QuestCatalogState(
      version: QuestCatalogVersion.fromJson(jsonEncode(decoded['version'])),
      source: decoded['source'] as String,
      lastCheckedAt: decoded['lastCheckedAt'] is String
          ? DateTime.tryParse(decoded['lastCheckedAt'] as String)?.toUtc()
          : null,
      result: decoded['result'] as String,
    );
  }

  String toJson() => jsonEncode(<String, Object?>{
    'version': jsonDecode(version.toJson()),
    'source': source,
    'lastCheckedAt': lastCheckedAt?.toUtc().toIso8601String(),
    'result': result,
  });
}

abstract interface class QuestCatalogStorage {
  Future<String> readBundledData();
  Future<String> readBundledMetadata();
  Future<String?> readCachedData();
  Future<String?> readCachedMetadata();
  Future<void> writeCached(QuestCatalogDataset dataset);
}

/// File stores read and validate a whole committed generation in one operation.
/// Legacy in-memory implementations can retain the original storage interface.
abstract interface class QuestCatalogPairStorage {
  Future<QuestCatalogDataset?> readCachedPair();
}

abstract interface class QuestCatalogStateStorage {
  Future<String?> readState();
  Future<void> writeState(String rawJson);
}

final class BundledOnlyQuestCatalogStorage implements QuestCatalogStorage {
  const BundledOnlyQuestCatalogStorage();

  @override
  Future<String> readBundledData() =>
      rootBundle.loadString(ApplicationQuestCatalogStorage.bundledDataPath);
  @override
  Future<String> readBundledMetadata() =>
      rootBundle.loadString(ApplicationQuestCatalogStorage.bundledMetadataPath);
  @override
  Future<String?> readCachedData() async => null;
  @override
  Future<String?> readCachedMetadata() async => null;
  @override
  Future<void> writeCached(QuestCatalogDataset dataset) => Future<void>.error(
    const FileSystemException('Application support directory is unavailable'),
  );
}

final class QuestCatalogStore {
  const QuestCatalogStore(this.storage, {this.minimumQuestCount = 500});

  final QuestCatalogStorage storage;
  final int minimumQuestCount;

  Future<LoadedQuestCatalog> loadBestAvailable() async {
    final bundled = await _loadBundled();
    QuestCatalogDataset? cached;
    try {
      if (storage is QuestCatalogPairStorage) {
        final pair = await (storage as QuestCatalogPairStorage)
            .readCachedPair();
        if (pair != null) cached = _parse(pair.rawJson, pair.version.toJson());
      } else {
        final data = await storage.readCachedData();
        final metadata = await storage.readCachedMetadata();
        if (data != null && metadata != null) cached = _parse(data, metadata);
      }
    } catch (_) {
      cached = null;
    }
    if (cached != null && cached.version.compareTo(bundled.version) >= 0) {
      return LoadedQuestCatalog(
        dataset: cached.withDisplayFallbackFrom(bundled),
        source: QuestCatalogSource.cache,
      );
    }
    return LoadedQuestCatalog(
      dataset: bundled,
      source: QuestCatalogSource.bundled,
    );
  }

  Future<QuestCatalogDataset> _loadBundled() async => _parse(
    await storage.readBundledData(),
    await storage.readBundledMetadata(),
  );

  Future<QuestCatalogDataset> withBundledDisplayFallback(
    QuestCatalogDataset dataset,
  ) async => dataset.withDisplayFallbackFrom(await _loadBundled());

  QuestCatalogDataset _parse(String data, String metadata) =>
      QuestCatalogDataset.parse(
        rawJson: data,
        version: QuestCatalogVersion.fromJson(metadata),
        minimumQuestCount: minimumQuestCount,
      );

  Future<void> save(QuestCatalogDataset dataset) =>
      storage.writeCached(dataset);

  Future<QuestCatalogState?> loadState() async {
    if (storage is! QuestCatalogStateStorage) return null;
    try {
      final raw = await (storage as QuestCatalogStateStorage).readState();
      return raw == null ? null : QuestCatalogState.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveState(QuestCatalogState state) async {
    if (storage is QuestCatalogStateStorage) {
      await (storage as QuestCatalogStateStorage).writeState(state.toJson());
    }
  }
}

final class ApplicationQuestCatalogStorage
    implements
        QuestCatalogStorage,
        QuestCatalogStateStorage,
        QuestCatalogPairStorage {
  ApplicationQuestCatalogStorage({
    required Future<String> Function() bundledDataReader,
    required Future<String> Function() bundledMetadataReader,
    required this.cacheDataFile,
    required this.cacheMetadataFile,
    required this.stateFile,
    this.minimumQuestCount = 500,
  }) : _bundledDataReader = bundledDataReader,
       _bundledMetadataReader = bundledMetadataReader;

  static const bundledDataPath = 'assets/data/quests-scn.json';
  static const bundledMetadataPath = 'assets/data/quests-meta.json';

  static Future<ApplicationQuestCatalogStorage> create() async {
    final directory = await getApplicationSupportDirectory();
    return ApplicationQuestCatalogStorage(
      bundledDataReader: () => rootBundle.loadString(bundledDataPath),
      bundledMetadataReader: () => rootBundle.loadString(bundledMetadataPath),
      cacheDataFile: File(path.join(directory.path, 'quest-catalog.json')),
      cacheMetadataFile: File(
        path.join(directory.path, 'quest-catalog-meta.json'),
      ),
      stateFile: File(path.join(directory.path, 'quest-catalog-state.json')),
    );
  }

  final Future<String> Function() _bundledDataReader;
  final Future<String> Function() _bundledMetadataReader;
  final File cacheDataFile;
  final File cacheMetadataFile;
  final File stateFile;
  final int minimumQuestCount;
  Future<void> _pendingCacheOperation = Future<void>.value();

  @override
  Future<String> readBundledData() => _bundledDataReader();
  @override
  Future<String> readBundledMetadata() => _bundledMetadataReader();
  @override
  Future<String?> readCachedData() async => (await readCachedPair())?.rawJson;
  @override
  Future<String?> readCachedMetadata() async =>
      (await readCachedPair())?.version.toJson();
  @override
  Future<String?> readState() => _readRecovering(stateFile);

  @override
  Future<void> writeCached(QuestCatalogDataset dataset) =>
      _serializeCacheOperation(() => _writeCachedPair(dataset));

  @override
  Future<QuestCatalogDataset?> readCachedPair() =>
      _serializeCacheOperation(_readCachedPairRecovering);

  Future<T> _serializeCacheOperation<T>(Future<T> Function() operation) {
    final result = _pendingCacheOperation.then((_) => operation());
    // A failed write must not prevent the next read from recovering the pair.
    _pendingCacheOperation = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> _writeCachedPair(QuestCatalogDataset dataset) async {
    final metadata = dataset.version.toJson();
    _parseCachedPair(dataset.rawJson, metadata);
    // First restore a prior interrupted commit, then stage both new files.
    // Neither primary is touched until both staged files validate together.
    await _readCachedPairRecovering(repairRequired: true);
    final dataTemporary = File('${cacheDataFile.path}.tmp');
    final metaTemporary = File('${cacheMetadataFile.path}.tmp');
    final dataBackup = File('${cacheDataFile.path}.bak');
    final metaBackup = File('${cacheMetadataFile.path}.bak');
    await cacheDataFile.parent.create(recursive: true);
    await cacheMetadataFile.parent.create(recursive: true);
    try {
      await dataTemporary.writeAsString(dataset.rawJson, flush: true);
      await metaTemporary.writeAsString(metadata, flush: true);
      _parseCachedPair(
        await dataTemporary.readAsString(),
        await metaTemporary.readAsString(),
      );
      // Keep both backups until both primaries contain a validated generation.
      for (final pair in <(File, File)>[
        (cacheDataFile, dataBackup),
        (cacheMetadataFile, metaBackup),
      ]) {
        if (await pair.$2.exists()) await pair.$2.delete();
        if (await pair.$1.exists()) await pair.$1.rename(pair.$2.path);
      }
      await dataTemporary.rename(cacheDataFile.path);
      await metaTemporary.rename(cacheMetadataFile.path);
      _parseCachedPair(
        await cacheDataFile.readAsString(),
        await cacheMetadataFile.readAsString(),
      );
      if (await dataBackup.exists()) await dataBackup.delete();
      if (await metaBackup.exists()) await metaBackup.delete();
    } finally {
      // On error, the original exception propagates. Recovery on the next read
      // selects a valid primary/backup pair, never two independently read halves.
      if (await dataTemporary.exists()) await dataTemporary.delete();
      if (await metaTemporary.exists()) await metaTemporary.delete();
    }
  }

  QuestCatalogDataset _parseCachedPair(String data, String metadata) =>
      QuestCatalogDataset.parse(
        rawJson: data,
        version: QuestCatalogVersion.fromJson(metadata),
        minimumQuestCount: minimumQuestCount,
      );

  Future<QuestCatalogDataset?> _readCachedPairRecovering({
    bool repairRequired = false,
  }) async {
    final dataBackup = File('${cacheDataFile.path}.bak');
    final metaBackup = File('${cacheMetadataFile.path}.bak');
    // The primary pair is the commit point. Mixed pairs cover interruptions
    // between backup renames; the content hash proves they belong together.
    for (final pair in <(File, File)>[
      (cacheDataFile, cacheMetadataFile),
      (dataBackup, metaBackup),
      (dataBackup, cacheMetadataFile),
      (cacheDataFile, metaBackup),
    ]) {
      QuestCatalogDataset candidate;
      try {
        if (!await pair.$1.exists() || !await pair.$2.exists()) continue;
        candidate = _parseCachedPair(
          await pair.$1.readAsString(),
          await pair.$2.readAsString(),
        );
      } on FormatException {
        continue;
      } on IOException {
        // An unreadable primary must not hide a readable valid backup.
        continue;
      }
      // Move a verified backup into place without deleting its only valid copy
      // first. A crash between these moves remains recoverable by this loop.
      try {
        if (pair.$1.path != cacheDataFile.path) {
          if (await cacheDataFile.exists()) await cacheDataFile.delete();
          await pair.$1.rename(cacheDataFile.path);
        }
        if (pair.$2.path != cacheMetadataFile.path) {
          if (await cacheMetadataFile.exists()) {
            await cacheMetadataFile.delete();
          }
          await pair.$2.rename(cacheMetadataFile.path);
        }
        if (await dataBackup.exists()) await dataBackup.delete();
        if (await metaBackup.exists()) await metaBackup.delete();
      } on IOException {
        // Reading can use the already-validated bytes. A write must stop here,
        // before consuming the only valid backups to start another generation.
        if (repairRequired) rethrow;
      }
      return candidate;
    }
    return null;
  }

  @override
  Future<void> writeState(String rawJson) async {
    QuestCatalogState.fromJson(rawJson);
    await _writeAtomically(stateFile, rawJson);
  }

  Future<String?> _readRecovering(File file) async {
    final backup = File('${file.path}.bak');
    if (!await file.exists() && await backup.exists()) {
      await file.parent.create(recursive: true);
      await backup.rename(file.path);
    } else if (await file.exists() && await backup.exists()) {
      await backup.delete();
    }
    return await file.exists() ? file.readAsString() : null;
  }

  Future<void> _writeAtomically(File target, String raw) async {
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.tmp');
    final backup = File('${target.path}.bak');
    try {
      await temporary.writeAsString(raw, flush: true);
      if (await backup.exists()) await backup.delete();
      if (await target.exists()) await target.rename(backup.path);
      try {
        await temporary.rename(target.path);
        if (await backup.exists()) await backup.delete();
      } catch (_) {
        if (await target.exists()) await target.delete();
        if (await backup.exists()) await backup.rename(target.path);
        rethrow;
      }
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
