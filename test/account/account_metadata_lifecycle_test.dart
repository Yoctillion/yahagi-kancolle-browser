import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/src/account/account_session.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/formation_memory.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_reducer.dart';
import 'package:yahagi_kancolle_browser/src/new_ship/new_ship_reminder_controller.dart';
import 'package:yahagi_kancolle_browser/src/new_ship/new_ship_reminder_store.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_controller.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_state.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_store.dart';
import '../fixtures/kcsapi_fixtures.dart';

final _time = DateTime.utc(2026, 9, 10);
final _basic = kcsapiEvent(
  '/kcsapi/api_get_member/basic',
  {'api_member_id': 1001, 'api_nickname': 'updated name'},
  capturedAt: _time,
  sequence: 902,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'same-account metadata preserves a pending Senka event and slow save',
    () async {
      final session = AccountSession(initialMemberId: 1001);
      final store = _SlowSenkaStore();
      final controller = SenkaController(
        store: store,
        accountSession: session,
        now: () => _time,
      );
      addTearDown(controller.dispose);
      addTearDown(session.dispose);
      await controller.initialize();
      expect(controller.state.monthExperienceSenka, 30);
      store.saveGate = Completer<void>();
      controller.setTargetSenka(200);
      await store.saveStarted.future;
      controller.accept(
        kcsapiEvent(
          '/kcsapi/api_req_map/start',
          {'api_maparea_id': 1, 'api_mapinfo_no': 1, 'api_no': 1},
          capturedAt: _time,
          sequence: 901,
        ),
      );
      final scope = session.current;
      session.accept(_basic);
      controller.accept(_basic);
      expect(session.current, same(scope));
      expect(session.admiralName, 'updated name');
      store.saveGate!.complete();
      await controller.idle;
      expect(controller.state.targetSenka, 200);
      expect(controller.state.monthExperienceSenka, 30);
      expect(store.saved.targetSenka, 200);
      expect(store.saved.monthExperienceSenka, 30);
      expect(store.loads, 1);
    },
  );

  test(
    'same-account metadata leaves the initial slow Senka restore valid',
    () async {
      final session = AccountSession(initialMemberId: 1001);
      final store = _SlowSenkaStore()..loadGate = Completer<void>();
      final controller = SenkaController(
        store: store,
        accountSession: session,
        now: () => _time,
      );
      addTearDown(controller.dispose);
      addTearDown(session.dispose);
      final initializing = controller.initialize();
      await store.loadStarted.future;
      session.accept(_basic);
      store.loadGate!.complete();
      await initializing;
      await controller.idle;
      expect(controller.state.targetSenka, 100);
      expect(store.loads, 1);
      session.reset();
      expect(controller.state.memberId, 0);
      session.selectMember(1001);
      await controller.idle;
      expect(controller.state.targetSenka, 100);
      expect(store.loads, 2);
    },
  );

  test(
    'battle metadata preserves active session until port archives it',
    () async {
      final reducer = GameStateReducer();
      final state = reducer
          .reduce(reducer.reduce(GameState.empty, start2Event), portEvent)
          .copyWith(memberId: 1001);
      final session = AccountSession(initialMemberId: 1001);
      final battle = BattleController(
        gameState: () => state,
        accountSession: session,
      );
      addTearDown(battle.dispose);
      addTearDown(session.dispose);
      battle
        ..accept(mapStartEvent)
        ..accept(dayBattleEvent)
        ..accept(battleResultEvent);
      await battle.idle;
      final active = battle.session;
      expect(active, isNotNull);
      session.accept(_basic);
      expect(battle.session, same(active));
      final port = kcsapiEvent('/kcsapi/api_port/port', {
        'api_basic': {'api_member_id': 1001},
      }, sequence: 903);
      session.accept(port);
      battle.accept(port);
      await battle.idle;
      expect(battle.session, isNull);
      expect(battle.recentSessions, contains(active));
      battle.accept(
        kcsapiEvent('/kcsapi/api_req_map/start', {
          'api_maparea_id': 1,
          'api_mapinfo_no': 1,
          'api_no': 1,
        }, sequence: 904),
      );
      await battle.idle;
      session.reset();
      session.selectMember(1001);
      expect(battle.current, isNull);
      expect(battle.session, isNull);
    },
  );

  test(
    'formation metadata does not clear loaded or freshly remembered values',
    () async {
      final session = AccountSession(initialMemberId: 1001);
      final store = MemoryFormationMemoryStore();
      await store.forAccount(1001).save({'1-1-3': 5});
      final controller = await FormationMemoryController.load(
        store,
        accountSession: session,
      );
      addTearDown(controller.dispose);
      addTearDown(session.dispose);
      int? value() =>
          controller.formationFor(mapAreaId: 1, mapInfoNo: 1, node: 3);
      expect(value(), 5);
      final save = controller.remember(
        mapAreaId: 1,
        mapInfoNo: 1,
        node: 3,
        formation: 2,
      );
      session.accept(_basic);
      expect(value(), 2);
      await save;
      await controller.idle;
      session.reset();
      expect(value(), isNull);
      session.selectMember(1001);
      await controller.idle;
      expect(value(), 2);
    },
  );

  test(
    'new ship pending load survives metadata and keeps event deduplication',
    () async {
      final session = AccountSession(initialMemberId: 1001);
      final store = _SlowNewShipStore(await SharedPreferences.getInstance());
      final state = GameState(
        memberId: 1001,
        hasMasterData: true,
        hasPortData: true,
        masterShips: const {
          4: MasterShip(id: 4, name: 'test ship', shipTypeId: 2, sortNo: 4),
        },
      );
      final published = <NewShipAlert>[];
      final controller = NewShipReminderController(
        accountSession: session,
        stateProvider: () => state,
        store: store,
        onPublish: published.add,
      );
      addTearDown(controller.dispose);
      addTearDown(session.dispose);
      final construction = kcsapiEvent('/kcsapi/api_req_kousyou/getship', {
        'api_ship': {'api_id': 401, 'api_ship_id': 4, 'api_locked': 0},
      }, sequence: 905);
      controller.accept(construction);
      await store.started.future;
      session.accept(_basic);
      controller.accept(_basic);
      store.release.complete();
      await controller.idle;
      expect(published, hasLength(1));
      final alert = controller.currentAlert;
      session.accept(_basic);
      expect(controller.currentAlert, same(alert));
      controller.accept(construction);
      await controller.idle;
      expect(published, hasLength(1));
      expect(store.loads, 1);
      session.reset();
      session.selectMember(1001);
      expect(controller.currentAlert, isNull);
      controller.accept(construction);
      await controller.idle;
      expect(published, hasLength(2));
    },
  );

  test('game state metadata does not clear the last processed event', () async {
    final session = AccountSession(initialMemberId: 1001);
    final controller = GameStateController(
      initialState: const GameState(memberId: 1001),
      accountSession: session,
    );
    addTearDown(controller.dispose);
    addTearDown(session.dispose);
    await controller.initialize();
    controller.accept(_basic);
    await controller.idle;
    expect(controller.lastUpdatedPath, _basic.path);
    session.accept(_basic);
    expect(controller.lastUpdatedPath, _basic.path);
    session.reset();
    expect(controller.lastUpdatedPath, isNull);
  });
}

class _SlowSenkaStore implements AccountSenkaStore {
  SenkaState saved = SenkaState.forMonth('2026-09').copyWith(
    memberId: 1001,
    targetSenka: 100,
    days: const {'2026-09-10': SenkaDayRecord(experience: 30)},
  );
  Completer<void>? saveGate;
  Completer<void>? loadGate;
  final saveStarted = Completer<void>();
  final loadStarted = Completer<void>();
  int loads = 0;
  @override
  Future<SenkaState?> load() => loadForAccount(1001);
  @override
  Future<SenkaState?> loadForAccount(int memberId) async {
    loads++;
    if (!loadStarted.isCompleted) loadStarted.complete();
    await loadGate?.future;
    return saved;
  }

  @override
  Future<void> save(SenkaState value) async {
    if (!saveStarted.isCompleted) saveStarted.complete();
    await saveGate?.future;
    saved = value;
  }
}

class _SlowNewShipStore extends NewShipReminderStore {
  _SlowNewShipStore(super.preferences);
  final started = Completer<void>();
  final release = Completer<void>();
  int loads = 0;
  @override
  Future<Set<int>> loadExcludedFamilyIds(int memberId) async {
    loads++;
    if (!started.isCompleted) started.complete();
    await release.future;
    return super.loadExcludedFamilyIds(memberId);
  }
}
