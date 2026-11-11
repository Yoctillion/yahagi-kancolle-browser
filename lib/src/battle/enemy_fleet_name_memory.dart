import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where remembered enemy fleet names persist, as one JSON document.
abstract interface class EnemyFleetNameStore {
  Future<String?> load();
  Future<void> save(String json);
}

final class SharedPreferencesEnemyFleetNameStore
    implements EnemyFleetNameStore {
  const SharedPreferencesEnemyFleetNameStore();

  // Fleet names are game data rather than account state, so they are shared
  // across accounts.
  static const String _key = 'battle.enemyFleetNames';

  @override
  Future<String?> load() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> save(String json) async {
    final saved = await (await SharedPreferences.getInstance()).setString(
      _key,
      json,
    );
    if (!saved) throw StateError('enemy fleet names were not saved');
  }
}

final class MemoryEnemyFleetNameStore implements EnemyFleetNameStore {
  MemoryEnemyFleetNameStore([this.json]);

  String? json;
  int saveCount = 0;

  @override
  Future<String?> load() async => json;

  @override
  Future<void> save(String json) async {
    saveCount++;
    this.json = json;
  }
}

final class _Encounter {
  const _Encounter(this.ships, this.formation, this.name);

  final List<int> ships;
  final int formation;
  final String name;

  Map<String, Object> toJson() => <String, Object>{
    's': ships,
    'f': formation,
    'n': name,
  };

  static _Encounter? fromJson(Object? value) {
    if (value is! Map) return null;
    final ships = value['s'];
    final formation = value['f'];
    final name = value['n'];
    if (ships is! List || formation is! int || name is! String) return null;
    if (name.isEmpty || ships.any((id) => id is! int)) return null;
    return _Encounter(
      List<int>.unmodifiable(ships.cast<int>()),
      formation,
      name,
    );
  }
}

/// Enemy fleet names learned from battle results.
///
/// The game names the enemy fleet only in the battle result. Keyed like
/// KC3Kai's encounter records (node, enemy composition, formation), a name
/// seen once can be shown from the start of every later encounter.
final class EnemyFleetNameMemory {
  EnemyFleetNameMemory._(this._store, this._nodes);

  static const int maxEncountersPerNode = 12;

  final EnemyFleetNameStore _store;
  final Map<String, List<_Encounter>> _nodes;
  Future<void> _pendingSave = Future<void>.value();

  static Future<EnemyFleetNameMemory> load(EnemyFleetNameStore store) async {
    final nodes = <String, List<_Encounter>>{};
    try {
      final raw = await store.load();
      final decoded = raw == null || raw.isEmpty ? null : jsonDecode(raw);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          if (entry.key is! String || entry.value is! List) continue;
          final encounters = <_Encounter>[
            for (final value in entry.value as List)
              ?_Encounter.fromJson(value),
          ];
          if (encounters.isNotEmpty) nodes[entry.key as String] = encounters;
        }
      }
    } on FormatException catch (error) {
      debugPrint('Ignoring unreadable enemy fleet names: $error');
    }
    return EnemyFleetNameMemory._(store, nodes);
  }

  Future<void> get idle => _pendingSave;

  static String nodeKey({
    required int mapAreaId,
    required int mapInfoNo,
    required int node,
  }) => '$mapAreaId-$mapInfoNo-$node';

  /// The one name the known encounters agree on, or null when there is none
  /// or they disagree. [ships] and [formation] narrow the encounters when
  /// known; a composition that was never seen is not guessed from others.
  String? nameFor(String node, {List<int>? ships, int formation = 0}) {
    var encounters = _nodes[node] ?? const <_Encounter>[];
    if (ships != null && ships.isNotEmpty) {
      encounters = [
        for (final encounter in encounters)
          if (listEquals(encounter.ships, ships)) encounter,
      ];
      if (formation > 0) {
        final sameFormation = [
          for (final encounter in encounters)
            if (encounter.formation == formation) encounter,
        ];
        if (sameFormation.isNotEmpty) encounters = sameFormation;
      }
    }
    final names = {for (final encounter in encounters) encounter.name};
    return names.length == 1 ? names.single : null;
  }

  Future<void> remember(
    String node, {
    required List<int> ships,
    required int formation,
    required String name,
  }) {
    if (name.isEmpty || ships.isEmpty) return _pendingSave;
    final encounters = _nodes.putIfAbsent(node, () => <_Encounter>[]);
    final existing = encounters.indexWhere(
      (encounter) =>
          listEquals(encounter.ships, ships) &&
          encounter.formation == formation,
    );
    if (existing == 0 && encounters.first.name == name) return _pendingSave;
    if (existing >= 0) encounters.removeAt(existing);
    encounters.insert(
      0,
      _Encounter(List<int>.unmodifiable(ships), formation, name),
    );
    if (encounters.length > maxEncountersPerNode) {
      encounters.removeRange(maxEncountersPerNode, encounters.length);
    }
    final json = jsonEncode(<String, Object>{
      for (final entry in _nodes.entries)
        entry.key: [for (final encounter in entry.value) encounter.toJson()],
    });
    return _pendingSave = _pendingSave
        .catchError((Object _) {})
        .then((_) => _store.save(json));
  }
}
