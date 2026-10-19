import 'dart:convert';

import '../localization/game_name_dictionary.dart';
import 'ship_subtitle_catalog.dart';
import 'ship_subtitle_language.dart';
import 'ship_subtitle_name_catalog.dart';

export 'ship_subtitle_name_catalog.dart';
export '../localization/game_name_dictionary.dart';

/// English/Korean voice text and all translated ship names from one SHA.
final class ShipSubtitleKc3Bundle {
  const ShipSubtitleKc3Bundle._({
    required this.version,
    required this.commit,
    required this.english,
    required this.korean,
    required this.names,
    required this.entityNames,
  });

  factory ShipSubtitleKc3Bundle({
    required String version,
    required String commit,
    required ShipSubtitleCatalog english,
    required ShipSubtitleCatalog korean,
    required Map<ShipSubtitleLanguage, ShipSubtitleNameCatalog> names,
    required Map<ShipSubtitleLanguage, GameNameDictionary> entityNames,
  }) => ShipSubtitleKc3Bundle.fromJson({
    'schema': 3,
    'version': version,
    'commit': commit,
    'english': english.toJson(),
    'korean': korean.toJson(),
    'names': {
      for (final entry in names.entries) entry.key.code: entry.value.toJson(),
    },
    'entityNames': {
      for (final entry in entityNames.entries)
        entry.key.code: entry.value.toJson(),
    },
  });

  factory ShipSubtitleKc3Bundle.fromJsonString(String source) {
    final value = jsonDecode(source);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('KC3 bundle must be an object.');
    }
    return ShipSubtitleKc3Bundle.fromJson(value);
  }

  factory ShipSubtitleKc3Bundle.fromJson(Map<String, dynamic> source) {
    final version = validateVersion(source['version']);
    final commit = validateCommit(source['commit']);
    final rawEnglish = source['english'];
    final rawKorean = source['korean'];
    final rawNames = source['names'];
    final rawEntities = source['entityNames'];
    if (source['schema'] != 3 ||
        rawEnglish is! Map<String, dynamic> ||
        rawKorean is! Map<String, dynamic> ||
        rawNames is! Map<String, dynamic> ||
        rawNames.length != _languages.length ||
        rawEntities is! Map<String, dynamic> ||
        rawEntities.length != _languages.length) {
      throw const FormatException('KC3 bundle is incomplete.');
    }
    final english = ShipSubtitleCatalog.fromJson(rawEnglish);
    final korean = ShipSubtitleCatalog.fromJson(rawKorean);
    if (english.version != version || korean.version != version) {
      throw const FormatException('KC3 quote versions do not match bundle.');
    }
    final names = <ShipSubtitleLanguage, ShipSubtitleNameCatalog>{};
    final entities = <ShipSubtitleLanguage, GameNameDictionary>{};
    for (final language in _languages.keys) {
      final raw = rawNames[language.code];
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('KC3 name language is missing.');
      }
      names[language] = ShipSubtitleNameCatalog.fromJson(raw);
      final rawEntity = rawEntities[language.code];
      if (rawEntity is! Map<String, dynamic>) {
        throw const FormatException('KC3 equipment language is missing.');
      }
      entities[language] = GameNameDictionary.fromJson(rawEntity);
    }
    return ShipSubtitleKc3Bundle._(
      version: version,
      commit: commit,
      english: english,
      korean: korean,
      names: Map.unmodifiable(names),
      entityNames: Map.unmodifiable(entities),
    );
  }

  factory ShipSubtitleKc3Bundle.fromKc3Files({
    required String version,
    required String commit,
    required Map<String, dynamic> files,
  }) {
    validateVersion(version);
    validateCommit(commit);
    if (files.length != sourcePaths.length ||
        sourcePaths.any((path) => !files.containsKey(path))) {
      throw const FormatException('KC3 source group is incomplete.');
    }
    return ShipSubtitleKc3Bundle(
      version: version,
      commit: commit,
      english: ShipSubtitleCatalog.fromKc3Json(
        _objectFile(files, 'data/en/quotes.json'),
        version: version,
      ),
      korean: ShipSubtitleCatalog.fromKc3Json(
        _objectFile(files, 'data/kr/quotes.json'),
        version: version,
      ),
      names: {
        for (final entry in _languages.entries)
          entry.key: ShipSubtitleNameCatalog.fromJson({
            'ships': files['data/${entry.value}/ships.json'],
            'affix': files['data/${entry.value}/ship_affix.json'],
          }),
      },
      entityNames: {
        for (final entry in _languages.entries)
          entry.key: GameNameDictionary.fromJson({
            'items': files['data/${entry.value}/items.json'],
            'stype': files['data/${entry.value}/stype.json'],
            'equiptype': files['data/${entry.value}/equiptype.json'],
          }),
      },
    );
  }

  static const bundledAsset = 'assets/data/subtitles/kc3-bundle.json';
  static const sourcePaths = [
    'data/en/quotes.json',
    'data/scn/ships.json',
    'data/scn/ship_affix.json',
    'data/tcn/ships.json',
    'data/tcn/ship_affix.json',
    'data/en/ships.json',
    'data/en/ship_affix.json',
    'data/kr/quotes.json',
    'data/kr/ships.json',
    'data/kr/ship_affix.json',
    'data/scn/items.json',
    'data/scn/stype.json',
    'data/scn/equiptype.json',
    'data/tcn/items.json',
    'data/tcn/stype.json',
    'data/tcn/equiptype.json',
    'data/en/items.json',
    'data/en/stype.json',
    'data/en/equiptype.json',
    'data/kr/items.json',
    'data/kr/stype.json',
    'data/kr/equiptype.json',
  ];
  static const _languages = {
    ShipSubtitleLanguage.simplifiedChinese: 'scn',
    ShipSubtitleLanguage.traditionalChinese: 'tcn',
    ShipSubtitleLanguage.english: 'en',
    ShipSubtitleLanguage.korean: 'kr',
  };

  static String validateCommit(Object? value) {
    if (value is! String || !RegExp(r'^[0-9a-f]{40}$').hasMatch(value)) {
      throw const FormatException('KC3 commit SHA is invalid.');
    }
    return value;
  }

  static String validateVersion(Object? value) {
    if (value is! String || !RegExp(r'^\d{14}$').hasMatch(value)) {
      throw const FormatException('KC3 bundle version is invalid.');
    }
    final iso =
        '${value.substring(0, 4)}-${value.substring(4, 6)}-${value.substring(6, 8)}T'
        '${value.substring(8, 10)}:${value.substring(10, 12)}:${value.substring(12, 14)}Z';
    versionFromCommitDate(iso);
    return value;
  }

  static String versionFromCommitDate(Object? value) {
    if (value is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$').hasMatch(value)) {
      throw const FormatException('KC3 commit timestamp is invalid.');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null ||
        parsed.toUtc().toIso8601String().replaceFirst('.000Z', 'Z') != value) {
      throw const FormatException('KC3 commit timestamp is invalid.');
    }
    return value.replaceAll(RegExp(r'[^0-9]'), '');
  }

  final String version;
  final String commit;
  final ShipSubtitleCatalog english;
  final ShipSubtitleCatalog korean;
  final Map<ShipSubtitleLanguage, ShipSubtitleNameCatalog> names;
  final Map<ShipSubtitleLanguage, GameNameDictionary> entityNames;

  ShipSubtitleCatalog? catalogFor(ShipSubtitleLanguage language) =>
      switch (language) {
        ShipSubtitleLanguage.english => english,
        ShipSubtitleLanguage.korean => korean,
        _ => null,
      };

  String shipName(
    ShipSubtitleLanguage language,
    String rawName, {
    int? shipId,
  }) => names[language]?.shipName(rawName, shipId: shipId) ?? rawName;

  Map<String, dynamic> toJson() => {
    'schema': 3,
    'version': version,
    'commit': commit,
    'english': english.toJson(),
    'korean': korean.toJson(),
    'names': {
      for (final entry in names.entries) entry.key.code: entry.value.toJson(),
    },
    'entityNames': {
      for (final entry in entityNames.entries)
        entry.key.code: entry.value.toJson(),
    },
  };

  String toJsonString() => jsonEncode(toJson());
}

Map<String, dynamic> _objectFile(Map<String, dynamic> files, String path) {
  final value = files[path];
  if (value is! Map<String, dynamic>) {
    throw const FormatException('KC3 quote file is invalid.');
  }
  return value;
}
