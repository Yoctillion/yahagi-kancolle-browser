import 'package:flutter/foundation.dart';

import '../account/account_session.dart';
import '../bridge/captured_api_event.dart';
import '../expedition/expedition_fleet_request.dart';
import '../game_state/game_api_event_pipeline.dart';
import '../game_state/game_state.dart';

enum SmartPanelState {
  home,
  sortieCheck,
  battle,
  quests,
  expeditionCheck,
  practice,
}

/// Infers the game screen from the API calls that open it (KC3 Activity tab
/// behaviour). Only screen-entering calls are triggers, so a manual pick made
/// mid-sortie survives node and battle updates until the next screen change.
class SmartPanelController extends ChangeNotifier
    implements GameApiEventConsumer {
  SmartPanelController({
    required this.stateProvider,
    required this.waitForGameState,
    required this.autoSwitchEnabled,
    this.accountSession,
  }) : _scope = accountSession?.current {
    accountSession?.addListener(_onAccountChanged);
  }

  final GameState Function() stateProvider;
  final Future<void> Function() waitForGameState;
  final bool Function() autoSwitchEnabled;
  final AccountSession? accountSession;

  static const _missionStart = '/kcsapi/api_req_mission/start';
  static const _missionList = '/kcsapi/api_get_member/mission';
  static const _triggers = <String, SmartPanelState>{
    '/kcsapi/api_port/port': SmartPanelState.home,
    '/kcsapi/api_get_member/mapinfo': SmartPanelState.sortieCheck,
    '/kcsapi/api_req_map/start': SmartPanelState.battle,
    '/kcsapi/api_req_practice/battle': SmartPanelState.battle,
    '/kcsapi/api_get_member/questlist': SmartPanelState.quests,
    _missionList: SmartPanelState.expeditionCheck,
    '/kcsapi/api_get_member/practice': SmartPanelState.practice,
    '/kcsapi/api_req_member/get_practice_enemyinfo': SmartPanelState.practice,
  };

  AccountScope? _scope;
  SmartPanelState _state = SmartPanelState.home;
  bool _autoSelected = false;
  ExpeditionFleetRequest? _fleetRequest;
  int _requestSerial = 0;
  bool _disposed = false;
  Future<void> _queue = Future<void>.value();

  SmartPanelState get state => _state;
  bool get autoSelected => _autoSelected;
  ExpeditionFleetRequest? get expeditionFleetRequest => _fleetRequest;

  @override
  Future<void> get idle => _queue;

  @override
  bool supportsPath(String path) =>
      path == _missionStart || _triggers.containsKey(path);

  @override
  void accept(CapturedApiEvent event) {
    if (_disposed || !autoSwitchEnabled()) return;
    final target = _triggers[event.path];
    if (target != null && (target != _state || !_autoSelected)) {
      _state = target;
      _autoSelected = true;
      notifyListeners();
    }
    if (event.path != _missionList && event.path != _missionStart) return;
    final scope = accountSession?.current;
    _queue = _queue.then((_) async {
      // The reducer applies mission/start asynchronously; read fleets after it.
      await waitForGameState();
      if (_disposed || (scope != null && !accountSession!.isCurrent(scope))) {
        return;
      }
      final gameState = stateProvider();
      final fleetId = firstIdleExpeditionFleet(gameState);
      if (fleetId != null) {
        _fleetRequest = ExpeditionFleetRequest(fleetId, ++_requestSerial);
        notifyListeners();
      } else if (_state == SmartPanelState.expeditionCheck &&
          gameState.hasPortData) {
        // Nothing left to send: the check has nothing to offer, show timers.
        _state = SmartPanelState.home;
        _autoSelected = true;
        notifyListeners();
      }
    });
  }

  void select(SmartPanelState state) {
    if (_state == state && !_autoSelected) return;
    _state = state;
    _autoSelected = false;
    notifyListeners();
  }

  void _onAccountChanged() {
    // AccountSession also notifies for admiral name updates on the same account.
    final current = accountSession?.current;
    if (identical(current, _scope)) return;
    _scope = current;
    _state = SmartPanelState.home;
    _autoSelected = false;
    _fleetRequest = null;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    accountSession?.removeListener(_onAccountChanged);
    super.dispose();
  }
}
