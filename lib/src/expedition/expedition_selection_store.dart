import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../account/account_session.dart';

abstract interface class ExpeditionSelectionStore {
  /// Fires after a saved mission changes so open checkers can re-read it.
  Listenable get changes;

  Future<int?> loadMissionId(int fleetId);

  Future<void> saveMissionId(int fleetId, int missionId);
}

final class SharedPreferencesExpeditionSelectionStore
    implements ExpeditionSelectionStore {
  const SharedPreferencesExpeditionSelectionStore({this.accountSession});

  final AccountSession? accountSession;
  AccountSession get _session => accountSession ?? AccountSession.shared;

  // Every instance reads the same preferences, so they share one signal.
  static final _changes = _ChangeSignal();

  static String _missionKey(int fleetId) =>
      'expedition.selected_mission.fleet_$fleetId';

  static String _dispatchKey(int fleetId) =>
      'expedition.recorded_dispatch.fleet_$fleetId';

  @override
  Listenable get changes => _changes;

  @override
  Future<int?> loadMissionId(int fleetId) async {
    final scope = _session.current;
    if (!scope.isKnown) return null;
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getInt(scope.key(_missionKey(fleetId)));
    } catch (_) {
      // The expedition checker still works if local preferences are unavailable.
      return null;
    }
  }

  @override
  Future<void> saveMissionId(int fleetId, int missionId) async {
    final scope = _session.current;
    if (!scope.isKnown) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setInt(scope.key(_missionKey(fleetId)), missionId);
      _changes.notify();
    } catch (_) {
      // Remembering the selection is optional and must not block evaluation.
    }
  }

  /// Makes the mission a fleet was sent on its selection, once per dispatch:
  /// the same dispatch is seen again after every restart, and must not undo a
  /// pick made for the fleet's next run while it was still away.
  Future<void> recordDispatch(
    int fleetId,
    int missionId,
    DateTime completionTime,
  ) async {
    final scope = _session.current;
    if (!scope.isKnown) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      final dispatchKey = scope.key(_dispatchKey(fleetId));
      final dispatch = completionTime.millisecondsSinceEpoch;
      if (preferences.getInt(dispatchKey) == dispatch) return;
      await preferences.setInt(dispatchKey, dispatch);
      await preferences.setInt(scope.key(_missionKey(fleetId)), missionId);
      _changes.notify();
    } catch (_) {
      // Same as saveMissionId: a lost record only means a manual pick later.
    }
  }
}

final class _ChangeSignal extends ChangeNotifier {
  void notify() => notifyListeners();
}
