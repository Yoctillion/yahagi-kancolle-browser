import '../fleet/nosaki_sparkle_calculator.dart';
import '../game_state/game_state.dart';

final class ExpeditionFleetRequest {
  const ExpeditionFleetRequest(this.fleetId, this.serial);

  final int fleetId;

  /// Monotonic so that re-requesting the same fleet still overrides a manual pick.
  final int serial;
}

/// First fleet that can be sent on an expedition, mirroring KC3
/// `ExpedTabAutoFleetSwitch`: fleet 1 (and fleet 2 while combined) is the
/// sortie fleet, so the search starts after it. Fleets parked for anchorage
/// repair or Nosaki sparkling are working in port and are skipped too.
int? firstIdleExpeditionFleet(GameState state) {
  final firstCandidate = state.combinedFleetType == CombinedFleetType.none
      ? 2
      : 3;
  for (final fleet in state.fleets) {
    if (fleet.id < firstCandidate || fleet.mission.isActive) continue;
    if (fleet.shipIds.where((id) => id > 0).length < 2) continue;
    if (_isWorkingInPort(state, fleet)) continue;
    return fleet.id;
  }
  return null;
}

/// 工作艦; any of them as flagship means the fleet is parked for repair.
const _repairShipType = 19;

bool _isWorkingInPort(GameState state, Fleet fleet) {
  MasterShip? masterAt(int index) {
    if (fleet.shipIds.length <= index) return null;
    final ship = state.ships[fleet.shipIds[index]];
    return ship == null ? null : state.masterForShip(ship);
  }

  final flagship = masterAt(0);
  return flagship?.shipTypeId == _repairShipType ||
      NosakiSparkleCalculator.isNosaki(flagship) ||
      NosakiSparkleCalculator.isNosaki(masterAt(1));
}
