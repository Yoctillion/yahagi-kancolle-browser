import 'package:flutter/foundation.dart';

import '../account/account_session.dart';
import '../bridge/captured_api_event.dart';
import '../expedition/expedition_fleet_request.dart';
import '../game_state/game_api_event_pipeline.dart';
import '../game_state/game_state.dart';

final class FleetFocusRequest {
  const FleetFocusRequest(this.fleetId, this.serial);

  final int fleetId;

  /// Monotonic so that focusing the same fleet again still overrides a manual
  /// pick made in between.
  final int serial;
}

/// Follows the fleet the game is acting on, mirroring KC3's auto fleet view
/// (`switchTo` in Kcsapi.js plus `ExpedTabAutoFleetSwitch`). KC3's combined
/// view has no counterpart here, so it maps to fleet 1.
class FleetFocusController extends ChangeNotifier
    implements GameApiEventConsumer {
  FleetFocusController({
    required this.stateProvider,
    required this.waitForGameState,
    required this.enabled,
    this.accountSession,
  }) : _scope = accountSession?.current {
    accountSession?.addListener(_onAccountChanged);
  }

  final GameState Function() stateProvider;
  final Future<void> Function() waitForGameState;
  final bool Function() enabled;
  final AccountSession? accountSession;

  static const _combined = '/kcsapi/api_req_hensei/combined';
  static const _missionPaths = <String>{
    '/kcsapi/api_get_member/mission',
    '/kcsapi/api_req_mission/start',
  };
  static const _fleetParams = <String, String>{
    '/kcsapi/api_req_hensei/change': 'api_id',
    '/kcsapi/api_req_hensei/preset_select': 'api_deck_id',
    '/kcsapi/api_req_map/start': 'api_deck_id',
    '/kcsapi/api_req_practice/battle': 'api_deck_id',
  };
  static const _shipParams = <String, String>{
    '/kcsapi/api_req_kaisou/slotset': 'api_id',
    '/kcsapi/api_req_kaisou/slotset_ex': 'api_id',
    '/kcsapi/api_req_kaisou/unsetslot_all': 'api_id',
    '/kcsapi/api_req_kaisou/slot_exchange_index': 'api_id',
    '/kcsapi/api_req_kaisou/slot_deprive': 'api_set_ship',
    '/kcsapi/api_req_kaisou/preset_slot_select': 'api_ship_id',
  };

  AccountScope? _scope;
  FleetFocusRequest? _request;
  int _serial = 0;
  bool _disposed = false;
  Future<void> _queue = Future<void>.value();

  FleetFocusRequest? get request => _request;

  @override
  Future<void> get idle => _queue;

  @override
  bool supportsPath(String path) =>
      path == _combined ||
      _missionPaths.contains(path) ||
      _fleetParams.containsKey(path) ||
      _shipParams.containsKey(path);

  @override
  void accept(CapturedApiEvent event) {
    if (_disposed || !enabled()) return;
    final scope = accountSession?.current;
    _queue = _queue.then((_) async {
      // Expedition and ship lookups read fleets after the reducer applied them.
      await waitForGameState();
      if (_disposed || (scope != null && !accountSession!.isCurrent(scope))) {
        return;
      }
      final fleetId = _target(event, stateProvider());
      if (fleetId == null) return;
      _request = FleetFocusRequest(fleetId, ++_serial);
      notifyListeners();
    });
  }

  int? _target(CapturedApiEvent event, GameState state) {
    final path = event.path;
    int param(String name) =>
        int.tryParse('${event.requestParams[name] ?? ''}') ?? 0;
    if (path == _combined) return param('api_combined_type') > 0 ? 1 : null;
    if (_missionPaths.contains(path)) {
      return firstIdleExpeditionFleet(state) ?? 1;
    }
    if (_fleetParams[path] case final name?) {
      final fleetId = param(name);
      return fleetId > 0 ? fleetId : null;
    }
    final shipId = param(_shipParams[path]!);
    if (shipId <= 0) return null;
    for (final fleet in state.fleets) {
      if (fleet.shipIds.contains(shipId)) return fleet.id;
    }
    return null;
  }

  void _onAccountChanged() {
    final current = accountSession?.current;
    if (identical(current, _scope)) return;
    _scope = current;
    _request = null;
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
