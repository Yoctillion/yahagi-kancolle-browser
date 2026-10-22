import 'package:flutter/widgets.dart';

import '../game_state/game_state.dart';
import '../localization/game_name_localizations.dart';
import '../settings/fleet_display_options.dart';
import 'fleet_ui_strings.dart';

const _shipTypeAbbreviations = <int, String>{
  1: 'DE',
  2: 'DD',
  3: 'CL',
  4: 'CLT',
  5: 'CA',
  6: 'CAV',
  7: 'CVL',
  8: 'FBB',
  9: 'BB',
  10: 'BBV',
  11: 'CV',
  12: 'BB',
  13: 'SS',
  14: 'SSV',
  15: 'AO',
  16: 'AV',
  17: 'LHA',
  18: 'CVB',
  19: 'AR',
  20: 'AS',
  21: 'CT',
  22: 'AO',
};

String fleetShipTypeAbbreviation(int shipTypeId, {String? fallback}) =>
    _shipTypeAbbreviations[shipTypeId] ??
    fallback ??
    FleetUiKeys.unknownShipType;

String? fleetShipTypeLabel(
  BuildContext context,
  GameState state,
  MasterShip? master,
  FleetShipTypeLabelMode mode,
) {
  final type = state.masterShipTypes[master?.shipTypeId];
  final localized = type == null
      ? null
      : gameNames(context).shipTypeName(type.name, typeId: type.id);
  if (mode == FleetShipTypeLabelMode.localizedName) return localized;
  return fleetShipTypeAbbreviation(
    master?.shipTypeId ?? 0,
    fallback: localized ?? fleetText(context, FleetUiKeys.unknownShipType),
  );
}

// 极简行的舰种只放得下两个字；中日界面显示的是游戏原名，换成惯用的两字简称。
const _shipTypeShortNames = <int, String>{
  1: '海防',
  2: '駆逐',
  3: '軽巡',
  4: '雷巡',
  5: '重巡',
  6: '航巡',
  7: '軽母',
  8: '戦艦',
  9: '戦艦',
  10: '航戦',
  11: '空母',
  12: '戦艦',
  13: '潜水',
  14: '潜空',
  15: '補給',
  16: '水母',
  17: '揚陸',
  18: '装母',
  19: '工作',
  20: '潜母',
  21: '練巡',
  22: '補給',
};

String? fleetShipTypeShortLabel(
  BuildContext context,
  GameState state,
  MasterShip? master,
  FleetShipTypeLabelMode mode,
) {
  final label = fleetShipTypeLabel(context, state, master, mode);
  final type = state.masterShipTypes[master?.shipTypeId];
  if (mode != FleetShipTypeLabelMode.localizedName ||
      type == null ||
      label != type.name) {
    return label;
  }
  return _shipTypeShortNames[type.id] ?? label;
}
