import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/account/account_session.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/fleet/fleet_focus_controller.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';

CapturedApiEvent _event(String api, [Map<String, Object?> params = const {}]) =>
    CapturedApiEvent(
      path: '/kcsapi/$api',
      requestParams: params,
      responseBody: '{"api_result":1,"api_data":{}}',
      source: CaptureSource.manual,
      capturedAt: DateTime(2026, 10, 28),
    );

Fleet _fleet(int id, {bool onExpedition = false}) => Fleet(
  id: id,
  name: '第$id舰队',
  shipIds: [for (var i = 0; i < 6; i++) id * 10 + i],
  mission: onExpedition
      ? FleetMission(state: 1, missionId: 5, completionTime: DateTime(2030))
      : const FleetMission(),
);

GameState _state({List<Fleet>? fleets}) => GameState.empty.copyWith(
  hasPortData: true,
  fleets: fleets ?? [_fleet(1), _fleet(2), _fleet(3), _fleet(4)],
);

void main() {
  late GameState state;
  late bool enabled;
  late AccountSession account;
  late FleetFocusController controller;

  setUp(() {
    state = _state();
    enabled = true;
    account = AccountSession(initialMemberId: 1001);
    controller = FleetFocusController(
      stateProvider: () => state,
      waitForGameState: () async {},
      enabled: () => enabled,
      accountSession: account,
    );
  });

  tearDown(() => controller.dispose());

  Future<int?> send(
    String api, [
    Map<String, Object?> params = const {},
  ]) async {
    controller.accept(_event(api, params));
    await controller.idle;
    return controller.request?.fleetId;
  }

  test('organizing, sortie and practice follow the requested fleet', () async {
    expect(await send('api_req_hensei/change', {'api_id': '3'}), 3);
    expect(await send('api_req_hensei/preset_select', {'api_deck_id': '4'}), 4);
    expect(await send('api_req_map/start', {'api_deck_id': '2'}), 2);
    expect(await send('api_req_practice/battle', {'api_deck_id': '3'}), 3);
  });

  test('refits follow the fleet holding the ship', () async {
    expect(await send('api_req_kaisou/slotset', {'api_id': '32'}), 3);
    expect(await send('api_req_kaisou/slotset_ex', {'api_id': '21'}), 2);
    expect(await send('api_req_kaisou/unsetslot_all', {'api_id': '45'}), 4);
    expect(
      await send('api_req_kaisou/slot_exchange_index', {'api_id': '10'}),
      1,
    );
    expect(
      await send('api_req_kaisou/slot_deprive', {'api_set_ship': '33'}),
      3,
    );
    expect(
      await send('api_req_kaisou/preset_slot_select', {'api_ship_id': '24'}),
      2,
    );
  });

  test('a refit on a ship outside every fleet keeps the current one', () async {
    await send('api_req_hensei/change', {'api_id': '2'});
    final before = controller.request;
    await send('api_req_kaisou/slotset', {'api_id': '999'});
    expect(controller.request, same(before));
  });

  test('forming a combined fleet shows fleet 1, disbanding keeps it', () async {
    await send('api_req_hensei/change', {'api_id': '3'});
    expect(
      await send('api_req_hensei/combined', {'api_combined_type': '1'}),
      1,
    );
    await send('api_req_hensei/change', {'api_id': '3'});
    expect(
      await send('api_req_hensei/combined', {'api_combined_type': '0'}),
      3,
    );
  });

  test('expeditions show the first fleet that can still be sent', () async {
    state = _state(
      fleets: [_fleet(1), _fleet(2, onExpedition: true), _fleet(3), _fleet(4)],
    );
    expect(await send('api_get_member/mission'), 3);

    state = _state(
      fleets: [
        _fleet(1),
        _fleet(2, onExpedition: true),
        _fleet(3, onExpedition: true),
        _fleet(4),
      ],
    );
    expect(await send('api_req_mission/start'), 4);
  });

  test('with every fleet away it falls back to fleet 1', () async {
    state = _state(
      fleets: [
        _fleet(1),
        _fleet(2, onExpedition: true),
        _fleet(3, onExpedition: true),
        _fleet(4, onExpedition: true),
      ],
    );
    expect(await send('api_req_mission/start'), 1);
  });

  test('refocusing the same fleet issues a newer request', () async {
    await send('api_req_hensei/change', {'api_id': '2'});
    final first = controller.request!;
    await send('api_req_map/start', {'api_deck_id': '2'});
    expect(controller.request!.serial, greaterThan(first.serial));
  });

  test('switched off it issues nothing', () async {
    enabled = false;
    expect(await send('api_req_hensei/change', {'api_id': '2'}), isNull);
  });

  test('an account switch clears the request', () async {
    await send('api_req_hensei/change', {'api_id': '2'});
    account.selectMember(2002);
    expect(controller.request, isNull);
  });
}
