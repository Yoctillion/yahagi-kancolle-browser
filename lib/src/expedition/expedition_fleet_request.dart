import '../game_state/game_state.dart';

final class ExpeditionFleetRequest {
  const ExpeditionFleetRequest(this.fleetId, this.serial);

  final int fleetId;

  /// Monotonic so that re-requesting the same fleet still overrides a manual pick.
  final int serial;
}

/// First fleet that can be sent on an expedition, mirroring KC3
/// `ExpedTabAutoFleetSwitch`: fleet 1 (and fleet 2 while combined) is the
/// sortie fleet, so the search starts after it.
int? firstIdleExpeditionFleet(GameState state) {
  final firstCandidate = state.combinedFleetType == CombinedFleetType.none
      ? 2
      : 3;
  for (final fleet in state.fleets) {
    if (fleet.id < firstCandidate || fleet.mission.isActive) continue;
    if (fleet.shipIds.where((id) => id > 0).length >= 2) return fleet.id;
  }
  return null;
}
