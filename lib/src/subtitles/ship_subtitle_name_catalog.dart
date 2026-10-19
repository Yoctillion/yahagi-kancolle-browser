/// KC3 ship-name dictionaries, independent of the app interface language.
final class ShipSubtitleNameCatalog {
  const ShipSubtitleNameCatalog._({required this.ships, required this.affix});

  factory ShipSubtitleNameCatalog.fromJson(Map<String, dynamic> source) {
    final ships = _stringMap(source['ships'], allowEmpty: false);
    final rawAffix = source['affix'];
    if (rawAffix is! Map<String, dynamic> ||
        !rawAffix.containsKey('prefixes') ||
        !rawAffix.containsKey('suffixes')) {
      throw const FormatException('KC3 ship affixes are incomplete.');
    }
    final affix = <String, Map<String, String>>{};
    for (final entry in rawAffix.entries) {
      affix[entry.key] = _stringMap(entry.value);
    }
    if (affix['suffixes']!.isEmpty) {
      throw const FormatException('KC3 remodel suffixes are empty.');
    }
    return ShipSubtitleNameCatalog._(
      ships: ships,
      affix: Map.unmodifiable(affix),
    );
  }

  final Map<String, String> ships;
  final Map<String, Map<String, String>> affix;

  Map<String, dynamic> toJson() => {'ships': ships, 'affix': affix};

  /// Mirrors KC3Meta.shipNameById's positive-ID override, then shipName's exact
  /// match priority, prefix stack, longest suffix and ^/$ relocation markers.
  /// Unlike KC3, a root absent from ships keeps the entire original name.
  String shipName(String rawName, {int? shipId}) {
    final byId = shipId != null && shipId > 0
        ? (affix['byId']?['$shipId'])
        : null;
    if (byId != null) return _distinctNameDelimiter(byId);
    final exact = ships[rawName];
    if (exact != null) return _distinctNameDelimiter(exact);
    var root = rawName;
    final prefixes = <String>[];
    final suffixes = <String>[];
    final remainingPrefixes = Map<String, String>.of(affix['prefixes']!);
    final remainingSuffixes = Map<String, String>.of(affix['suffixes']!);
    while (root.isNotEmpty) {
      MapEntry<String, String>? match;
      for (final entry in remainingPrefixes.entries) {
        if (root.toLowerCase().startsWith(entry.key.toLowerCase())) {
          match = entry;
          break;
        }
      }
      if (match == null) break;
      root = root.substring(match.key.length);
      if (match.value.endsWith(r'$')) {
        suffixes.insert(0, match.value.substring(0, match.value.length - 1));
      } else {
        prefixes.insert(0, match.value);
      }
      remainingPrefixes.remove(match.key);
    }
    while (root.isNotEmpty) {
      MapEntry<String, String>? match;
      for (final entry in remainingSuffixes.entries) {
        // KC3's unanchored regex search tries the leftmost start first.
        if (root.toLowerCase().endsWith(entry.key.toLowerCase()) &&
            (match == null || entry.key.length > match.key.length)) {
          match = entry;
        }
      }
      if (match == null) break;
      root = root.substring(0, root.length - match.key.length);
      if (match.value.startsWith('^')) {
        prefixes.insert(0, match.value.substring(1));
      } else {
        suffixes.insert(0, match.value);
      }
      remainingSuffixes.remove(match.key);
    }
    final translated = ships[root];
    return translated == null
        ? rawName
        : _distinctNameDelimiter(
            '${prefixes.join()}$translated${suffixes.join()}',
          );
  }
}

/// KC3's enemy-name delimiters retain the first separator and remove later ones.
/// This is applied only to translated output, never to unknown raw names.
String _distinctNameDelimiter(String value) {
  var first = true;
  return value.replaceAllMapped(RegExp(r'\{(.*?)\}\?'), (match) {
    if (!first) return '';
    first = false;
    return match.group(1)!;
  });
}

Map<String, String> _stringMap(Object? value, {bool allowEmpty = true}) {
  if (value is! Map ||
      value.length > 100000 ||
      (!allowEmpty && value.isEmpty)) {
    throw const FormatException('KC3 name dictionary is invalid.');
  }
  final result = <String, String>{};
  for (final entry in value.entries) {
    if (entry.key is! String ||
        (entry.key as String).trim().isEmpty ||
        (entry.key as String).length > 512 ||
        entry.value is! String ||
        (entry.value as String).trim().isEmpty ||
        (entry.value as String).length > 1024) {
      throw const FormatException('KC3 name dictionary entry is invalid.');
    }
    result[entry.key as String] = entry.value as String;
  }
  return Map.unmodifiable(result);
}
