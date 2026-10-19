import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'ship_subtitle_catalog.dart';
import 'ship_subtitle_language.dart';

const kcwikiSubtitleLanguages = [
  ShipSubtitleLanguage.simplifiedChinese,
  ShipSubtitleLanguage.traditionalChinese,
  ShipSubtitleLanguage.japanese,
];

/// The three kcwiki catalogs are published in one recoverable file. Attempt
/// times remain separate from the last successful check shown to the user.
final class ShipSubtitleResourceState {
  const ShipSubtitleResourceState({
    this.catalogs = const {},
    this.kcwikiLastCheckedAt,
    this.kcwikiLastAttemptAt,
    this.kc3LastAttemptAt,
  });

  final Map<ShipSubtitleLanguage, ShipSubtitleCatalog> catalogs;
  final DateTime? kcwikiLastCheckedAt;
  final DateTime? kcwikiLastAttemptAt;
  final DateTime? kc3LastAttemptAt;

  ShipSubtitleResourceState withBestOfflineCatalogs(
    Map<ShipSubtitleLanguage, ShipSubtitleCatalog> offline,
  ) {
    if (offline.length != kcwikiSubtitleLanguages.length ||
        kcwikiSubtitleLanguages.any(
          (language) => !offline.containsKey(language),
        ) ||
        offline.values.map((catalog) => catalog.version).toSet().length != 1) {
      throw const FormatException(
        'The offline subtitle language group is incomplete.',
      );
    }
    if (catalogs.isEmpty) return copyWith(catalogs: Map.unmodifiable(offline));
    if (catalogs.values.first.version.compareTo(offline.values.first.version) >=
        0) {
      return this;
    }
    // A newer app snapshot supersedes both the downloaded group and metadata
    // describing that older group. Its first automatic check is due again.
    return ShipSubtitleResourceState(
      catalogs: Map.unmodifiable(offline),
      kc3LastAttemptAt: kc3LastAttemptAt,
    );
  }

  ShipSubtitleResourceState copyWith({
    Map<ShipSubtitleLanguage, ShipSubtitleCatalog>? catalogs,
    DateTime? kcwikiLastCheckedAt,
    DateTime? kcwikiLastAttemptAt,
    DateTime? kc3LastAttemptAt,
  }) => ShipSubtitleResourceState(
    catalogs: catalogs ?? this.catalogs,
    kcwikiLastCheckedAt: kcwikiLastCheckedAt ?? this.kcwikiLastCheckedAt,
    kcwikiLastAttemptAt: kcwikiLastAttemptAt ?? this.kcwikiLastAttemptAt,
    kc3LastAttemptAt: kc3LastAttemptAt ?? this.kc3LastAttemptAt,
  );

  Map<String, dynamic> toJson() => {
    'catalogs': {
      for (final entry in catalogs.entries)
        entry.key.code: entry.value.toJson(),
    },
    'kcwikiLastCheckedAt': kcwikiLastCheckedAt?.toUtc().toIso8601String(),
    'kcwikiLastAttemptAt': kcwikiLastAttemptAt?.toUtc().toIso8601String(),
    'kc3LastAttemptAt': kc3LastAttemptAt?.toUtc().toIso8601String(),
  };

  factory ShipSubtitleResourceState.fromJson(Map<String, dynamic> source) {
    final raw = source['catalogs'];
    if (raw is! Map) {
      throw const FormatException('Invalid subtitle resource state.');
    }
    final catalogs = <ShipSubtitleLanguage, ShipSubtitleCatalog>{};
    for (final language in kcwikiSubtitleLanguages) {
      final value = raw[language.code];
      if (value != null) {
        if (value is! Map<String, dynamic>) {
          throw const FormatException('Invalid subtitle group catalog.');
        }
        catalogs[language] = ShipSubtitleCatalog.fromJson(value);
      }
    }
    if (catalogs.isNotEmpty &&
        (catalogs.length != 3 ||
            catalogs.values.map((data) => data.version).toSet().length != 1)) {
      throw const FormatException('Subtitle group versions disagree.');
    }
    DateTime? time(String key) => switch (source[key]) {
      final String value => DateTime.tryParse(value)?.toUtc(),
      _ => null,
    };
    return ShipSubtitleResourceState(
      catalogs: Map.unmodifiable(catalogs),
      kcwikiLastCheckedAt: time('kcwikiLastCheckedAt'),
      kcwikiLastAttemptAt: time('kcwikiLastAttemptAt'),
      kc3LastAttemptAt: time('kc3LastAttemptAt'),
    );
  }
}

abstract interface class ShipSubtitleResourceStateStore {
  Future<ShipSubtitleResourceState> load();
  Future<void> save(ShipSubtitleResourceState state);
}

final class FileShipSubtitleResourceStateStore
    implements ShipSubtitleResourceStateStore {
  FileShipSubtitleResourceStateStore(this.file);
  factory FileShipSubtitleResourceStateStore.inDirectory(Directory directory) =>
      FileShipSubtitleResourceStateStore(
        File(path.join(directory.path, 'ship-subtitle-resources.json')),
      );
  static Future<FileShipSubtitleResourceStateStore> create() async =>
      FileShipSubtitleResourceStateStore.inDirectory(
        await getApplicationSupportDirectory(),
      );
  final File file;
  Map<ShipSubtitleLanguage, WeakReference<ShipSubtitleCatalog>>? _savedCatalogs;
  bool _snapshotNeedsRecovery = false;
  File get _metadataFile => File('${file.path}.state');

  @override
  Future<ShipSubtitleResourceState> load() async {
    var state = const ShipSubtitleResourceState();
    _snapshotNeedsRecovery = false;
    for (final candidate in [file, File('${file.path}.bak')]) {
      try {
        state = await compute(
          _decodeResourceState,
          await candidate.readAsBytes(),
        );
        _snapshotNeedsRecovery = candidate.path != file.path;
        break;
      } on Object {
        // Missing or damaged downloaded state never prevents offline use.
      }
    }
    if (_snapshotNeedsRecovery) {
      try {
        await _recoverSnapshot();
      } on Object {
        // Keep the valid backup for offline use. A later complete replacement
        // must restore it first, before the normal writer can rotate backups.
      }
    }
    _rememberCatalogs(state.catalogs);
    for (final candidate in [
      _metadataFile,
      File('${_metadataFile.path}.bak'),
    ]) {
      try {
        final metadata = jsonDecode(await candidate.readAsString());
        if (metadata is! Map<String, dynamic> ||
            metadata['schema'] != 1 ||
            metadata['groupVersion'] != _groupVersion(state.catalogs)) {
          continue;
        }
        DateTime? newest(String key, DateTime? baseline) {
          final raw = metadata[key];
          final value = raw is String ? DateTime.tryParse(raw)?.toUtc() : null;
          return value != null && (baseline == null || value.isAfter(baseline))
              ? value
              : baseline;
        }

        return state.copyWith(
          kcwikiLastCheckedAt: newest(
            'kcwikiLastCheckedAt',
            state.kcwikiLastCheckedAt,
          ),
          kcwikiLastAttemptAt: newest(
            'kcwikiLastAttemptAt',
            state.kcwikiLastAttemptAt,
          ),
          kc3LastAttemptAt: newest('kc3LastAttemptAt', state.kc3LastAttemptAt),
        );
      } on Object {
        // A torn metadata update cannot invalidate the complete data group.
      }
    }
    return state;
  }

  @override
  Future<void> save(ShipSubtitleResourceState state) async {
    final sameCatalogs =
        _savedCatalogs != null &&
        _savedCatalogs!.length == state.catalogs.length &&
        state.catalogs.entries.every(
          (entry) => identical(_savedCatalogs![entry.key]?.target, entry.value),
        );
    final emptyWithoutSnapshot =
        _savedCatalogs == null &&
        state.catalogs.isEmpty &&
        !await file.exists();
    if (sameCatalogs || emptyWithoutSnapshot) {
      // Update attempts and successful checks normally change only a few bytes.
      // The complete group's baseline remains valid if this sidecar is lost.
      await _replaceResourceFile(
        _metadataFile,
        utf8.encode(
          jsonEncode({
            'schema': 1,
            'groupVersion': _groupVersion(state.catalogs),
            'kcwikiLastCheckedAt': state.kcwikiLastCheckedAt
                ?.toUtc()
                .toIso8601String(),
            'kcwikiLastAttemptAt': state.kcwikiLastAttemptAt
                ?.toUtc()
                .toIso8601String(),
            'kc3LastAttemptAt': state.kc3LastAttemptAt
                ?.toUtc()
                .toIso8601String(),
          }),
        ),
      );
    } else {
      await _recoverSnapshot();
      await _replaceResourceFile(
        file,
        await compute(_encodeResourceState, state),
      );
    }
    _rememberCatalogs(state.catalogs);
  }

  Future<void> _recoverSnapshot() async {
    if (!_snapshotNeedsRecovery) return;
    // This flag is set only after the primary failed to load and its backup
    // passed complete validation. Never delete that sole valid backup.
    if (await file.exists()) await file.delete();
    await File('${file.path}.bak').rename(file.path);
    _snapshotNeedsRecovery = false;
  }

  void _rememberCatalogs(
    Map<ShipSubtitleLanguage, ShipSubtitleCatalog> catalogs,
  ) => _savedCatalogs = {
    for (final entry in catalogs.entries) entry.key: WeakReference(entry.value),
  };
}

String? _groupVersion(
  Map<ShipSubtitleLanguage, ShipSubtitleCatalog> catalogs,
) => catalogs.isEmpty ? null : catalogs.values.first.version;

ShipSubtitleResourceState _decodeResourceState(List<int> source) {
  final decoded = jsonDecode(utf8.decode(source));
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Invalid subtitle resource state.');
  }
  return ShipSubtitleResourceState.fromJson(decoded);
}

List<int> _encodeResourceState(ShipSubtitleResourceState state) =>
    utf8.encode(jsonEncode(state.toJson()));

Future<void> _replaceResourceFile(File target, List<int> source) async {
  final temporary = File('${target.path}.tmp');
  final backup = File('${target.path}.bak');
  await target.parent.create(recursive: true);
  try {
    await temporary.writeAsBytes(source, flush: true);
    if (await backup.exists()) await backup.delete();
    if (await target.exists()) await target.rename(backup.path);
    try {
      await temporary.rename(target.path);
    } on Object {
      if (await backup.exists()) await backup.rename(target.path);
      rethrow;
    }
    if (await backup.exists()) await backup.delete();
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}
