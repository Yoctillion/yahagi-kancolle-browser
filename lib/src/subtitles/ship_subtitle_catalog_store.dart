import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'ship_subtitle_catalog.dart';
import 'ship_subtitle_language.dart';
import 'ship_subtitle_kc3_bundle.dart';

abstract interface class ShipSubtitleCatalogStore {
  Future<ShipSubtitleCatalog> loadBestAvailable();
  Future<void> save(ShipSubtitleCatalog catalog);
  Future<DateTime?> loadLastCheckedAt();
  Future<void> saveLastCheckedAt(DateTime value);
}

final class FileShipSubtitleCatalogStore implements ShipSubtitleCatalogStore {
  const FileShipSubtitleCatalogStore({
    required this.cacheFile,
    required this.bundledReader,
  });

  factory FileShipSubtitleCatalogStore.inDirectory(
    Directory directory, {
    ShipSubtitleLanguage language = ShipSubtitleLanguage.simplifiedChinese,
    Future<String> Function()? bundledReader,
  }) => FileShipSubtitleCatalogStore(
    cacheFile: File(
      path.join(directory.path, 'ship-subtitles-${language.code}.json'),
    ),
    bundledReader: bundledReader ?? () => _readBundledCatalog(language),
  );

  static Future<FileShipSubtitleCatalogStore> create({
    ShipSubtitleLanguage language = ShipSubtitleLanguage.simplifiedChinese,
  }) async {
    final directory = await getApplicationSupportDirectory();
    return FileShipSubtitleCatalogStore.inDirectory(
      directory,
      language: language,
    );
  }

  final File cacheFile;
  final Future<String> Function() bundledReader;
  File get _stateFile => File('${cacheFile.path}.state');

  @override
  Future<ShipSubtitleCatalog> loadBestAvailable() async {
    final bundled = await compute(
      ShipSubtitleCatalog.fromJsonString,
      await bundledReader(),
    );
    final backup = File('${cacheFile.path}.bak');
    ShipSubtitleCatalog cached;
    try {
      cached = await _readCatalog(cacheFile);
    } on Object {
      try {
        cached = await _readCatalog(backup);
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
  Future<void> save(ShipSubtitleCatalog catalog) async {
    await _restoreValidBackup();
    await _replaceAtomically(cacheFile, await compute(_encodeCatalog, catalog));
  }

  Future<void> _restoreValidBackup() async {
    final backup = File('${cacheFile.path}.bak');
    if (!await backup.exists()) return;
    try {
      await _readCatalog(cacheFile);
      return;
    } on Object {
      // A damaged primary must not replace its sole valid backup on rotation.
    }
    try {
      await _readCatalog(backup);
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
    final backup = File('${_stateFile.path}.bak');
    for (final candidate in [_stateFile, backup]) {
      try {
        final value = jsonDecode(await candidate.readAsString());
        if (value is Map<String, dynamic> && value['lastCheckedAt'] is String) {
          final parsed = DateTime.tryParse(value['lastCheckedAt'] as String);
          if (parsed != null) return parsed.toUtc();
        }
      } on Object {
        // An unavailable or invalid timestamp must not prevent offline use.
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

Future<String> _readBundledCatalog(ShipSubtitleLanguage language) async {
  if (language == ShipSubtitleLanguage.korean) {
    final bundle = await compute(
      ShipSubtitleKc3Bundle.fromJsonString,
      await rootBundle.loadString(
        ShipSubtitleKc3Bundle.bundledAsset,
        cache: false,
      ),
    );
    return bundle.korean.toJsonString();
  }
  return rootBundle.loadString(language.bundledAsset, cache: false);
}

Future<ShipSubtitleCatalog> _readCatalog(File file) async =>
    compute(ShipSubtitleCatalog.fromJsonString, await file.readAsString());

String _encodeCatalog(ShipSubtitleCatalog catalog) => catalog.toJsonString();

/// A validated new file is installed with a recoverable backup on all platforms.
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
