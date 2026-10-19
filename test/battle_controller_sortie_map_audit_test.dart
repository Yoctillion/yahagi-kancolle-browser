import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/account/account_session.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/fcd_map_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/fcd_map_dataset.dart';
import 'package:yahagi_kancolle_browser/src/battle/fcd_map_update_service.dart';
import 'package:yahagi_kancolle_browser/src/battle/prediction/battle_prediction_executor.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/game_state/combat_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_reducer.dart';

import 'fixtures/kcsapi_fixtures.dart';

void main() {
  late GameState state;
  late BattleController controller;
  final reducer = GameStateReducer();

  setUp(() {
    state = reducer.reduce(GameState.empty, start2Event);
    state = reducer.reduce(state, portEvent);
    controller = BattleController(
      gameState: () => state,
      predictionExecutor: const ImmediateBattlePredictionExecutor(),
    );
  });
  tearDown(() => controller.dispose());

  Future<void> send(CapturedApiEvent event, {bool reduceState = false}) async {
    if (reduceState) state = reducer.reduce(state, event);
    controller.accept(event);
    await controller.idle;
  }

  test(
    'request-only map ids keep navigation context and progress in sync',
    () async {
      await send(_move(start: true, node: 42));
      await send(
        _move(
          start: true,
          node: 3,
          area: null,
          info: null,
          sequence: 102,
          request: {'api_maparea_id': '99', 'api_mapinfo_no': '5'},
        ),
        reduceState: true,
      );

      expect(controller.sortieMapProgress!.mapKey, '99-5');
      expect(controller.current!.context.mapAreaId, 99);
      expect(controller.current!.context.mapInfoNo, 5);
      expect(controller.current!.context.node, 3);
      expect(controller.lastError, isNull);
    },
  );

  test(
    'observed partial battle node is retained when navigation resumes',
    () async {
      state = state.copyWith(
        combatState: const CombatState(
          isActive: true,
          mapArea: 5,
          mapInfo: 6,
          currentNode: 43,
          sortieFleetId: 1,
        ),
      );
      await send(_copy(dayBattleEvent, sequence: 101));
      expect(controller.sortieMapProgress!.routeIds, [43]);
      await send(_move(node: 44, sequence: 102), reduceState: true);

      expect(controller.sortieMapProgress!.routeIds, [43, 44]);
      expect(controller.sortieMapProgress!.isPartial, isTrue);
      expect(controller.lastError, isNull);
    },
  );

  test(
    'new sortie without a boss does not keep the prior context boss',
    () async {
      await send(_move(start: true, node: 42, boss: 45));
      await send(_move(start: true, node: 3, area: 6, info: 1, sequence: 102));

      expect(controller.sortieMapProgress!.bossRouteId, isNull);
      expect(controller.current!.context.bossNode, 0);
    },
  );

  test('an unidentified new start cannot borrow a stale active map', () async {
    await send(_move(start: true, node: 42));
    state = state.copyWith(combatState: _activeCombat());
    await send(
      _move(start: true, node: 3, area: null, info: null, sequence: 102),
    );

    expect(controller.sortieMapProgress, isNull);
    expect(controller.current!.context.mapAreaId, 0);
    expect(controller.current!.context.mapInfoNo, 0);
  });

  test(
    'the real reducer clears map identity for an unidentified start',
    () async {
      await send(_move(start: true, node: 42), reduceState: true);
      await send(
        _move(start: true, node: 3, area: null, info: null, sequence: 102),
        reduceState: true,
      );

      expect(state.combatState.mapArea, 0);
      expect(state.combatState.mapInfo, 0);
      expect(controller.sortieMapProgress, isNull);
    },
  );

  for (final reset in [portEvent, start2Event]) {
    test(
      '${reset.path} cannot recover a stale map without a new packet',
      () async {
        await send(_move(start: true, node: 42));
        state = state.copyWith(combatState: _activeCombat());
        await send(_copy(reset, sequence: 102));

        expect(controller.sortieMapProgress, isNull);
        controller.refreshNodeLabel();
        expect(controller.sortieMapProgress, isNull);
      },
    );

    test(
      '${reset.path} permits partial recovery from a new active battle',
      () async {
        await send(_move(start: true, node: 42));
        state = state.copyWith(combatState: _activeCombat());
        await send(_copy(reset, sequence: 102));
        state = state.copyWith(
          combatState: _activeCombat(area: 6, info: 1, node: 3),
        );
        expect(controller.sortieMapProgress, isNull);

        await send(_copy(dayBattleEvent, sequence: 103), reduceState: true);

        expect(controller.sortieMapProgress, isNotNull);
        expect(controller.sortieMapProgress!.mapKey, '6-1');
        expect(controller.sortieMapProgress!.routeIds, [3]);
        expect(controller.sortieMapProgress!.isPartial, isTrue);
        await send(
          _move(node: 4, area: 6, info: 1, sequence: 104),
          reduceState: true,
        );
        expect(controller.sortieMapProgress!.routeIds, [3, 4]);
      },
    );

    test(
      '${reset.path} cannot recover from a battle with unchanged stale location',
      () async {
        await send(_move(start: true, node: 42));
        state = state.copyWith(combatState: _activeCombat());
        await send(_copy(reset, sequence: 102));

        // The reducer can create a new combat object while retaining the same
        // location. Object identity alone therefore cannot establish freshness.
        await send(_copy(dayBattleEvent, sequence: 103), reduceState: true);
        expect(controller.sortieMapProgress, isNull);
      },
    );
  }

  test('failed fresh battle cannot reopen a reset map fallback', () async {
    await send(_move(start: true, node: 42));
    state = state.copyWith(combatState: _activeCombat());
    await send(_copy(portEvent, sequence: 102));
    state = state.copyWith(
      combatState: _activeCombat(area: 6, info: 1, node: 3),
    );
    await send(
      kcsapiEvent(
        '/kcsapi/api_req_sortie/battle',
        {},
        apiResult: 0,
        sequence: 103,
      ),
    );

    expect(controller.sortieMapProgress, isNull);
  });

  test('battle fleet-id completion cannot revive a reset stale map', () async {
    await send(_move(start: true, node: 42));
    state = state.copyWith(
      combatState: _activeCombat().copyWith(sortieFleetId: 0),
    );
    await send(_copy(portEvent, sequence: 102));

    await send(_copy(dayBattleEvent, sequence: 103), reduceState: true);

    expect(state.combatState.sortieFleetId, 1);
    expect(state.combatState.mapArea, 5);
    expect(state.combatState.mapInfo, 6);
    expect(state.combatState.currentNode, 42);
    expect(controller.sortieMapProgress, isNull);
  });

  test(
    'a port-cleared combat can recover even at the same map position',
    () async {
      await send(_move(start: true, node: 42), reduceState: true);
      await send(_copy(portEvent, sequence: 102), reduceState: true);
      expect(state.combatState.isActive, isFalse);
      state = state.copyWith(combatState: _activeCombat());

      await send(_copy(dayBattleEvent, sequence: 103), reduceState: true);

      expect(controller.sortieMapProgress, isNotNull);
      expect(controller.sortieMapProgress!.mapKey, '5-6');
      expect(controller.sortieMapProgress!.routeIds, [42]);
      expect(controller.sortieMapProgress!.isPartial, isTrue);
    },
  );

  test(
    'recovery cannot read an active snapshot owned by the previous account',
    () async {
      controller.dispose();
      final account = AccountSession(initialMemberId: 1);
      addTearDown(account.dispose);
      state = state.copyWith(memberId: 1, combatState: _activeCombat());
      controller = BattleController(
        gameState: () => state,
        accountSession: account,
        predictionExecutor: const ImmediateBattlePredictionExecutor(),
      );
      account.selectMember(2);
      state = state.copyWith(
        combatState: _activeCombat(area: 6, info: 1, node: 3),
      );

      await send(_copy(dayBattleEvent, sequence: 101));

      expect(controller.sortieMapProgress, isNull);
    },
  );

  test(
    'old-account queued battle cannot enable new-account partial recovery',
    () async {
      controller.dispose();
      final account = AccountSession(initialMemberId: 1);
      addTearDown(account.dispose);
      final stateReady = Completer<void>();
      state = state.copyWith(memberId: 1, combatState: _activeCombat());
      controller = BattleController(
        gameState: () => state,
        accountSession: account,
        waitForGameState: () => stateReady.future,
        predictionExecutor: const ImmediateBattlePredictionExecutor(),
      );
      controller.accept(_copy(dayBattleEvent, sequence: 101));
      account.selectMember(2);
      state = state.copyWith(
        memberId: 2,
        combatState: _activeCombat(area: 6, info: 1, node: 3),
      );
      stateReady.complete();
      await controller.idle;
      expect(controller.sortieMapProgress, isNull);

      await send(_copy(dayBattleEvent, sequence: 101));
      expect(controller.sortieMapProgress, isNotNull);
      expect(controller.sortieMapProgress!.mapKey, '6-1');
      expect(controller.sortieMapProgress!.routeIds, [3]);
      expect(controller.sortieMapProgress!.isPartial, isTrue);
    },
  );

  test(
    'real reducer and controller follow resource, branch and battle nodes',
    () async {
      await send(_move(start: true, node: 42, from: 0), reduceState: true);
      await send(
        _move(
          node: 43,
          sequence: 102,
          extra: {
            'api_event_id': 2,
            'api_select_route': {
              'api_select_cells': [44, 45],
            },
            'api_cell_data': [
              {'api_no': 44},
              {'api_no': 45},
            ],
          },
        ),
        reduceState: true,
      );
      expect(controller.sortieMapProgress!.routeIds, [0, 42, 43]);
      await send(
        _move(node: 45, sequence: 103, request: {'api_cell_id': '45'}),
        reduceState: true,
      );

      expect(controller.sortieMapProgress!.routeIds, [0, 42, 43, 45]);
      expect(state.combatState.currentNode, 45);
      expect(controller.lastError, isNull);
    },
  );

  test(
    'failed navigation and port responses preserve the active route',
    () async {
      await send(_move(start: true, node: 42));
      final before = controller.sortieMapProgress;
      for (final path in [
        '/kcsapi/api_req_map/start',
        '/kcsapi/api_req_map/next',
        '/kcsapi/api_port/port',
      ]) {
        await send(
          kcsapiEvent(path, null, apiResult: 0, sequence: 200 + path.length),
        );
        expect(controller.sortieMapProgress, same(before));
      }
    },
  );

  test('malformed port snapshot cannot discard a known active route', () async {
    await send(_move(start: true, node: 42));
    final before = controller.sortieMapProgress;
    await send(kcsapiEvent('/kcsapi/api_port/port', [], sequence: 102));

    expect(controller.sortieMapProgress, same(before));
    expect(controller.lastError, isNotNull);
    await send(_move(node: 43, sequence: 103));
    expect(controller.sortieMapProgress!.routeIds, [42, 43]);
    expect(controller.lastError, isNull);
  });

  test(
    'next can use request-only ids after the reducer loses omitted response ids',
    () async {
      await send(_move(start: true, node: 42), reduceState: true);
      await send(
        _move(
          node: 43,
          area: null,
          info: null,
          sequence: 102,
          request: {'api_maparea_id': '5', 'api_mapinfo_no': '6'},
        ),
        reduceState: true,
      );

      expect(controller.sortieMapProgress!.mapKey, '5-6');
      expect(controller.sortieMapProgress!.routeIds, [42, 43]);
      expect(controller.sortieMapProgress!.isPartial, isFalse);
    },
  );

  test(
    'response map ids take precedence over conflicting request ids',
    () async {
      await send(
        _move(
          start: true,
          node: 42,
          request: {'api_maparea_id': '99', 'api_mapinfo_no': '9'},
        ),
      );
      expect(controller.sortieMapProgress!.mapKey, '5-6');
    },
  );

  test(
    'same-map next without ids retains only already captured history',
    () async {
      await send(_move(start: true, node: 42, from: 0), reduceState: true);
      await send(
        _move(node: 43, area: null, info: null, sequence: 102),
        reduceState: true,
      );
      expect(controller.sortieMapProgress!.routeIds, [0, 42, 43]);
      expect(controller.sortieMapProgress!.mapKey, '5-6');
    },
  );

  test(
    'integer strings are accepted without treating request branch as visited',
    () async {
      await send(
        kcsapiEvent('/kcsapi/api_req_map/start', {
          'api_maparea_id': '5',
          'api_mapinfo_no': '6',
          'api_from_no': '0',
          'api_no': '42',
        }, sequence: 101),
      );
      await send(
        _move(node: 43, sequence: 102, request: {'api_cell_id': '99'}),
      );
      expect(controller.sortieMapProgress!.routeIds, [0, 42, 43]);
    },
  );

  for (final invalid in [null, -1, 'invalid', 0]) {
    test('invalid next node $invalid cannot append a phantom route', () async {
      await send(_move(start: true, node: 42, from: 0));
      await send(
        kcsapiEvent('/kcsapi/api_req_map/next', {
          'api_maparea_id': 5,
          'api_mapinfo_no': 6,
          'api_no': invalid,
        }, sequence: 102),
      );
      expect(controller.sortieMapProgress!.routeIds, [0, 42]);
      expect(controller.sortieMapProgress!.currentRouteId, 42);
      expect(controller.lastError, isNull);
    });
  }

  test(
    'negative departure is excluded while positive observed node is retained',
    () async {
      await send(_move(start: true, node: 42, from: -1));
      expect(controller.sortieMapProgress!.routeIds, [42]);
    },
  );

  test(
    'explicit zero departure is retained separately from terminal next zero',
    () async {
      await send(_move(start: true, node: 42, from: 0));
      await send(_move(node: 0, sequence: 102));
      await send(_move(node: 43, sequence: 103));
      expect(controller.sortieMapProgress!.routeIds, [0, 42, 43]);
    },
  );

  test('a new unknown map is retained while geometry is absent', () async {
    await send(_move(start: true, node: 42));
    await send(
      _move(start: true, node: 3, from: 0, area: 99, info: 1, sequence: 102),
    );
    await send(_move(node: 4, area: 99, info: 1, sequence: 103));

    expect(controller.sortieMapProgress!.mapKey, '99-1');
    expect(controller.sortieMapProgress!.routeIds, [0, 3, 4]);
    expect(controller.sortieMapGeometry, isNull);
  });

  test(
    'a deferred old-account navigation cannot revive progress after switch',
    () async {
      controller.dispose();
      final account = AccountSession(initialMemberId: 1);
      final stateReady = Completer<void>();
      addTearDown(account.dispose);
      controller = BattleController(
        gameState: () => state,
        waitForGameState: () => stateReady.future,
        accountSession: account,
      );
      controller.accept(_move(start: true, node: 42));
      account.selectMember(2);
      stateReady.complete();
      await controller.idle;

      expect(controller.sortieMapProgress, isNull);
      await send(_move(start: true, node: 3, area: 6, info: 1, sequence: 101));
      expect(controller.sortieMapProgress!.routeIds, [3]);
      expect(controller.sortieMapProgress!.mapKey, '6-1');
    },
  );

  test(
    'start2 cancels queued earlier navigation without an account session',
    () async {
      final stateReady = Completer<void>();
      controller.dispose();
      controller = BattleController(
        gameState: () => state,
        waitForGameState: () => stateReady.future,
      );
      controller.accept(_move(start: true, node: 42));
      controller.accept(_copy(start2Event, sequence: 102));
      stateReady.complete();
      await controller.idle;
      expect(controller.sortieMapProgress, isNull);
      expect(controller.current, isNull);
    },
  );

  test(
    'all practice endpoints clear route history before resumed sortie',
    () async {
      for (final path in [
        '/kcsapi/api_req_practice/battle',
        '/kcsapi/api_req_practice/midnight_battle',
        '/kcsapi/api_req_practice/battle_result',
      ]) {
        await send(_move(start: true, node: 42, sequence: 200 + path.length));
        final fixture = path.endsWith('battle_result')
            ? battleResultEvent
            : dayBattleEvent;
        await send(_copy(fixture, path: path, sequence: 300 + path.length));
        expect(controller.sortieMapProgress, isNull, reason: path);
      }
      await send(_move(start: true, node: 3, sequence: 500));
      expect(controller.sortieMapProgress!.routeIds, [3]);
    },
  );

  test(
    'geometry update resumes a previously missing map without altering history',
    () async {
      controller.dispose();
      final mapController = FcdMapController(
        dataset: FcdMapDataset.empty(),
        updater: _Updater(FcdMapUpdated(_dataset())),
      );
      addTearDown(mapController.dispose);
      controller = BattleController(
        gameState: () => state,
        nodeLabelResolver: mapController,
      );
      mapController.addListener(controller.refreshNodeLabel);
      addTearDown(
        () => mapController.removeListener(controller.refreshNodeLabel),
      );
      await send(_move(start: true, node: 42, from: 0));
      await send(_move(node: 43, sequence: 102));
      final observed = controller.sortieMapProgress;
      expect(controller.sortieMapGeometry, isNull);
      expect(controller.current!.context.nodeDisplayLabel, isNull);
      var notifications = 0;
      controller.addListener(() => notifications++);

      await mapController.checkForUpdates();

      expect(controller.sortieMapProgress, same(observed));
      expect(controller.sortieMapGeometry!.routes[43]!.to, 'B');
      expect(controller.current!.context.nodeDisplayLabel, 'B');
      expect(notifications, greaterThan(0));
    },
  );

  test(
    'failed geometry update leaves active history and prior geometry usable',
    () async {
      controller.dispose();
      final mapController = FcdMapController(
        dataset: _dataset(),
        updater: const _Updater(
          FcdMapUpdateFailed(FcdMapUpdateFailure.network, 'offline'),
        ),
      );
      addTearDown(mapController.dispose);
      controller = BattleController(
        gameState: () => state,
        nodeLabelResolver: mapController,
      );
      await send(_move(start: true, node: 42));
      final geometry = controller.sortieMapGeometry;
      final progress = controller.sortieMapProgress;

      await mapController.checkForUpdates();

      expect(controller.sortieMapGeometry, same(geometry));
      expect(controller.sortieMapProgress, same(progress));
      expect(mapController.lastResult, isA<FcdMapUpdateFailed>());
    },
  );
}

CapturedApiEvent _move({
  bool start = false,
  required int node,
  int? area = 5,
  int? info = 6,
  int? from,
  int? boss,
  int sequence = 101,
  Map<String, Object?> request = const {},
  Map<String, Object?> extra = const {},
}) => kcsapiEvent(
  '/kcsapi/api_req_map/${start ? 'start' : 'next'}',
  {
    'api_maparea_id': ?area,
    'api_mapinfo_no': ?info,
    'api_from_no': ?from,
    'api_bosscell_no': ?boss,
    'api_no': node,
    'api_event_id': 4,
    ...extra,
  },
  requestParams: request,
  sequence: sequence,
);

CapturedApiEvent _copy(
  CapturedApiEvent event, {
  String? path,
  required int sequence,
}) => kcsapiEvent(
  path ?? event.path,
  (jsonDecode(event.responseBody) as Map)['api_data'],
  sequence: sequence,
);

FcdMapDataset _dataset() => FcdMapDataset.parse(
  jsonEncode({
    'meta': {'name': 'map', 'version': '2026/10/18/01'},
    'data': {
      '5-6': {
        'route': {
          '0': [null, 'Start'],
          '42': ['Start', 'A'],
          '43': ['A', 'B'],
        },
        'spots': {
          'Start': [0, 0, 'start'],
          'A': [100, 0, ''],
          'B': [200, 100, ''],
        },
      },
    },
  }),
  minimumMapCount: 1,
);

final class _Updater implements FcdMapUpdateClient {
  const _Updater(this.result);
  final FcdMapUpdateResult result;

  @override
  Future<FcdMapUpdateResult> checkAndUpdate({
    required FcdMapDataset current,
  }) async => result;
}

CombatState _activeCombat({int area = 5, int info = 6, int node = 42}) =>
    CombatState(
      mapArea: area,
      mapInfo: info,
      currentNode: node,
      sortieFleetId: 1,
      isActive: true,
    );
