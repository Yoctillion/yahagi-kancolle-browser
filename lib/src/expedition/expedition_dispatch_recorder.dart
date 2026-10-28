import '../account/account_session.dart';
import '../game_state/game_state_controller.dart';
import 'expedition_selection_store.dart';

/// Watches fleets rather than mission/start so dispatches made before launch,
/// or from another device, still become the fleet's remembered mission.
final class ExpeditionDispatchRecorder {
  ExpeditionDispatchRecorder({
    required this.controller,
    required this.accountSession,
  }) : store = SharedPreferencesExpeditionSelectionStore(
         accountSession: accountSession,
       ) {
    controller.addListener(_record);
    accountSession.addListener(_onAccountChanged);
    _record();
  }

  final GameStateController controller;
  final AccountSession accountSession;
  final SharedPreferencesExpeditionSelectionStore store;

  /// Last dispatch forwarded per fleet; the store dedupes persistently, this
  /// only spares a preferences round trip on every game state change.
  final _forwarded = <int, DateTime>{};

  void _record() {
    for (final fleet in controller.state.fleets) {
      final mission = fleet.mission;
      final completionTime = mission.completionTime;
      if (!mission.isActive || mission.missionId <= 0) continue;
      if (_forwarded[fleet.id] == completionTime) continue;
      _forwarded[fleet.id] = completionTime!;
      store.recordDispatch(fleet.id, mission.missionId, completionTime);
    }
  }

  void _onAccountChanged() {
    // Fleets seen before the account was known were never stored.
    _forwarded.clear();
    _record();
  }

  void dispose() {
    controller.removeListener(_record);
    accountSession.removeListener(_onAccountChanged);
  }
}
