import '../fleet/equipment_display.dart';
import '../fleet/fleet_ui_strings.dart';

enum FleetShipTypeLabelMode { localizedName, abbreviation }

enum FleetSelectorLabelMode { customName, number }

FleetSelectorLabelMode _fleetSelectorLabelMode =
    FleetSelectorLabelMode.customName;

FleetSelectorLabelMode get fleetSelectorLabelModeSetting =>
    _fleetSelectorLabelMode;

void setFleetSelectorLabelModeSetting(FleetSelectorLabelMode mode) {
  _fleetSelectorLabelMode = mode;
}

const displayGroups = FleetUiKeys.displayGroups;
const defaultFields = <String>{
  'portrait',
  'equipment',
  'hp',
  'fuel',
  'ammo',
  'bars',
  'level',
  'type',
  'shipSpeed',
  'morale',
  ...mechanismFields,
  'speed',
  'total-level',
  'air-power',
  'line-of-sight',
  'minimum-condition',
};
Set<String> get compactFields => defaultFields.difference({
  'portrait',
  'type',
  'shipSpeed',
  'bars',
  'total-level',
});

final summaryFields = displayGroups[FleetUiKeys.summaryGroup]!.keys.toSet();
const mechanismFields = {'asw', 'aaci', 'rocket', 'night', 'special'};

bool showsMechanism(Set<String> visible, EquipmentMechanismDisplay mechanism) =>
    visible.contains(switch (mechanism.kind) {
      CombatMechanismKind.openingAsw => 'asw',
      CombatMechanismKind.antiAirCutIn => 'aaci',
      CombatMechanismKind.rocketBarrage => 'rocket',
      CombatMechanismKind.nightCarrierAttack => 'night',
      CombatMechanismKind.fleetSpecialAttack => 'special',
      null => null,
    });
Set<String> get allFields =>
    displayGroups.values.expand((group) => group.keys).toSet();
const maximumSummaryFields = 5;

Set<String> normalizeDisplayFields(Iterable<String> saved) {
  final migrated = saved.toSet();
  // 曾有一版把五个机制开关合并成单个 'mechanisms'，读到它时按全开还原。
  if (migrated.remove('mechanisms')) {
    migrated.addAll(mechanismFields);
  }
  final valid = migrated.intersection(allFields);
  final overflow = summaryFields
      .where(valid.contains)
      .skip(maximumSummaryFields);
  return valid.difference(overflow.toSet());
}
