import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/account/account_session.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/expedition/expedition_fleet_request.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/smart_panel/smart_panel_controller.dart';

CapturedApiEvent _event(String api) => CapturedApiEvent(
  path: '/kcsapi/$api',
  responseBody: '{"api_result":1,"api_data":{}}',
  source: CaptureSource.manual,
  capturedAt: DateTime(2026, 10, 24),
);

Fleet _fleet(int id, {int ships = 6, bool onExpedition = false}) => Fleet(
  id: id,
  name: '第$id舰队',
  shipIds: [for (var i = 0; i < ships; i++) id * 10 + i],
  mission: onExpedition
      ? FleetMission(state: 1, missionId: 5, completionTime: DateTime(2030))
      : const FleetMission(),
);

GameState _state({
  List<Fleet>? fleets,
  CombinedFleetType combined = CombinedFleetType.none,
}) => GameState.empty.copyWith(
  fleets: fleets ?? [_fleet(1), _fleet(2), _fleet(3), _fleet(4)],
  combinedFleetType: combined,
);

void main() {
  late GameState state;
  late bool autoSwitch;
  late AccountSession account;
  late SmartPanelController controller;

  setUp(() {
    state = _state();
    autoSwitch = true;
    account = AccountSession(initialMemberId: 1001);
    controller = SmartPanelController(
      stateProvider: () => state,
      waitForGameState: () async {},
      autoSwitchEnabled: () => autoSwitch,
      accountSession: account,
    );
  });

  tearDown(() => controller.dispose());

  Future<void> send(String api) async {
    controller.accept(_event(api));
    await controller.idle;
  }

  test('starts at home without auto marker', () {
    expect(controller.state, SmartPanelState.home);
    expect(controller.autoSelected, isFalse);
  });

  test('each trigger path switches to its state', () async {
    const cases = <String, SmartPanelState>{
      'api_get_member/mapinfo': SmartPanelState.sortieCheck,
      'api_req_map/start': SmartPanelState.battle,
      'api_port/port': SmartPanelState.home,
      'api_get_member/questlist': SmartPanelState.quests,
      'api_get_member/mission': SmartPanelState.expeditionCheck,
      'api_get_member/practice': SmartPanelState.practice,
      'api_req_practice/battle': SmartPanelState.battle,
      'api_req_member/get_practice_enemyinfo': SmartPanelState.practice,
    };
    for (final entry in cases.entries) {
      await send(entry.key);
      expect(controller.state, entry.value, reason: entry.key);
      expect(controller.autoSelected, isTrue, reason: entry.key);
    }
  });

  test('in-sortie updates are not triggers', () {
    expect(controller.supportsPath('/kcsapi/api_req_map/next'), isFalse);
    expect(controller.supportsPath('/kcsapi/api_req_sortie/battle'), isFalse);
    expect(
      controller.supportsPath('/kcsapi/api_req_sortie/battleresult'),
      isFalse,
    );
  });

  test('manual selection holds until the next trigger', () async {
    await send('api_req_map/start');
    controller.select(SmartPanelState.quests);
    expect(controller.state, SmartPanelState.quests);
    expect(controller.autoSelected, isFalse);

    await send('api_port/port');
    expect(controller.state, SmartPanelState.home);
    expect(controller.autoSelected, isTrue);
  });

  test('auto switch off keeps state and sends no fleet request', () async {
    autoSwitch = false;
    await send('api_get_member/mapinfo');
    await send('api_get_member/mission');
    await send('api_req_mission/start');
    expect(controller.state, SmartPanelState.home);
    expect(controller.expeditionFleetRequest, isNull);
  });

  test(
    'opening expedition requests the first idle fleet from fleet 2',
    () async {
      state = _state(
        fleets: [
          _fleet(1),
          _fleet(2, onExpedition: true),
          _fleet(3),
          _fleet(4),
        ],
      );
      await send('api_get_member/mission');
      expect(controller.expeditionFleetRequest?.fleetId, 3);
    },
  );

  test('fleets with fewer than two ships are skipped', () async {
    state = _state(fleets: [_fleet(1), _fleet(2, ships: 1), _fleet(3)]);
    await send('api_get_member/mission');
    expect(controller.expeditionFleetRequest?.fleetId, 3);
  });

  test('combined fleet starts searching from fleet 3', () async {
    state = _state(combined: CombinedFleetType.carrierTaskForce);
    await send('api_get_member/mission');
    expect(controller.expeditionFleetRequest?.fleetId, 3);
  });

  test(
    'dispatching jumps to the next idle fleet without changing state',
    () async {
      await send('api_get_member/mission');
      final first = controller.expeditionFleetRequest!;
      expect(first.fleetId, 2);

      state = _state(
        fleets: [
          _fleet(1),
          _fleet(2, onExpedition: true),
          _fleet(3),
          _fleet(4),
        ],
      );
      controller.select(SmartPanelState.home);
      await send('api_req_mission/start');
      final next = controller.expeditionFleetRequest!;
      expect(next.fleetId, 3);
      expect(next.serial, greaterThan(first.serial));
      expect(controller.state, SmartPanelState.home);
    },
  );

  test('dispatch reads fleets after game state settles', () async {
    var settled = false;
    final waiting = SmartPanelController(
      stateProvider: () => settled
          ? _state(
              fleets: [_fleet(1), _fleet(2, onExpedition: true), _fleet(3)],
            )
          : _state(),
      waitForGameState: () async => settled = true,
      autoSwitchEnabled: () => true,
    );
    addTearDown(waiting.dispose);
    waiting.accept(_event('api_req_mission/start'));
    await waiting.idle;
    expect(waiting.expeditionFleetRequest?.fleetId, 3);
  });

  test('no idle fleet leaves the previous request', () async {
    await send('api_get_member/mission');
    final before = controller.expeditionFleetRequest;
    state = _state(
      fleets: [
        _fleet(1),
        _fleet(2, onExpedition: true),
        _fleet(3, onExpedition: true),
        _fleet(4, onExpedition: true),
      ],
    );
    await send('api_req_mission/start');
    expect(controller.expeditionFleetRequest, same(before));
  });

  test('account switch returns home and clears the request', () async {
    await send('api_get_member/mission');
    account.selectMember(2002);
    expect(controller.state, SmartPanelState.home);
    expect(controller.autoSelected, isFalse);
    expect(controller.expeditionFleetRequest, isNull);
  });

  test('admiral name update on the same account keeps the state', () async {
    await send('api_get_member/questlist');
    account.accept(
      CapturedApiEvent(
        path: '/kcsapi/api_get_member/basic',
        responseBody:
            '{"api_result":1,"api_data":{"api_member_id":1001,"api_nickname":"提督"}}',
        source: CaptureSource.manual,
        capturedAt: DateTime(2026, 10, 24),
      ),
    );
    expect(account.admiralName, '提督');
    expect(controller.state, SmartPanelState.quests);
  });

  test('firstIdleExpeditionFleet returns null when every fleet is busy', () {
    expect(
      firstIdleExpeditionFleet(
        _state(fleets: [_fleet(1), _fleet(2, onExpedition: true)]),
      ),
      isNull,
    );
  });
}
