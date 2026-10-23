import 'dart:math' as math;

import '../game_state/game_state.dart';
import '../toolbox/exp_calc/ship_exp_table.dart';

enum PracticeRank { s, a, b, c, d, e }

const _rankCoefficients = <PracticeRank, double>{
  PracticeRank.s: 1.2,
  PracticeRank.a: 1.0,
  PracticeRank.b: 1.0,
  PracticeRank.c: 0.64,
  PracticeRank.d: 0.56,
  PracticeRank.e: 0.4,
};

final class PracticeCtBonus {
  const PracticeCtBonus({
    required this.modifier,
    required this.submarineModifier,
  });

  static const none = PracticeCtBonus(modifier: 1, submarineModifier: 1);

  final double modifier;
  final double submarineModifier;
}

/// 演习基础经验（评价补正前），对齐 KC3 `estimatePvpBaseExp`：随机加值 0~3 按最大值取。
int practiceBaseExp(int flagshipLevel, int secondShipLevel) {
  if (flagshipLevel <= 0) return 0;
  final secondExp = secondShipLevel > 0
      ? shipCumulativeExp(secondShipLevel)
      : 0;
  final raw =
      (shipCumulativeExp(flagshipLevel) / 100 + secondExp / 300).floor() + 3;
  if (raw <= 500) return raw;
  return (500 + math.sqrt(raw - 500)).floor();
}

/// [submarine] applies Asahi's submarine modifier (KC3 `expectedSub`).
int practiceRankExp(
  int baseExp,
  PracticeRank rank,
  PracticeCtBonus bonus, {
  bool submarine = false,
}) {
  final ranked = (baseExp * _rankCoefficients[rank]!).floor();
  return (ranked * (submarine ? bonus.submarineModifier : bonus.modifier))
      .floor();
}

const _asahiMasterId = 953;
const _trainingCruiserTypeId = 21;

// 行：无 CT / 旗舰 CT / 随伴 CT×1 / 旗舰 CT + 随伴 / 随伴 CT×2；列：Lv ~9 / ~29 / ~59 / ~99 / 100~。
const _ctBonusTable = <List<double>>[
  [1.0, 1.0, 1.0, 1.0, 1.0],
  [1.05, 1.08, 1.12, 1.15, 1.20],
  [1.03, 1.05, 1.07, 1.10, 1.15],
  [1.10, 1.13, 1.16, 1.20, 1.25],
  [1.04, 1.06, 1.08, 1.12, 1.175],
];

int _levelColumn(int level) => level < 10
    ? 0
    : level < 30
    ? 1
    : level < 60
    ? 2
    : level < 100
    ? 3
    : 4;

double _fixed4(double value) => (value * 10000).round() / 10000;

/// 按第 1 舰队计算练巡（香取级）与朝日加成，逻辑照搬 KC3 `lookupKatoriClassBonus`。
PracticeCtBonus practiceCtBonus(GameState state) {
  if (state.fleets.isEmpty) return PracticeCtBonus.none;
  final ships = [for (final id in state.fleets.first.shipIds) state.ships[id]];

  var katoriIndex = 0;
  var flagshipCtLevel = 0;
  var maxCtLevel = 0;
  int? asahiLevel;
  for (var i = 0; i < ships.length; i++) {
    final ship = ships[i];
    if (ship == null) continue;
    if (ship.masterId == _asahiMasterId) {
      asahiLevel ??= ship.level;
      continue;
    }
    if (state.masterShips[ship.masterId]?.shipTypeId !=
        _trainingCruiserTypeId) {
      continue;
    }
    maxCtLevel = math.max(maxCtLevel, ship.level);
    if (i == 0) {
      katoriIndex = 1;
      flagshipCtLevel = ship.level;
    } else if (katoriIndex < 3) {
      katoriIndex += 2;
    }
  }
  if (katoriIndex == 3) maxCtLevel = flagshipCtLevel;

  final katoriModifier = _ctBonusTable[katoriIndex][_levelColumn(maxCtLevel)];
  final asahiFlagship =
      ships.isNotEmpty && ships.first?.masterId == _asahiMasterId;
  if (asahiLevel == null ||
      !(asahiFlagship || katoriIndex == 1 || katoriIndex == 3)) {
    return PracticeCtBonus(
      modifier: katoriModifier,
      submarineModifier: katoriModifier,
    );
  }

  var base = katoriModifier;
  var asahiModifier = 0.6;
  var asahiSubmarineModifier = 1.3;
  if (asahiFlagship) {
    base = _ctBonusTable[katoriIndex == 4 ? 3 : 1][_levelColumn(asahiLevel)];
  }
  if (katoriIndex > 0) {
    asahiModifier += 0.45;
    asahiSubmarineModifier += 0.15;
    if (katoriIndex == 3) {
      base = _ctBonusTable[1][_levelColumn(flagshipCtLevel)];
    }
  }
  return PracticeCtBonus(
    modifier: _fixed4(base * asahiModifier),
    submarineModifier: _fixed4(base * asahiSubmarineModifier),
  );
}
