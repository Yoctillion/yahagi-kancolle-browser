/// One KC3 language's equipment names and ID-indexed category labels.
///
/// Equipment group 2 follows api_type[2] / api_mst_slotitem_equiptype IDs.
/// Other groups remain available without merging their unrelated ID spaces.
final class GameNameDictionary {
  const GameNameDictionary._({
    required this.items,
    required this.shipTypes,
    required this.equipmentTypes,
  });

  factory GameNameDictionary.fromJson(Map<String, dynamic> source) {
    final rawItems = source['items'];
    if (rawItems is! Map || rawItems.isEmpty || rawItems.length > 100000) {
      throw const FormatException('KC3 equipment names are incomplete.');
    }
    final items = <String, String>{};
    for (final entry in rawItems.entries) {
      if (entry.key is! String ||
          (entry.key as String).trim().isEmpty ||
          (entry.key as String).length > 512 ||
          entry.value is! String ||
          (entry.value as String).trim().isEmpty ||
          (entry.value as String).length > 1024) {
        throw const FormatException('KC3 equipment-name entry is invalid.');
      }
      items[entry.key as String] = entry.value as String;
    }
    final shipTypes = _labelList(source['stype']);
    final rawTypes = source['equiptype'];
    if (shipTypes.length < 23 || rawTypes is! List || rawTypes.length != 5) {
      throw const FormatException('KC3 category groups are incomplete.');
    }
    final equipmentTypes = [
      for (var index = 0; index < rawTypes.length; index++)
        _labelList(rawTypes[index], allowEmpty: index == 4),
    ];
    if (equipmentTypes.take(4).any((group) => group.length < 2)) {
      throw const FormatException('KC3 equipment categories are empty.');
    }
    return GameNameDictionary._(
      items: Map.unmodifiable(items),
      shipTypes: shipTypes,
      equipmentTypes: List.unmodifiable(equipmentTypes),
    );
  }

  final Map<String, String> items;
  final List<String> shipTypes;
  final List<List<String>> equipmentTypes;

  String? shipType(int? id) => _labelAt(shipTypes, id);
  String? equipmentType(int? id) => _labelAt(equipmentTypes[2], id);

  Map<String, dynamic> toJson() => {
    'items': items,
    'stype': shipTypes,
    'equiptype': equipmentTypes,
  };
}

List<String> _labelList(Object? source, {bool allowEmpty = false}) {
  if (source is! List ||
      (!allowEmpty && source.isEmpty) ||
      source.length > 1024) {
    throw const FormatException('KC3 category labels are invalid.');
  }
  final values = <String>[];
  for (final value in source) {
    if (value is! String || value.length > 512) {
      throw const FormatException('KC3 category label is invalid.');
    }
    values.add(value);
  }
  if (!allowEmpty && values.every((value) => value.isEmpty || value == '?')) {
    throw const FormatException('KC3 category labels are empty.');
  }
  return List.unmodifiable(values);
}

String? _labelAt(List<String> values, int? id) {
  if (id == null || id < 0 || id >= values.length) return null;
  final value = values[id];
  return value.trim().isEmpty || value == '?' ? null : value;
}
