import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/account/account_session.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_node_label_resolver.dart';
import 'package:yahagi_kancolle_browser/src/battle/fcd_map_dataset.dart';
import 'package:yahagi_kancolle_browser/src/battle/fcd_map_geometry.dart';
import 'package:yahagi_kancolle_browser/src/battle/prediction/battle_prediction_executor.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/game_state/combat_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_reducer.dart';

import 'fixtures/kcsapi_fixtures.dart';

void main() {
  late GameState state;
  late BattleController controller;

  setUp(() {
    final reducer = GameStateReducer();
    state = reducer.reduce(GameState.empty, start2Event);
    state = reducer.reduce(state, portEvent);
    controller = BattleController(
      gameState: () => state,
      predictionExecutor: const ImmediateBattlePredictionExecutor(),
    );
  });
  tearDown(() => controller.dispose());

  test(
    'start and every next capture retain internal routes including resource nodes',
    () async {
      controller.accept(_navigation(start: true, node: 42, from: 0, boss: 45));
      await controller.idle;
      expect(controller.sortieMapProgress, isNotNull);
      final first = controller.sortieMapProgress!;
      expect(first.routeIds, [0, 42]);
      expect(first.isPartial, isFalse);
      expect(first.mapKey, '5-6');
      expect(first.bossRouteId, 45);

      controller.accept(_navigation(node: 43, sequence: 102, eventId: 2));
      controller.accept(_navigation(node: 44, sequence: 103, eventId: 6));
      await controller.idle;

      expect(controller.sortieMapProgress!.routeIds, [0, 42, 43, 44]);
      expect(controller.sortieMapProgress!.currentRouteId, 44);
      expect(controller.sortieMapProgress!.bossRouteId, 45);
      expect(first.routeIds, [0, 42]);
    },
  );

  test(
    'day, night, air raid and result packets do not append route history',
    () async {
      controller.accept(_navigation(start: true, node: 42, from: 0, boss: 45));
      await controller.idle;
      for (final event in [
        dayBattleEvent,
        nightBattleEvent,
        battleResultEvent,
        kcsapiEvent('/kcsapi/api_req_map/air_raid', {
          'api_no': 99,
        }, sequence: 104),
      ]) {
        controller.accept(event);
        await controller.idle;
        expect(controller.sortieMapProgress!.routeIds, [0, 42]);
      }
      expect(controller.lastError, isNull);
    },
  );

  test(
    'duplicate capture sequences are ignored while real revisits are retained',
    () async {
      controller.accept(_navigation(start: true, node: 42));
      controller.accept(_navigation(node: 43, sequence: 102));
      controller.accept(_navigation(node: 43, sequence: 102));
      controller.accept(_navigation(node: 42, sequence: 103));
      controller.accept(_navigation(node: 42, sequence: 104));
      await controller.idle;

      expect(controller.sortieMapProgress!.routeIds, [42, 43, 42, 42]);
    },
  );

  test('a new sortie on the same map resets the observed route', () async {
    controller.accept(_navigation(start: true, node: 42, from: 0, boss: 45));
    controller.accept(_navigation(node: 43, sequence: 102));
    controller.accept(
      _navigation(start: true, node: 44, from: 7, sequence: 103),
    );
    await controller.idle;

    expect(controller.sortieMapProgress!.routeIds, [7, 44]);
    expect(controller.sortieMapProgress!.bossRouteId, isNull);
    expect(controller.sortieMapProgress!.isPartial, isFalse);
  });

  test(
    'a later next cannot revive the boss from the preceding sortie',
    () async {
      controller.accept(_navigation(start: true, node: 42, boss: 45));
      controller.accept(_navigation(start: true, node: 44, sequence: 102));
      controller.accept(_navigation(node: 46, sequence: 103));
      await controller.idle;

      expect(controller.sortieMapProgress!.bossRouteId, isNull);
    },
  );

  test('a terminal zero does not append a phantom route', () async {
    controller.accept(_navigation(start: true, node: 42, from: 0));
    controller.accept(_navigation(node: 0, sequence: 102));
    await controller.idle;

    expect(controller.sortieMapProgress!.routeIds, [0, 42]);
    expect(controller.sortieMapProgress!.currentRouteId, 42);
  });

  test(
    'first next capture has only its observed route and is partial',
    () async {
      controller.accept(_navigation(node: 44, from: 43, boss: 45));
      await controller.idle;

      expect(controller.sortieMapProgress!.routeIds, [44]);
      expect(controller.sortieMapProgress!.isPartial, isTrue);
      expect(controller.sortieMapProgress!.bossRouteId, 45);
    },
  );

  test('next on another map starts a separate partial route', () async {
    controller.accept(_navigation(start: true, node: 42, boss: 45));
    controller.accept(_navigation(node: 3, area: 6, map: 1, sequence: 102));
    await controller.idle;

    expect(controller.sortieMapProgress!.mapKey, '6-1');
    expect(controller.sortieMapProgress!.routeIds, [3]);
    expect(controller.sortieMapProgress!.bossRouteId, isNull);
    expect(controller.sortieMapProgress!.isPartial, isTrue);
  });

  test(
    'a start uses raw request map ids instead of the prior map context',
    () async {
      controller.accept(_navigation(start: true, node: 42, boss: 45));
      controller.accept(
        kcsapiEvent(
          '/kcsapi/api_req_map/start',
          {'api_from_no': 0, 'api_no': 3},
          requestParams: {'api_maparea_id': '6', 'api_mapinfo_no': '2'},
          sequence: 102,
        ),
      );
      await controller.idle;

      expect(controller.sortieMapProgress!.mapKey, '6-2');
      expect(controller.sortieMapProgress!.routeIds, [0, 3]);
      expect(controller.sortieMapProgress!.bossRouteId, isNull);
    },
  );

  test(
    'a missing map id uses active game state when attaching mid-sortie',
    () async {
      state = state.copyWith(
        combatState: const CombatState(
          mapArea: 6,
          mapInfo: 2,
          currentNode: 3,
          sortieFleetId: 1,
          isActive: true,
        ),
      );
      controller.accept(
        kcsapiEvent('/kcsapi/api_req_map/next', {'api_no': 3}, sequence: 102),
      );
      await controller.idle;

      expect(controller.sortieMapProgress!.mapKey, '6-2');
      expect(controller.sortieMapProgress!.routeIds, [3]);
      expect(controller.sortieMapProgress!.isPartial, isTrue);
    },
  );

  test('hot reload fallback exposes only the active game state node', () {
    state = state.copyWith(
      combatState: const CombatState(
        mapArea: 5,
        mapInfo: 6,
        currentNode: 43,
        sortieFleetId: 1,
        isActive: true,
      ),
    );

    expect(controller.sortieMapProgress!.routeIds, [43]);
    expect(controller.sortieMapProgress!.isPartial, isTrue);
    expect(controller.sortieMapProgress!.mapKey, '5-6');
  });

  test(
    'battle-only attachment retains a partial current-node fallback',
    () async {
      state = state.copyWith(
        combatState: const CombatState(
          mapArea: 5,
          mapInfo: 6,
          currentNode: 43,
          sortieFleetId: 1,
          isActive: true,
        ),
      );
      controller.accept(dayBattleEvent);
      await controller.idle;

      expect(controller.sortieMapProgress!.routeIds, [43]);
      expect(controller.sortieMapProgress!.isPartial, isTrue);
    },
  );

  for (final active in [false, true]) {
    test(
      'port and start2 clear progress even with isActive=$active stale state',
      () async {
        controller.accept(_navigation(start: true, node: 42));
        await controller.idle;
        state = state.copyWith(
          combatState: CombatState(
            mapArea: 5,
            mapInfo: 6,
            currentNode: 42,
            isActive: active,
          ),
        );
        controller.accept(portEvent);
        await controller.idle;
        expect(controller.sortieMapProgress, isNull);
        controller.accept(_navigation(start: true, node: 43, sequence: 102));
        await controller.idle;
        controller.accept(start2Event);
        await controller.idle;
        expect(controller.sortieMapProgress, isNull);
      },
    );
  }

  test(
    'practice battle clears progress and excludes stale active sortie state',
    () async {
      controller.accept(_navigation(start: true, node: 42));
      await controller.idle;
      state = state.copyWith(
        combatState: const CombatState(
          mapArea: 5,
          mapInfo: 6,
          currentNode: 42,
          isActive: true,
        ),
      );
      controller.accept(
        _withPath(dayBattleEvent, '/kcsapi/api_req_practice/battle', 103),
      );
      await controller.idle;

      expect(controller.sortieMapProgress, isNull);
      expect(controller.sortieMapGeometry, isNull);
    },
  );

  test('practice result alone clears progress', () async {
    controller.accept(_navigation(start: true, node: 42));
    controller.accept(
      _withPath(
        battleResultEvent,
        '/kcsapi/api_req_practice/battle_result',
        103,
      ),
    );
    await controller.idle;

    expect(controller.sortieMapProgress, isNull);
  });

  test(
    'account change and session reset clear rather than inherit route history',
    () async {
      controller.dispose();
      final account = AccountSession(initialMemberId: 1);
      addTearDown(account.dispose);
      controller = BattleController(
        gameState: () => state,
        accountSession: account,
      );
      controller.accept(_navigation(start: true, node: 42));
      await controller.idle;
      state = state.copyWith(
        combatState: const CombatState(
          mapArea: 5,
          mapInfo: 6,
          currentNode: 42,
          isActive: true,
        ),
      );
      account.selectMember(2);
      expect(controller.sortieMapProgress, isNull);
      controller.accept(_navigation(start: true, node: 43, sequence: 102));
      await controller.idle;
      account.reset();
      expect(controller.sortieMapProgress, isNull);
    },
  );

  test('an inactive or invalid game state cannot create progress', () {
    state = state.copyWith(
      combatState: const CombatState(mapArea: 5, mapInfo: 6, currentNode: 42),
    );
    expect(controller.sortieMapProgress, isNull);
    state = state.copyWith(combatState: const CombatState(isActive: true));
    expect(controller.sortieMapProgress, isNull);
  });

  test('geometry is supplied by a compatible label resolver', () async {
    controller.dispose();
    final dataset = FcdMapDataset.parse(_dataset(), minimumMapCount: 1);
    controller = BattleController(
      gameState: () => state,
      nodeLabelResolver: dataset,
    );
    controller.accept(_navigation(start: true, node: 42));
    await controller.idle;

    expect(controller.sortieMapGeometry, isNotNull);
    expect(controller.sortieMapGeometry!.routes[42]!.to, 'Y');
  });

  test(
    'geometry refresh notifies even when the resolved node label is unchanged',
    () async {
      controller.dispose();
      final resolver = _MutableResolver(
        FcdMapDataset.parse(_dataset(), minimumMapCount: 1),
      );
      controller = BattleController(
        gameState: () => state,
        nodeLabelResolver: resolver,
      );
      controller.accept(_navigation(start: true, node: 42));
      await controller.idle;
      var notifications = 0;
      controller.addListener(() => notifications++);
      resolver.dataset = FcdMapDataset.parse(
        _dataset(x: 200),
        minimumMapCount: 1,
      );

      controller.refreshNodeLabel();

      expect(notifications, 1);
      expect(controller.sortieMapGeometry!.spots['Y']!.x, 200);
    },
  );
}

CapturedApiEvent _navigation({
  bool start = false,
  int node = 42,
  int? from,
  int? boss,
  int area = 5,
  int map = 6,
  int sequence = 101,
  int eventId = 4,
}) => kcsapiEvent('/kcsapi/api_req_map/${start ? 'start' : 'next'}', {
  'api_maparea_id': area,
  'api_mapinfo_no': map,
  'api_no': node,
  'api_from_no': ?from,
  'api_bosscell_no': ?boss,
  'api_event_id': eventId,
}, sequence: sequence);

CapturedApiEvent _withPath(CapturedApiEvent event, String path, int sequence) =>
    kcsapiEvent(
      path,
      (jsonDecode(event.responseBody) as Map)['api_data'],
      sequence: sequence,
    );

String _dataset({int x = 100}) => jsonEncode({
  'meta': {'name': 'map', 'version': '2026/07/28/02'},
  'data': {
    '5-6': {
      'route': {
        '42': ['X', 'Y'],
      },
      'spots': {
        'X': [0, 0, ''],
        'Y': [x, 100, ''],
      },
    },
  },
});

// Geometry can update independently of labels in an FCD refresh.
class _MutableResolver
    implements BattleNodeLabelResolver, BattleMapGeometryResolver {
  _MutableResolver(this.dataset);
  FcdMapDataset dataset;

  @override
  String? resolve({
    required int mapAreaId,
    required int mapInfoNo,
    required int internalNodeId,
  }) => dataset.resolve(
    mapAreaId: mapAreaId,
    mapInfoNo: mapInfoNo,
    internalNodeId: internalNodeId,
  );

  @override
  FcdMapGeometry? geometryFor({
    required int mapAreaId,
    required int mapInfoNo,
  }) => dataset.geometryFor(mapAreaId: mapAreaId, mapInfoNo: mapInfoNo);
}
