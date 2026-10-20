import 'dart:math' as math;

import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';

import '../battle/battle_models.dart';
import '../fleet/operation_progress.dart';
import '../fleet/ship_damage_level.dart';
import '../game_state/game_state.dart';

/// 远征中且尚未到时间的舰队；已到时间的不算进行中。
List<Fleet> activeExpeditionFleets(GameState state, DateTime now) => [
  for (final fleet in state.fleets)
    if (fleet.mission.isActive && now.isBefore(fleet.mission.completionTime!))
      fleet,
];

List<RepairDock> busyRepairDocks(GameState state, DateTime now) => [
  for (final dock in state.repairDocks)
    if (dock.isRepairing &&
        !operationIsCompleted(dock.completionTime, now: now))
      dock,
];

int completedConstructionCount(GameState state, DateTime now) =>
    state.constructionDocks.where((dock) => dock.isCompletedAt(now)).length;

String? battleSummary(AppLocalizations l10n, LiveBattle? battle) {
  if (battle == null || battle.friendShips.isEmpty) return null;
  final node = battle.context.forecastNodeLabel;
  if (battle.rank == BattleRank.unknown) return node;
  return '$node · ${battle.rank.label}';
}

String? fleetSummary(AppLocalizations l10n, GameState state, int fleetId) {
  final ships = state.shipsForFleet(fleetId);
  if (ships.isEmpty) return null;
  var heavy = 0;
  var medium = 0;
  for (final ship in ships) {
    switch (shipDamageLevel(currentHp: ship.currentHp, maxHp: ship.maxHp)) {
      case ShipDamageLevel.heavy:
        heavy++;
      case ShipDamageLevel.moderate:
        medium++;
      case ShipDamageLevel.none ||
          ShipDamageLevel.healthy ||
          ShipDamageLevel.minor:
        break;
    }
  }
  final minMorale = ships.map((ship) => ship.condition).reduce(math.min);
  return [
    if (heavy > 0) l10n.summaryFleetHeavy(heavy),
    if (medium > 0) l10n.summaryFleetMedium(medium),
    l10n.summaryFleetMinMorale(minMorale),
  ].join(' · ');
}

String? expeditionSummary(
  AppLocalizations l10n,
  GameState state,
  DateTime now,
) {
  final active = activeExpeditionFleets(state, now);
  if (active.isEmpty) return null;
  return l10n.summaryExpedition(
    active.length,
    _nearestRemaining(
      active.map((fleet) => fleet.mission.completionTime),
      now,
    )!,
  );
}

String? repairSummary(AppLocalizations l10n, GameState state, DateTime now) {
  final busy = busyRepairDocks(state, now);
  if (busy.isEmpty) return null;
  final total = state.repairDocks.where((dock) => !dock.isLocked).length;
  final nearest = _nearestRemaining(
    busy.map((dock) => dock.completionTime),
    now,
  );
  return nearest == null
      ? l10n.summaryRepairBusy(busy.length, total)
      : l10n.summaryRepair(busy.length, total, nearest);
}

String? constructionSummary(
  AppLocalizations l10n,
  GameState state,
  DateTime now,
) {
  final done = completedConstructionCount(state, now);
  final building =
      state.constructionDocks.where((dock) => dock.isBuilding).length - done;
  if (done == 0 && building == 0) return null;
  return l10n.summaryConstruction(done, building);
}

String? questSummary(AppLocalizations l10n, GameState state) {
  final accepted = state.quests.values.where((quest) => quest.isAccepted);
  final done = accepted.where((quest) => quest.isCompleted).length;
  final active = accepted.length - done;
  if (done == 0 && active == 0) return null;
  return l10n.summaryQuests(done, active);
}

String? landBaseSummary(AppLocalizations l10n, Iterable<LandBaseState> bases) {
  if (bases.isEmpty) return null;
  return l10n.summaryLandBase(
    bases.where((base) => base.actionKind == 1).length,
    bases.where((base) => base.actionKind == 2).length,
  );
}

String preSortieSummary(AppLocalizations l10n, int warningCount) =>
    warningCount == 0
    ? l10n.noSortieWarnings
    : l10n.summaryWarnings(warningCount);

String? _nearestRemaining(Iterable<DateTime?> completionTimes, DateTime now) {
  DateTime? nearest;
  for (final time in completionTimes) {
    if (time != null && (nearest == null || time.isBefore(nearest))) {
      nearest = time;
    }
  }
  return nearest == null
      ? null
      : formatOperationDuration(nearest.difference(now));
}
