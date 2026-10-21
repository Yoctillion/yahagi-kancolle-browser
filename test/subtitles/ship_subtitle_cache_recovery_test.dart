import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_catalog.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_catalog_store.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_kc3_bundle.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_kc3_store.dart';

import 'ship_subtitle_kc3_bundle_test.dart' show kc3Fixture;

const _bundledVersion = '20261017023118';
const _backupVersion = '20261018030405';
const _updatedVersion = '20261019030405';
const _latestVersion = '20261020030405';

void main() {
  for (final kind in ['catalog', 'KC3 bundle']) {
    group('$kind cache recovery', () {
      late Directory directory;
      late File primary;
      late File backup;

      String source(String version) => kind == 'catalog'
          ? jsonEncode({
              'version': version,
              '1': {'1': 'Hello!'},
            })
          : jsonEncode(kc3Fixture(version: version));

      _CacheStore store([File? target]) {
        if (kind == 'catalog') {
          final value = FileShipSubtitleCatalogStore(
            cacheFile: target ?? primary,
            bundledReader: () async => source(_bundledVersion),
          );
          return _CacheStore(
            loadVersion: () async => (await value.loadBestAvailable()).version,
            save: (version) =>
                value.save(ShipSubtitleCatalog.fromJsonString(source(version))),
          );
        }
        final value = FileShipSubtitleKc3Store(
          cacheFile: target ?? primary,
          bundledReader: () async => source(_bundledVersion),
        );
        return _CacheStore(
          loadVersion: () async => (await value.loadBestAvailable()).version,
          save: (version) =>
              value.save(ShipSubtitleKc3Bundle.fromJsonString(source(version))),
        );
      }

      setUp(() async {
        directory = await Directory.systemTemp.createTemp(
          'ship-subtitle-cache-recovery-',
        );
        primary = File('${directory.path}/cache.json');
        backup = File('${primary.path}.bak');
        await backup.writeAsString(source(_backupVersion));
      });
      tearDown(() => directory.delete(recursive: true));

      test(
        'uses a valid backup when its primary path cannot be repaired',
        () async {
          await Directory(primary.path).create();
          expect(await store().loadVersion(), _backupVersion);
          expect(await backup.readAsString(), source(_backupVersion));
        },
      );

      test(
        'a failed save preserves the sole valid backup without a prior load',
        () async {
          await Directory(primary.path).create();
          await expectLater(
            store().save(_updatedVersion),
            throwsA(isA<FileSystemException>()),
          );
          expect(await backup.readAsString(), source(_backupVersion));
          expect(await File('${primary.path}.tmp').exists(), isFalse);
        },
      );

      test(
        'uses and preserves a valid backup when a damaged primary cannot be deleted',
        () async {
          await primary.writeAsString('{broken');
          final blocked = store(_FaultyFile(primary, failDelete: true));
          expect(await blocked.loadVersion(), _backupVersion);
          await expectLater(
            blocked.save(_updatedVersion),
            throwsA(isA<FileSystemException>()),
          );
          expect(await backup.readAsString(), source(_backupVersion));
          expect(await primary.readAsString(), '{broken');
        },
      );

      test(
        'recovers after a blocked repair and replaces consecutive complete snapshots',
        () async {
          final occupied = await Directory(primary.path).create();
          final cache = store();
          await cache.loadVersion();
          await occupied.delete();
          await cache.save(_updatedVersion);
          expect(await store().loadVersion(), _updatedVersion);
          await cache.save(_latestVersion);
          expect(await store().loadVersion(), _latestVersion);
          expect(await backup.exists(), isFalse);
          expect(await File('${primary.path}.tmp').exists(), isFalse);
        },
      );

      test(
        'a failed staging write preserves a previously recovered snapshot',
        () async {
          final cache = store();
          expect(await cache.loadVersion(), _backupVersion);
          await Directory('${primary.path}.tmp').create();
          await expectLater(
            cache.save(_updatedVersion),
            throwsA(isA<FileSystemException>()),
          );
          expect(await store().loadVersion(), _backupVersion);
        },
      );

      test(
        'an interrupted replacement preserves a recovered snapshot',
        () async {
          expect(await store().loadVersion(), _backupVersion);
          final cache = store(_FaultyFile(primary, blockReplacement: true));
          await expectLater(
            cache.save(_updatedVersion),
            throwsA(isA<FileSystemException>()),
          );
          expect(await backup.readAsString(), source(_backupVersion));
          expect(await File('${primary.path}.tmp').exists(), isFalse);
          await Directory(primary.path).delete();
          expect(await store().loadVersion(), _backupVersion);
          await store().save(_latestVersion);
          expect(await store().loadVersion(), _latestVersion);
        },
      );
    });
  }
}

final class _CacheStore {
  const _CacheStore({required this.loadVersion, required this.save});
  final Future<String> Function() loadVersion;
  final Future<void> Function(String version) save;
}

/// Real disk contents, with a deterministic access-denied failure on repair.
final class _FaultyFile implements File {
  const _FaultyFile(
    this.delegate, {
    this.failDelete = false,
    this.blockReplacement = false,
  });
  final File delegate;
  final bool failDelete;
  final bool blockReplacement;
  @override
  String get path => delegate.path;
  @override
  Directory get parent => delegate.parent;
  @override
  Future<bool> exists() => delegate.exists();
  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      delegate.readAsString(encoding: encoding);
  @override
  Future<File> delete({bool recursive = false}) async {
    if (failDelete) {
      throw FileSystemException('Injected repair access denied', path);
    }
    await delegate.delete(recursive: recursive);
    return delegate;
  }

  @override
  Future<File> rename(String newPath) async {
    final renamed = await delegate.rename(newPath);
    if (blockReplacement) await Directory(path).create();
    return renamed;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
