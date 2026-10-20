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
    fallback: localized ?? fleetText(context, '未知舰种'),
  );
}
