import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/enemy_fleet_name_memory.dart';
import 'package:yahagi_kancolle_browser/src/battle/prediction/battle_prediction_executor.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_reducer.dart';

import 'fixtures/kcsapi_fixtures.dart';

const _node = '1-1-1';

void main() {
  group('EnemyFleetNameMemory', () {
    test('answers by node, composition and formation', () async {
      final memory = await EnemyFleetNameMemory.load(
        MemoryEnemyFleetNameStore(),
      );
      await memory.remember(_node, ships: [501, 502], formation: 1, name: 'A');

      expect(memory.nameFor(_node), 'A');
      expect(memory.nameFor(_node, ships: [501, 502]), 'A');
      expect(memory.nameFor(_node, ships: [501, 502], formation: 1), 'A');
      // An unseen composition is not guessed from another one.
      expect(memory.nameFor(_node, ships: [503]), isNull);
      expect(memory.nameFor('1-1-2'), isNull);
    });

    test('disagreeing encounters give no node-only guess', () async {
      final memory = await EnemyFleetNameMemory.load(
        MemoryEnemyFleetNameStore(),
      );
      await memory.remember(_node, ships: [501], formation: 1, name: 'A');
      await memory.remember(_node, ships: [502], formation: 1, name: 'B');

      expect(memory.nameFor(_node), isNull);
      expect(memory.nameFor(_node, ships: [502]), 'B');
    });

    test(
      'a formation without a record falls back to the composition',
      () async {
        final memory = await EnemyFleetNameMemory.load(
          MemoryEnemyFleetNameStore(),
        );
        await memory.remember(_node, ships: [501], formation: 1, name: 'A');

        expect(memory.nameFor(_node, ships: [501], formation: 4), 'A');
      },
    );

    test('persists and reloads, ignoring unreadable entries', () async {
      final store = MemoryEnemyFleetNameStore();
      final memory = await EnemyFleetNameMemory.load(store);
      await memory.remember(_node, ships: [501], formation: 1, name: 'A');
      await memory.remember(_node, ships: [501], formation: 1, name: 'A');
      expect(store.saveCount, 1);

      final reloaded = await EnemyFleetNameMemory.load(store);
      expect(reloaded.nameFor(_node, ships: [501]), 'A');

      final broken = await EnemyFleetNameMemory.load(
        MemoryEnemyFleetNameStore('{"1-1-1": [{"s": "x"}], "2-1-1": 3}'),
      );
      expect(broken.nameFor(_node), isNull);
      final unreadable = await EnemyFleetNameMemory.load(
        MemoryEnemyFleetNameStore('not json'),
      );
      expect(unreadable.nameFor(_node), isNull);
    });

    test('keeps only the most recent encounters per node', () async {
      final memory = await EnemyFleetNameMemory.load(
        MemoryEnemyFleetNameStore(),
      );
      for (
        var ship = 0;
        ship <= EnemyFleetNameMemory.maxEncountersPerNode;
        ship++
      ) {
        await memory.remember(
          _node,
          ships: [ship],
          formation: 1,
          name: '$ship',
        );
      }
      expect(memory.nameFor(_node, ships: [0]), isNull);
      expect(memory.nameFor(_node, ships: [1]), '1');
    });
  });

  group('BattleController enemy fleet names', () {
    final reducer = GameStateReducer();

    test('a remembered name is guessed on the next visit', () async {
      var state = reducer.reduce(GameState.empty, start2Event);
      state = reducer.reduce(state, portEvent);
      final store = MemoryEnemyFleetNameStore();
      final controller = BattleController(
        gameState: () => state,
        predictionExecutor: const ImmediateBattlePredictionExecutor(),
        enemyFleetNames: await EnemyFleetNameMemory.load(store),
      );
      addTearDown(controller.dispose);
      Future<void> send(CapturedApiEvent event) async {
        state = reducer.reduce(state, event);
        controller.accept(event);
        await controller.idle;
      }

      await send(mapStartEvent);
      expect(controller.current!.enemyFleetNameGuess, isEmpty);
      await send(dayBattleEvent);
      expect(controller.current!.enemyFleetNameGuess, isEmpty);
      await send(battleResultEvent);
      expect(controller.current!.enemyFleetName, 'Test Enemy Fleet');
      await controller.enemyFleetNames!.idle;
      expect(store.json, contains('Test Enemy Fleet'));

      await send(_resequenced(mapStartEvent, 30));
      expect(controller.current!.enemyFleetNameGuess, 'Test Enemy Fleet');
      await send(_resequenced(dayBattleEvent, 31));
      expect(controller.current!.enemyFleetName, isEmpty);
      expect(controller.current!.enemyFleetNameGuess, 'Test Enemy Fleet');
    });
  });
}

CapturedApiEvent _resequenced(CapturedApiEvent event, int sequence) =>
    CapturedApiEvent(
      path: event.path,
      responseBody: event.responseBody,
      source: event.source,
      sourceOrigin: event.sourceOrigin,
      capturedAt: event.capturedAt,
      requestParams: event.requestParams,
      sequence: sequence,
    );
