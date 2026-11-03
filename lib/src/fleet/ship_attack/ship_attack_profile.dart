import '../../game_state/game_state.dart';
import 'attack_power.dart';
import 'attack_profile.dart';
import 'day_attack.dart';
import 'night_attack.dart';
import 'ship_loadout.dart';

class ShipAttackProfile {
  const ShipAttackProfile({
    required this.day,
    required this.night,
    required this.omitsBombingBonus,
  });

  final AttackPhaseProfile? day;
  final AttackPhaseProfile? night;

  /// Ship-side bombing visible bonuses are not exposed by the API, so the
  /// carrier formulas only see equipment panel bombing.
  final bool omitsBombingBonus;
}

ShipAttackProfile? computeShipAttackProfile(GameState state, OwnedShip ship) {
  final loadout = ShipLoadout.fromState(state, ship);
  if (loadout == null) return null;

  final fleet = state.fleetForShip(ship.id);
  final members = <ShipLoadout>[
    if (fleet == null)
      loadout
    else
      for (final id in fleet.shipIds)
        if (id == ship.id)
          loadout
        else if (state.ships[id] case final other?)
          ?ShipLoadout.fromState(state, other),
  ];
  final isFlagship = fleet != null && fleet.shipIds.first == ship.id;

  final nightKind = nightAttackKind(loadout);
  return ShipAttackProfile(
    day: computeDayProfile(
      loadout,
      fleetLosMod: fleetObservationLosMod(members),
      isFlagship: isFlagship,
    ),
    night: computeNightProfile(
      loadout,
      isFlagship: isFlagship,
      fleet: nightFleetConditions(members),
    ),
    omitsBombingBonus:
        isCarrierLike(loadout) || nightKind == NightAttackKind.carrierAerial,
  );
}
