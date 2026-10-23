import '../fleet/ship_damage_level.dart';
import '../game_state/game_state.dart';

enum AdvanceDamageControlStatus { missing, unknown, equipped }

class AdvanceWarningShip {
  const AdvanceWarningShip({
    required this.ship,
    required this.fleetId,
    required this.position,
    required this.name,
    required this.requiresDisambiguation,
    required this.damageControlStatus,
    required this.remainingDamageControls,
  });

  final OwnedShip ship;
  final int fleetId;
  final int position;
  final String name;
  final bool requiresDisambiguation;
  final AdvanceDamageControlStatus damageControlStatus;
  final Map<int, int> remainingDamageControls;

  bool get hasConfirmedDamageControl =>
      damageControlStatus == AdvanceDamageControlStatus.equipped &&
      remainingDamageControls.isNotEmpty &&
      remainingDamageControls.entries.every(
        (entry) => (entry.key == 42 || entry.key == 43) && entry.value > 0,
      );
}

List<AdvanceWarningShip> collectAdvanceWarningShips(
  GameState state, {
  required bool damageControlStateTrusted,
}) {
  final combat = state.combatState;
  final sortieFleetId = combat.sortieFleetId;
  if (!combat.isActive || sortieFleetId <= 0) {
    return const <AdvanceWarningShip>[];
  }

  final fleetIds = <int>[
    sortieFleetId,
    if (sortieFleetId == 1 && state.combinedFleetType != CombinedFleetType.none)
      2,
  ];
  final candidates =
      <({OwnedShip ship, int fleetId, int position, String name})>[];
  final nameCounts = <String, int>{};
  for (final fleetId in fleetIds) {
    final fleet = state.fleets
        .where((candidate) => candidate.id == fleetId)
        .firstOrNull;
    if (fleet == null) continue;
    for (var slotIndex = 1; slotIndex < fleet.shipIds.length; slotIndex++) {
      final ship = state.ships[fleet.shipIds[slotIndex]];
      if (ship == null || combat.escapedShipIds.contains(ship.id)) continue;
      if (shipDamageLevel(currentHp: ship.currentHp, maxHp: ship.maxHp) !=
          ShipDamageLevel.heavy) {
        continue;
      }
      final name = state.masterForShip(ship)?.name ?? '#${ship.id}';
      candidates.add((
        ship: ship,
        fleetId: fleetId,
        position: slotIndex + 1,
        name: name,
      ));
      nameCounts.update(name, (count) => count + 1, ifAbsent: () => 1);
    }
  }

  final details = <AdvanceWarningShip>[];
  final referencedInstances = <int>{};
  final conflictingInstances = <int>{};
  for (final ship in state.ships.values) {
    for (final instanceId in <int>[...ship.slotIds, ship.extraSlotId]) {
      if (instanceId > 0 && !referencedInstances.add(instanceId)) {
        conflictingInstances.add(instanceId);
      }
    }
  }
  for (final candidate in candidates) {
    var status = AdvanceDamageControlStatus.unknown;
    var remainingDamageControls = const <int, int>{};
    if (damageControlStateTrusted && state.hasEquipmentInventory) {
      final instanceIds = <int>[
        ...candidate.ship.slotIds.where((instanceId) => instanceId > 0),
        if (candidate.ship.extraSlotId > 0) candidate.ship.extraSlotId,
      ];
      final seenInstanceIds = <int>{};
      final counts = <int, int>{};
      var equipmentKnown = true;
      for (final instanceId in instanceIds) {
        final equipment = state.slotItems[instanceId];
        if (!seenInstanceIds.add(instanceId) ||
            conflictingInstances.contains(instanceId) ||
            equipment == null ||
            equipment.instanceId != instanceId ||
            equipment.masterSlotItemId <= 0) {
          equipmentKnown = false;
          break;
        }
        final masterId = equipment.masterSlotItemId;
        if (masterId == 42 || masterId == 43) {
          counts.update(masterId, (count) => count + 1, ifAbsent: () => 1);
        }
      }
      if (equipmentKnown) {
        status = counts.isEmpty
            ? AdvanceDamageControlStatus.missing
            : AdvanceDamageControlStatus.equipped;
        remainingDamageControls = Map<int, int>.unmodifiable(counts);
      }
    }
    details.add(
      AdvanceWarningShip(
        ship: candidate.ship,
        fleetId: candidate.fleetId,
        position: candidate.position,
        name: candidate.name,
        requiresDisambiguation: nameCounts[candidate.name]! > 1,
        damageControlStatus: status,
        remainingDamageControls: remainingDamageControls,
      ),
    );
  }
  return <AdvanceWarningShip>[
    for (final status in AdvanceDamageControlStatus.values)
      ...details.where((detail) => detail.damageControlStatus == status),
  ];
}
