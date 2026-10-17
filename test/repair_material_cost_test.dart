import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_reducer.dart';
import 'fixtures/kcsapi_fixtures.dart';

void main() {
  final reducer = GameStateReducer();
  GameState initial() => reducer.reduce(
    GameState.empty,
    kcsapiEvent('/kcsapi/api_port/port', {
      'api_basic': {'api_member_id': 1001},
      'api_ship': [
        {
          'api_id': 1,
          'api_ship_id': 1,
          'api_nowhp': 73,
          'api_maxhp': 90,
          'api_ndock_item': [54, 102],
          'api_ndock_time': 20430000,
        },
      ],
      'api_material': [
        {'api_id': 1, 'api_value': 1000},
        {'api_id': 3, 'api_value': 1000},
        {'api_id': 6, 'api_value': 8},
      ],
    }),
  );
  GameState start(GameState state, {int speed = 0}) => reducer.reduce(
    state,
    kcsapiEvent(
      '/kcsapi/api_req_nyukyo/start',
      {},
      includeApiData: false,
      requestParams: {
        'api_ndock_id': 1,
        'api_ship_id': 1,
        'api_highspeed': speed,
      },
    ),
  );

  for (final speed in [0, 1]) {
    test('two repair costs deduct fuel and steel, highspeed=$speed', () {
      final state = start(initial(), speed: speed);
      expect(state.resource(GameResourceType.fuel), 946);
      expect(state.resource(GameResourceType.steel), 898);
      expect(state.resource(GameResourceType.instantRepair), 8 - speed);
      expect(state.ships[1]!.currentHp, speed == 1 ? 90 : 73);
      expect(state.repairDocks.single.steelCost, speed == 1 ? 0 : 102);
    });
  }
  test('missing costs inherit while explicit empty costs clear', () {
    var state = reducer.reduce(
      initial(),
      kcsapiEvent('/kcsapi/api_get_member/ship2', [
        {'api_id': 1, 'api_ship_id': 1, 'api_nowhp': 72},
      ]),
    );
    expect(state.ships[1]!.repairFuelCost, 54);
    expect(state.ships[1]!.repairSteelCost, 102);
    state = reducer.reduce(
      state,
      kcsapiEvent('/kcsapi/api_get_member/ship2', [
        {'api_id': 1, 'api_ship_id': 1, 'api_ndock_item': []},
      ]),
    );
    expect(state.ships[1]!.repairFuelCost, 0);
    expect(state.ships[1]!.repairSteelCost, 0);
    expect(start(state).resource(GameResourceType.steel), 1000);
  });
  test(
    'new ship at an existing owned ID does not inherit old repair costs',
    () {
      final state = reducer.reduce(
        initial(),
        kcsapiEvent('/kcsapi/api_get_member/ship2', [
          {'api_id': 1, 'api_ship_id': 2, 'api_nowhp': 20},
        ]),
      );
      expect(state.ships[1]!.repairFuelCost, 0);
      expect(state.ships[1]!.repairSteelCost, 0);
    },
  );
  test(
    'bucket completes repair and authoritative snapshots replace estimates',
    () {
      var state = start(initial());
      state = reducer.reduce(
        state,
        kcsapiEvent(
          '/kcsapi/api_req_nyukyo/speedchange',
          {},
          includeApiData: false,
          requestParams: {'api_ndock_id': 1},
        ),
      );
      expect(state.ships[1]!.currentHp, 90);
      expect(state.resource(GameResourceType.instantRepair), 7);
      state = reducer.reduce(
        state,
        kcsapiEvent('/kcsapi/api_get_member/material', [
          {'api_id': 1, 'api_value': 900},
          {'api_id': 3, 'api_value': 800},
        ]),
      );
      state = reducer.reduce(
        state,
        kcsapiEvent('/kcsapi/api_get_member/ndock', [
          {
            'api_id': 1,
            'api_state': 1,
            'api_ship_id': 1,
            'api_item1': 60,
            'api_item3': 120,
          },
        ]),
      );
      expect(state.resource(GameResourceType.fuel), 900);
      expect(state.resource(GameResourceType.steel), 800);
      expect(state.repairDocks.single.steelCost, 120);
    },
  );
}
