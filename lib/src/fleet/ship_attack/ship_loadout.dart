import 'dart:math' as math;

import '../../game_state/game_state.dart';

class LoadoutSlot {
  const LoadoutSlot({
    required this.item,
    required this.stars,
    required this.planes,
    required this.isExSlot,
  });

  final MasterSlotItem item;
  final int stars;

  /// Full-capacity plane count; loadout comparisons must not drift with
  /// post-sortie losses.
  final int planes;
  final bool isExSlot;
}

class ShipLoadout {
  const ShipLoadout({
    required this.ship,
    required this.master,
    required this.slots,
  });

  final OwnedShip ship;
  final MasterShip master;
  final List<LoadoutSlot> slots;

  static ShipLoadout? fromState(GameState state, OwnedShip ship) {
    final master = state.masterForShip(ship);
    if (master == null) return null;

    LoadoutSlot? resolve(int slotId, int planes, bool isExSlot) {
      if (slotId <= 0) return null;
      final owned = state.slotItems[slotId];
      if (owned == null) return null;
      final item = state.masterSlotItems[owned.masterSlotItemId];
      if (item == null) return null;
      return LoadoutSlot(
        item: item,
        stars: owned.level,
        planes: planes,
        isExSlot: isExSlot,
      );
    }

    final slots = <LoadoutSlot>[];
    for (var index = 0; index < ship.slotIds.length; index++) {
      final slot = resolve(
        ship.slotIds[index],
        _fullPlanes(ship, master, index),
        false,
      );
      if (slot != null) slots.add(slot);
    }
    final ex = resolve(ship.extraSlotId, 0, true);
    if (ex != null) slots.add(ex);
    return ShipLoadout(ship: ship, master: master, slots: slots);
  }

  static int _fullPlanes(OwnedShip ship, MasterShip master, int index) {
    final owned = index < ship.maxSlotCounts.length
        ? ship.maxSlotCounts[index]
        : 0;
    if (owned > 0) return owned;
    return index < master.slotCapacities.length
        ? master.slotCapacities[index]
        : 0;
  }

  int count(bool Function(MasterSlotItem) test) =>
      slots.where((slot) => test(slot.item)).length;

  bool has(bool Function(MasterSlotItem) test) =>
      slots.any((slot) => test(slot.item));

  int countNonZeroSlot(bool Function(MasterSlotItem) test) => slots
      .where((slot) => !slot.isExSlot && slot.planes > 0 && test(slot.item))
      .length;

  bool hasNonZeroSlot(bool Function(MasterSlotItem) test) =>
      countNonZeroSlot(test) > 0;

  int sumEquipment(int Function(MasterSlotItem) stat) =>
      slots.fold<int>(0, (sum, slot) => sum + stat(slot.item));

  int get nakedFirepower =>
      master.baseFirepower +
      (ship.modernization.isEmpty ? 0 : ship.modernization[0]);

  /// Approximation: visible LoS bonuses from equipment are not subtracted.
  int get nakedLineOfSight =>
      math.max(0, ship.lineOfSight - sumEquipment((item) => item.lineOfSight));
}
