import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';

class GearSpec {
  const GearSpec(this.item, {this.stars = 0});

  final MasterSlotItem item;
  final int stars;
}

class ShipSpec {
  const ShipSpec({
    required this.id,
    required this.shipTypeId,
    this.masterId,
    this.classTypeId = 0,
    this.sortNo = 0,
    this.level = 99,
    this.firepower = 0,
    this.torpedo = 0,
    this.luck = 0,
    this.lineOfSight = 0,
    this.baseFirepower = 1,
    this.baseTorpedo = 0,
    this.modernization = const <int>[],
    this.gears = const <GearSpec?>[],
    this.exGear,
    this.slotCapacities,
    this.maxSlotCounts = const <int>[],
  });

  final int id;
  final int shipTypeId;
  final int? masterId;
  final int classTypeId;
  final int sortNo;
  final int level;
  final int firepower;
  final int torpedo;
  final int luck;
  final int lineOfSight;
  final int baseFirepower;
  final int baseTorpedo;
  final List<int> modernization;

  /// `null` entries model empty slots (slot ID -1).
  final List<GearSpec?> gears;
  final GearSpec? exGear;
  final List<int>? slotCapacities;
  final List<int> maxSlotCounts;
}

/// Builds a state where each fleet lists ship IDs in position order.
GameState buildState(
  List<ShipSpec> ships, {
  List<List<int>> fleets = const <List<int>>[],
  Map<int, MasterSlotItem> extraMasterSlotItems = const {},
}) {
  final masterShips = <int, MasterShip>{};
  final ownedShips = <int, OwnedShip>{};
  final masterSlotItems = <int, MasterSlotItem>{...extraMasterSlotItems};
  final slotItems = <int, OwnedSlotItem>{};

  for (final spec in ships) {
    final masterId = spec.masterId ?? 1000 + spec.id;
    masterShips[masterId] = MasterShip(
      id: masterId,
      name: 'ship ${spec.id}',
      shipTypeId: spec.shipTypeId,
      classTypeId: spec.classTypeId,
      sortNo: spec.sortNo,
      baseFirepower: spec.baseFirepower,
      baseTorpedo: spec.baseTorpedo,
      slotCapacities:
          spec.slotCapacities ?? List<int>.filled(spec.gears.length, 0),
    );
    final slotIds = <int>[];
    for (var index = 0; index < spec.gears.length; index++) {
      final gear = spec.gears[index];
      if (gear == null) {
        slotIds.add(-1);
        continue;
      }
      final ownedId = spec.id * 100 + index;
      slotIds.add(ownedId);
      slotItems[ownedId] = OwnedSlotItem(
        id: ownedId,
        masterId: gear.item.id,
        level: gear.stars,
      );
      masterSlotItems[gear.item.id] = gear.item;
    }
    var extraSlotId = -1;
    if (spec.exGear case final ex?) {
      extraSlotId = spec.id * 100 + 99;
      slotItems[extraSlotId] = OwnedSlotItem(
        id: extraSlotId,
        masterId: ex.item.id,
        level: ex.stars,
      );
      masterSlotItems[ex.item.id] = ex.item;
    }
    ownedShips[spec.id] = OwnedShip(
      id: spec.id,
      masterId: masterId,
      level: spec.level,
      currentHp: 50,
      maxHp: 50,
      firepower: spec.firepower,
      torpedo: spec.torpedo,
      luck: spec.luck,
      lineOfSight: spec.lineOfSight,
      modernization: spec.modernization,
      slotIds: slotIds,
      maxSlotCounts: spec.maxSlotCounts,
      extraSlotId: extraSlotId,
    );
  }

  return GameState(
    masterShips: masterShips,
    ships: ownedShips,
    masterSlotItems: masterSlotItems,
    slotItems: slotItems,
    fleets: <Fleet>[
      for (var index = 0; index < fleets.length; index++)
        Fleet(id: index + 1, name: '', shipIds: fleets[index]),
    ],
  );
}

MasterSlotItem gear(
  int id, {
  required int t2,
  int t3 = 0,
  int firepower = 0,
  int torpedo = 0,
  int bombing = 0,
  int antiSub = 0,
  int lineOfSight = 0,
}) => MasterSlotItem(
  id: id,
  name: 'gear $id',
  type: <int>[0, 0, t2, t3, 0],
  firepower: firepower,
  torpedo: torpedo,
  bombing: bombing,
  antiSub: antiSub,
  lineOfSight: lineOfSight,
);
