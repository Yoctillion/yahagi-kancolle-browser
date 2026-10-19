import 'package:flutter/widgets.dart';

import '../subtitles/ship_subtitle_kc3_bundle.dart';
import '../subtitles/ship_subtitle_language.dart';

/// Display-only entity translations. Game state and stored names stay original.
/// Chinese and Japanese interfaces deliberately retain their existing names.
final class GameNameCatalog {
  GameNameCatalog({this.bundle, required this.locale});

  final ShipSubtitleKc3Bundle? bundle;
  final Locale locale;
  late final _uniqueShipAliases = _combinedReverse([
    for (final language in _chineseLanguages)
      if (bundle?.names[language] case final source?) source.ships,
  ]);
  late final _uniqueItemAliases = _combinedReverse([
    for (final language in _chineseLanguages)
      if (bundle?.entityNames[language] case final source?) source.items,
  ]);
  late final _reverseShips = {
    for (final language in _chineseLanguages)
      if (bundle?.names[language] case final source?)
        language: _reversedShipNames(source, _uniqueShipAliases),
  };
  late final _entityIndex = _buildEntityIndex();
  late final _shipTypeAliases = _typeAliases(ship: true);
  late final _equipmentTypeAliases = _typeAliases(ship: false);
  late final _shipNameResults = _BoundedTranslationCache<(String, int?)>(
    maximumEntries: 2048,
    maximumCharacters: 128 * 1024,
    maximumInputCharacters: 512,
  );
  late final _entityTextResults = _BoundedTranslationCache<String>(
    maximumEntries: 2048,
    maximumCharacters: 512 * 1024,
    maximumInputCharacters: 8192,
  );

  ShipSubtitleLanguage? get _language => switch (locale.languageCode) {
    'en' => ShipSubtitleLanguage.english,
    'ko' => ShipSubtitleLanguage.korean,
    _ => null,
  };
  GameNameDictionary? get _dictionary => bundle?.entityNames[_language];

  String shipName(String rawName, {int? shipId}) {
    final language = _language;
    final data = bundle;
    if (language == null || data == null) return rawName;
    final key = (rawName, shipId);
    final cached = _shipNameResults.lookup(key);
    if (cached != null) return cached;
    final translated = _resolveShipName(data, language, rawName, shipId);
    _shipNameResults.store(key, translated, inputCharacters: rawName.length);
    return translated;
  }

  String _resolveShipName(
    ShipSubtitleKc3Bundle data,
    ShipSubtitleLanguage language,
    String rawName,
    int? shipId,
  ) {
    final direct = data.shipName(language, rawName, shipId: shipId);
    if (direct != rawName) return direct;
    for (final source in _chineseLanguages) {
      final sourceNames = data.names[source];
      if (sourceNames == null) continue;
      final reverse = _reverseShips[source];
      final japanese = reverse?.shipName(rawName) ?? rawName;
      if (japanese != rawName) {
        final translated = data.shipName(language, japanese, shipId: shipId);
        if (translated != japanese) return translated;
      }
    }
    return rawName;
  }

  String equipmentName(String rawName) {
    final target = _dictionary;
    if (target == null) return rawName;
    final direct = target.items[rawName];
    if (direct != null) return direct;
    return target.items[_uniqueItemAliases[rawName]] ?? rawName;
  }

  String shipTypeName(String rawName, {int? typeId}) {
    final target = _dictionary;
    if (target == null) return rawName;
    if (_installationTypes.contains(rawName)) {
      return _language == ShipSubtitleLanguage.korean
          ? '육상기지'
          : 'Land Installation';
    }
    final id =
        typeId ?? _shipTypeIds[rawName] ?? _reverseType(rawName, ship: true);
    return target.shipType(id) ?? rawName;
  }

  String equipmentTypeName(String rawName, {int? typeId}) {
    final target = _dictionary;
    if (target == null) return rawName;
    final id =
        typeId ??
        _equipmentTypeIds[rawName] ??
        _reverseType(rawName, ship: false);
    return target.equipmentType(id) ?? rawName;
  }

  int? _reverseType(String rawName, {required bool ship}) {
    return (ship ? _shipTypeAliases : _equipmentTypeAliases)[rawName];
  }

  Map<String, int> _typeAliases({required bool ship}) {
    final aliases = <String, Set<int>>{};
    for (final dictionary in bundle!.entityNames.values) {
      final values = ship ? dictionary.shipTypes : dictionary.equipmentTypes[2];
      for (var index = 1; index < values.length; index++) {
        final value = values[index];
        if (value.isNotEmpty && value != '?') {
          aliases.putIfAbsent(value, () => <int>{}).add(index);
        }
      }
    }
    return {
      for (final entry in aliases.entries)
        if (entry.value.length == 1) entry.key: entry.value.single,
    };
  }

  /// For fields known to contain entity names, never arbitrary interface prose.
  /// A single replacement pass prevents translated names being translated again.
  String entityText(String text) {
    if (_dictionary == null || text.isEmpty) return text;
    final cached = _entityTextResults.lookup(text);
    if (cached != null) return cached;
    final translated = _resolveEntityText(text);
    _entityTextResults.store(text, translated, inputCharacters: text.length);
    return translated;
  }

  String _resolveEntityText(String text) {
    final index = _entityIndex;
    StringBuffer? output;
    var copiedThrough = 0;
    var offset = 0;
    while (offset < text.length) {
      final exactMatch = index.exactPattern.matchAsPrefix(text, offset);
      final shipMatch = index.shipsPattern.matchAsPrefix(text, offset);
      final match =
          exactMatch == null ||
              (shipMatch != null && shipMatch.end > exactMatch.end)
          ? shipMatch
          : exactMatch;
      if (match == null) {
        offset++;
        continue;
      }
      final raw = match.group(0)!;
      final translated = switch (index.kinds[raw]) {
        _EntityKind.equipment => equipmentName(raw),
        _EntityKind.shipType => shipTypeName(raw),
        _EntityKind.equipmentType => equipmentTypeName(raw),
        _EntityKind.ship || null => shipName(raw),
      };
      if (translated != raw) {
        output ??= StringBuffer();
        output.write(text.substring(copiedThrough, offset));
        output.write(translated);
        copiedThrough = match.end;
      }
      offset = match.end;
    }
    if (output == null) return text;
    output.write(text.substring(copiedThrough));
    return output.toString();
  }

  ({
    Map<String, _EntityKind> kinds,
    _InitialPatterns exactPattern,
    _InitialPatterns shipsPattern,
  })
  _buildEntityIndex() {
    // Resolve only words actually encountered. Eagerly translating every entry
    // needlessly parses thousands of remodel names when the first field opens.
    final kinds = <String, _EntityKind>{};
    final shipPatterns = <int, List<String Function()>>{};
    for (final entry in bundle!.names.entries) {
      final names = entry.value;
      for (final raw in names.ships.keys) {
        kinds[raw] = _EntityKind.ship;
      }
      if (_chineseLanguages.contains(entry.key)) {
        for (final localized in _uniqueShipAliases.keys) {
          kinds[localized] = _EntityKind.ship;
        }
      }
      if (entry.key == _language || _chineseLanguages.contains(entry.key)) {
        final prefixes = <String>{...names.affix['prefixes']!.keys};
        final suffixes = <String>{...names.affix['suffixes']!.keys};
        if (_chineseLanguages.contains(entry.key)) {
          prefixes.addAll(
            names.affix['prefixes']!.values.where(
              (value) => !value.endsWith(r'$'),
            ),
          );
          suffixes.addAll(
            names.affix['suffixes']!.values.where(
              (value) => !value.startsWith('^'),
            ),
          );
        }
        final roots = <String>{...names.ships.keys};
        if (_chineseLanguages.contains(entry.key)) {
          roots.addAll(_uniqueShipAliases.keys);
        }
        final sortedPrefixes = _longestFirst(prefixes);
        final suffix = _optionalAffixes(suffixes);
        final sortedRoots = _longestFirst(roots);
        final rootPattern = _alternatives(sortedRoots);
        final prefixPattern = _alternatives(sortedPrefixes);
        final prefixGroups = _initialGroups(sortedPrefixes);
        final rootGroups = _initialGroups(sortedRoots);
        final starts = {...prefixGroups.keys, ...rootGroups.keys};
        for (final first in starts) {
          final firstPrefixes = prefixGroups[first] ?? const <String>[];
          final firstRoots = rootGroups[first] ?? const <String>[];
          // Expanding greedy prefix{0,8} into prefix + prefix{0,7}, then its
          // zero-prefix branch keeps the original order and backtracking rules.
          // Filtering the first token cannot remove a match at this character.
          shipPatterns.putIfAbsent(first, () => <String Function()>[]).add(() {
            final branches = <String>[
              if (firstPrefixes.isNotEmpty)
                '${_alternatives(firstPrefixes)}$prefixPattern{0,7}$rootPattern$suffix',
              if (firstRoots.isNotEmpty) '${_alternatives(firstRoots)}$suffix',
            ];
            return _alternatives(branches, escape: false);
          });
        }
      }
    }
    for (final dictionary in bundle!.entityNames.values) {
      for (final raw in dictionary.items.keys) {
        kinds[raw] = _EntityKind.equipment;
      }
    }
    for (final localized in _uniqueItemAliases.keys) {
      kinds[localized] = _EntityKind.equipment;
    }
    for (final raw in _shipTypeIds.keys) {
      kinds.putIfAbsent(raw, () => _EntityKind.shipType);
    }
    for (final raw in _installationTypes) {
      kinds.putIfAbsent(raw, () => _EntityKind.shipType);
    }
    for (final raw in _equipmentTypeIds.keys) {
      kinds.putIfAbsent(raw, () => _EntityKind.equipmentType);
    }
    for (final raw in _shipTypeAliases.keys) {
      kinds.putIfAbsent(raw, () => _EntityKind.shipType);
    }
    for (final raw in _equipmentTypeAliases.keys) {
      kinds.putIfAbsent(raw, () => _EntityKind.equipmentType);
    }
    final exact = _longestFirst(kinds.keys);
    // Match all candidates at each position and keep the longest, including
    // complete remodel forms rather than a shorter base-name replacement.
    final exactPattern = _InitialPatterns({
      for (final entry in _initialGroups(exact).entries)
        entry.key: () => entry.value.map(RegExp.escape).join('|'),
    });
    final shipsPattern = _InitialPatterns({
      for (final entry in shipPatterns.entries)
        entry.key: () => entry.value.map((build) => build()).join('|'),
    });
    return (
      kinds: kinds,
      exactPattern: exactPattern,
      shipsPattern: shipsPattern,
    );
  }
}

const _chineseLanguages = [
  ShipSubtitleLanguage.simplifiedChinese,
  ShipSubtitleLanguage.traditionalChinese,
];

Map<String, String> _uniqueReverse(Map<String, String> source) {
  return _combinedReverse([source]);
}

Map<String, String> _combinedReverse(Iterable<Map<String, String>> sources) {
  final result = <String, String>{};
  final ambiguous = <String>{};
  for (final entry in sources.expand((source) => source.entries)) {
    if (result.containsKey(entry.value) && result[entry.value] != entry.key) {
      ambiguous.add(entry.value);
    } else {
      result[entry.value] = entry.key;
    }
  }
  for (final value in ambiguous) {
    result.remove(value);
  }
  return result;
}

ShipSubtitleNameCatalog? _reversedShipNames(
  ShipSubtitleNameCatalog source,
  Map<String, String> uniqueAliases,
) {
  final prefixes = <String, String>{};
  final suffixes = <String, String>{};
  for (final entry in source.affix['prefixes']!.entries) {
    if (entry.value.endsWith(r'$')) {
      suffixes[entry.value.substring(0, entry.value.length - 1)] =
          '^${entry.key}';
    } else {
      prefixes[entry.value] = entry.key;
    }
  }
  for (final entry in source.affix['suffixes']!.entries) {
    if (entry.value.startsWith('^')) {
      prefixes[entry.value.substring(1)] = '${entry.key}\$';
    } else {
      suffixes[entry.value] = entry.key;
    }
  }
  prefixes.remove('');
  suffixes.remove('');
  final ships = {
    for (final entry in _uniqueReverse(source.ships).entries)
      if (uniqueAliases[entry.key] == entry.value) entry.key: entry.value,
  };
  if (ships.isEmpty || suffixes.isEmpty) return null;
  return ShipSubtitleNameCatalog.fromJson({
    'ships': ships,
    'affix': {'prefixes': prefixes, 'suffixes': suffixes},
  });
}

String _optionalAffixes(Set<String> source) {
  final values = _longestFirst(source);
  return values.isEmpty
      ? ''
      : '(?:${values.map(RegExp.escape).join('|')}){0,8}';
}

enum _EntityKind { ship, equipment, shipType, equipmentType }

List<String> _longestFirst(Iterable<String> source) =>
    source.where((value) => value.isNotEmpty).toList()
      ..sort((a, b) => b.length.compareTo(a.length));

String _alternatives(Iterable<String> values, {bool escape = true}) =>
    '(?:${(escape ? values.map(RegExp.escape) : values).join('|')})';

Map<int, List<String>> _initialGroups(Iterable<String> values) {
  final groups = <int, List<String>>{};
  for (final value in values) {
    if (value.isNotEmpty) {
      groups.putIfAbsent(value.codeUnitAt(0), () => <String>[]).add(value);
    }
  }
  return groups;
}

/// Build and compile only initials a field encounters. Unused ship buckets share
/// root/prefix/suffix fragments instead of retaining a large combined source for
/// every initial. Candidate order and prefix backtracking remain unchanged.
final class _InitialPatterns {
  _InitialPatterns(this._builders);

  final Map<int, String Function()> _builders;
  final _compiled = <int, RegExp>{};

  Match? matchAsPrefix(String text, int offset) {
    final first = text.codeUnitAt(offset);
    var pattern = _compiled[first];
    if (pattern == null) {
      final build = _builders.remove(first);
      if (build == null) return null;
      pattern = _compiled[first] = RegExp(build());
    }
    return pattern.matchAsPrefix(text, offset);
  }
}

/// Insertion-ordered result reuse without per-hit list churn. Both entry count
/// and retained input/output characters are bounded; large log fields bypass
/// the cache. The task corpus and visible labels fit without cyclic eviction.
final class _BoundedTranslationCache<K> {
  _BoundedTranslationCache({
    required this.maximumEntries,
    required this.maximumCharacters,
    required this.maximumInputCharacters,
  });

  final int maximumEntries;
  final int maximumCharacters;
  final int maximumInputCharacters;
  final _entries = <K, ({String text, int characters})>{};
  var _characters = 0;

  String? lookup(K key) => _entries[key]?.text;

  void store(K key, String text, {required int inputCharacters}) {
    final characters = inputCharacters + text.length;
    if (inputCharacters > maximumInputCharacters ||
        characters > maximumCharacters) {
      return;
    }
    while (_entries.length >= maximumEntries ||
        _characters + characters > maximumCharacters) {
      final oldest = _entries.remove(_entries.keys.first)!;
      _characters -= oldest.characters;
    }
    _entries[key] = (text: text, characters: characters);
    _characters += characters;
  }
}

// Canonical game labels and common abbreviated source labels. Live UI callers
// should pass the master-data ID whenever available.
const _shipTypeIds = <String, int>{
  'DE': 1,
  'DD': 2,
  'CL': 3,
  'CLT': 4,
  'CA': 5,
  'CAV': 6,
  'CVL': 7,
  'FBB': 8,
  'BB': 9,
  'BBV': 10,
  'CV': 11,
  'XBB': 12,
  'SS': 13,
  'SSV': 14,
  'AP': 15,
  'AV': 16,
  'LHA': 17,
  'CVB': 18,
  'AR': 19,
  'AS': 20,
  'CT': 21,
  'AO': 22,
  'CVE': 30,
  '海防': 1,
  '駆逐': 2,
  '驅逐': 2,
  '驱逐': 2,
  '驱逐舰': 2,
  '驅逐艦': 2,
  '轻巡': 3,
  '輕巡': 3,
  '轻巡洋舰': 3,
  '輕巡洋艦': 3,
  '重雷装巡洋舰': 4,
  '重雷裝巡洋艦': 4,
  '重巡洋舰': 5,
  '航空巡洋舰': 6,
  '轻母': 7,
  '輕母': 7,
  '轻空母': 7,
  '輕空母': 7,
  '高速战舰': 8,
  '高戦': 8,
  '高戰': 8,
  '战舰': 9,
  '戰艦': 9,
  '航空战舰': 10,
  '航空戰艦': 10,
  '航战': 10,
  '航戰': 10,
  '正规航母': 11,
  '正規航母': 11,
  '空母': 11,
  '航母': 11,
  '潜水舰': 13,
  '潛水艦': 13,
  '潜水航母': 14,
  '潛水航母': 14,
  '运输舰': 15,
  '運輸艦': 15,
  '水上机母舰': 16,
  '水母': 16,
  '扬陆舰': 17,
  '登陸艦': 17,
  '装甲航母': 18,
  '裝甲航母': 18,
  '潜水母舰': 20,
  '潛水母艦': 20,
  '潜母': 20,
  '潛母': 20,
  '练习巡洋舰': 21,
  '練巡': 21,
  '练巡': 21,
  '补给舰': 22,
  '補給艦': 22,
  '補給': 22,
  '海防艦': 1,
  '駆逐艦': 2,
  '軽巡洋艦': 3,
  '軽巡': 3,
  '重雷装巡洋艦': 4,
  '雷巡': 4,
  '重巡洋艦': 5,
  '重巡': 5,
  '航空巡洋艦': 6,
  '航巡': 6,
  '軽空母': 7,
  '軽航空母艦': 7,
  '巡洋戦艦': 8,
  '高速戦艦': 8,
  '戦艦': 9,
  '航空戦艦': 10,
  '航戦': 10,
  '正規空母': 11,
  '超弩級戦艦': 12,
  '潜水艦': 13,
  '潜水空母': 14,
  '潜水航空母艦': 14,
  '水上機母艦': 16,
  '揚陸艦': 17,
  '装甲空母': 18,
  '工作艦': 19,
  '潜水母艦': 20,
  '練習巡洋艦': 21,
  '補給艦(速吸)': 22,
};

// Enemy-map data uses this class outside the game's numbered ship-type table.
const _installationTypes = {'陸上施設', '陆上设施', '陸上設施'};

const _equipmentTypeIds = <String, int>{
  '小口径主砲': 1,
  '中口径主砲': 2,
  '大口径主砲': 3,
  '副砲': 4,
  '魚雷': 5,
  '艦上戦闘機': 6,
  '艦上爆撃機': 7,
  '艦上攻撃機': 8,
  '艦上偵察機': 9,
  '水上偵察機': 10,
  '水上爆撃機': 11,
  '小型電探': 12,
  '大型電探': 13,
  'ソナー': 14,
  '爆雷投射機': 15,
  '追加装甲': 16,
  '機関部強化': 17,
  '対空強化弾': 18,
  '対艦強化弾': 19,
  'VT信管': 20,
  '対空機銃': 21,
  '特殊潜航艇': 22,
  '応急修理要員': 23,
  '上陸用舟艇': 24,
  '回転翼機': 25,
  '対潜哨戒機': 26,
  '追加装甲(中型)': 27,
  '追加装甲(大型)': 28,
  '探照灯': 29,
  '簡易輸送部材': 30,
  '艦艇修理施設': 31,
  '潜水艦魚雷': 32,
  '照明弾': 33,
  '艦隊司令部施設': 34,
  '航空要員': 35,
  '高射装置': 36,
  '対地装備': 37,
  '大口径主砲(II)': 38,
  '水上艦要員': 39,
  '大型ソナー': 40,
  '大型飛行艇': 41,
  '大型探照灯': 42,
  '戦闘糧食': 43,
  '補給物資': 44,
  '水上戦闘機': 45,
  '特型内火艇': 46,
  '陸上攻撃機': 47,
  '局地戦闘機': 48,
  '陸上偵察機': 49,
  '輸送機材': 50,
  '潜水艦装備': 51,
  '陸戦部隊': 52,
  '大型陸上機': 53,
  '水上艦装備': 54,
  '噴式戦闘機': 56,
  '噴式戦闘爆撃機': 57,
  '噴式攻撃機': 58,
  '噴式偵察機': 59,
  '大型電探(II)': 93,
  '艦上偵察機(II)': 94,
  '副砲(II)': 95,
};
