import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'ship_subtitle_kc3_bundle.dart';

abstract interface class ShipSubtitleKc3Store {
  Future<ShipSubtitleKc3Bundle> loadBestAvailable();
  Future<void> save(ShipSubtitleKc3Bundle bundle);
  Future<DateTime?> loadLastCheckedAt();
  Future<void> saveLastCheckedAt(DateTime value);
}

final class FileShipSubtitleKc3Store implements ShipSubtitleKc3Store {
  const FileShipSubtitleKc3Store({
    required this.cacheFile,
    required this.bundledReader,
  });

  factory FileShipSubtitleKc3Store.inDirectory(
    Directory directory, {
    Future<String> Function()? bundledReader,
  }) => FileShipSubtitleKc3Store(
    cacheFile: File(
      path.join(directory.path, 'ship-subtitles-kc3-bundle.json'),
    ),
    bundledReader:
        bundledReader ??
        () => rootBundle.loadString(
          ShipSubtitleKc3Bundle.bundledAsset,
          cache: false,
        ),
  );

  static Future<FileShipSubtitleKc3Store> create() async =>
      FileShipSubtitleKc3Store.inDirectory(
        await getApplicationSupportDirectory(),
      );

  final File cacheFile;
  final Future<String> Function() bundledReader;
  File get _stateFile => File('${cacheFile.path}.state');

  @override
  Future<ShipSubtitleKc3Bundle> loadBestAvailable() async {
    final bundled = await compute(
      ShipSubtitleKc3Bundle.fromJsonString,
      await bundledReader(),
    );
    final backup = File('${cacheFile.path}.bak');
    ShipSubtitleKc3Bundle cached;
    try {
      cached = await _readBundle(cacheFile);
    } on Object {
      try {
        cached = await _readBundle(backup);
      } on Object {
        return bundled;
      }
      try {
        await _restoreBackup();
      } on Object {
        // A valid backup remains usable even when its primary cannot be repaired.
      }
      return cached.version.compareTo(bundled.version) >= 0 ? cached : bundled;
    }
    try {
      if (await backup.exists()) await backup.delete();
    } on Object {
      // Backup cleanup must not hide a successfully validated primary.
    }
    return cached.version.compareTo(bundled.version) >= 0 ? cached : bundled;
  }

  @override
  Future<void> save(ShipSubtitleKc3Bundle bundle) async {
    await _restoreValidBackup();
    await _replaceAtomically(cacheFile, await compute(_encodeBundle, bundle));
  }

  Future<void> _restoreValidBackup() async {
    final backup = File('${cacheFile.path}.bak');
    if (!await backup.exists()) return;
    try {
      await _readBundle(cacheFile);
      return;
    } on Object {
      // A damaged primary must not replace its sole valid backup on rotation.
    }
    try {
      await _readBundle(backup);
    } on Object {
      return;
    }
    // Propagate repair failures so the normal writer cannot discard this backup.
    await _restoreBackup();
  }

  Future<void> _restoreBackup() async {
    if (await cacheFile.exists()) await cacheFile.delete();
    await File('${cacheFile.path}.bak').rename(cacheFile.path);
  }

  @override
  Future<DateTime?> loadLastCheckedAt() async {
    for (final candidate in [_stateFile, File('${_stateFile.path}.bak')]) {
      try {
        final value = jsonDecode(await candidate.readAsString());
        if (value is Map<String, dynamic> && value['lastCheckedAt'] is String) {
          final parsed = DateTime.tryParse(value['lastCheckedAt'] as String);
          if (parsed != null) return parsed.toUtc();
        }
      } on Object {
        // Offline use must survive corrupt or missing update state.
      }
    }
    return null;
  }

  @override
  Future<void> saveLastCheckedAt(DateTime value) => _replaceAtomically(
    _stateFile,
    jsonEncode({'lastCheckedAt': value.toUtc().toIso8601String()}),
  );
}

Future<ShipSubtitleKc3Bundle> _readBundle(File file) async =>
    compute(ShipSubtitleKc3Bundle.fromJsonString, await file.readAsString());

String _encodeBundle(ShipSubtitleKc3Bundle bundle) => bundle.toJsonString();

/// The previous whole group remains recoverable until replacement succeeds.
Future<void> _replaceAtomically(File target, String source) async {
  await target.parent.create(recursive: true);
  final temporary = File('${target.path}.tmp');
  final backup = File('${target.path}.bak');
  try {
    await temporary.writeAsString(source, flush: true);
    if (await target.exists()) {
      if (await backup.exists()) await backup.delete();
      await target.rename(backup.path);
    }
    try {
      await temporary.rename(target.path);
      if (await backup.exists()) await backup.delete();
    } on Object {
      if (await target.exists()) await target.delete();
      if (await backup.exists()) await backup.rename(target.path);
      rethrow;
    }
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}
