import '../../game_state/game_state.dart';

// Gear and ship classifications follow fleethub's master_data gear_attrs /
// ship_attrs (2026-10), re-expressed against api_type indices.

abstract final class ShipTypeIds {
  static const destroyer = 2;
  static const lightCruiser = 3;
  static const torpedoCruiser = 4;
  static const aviationCruiser = 6;
  static const lightCarrier = 7;
  static const aviationBattleship = 10;
  static const carrier = 11;
  static const submarine = 13;
  static const aircraftCarryingSubmarine = 14;
  static const seaplaneTender = 16;
  static const armoredCarrier = 18;
  static const trainingCruiser = 21;

  static const carriers = <int>{lightCarrier, carrier, armoredCarrier};
  static const submarines = <int>{submarine, aircraftCarryingSubmarine};
  static const lightCruisers = <int>{
    lightCruiser,
    torpedoCruiser,
    trainingCruiser,
  };
  static const nightZuiunCapable = <int>{
    lightCruiser,
    aviationCruiser,
    aviationBattleship,
    seaplaneTender,
  };
}

abstract final class ShipClassIds {
  static const zara = 64;
  static const arkRoyal = 78;
  static const toku2tl = 115;
  static const toku1tl = 132;
}

abstract final class ShipIds {
  static const hayasuiKai = 352;
  static const shimanemaruKai = 1008;
  static const iseClassKai2 = <int>{553, 554};
  static const nightCarriers = <int>{545, 599, 610, 883, 1008};
}

abstract final class GearIds {
  static const skilledLookouts = 129;
  static const torpedoSquadronLookouts = 412;
  static const transportDrum = 75;
  static const photoelectricSuisei = 320;
  static const nightZuiun = 490;
  static const nightOperationPersonnel = <int>{258, 259};
  static const modelDKai2 = 267;
  static const modelDKai3 = 366;
  static const zara203mm53 = 162;
  static const fighterBombers = <int>{60, 219, 154, 447, 487};
  static const swordfish = <int>{242, 243, 244};
  static const semiNightPlaneExtras = <int>{154, 320};
  static const lateModelBowTorpedoes = <int>{
    213,
    214,
    383,
    441,
    443,
    457,
    461,
    512,
  };
  static const iseZuiun = <int>{26, 207, 79, 237, 80, 81, 322, 323, 490};
  static const ise634Suisei = <int>{319, 291, 292};
  static const cruiserFitSingleGuns = <int>{4, 11};
  static const cruiserFitTwinGuns = <int>{
    65,
    119,
    139,
    303,
    310,
    359,
    360,
    361,
    407,
    518,
    534,
    535,
  };
}

extension GearTraits on MasterSlotItem {
  int get categoryId => type.length > 2 ? type[2] : -1;
  int get iconId => type.length > 3 ? type[3] : -1;

  bool get isMainGun => const <int>{1, 2, 3}.contains(categoryId);
  bool get isSecondaryGun => categoryId == 4;
  bool get isTorpedo => categoryId == 5;
  bool get isSubmarineTorpedo => categoryId == 32;
  bool get isApShell => categoryId == 19;
  bool get isRadar => categoryId == 12 || categoryId == 13;
  bool get isSurfaceRadar => isRadar && lineOfSight >= 5;
  bool get isSubmarineEquipment => categoryId == 51;
  bool get isObservationSeaplane => categoryId == 10 || categoryId == 11;
  bool get isCbFighter => categoryId == 6;
  bool get isCbDiveBomber => categoryId == 7;
  bool get isCbTorpedoBomber => categoryId == 8;
  bool get isCbFighterBomber => GearIds.fighterBombers.contains(id);
  bool get isJetFighter => categoryId == 56;
  bool get isJetFighterBomber => categoryId == 57;
  bool get isJetTorpedoBomber => categoryId == 58;
  bool get isCarrierShellingPlane =>
      isCbDiveBomber ||
      isCbTorpedoBomber ||
      isJetFighterBomber ||
      isJetTorpedoBomber;
  bool get isNightFighter => iconId == 45;
  bool get isNightAttacker => iconId == 46;
  bool get isNightBomber => iconId == 58;
  bool get isSwordfish => GearIds.swordfish.contains(id);
  bool get isSemiNightPlane =>
      isSwordfish || GearIds.semiNightPlaneExtras.contains(id);
  bool get isNightPlane =>
      isNightAttacker || isNightFighter || isNightBomber || isSemiNightPlane;
  bool get isLateModelBowTorpedo => GearIds.lateModelBowTorpedoes.contains(id);
  bool get isSearchlight => categoryId == 29 || categoryId == 42;
  bool get isStarshell => categoryId == 33;
}
