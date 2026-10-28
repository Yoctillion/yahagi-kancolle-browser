abstract interface class FleetAutoSwitchSettingsStore {
  Future<bool> loadFleetAutoSwitch();
  Future<void> saveFleetAutoSwitch(bool enabled);
}
