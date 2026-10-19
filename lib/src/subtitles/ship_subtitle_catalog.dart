import 'dart:convert';

/// Validated voice lines indexed by ship and voice IDs in the poi format.
final class ShipSubtitleCatalog {
  factory ShipSubtitleCatalog({
    required String version,
    required Map<String, Map<String, String>> quotes,
  }) => ShipSubtitleCatalog.fromJson({'version': version, ...quotes});

  const ShipSubtitleCatalog._({required this.version, required this.quotes});

  factory ShipSubtitleCatalog.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Subtitle catalog must be an object.');
    }
    return ShipSubtitleCatalog.fromJson(decoded);
  }

  /// Converts KC3's maintained English voice data into numeric voice IDs.
  /// Seasonal and friend-fleet labels require additional game context and are
  /// intentionally excluded instead of replacing an unrelated base voice.
  factory ShipSubtitleCatalog.fromKc3Json(
    Map<String, dynamic> source, {
    required String version,
  }) {
    final quotes = <String, Map<String, String>>{};
    for (final entry in source.entries) {
      if (!_identifier.hasMatch(entry.key)) continue;
      if (entry.value is! Map) {
        throw const FormatException('KC3 subtitle ship entry is invalid.');
      }
      final ship = <String, String>{};
      for (final quote in (entry.value as Map).entries) {
        final label = quote.key;
        if (label is! String) {
          throw const FormatException('KC3 subtitle voice label is invalid.');
        }
        final id =
            _kc3VoiceIds[label] ?? (_identifier.hasMatch(label) ? label : null);
        if (id == null) continue;
        final text = _kc3QuoteText(quote.value);
        if (text.isNotEmpty) ship[id] = text;
      }
      if (ship.isNotEmpty) quotes[entry.key] = ship;
    }
    return ShipSubtitleCatalog(version: version, quotes: quotes);
  }

  factory ShipSubtitleCatalog.fromJson(Map<String, dynamic> source) {
    final version = validateVersion(source['version']);
    final quotes = <String, Map<String, String>>{};
    var quoteCount = 0;
    for (final entry in source.entries) {
      if (entry.key == 'version') continue;
      if (!_identifier.hasMatch(entry.key) || entry.value is! Map) {
        throw const FormatException('Subtitle ship entry is invalid.');
      }
      final ship = <String, String>{};
      for (final quote in (entry.value as Map).entries) {
        if (quote.key is! String ||
            !_identifier.hasMatch(quote.key as String) ||
            quote.value is! String ||
            (quote.value as String).trim().isEmpty ||
            (quote.value as String).length > 8192) {
          throw const FormatException('Subtitle quote is invalid.');
        }
        ship[quote.key as String] = quote.value as String;
        if (++quoteCount > 1000000) {
          throw const FormatException('Subtitle catalog has too many quotes.');
        }
      }
      if (ship.isEmpty) {
        throw const FormatException('Subtitle ship entry has no quotes.');
      }
      quotes[entry.key] = Map.unmodifiable(ship);
    }
    if (quotes.isEmpty) {
      throw const FormatException('Subtitle catalog is empty.');
    }
    return ShipSubtitleCatalog._(
      version: version,
      quotes: Map.unmodifiable(quotes),
    );
  }

  static final _identifier = RegExp(r'^\d{1,8}$');

  static String validateVersion(Object? value) {
    if (value is! String || !RegExp(r'^(?:\d{10}|\d{14})$').hasMatch(value)) {
      throw const FormatException('Subtitle version is invalid.');
    }
    return value;
  }

  final String version;
  final Map<String, Map<String, String>> quotes;
  bool get isEmpty => quotes.isEmpty;
  int get quoteCount =>
      quotes.values.fold(0, (total, ship) => total + ship.length);

  Map<String, dynamic> toJson() => {'version': version, ...quotes};
  String toJsonString() => jsonEncode(toJson());
}

// KC3Kai/kc3-translations tools/convert-quotes.py (MIT), see bundled licenses.
final _kc3VoiceIds = <String, String>{
  'Intro': '1',
  'Library': '25',
  'Poke(1)': '2',
  'Poke(2)': '3',
  'Poke(3)': '4',
  'Married': '28',
  'Wedding': '24',
  'Ranking': '8',
  'Join': '13',
  'Equip(1)': '9',
  'Equip(2)': '10',
  'Equip(3)': '26',
  'Supply': '27',
  'Docking(1)': '11',
  'Docking(2)': '12',
  'Construction': '5',
  'Return': '7',
  'Sortie': '14',
  'Battle': '15',
  'Attack': '16',
  'Yasen(1)': '18',
  'Yasen(2)': '17',
  'MVP': '23',
  'Damaged(1)': '19',
  'Damaged(2)': '20',
  'Damaged(3)': '21',
  'Sunk': '22',
  'Idle': '29',
  'Repair': '6',
  for (var hour = 0; hour < 24; hour++)
    'H${hour.toString().padLeft(2, '0')}00': '${hour + 30}',
};

String _kc3QuoteText(Object? value) {
  if (value is String) return _plainSubtitleText(value);
  if (value is! Map) {
    throw const FormatException('KC3 subtitle quote is invalid.');
  }
  final segments = <({int start, String text})>[];
  for (final entry in value.entries) {
    if (entry.key is! String ||
        !RegExp(r'^\d+(?:,\d+)?$').hasMatch(entry.key as String) ||
        entry.value is! String) {
      throw const FormatException('KC3 subtitle timing is invalid.');
    }
    final text = _plainSubtitleText(entry.value as String);
    if (text.isEmpty) continue;
    segments.add((
      start: int.parse((entry.key as String).split(',').first),
      text: text,
    ));
  }
  segments.sort((a, b) => a.start.compareTo(b.start));
  return segments.map((segment) => segment.text).join('\n');
}

String _plainSubtitleText(String source) => source
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAllMapped(
      RegExp(
        r'&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos|nbsp);',
        caseSensitive: false,
      ),
      (match) {
        final entity = match[1]!.toLowerCase();
        final named = const {
          'amp': '&',
          'lt': '<',
          'gt': '>',
          'quot': '"',
          'apos': "'",
          'nbsp': ' ',
        };
        if (named.containsKey(entity)) return named[entity]!;
        final value = entity.startsWith('#x')
            ? int.tryParse(entity.substring(2), radix: 16)
            : int.tryParse(entity.substring(1));
        return value != null &&
                value > 0 &&
                value <= 0x10ffff &&
                !(value >= 0xd800 && value <= 0xdfff)
            ? String.fromCharCode(value)
            : '\uFFFD';
      },
    )
    .trim();
