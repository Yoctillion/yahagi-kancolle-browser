import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/account/account_session.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/prediction/battle_prediction_executor.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/capture/advance_warning_details.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_api_event_pipeline.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_progress_engine.dart';

enum _RevivalLocation { ordinary, extra, otherShip, inventoryOnly }

enum _IncompletePort {
  missingShips,
  invalidShips,
  missingBasic,
  missingDecks,
  nullPrimaryWithFallback,
  emptyDecks,
  emptyDeckShips,
  invalidMaxHp,
  unreferencedDeckShips,
}

void main() {
  for (final instanceId in <int>[501, 502]) {
    for (final location in _RevivalLocation.values) {
      for (final changesAccount in <bool>[false, true]) {
        test(
          'post-gap port cannot restore spent $instanceId in $location changesAccount=$changesAccount',
          () async {
            final fixture = await _InterruptionFixture.create();
            addTearDown(fixture.dispose);
            await fixture.resumeAfterGap();
            final beforeState = fixture.state.state;
            final beforeAccount = fixture.account.current;
            final warningGeneration = fixture.battle.warningSession.generation;

            await fixture.publish(
              '/kcsapi/api_port/port',
              _portData(
                memberId: changesAccount ? 72002 : 71001,
                revivedInstance: instanceId,
                location: location,
                inventoryInstances: <int>[instanceId, 701],
                healthy: true,
              ),
            );

            expect(fixture.account.current, same(beforeAccount));
            expect(fixture.state.state, same(beforeState));
            expect(fixture.battle.warningSession.generation, warningGeneration);
            fixture.expectSpent(trusted: false);
            await fixture.next();
            fixture.expectSpent(trusted: false);
          },
        );
      }
    }
  }

  for (final incomplete in _IncompletePort.values) {
    test('post-gap $incomplete port cannot end the sortie', () async {
      final fixture = await _InterruptionFixture.create();
      addTearDown(fixture.dispose);
      await fixture.resumeAfterGap();
      final beforeState = fixture.state.state;
      final beforeAccount = fixture.account.current;
      final payload = _portData(healthy: true);
      switch (incomplete) {
        case _IncompletePort.missingShips:
          payload.remove('api_ship');
        case _IncompletePort.invalidShips:
          payload['api_ship'] = <String, Object?>{};
        case _IncompletePort.missingBasic:
          payload.remove('api_basic');
        case _IncompletePort.missingDecks:
          payload.remove('api_deck_port');
        case _IncompletePort.nullPrimaryWithFallback:
          payload['api_deck'] = payload['api_deck_port'];
          payload['api_deck_port'] = null;
        case _IncompletePort.emptyDecks:
          payload['api_deck_port'] = <Object?>[];
        case _IncompletePort.emptyDeckShips:
          for (final deck in payload['api_deck_port']! as List<Object?>) {
            (deck! as Map<String, Object?>)['api_ship'] = <int>[-1, -1];
          }
        case _IncompletePort.invalidMaxHp:
          final ships = payload['api_ship']! as List<Object?>;
          (ships[1]! as Map<String, Object?>)['api_nowhp'] = 0;
          (ships[1]! as Map<String, Object?>)['api_maxhp'] = 0;
        case _IncompletePort.unreferencedDeckShips:
          payload['api_deck_port'] = <Object?>[
            <String, Object?>{
              'api_id': 1,
              'api_name': 'Missing owned ships',
              'api_ship': <int>[99999],
            },
          ];
      }

      await fixture.publish('/kcsapi/api_port/port', payload);

      expect(fixture.account.current, same(beforeAccount));
      expect(fixture.state.state, same(beforeState));
      fixture.expectSpent(trusted: false);
      await fixture.next();
      fixture.expectSpent(trusted: false);
    });
  }

  test('post-gap same-document getData cannot reset the account', () async {
    final fixture = await _InterruptionFixture.create();
    addTearDown(fixture.dispose);
    await fixture.resumeAfterGap();
    final beforeState = fixture.state.state;
    final beforeAccount = fixture.account.current;

    await fixture.publish('/kcsapi/api_start2/getData', <String, Object?>{});

    expect(fixture.account.current, same(beforeAccount));
    expect(fixture.state.state, same(beforeState));
    fixture.expectSpent(trusted: false);
    await fixture.next();
    fixture.expectSpent(trusted: false);
  });

  test('post-gap different-member basic cannot erase spent evidence', () async {
    final fixture = await _InterruptionFixture.create();
    addTearDown(fixture.dispose);
    await fixture.resumeAfterGap();
    final beforeAccount = fixture.account.current;

    await fixture.publish('/kcsapi/api_get_member/basic', <String, Object?>{
      'api_member_id': 72002,
      'api_nickname': 'Retired account',
    });

    expect(fixture.account.current, same(beforeAccount));
    fixture.expectSpent(trusted: false);
    await fixture.publish(
      '/kcsapi/api_port/port',
      _portData(
        memberId: 72002,
        equipped: true,
        inventoryInstances: <int>[501, 502, 701],
      ),
    );

    expect(fixture.account.current, same(beforeAccount));
    fixture.expectSpent(trusted: false);
    await fixture.start();
    await fixture.publish(
      '/kcsapi/api_get_member/slot_item',
      _items(<int>[501, 502, 701]),
    );
    await fixture.publish('/kcsapi/api_get_member/ship_deck', <String, Object?>{
      'api_ship_data': _ships(equipped: true),
    });
    fixture.expectSpent(trusted: false);
  });

  for (final basic in <Map<String, Object?>>[
    <String, Object?>{'api_member_id': 72002},
    <String, Object?>{},
  ]) {
    test('post-gap require_info rejects invalid identity $basic', () async {
      final fixture = await _InterruptionFixture.create();
      addTearDown(fixture.dispose);
      await fixture.resumeAfterGap();
      final beforeState = fixture.state.state;
      final beforeAccount = fixture.account.current;

      await fixture.publish(
        '/kcsapi/api_get_member/require_info',
        <String, Object?>{
          'api_basic': basic,
          'api_slot_item': _items(<int>[501, 502, 701]),
        },
      );

      expect(fixture.account.current, same(beforeAccount));
      expect(fixture.state.state, same(beforeState));
      fixture.expectSpent(trusted: false);
      await fixture.start();
      await fixture.publish(
        '/kcsapi/api_get_member/ship_deck',
        <String, Object?>{'api_ship_data': _ships(equipped: true)},
      );
      fixture.expectSpent(trusted: false);
    });
  }

  test(
    'post-gap fleet 2 start retains spent instances across snapshots',
    () async {
      final fixture = await _InterruptionFixture.create();
      addTearDown(fixture.dispose);
      await fixture.resumeAfterGap();

      await fixture.start(fleetId: 2);

      fixture.expectSpent(trusted: false, fleetId: 2);
      for (final instanceId in <int>[501, 502]) {
        await fixture
            .publish('/kcsapi/api_get_member/ship_deck', <String, Object?>{
              'api_ship_data': _ships(
                revivedInstance: instanceId,
                location: _RevivalLocation.otherShip,
                healthy: true,
              ),
            });
        await fixture.publish(
          '/kcsapi/api_get_member/slot_item',
          _items(<int>[501, 502, 701]),
        );
        fixture.expectSpent(trusted: false, fleetId: 2);
      }
      await fixture.next(fleetId: 2);
      fixture.expectSpent(trusted: false, fleetId: 2);
    },
  );

  test(
    'post-gap clean full port permits returning and starting again',
    () async {
      final fixture = await _InterruptionFixture.create();
      addTearDown(fixture.dispose);
      await fixture.resumeAfterGap();

      await fixture.publish('/kcsapi/api_port/port', _portData(healthy: true));

      expect(fixture.account.current.memberId, 71001);
      expect(fixture.state.state.combatState.isActive, isFalse);
      expect(fixture.state.state.ships[102]!.currentHp, 100);
      expect(fixture.state.state.slotItems.keys, <int>[701]);
      expect(fixture.battle.warningSession.isActive, isFalse);
      expect(fixture.warnings, isEmpty);

      await fixture.start();

      expect(fixture.state.state.combatState.isActive, isTrue);
      expect(fixture.battle.isDamageControlStateTrusted, isTrue);
      expect(fixture.battle.warningSession.isActive, isTrue);
      expect(fixture.warnings, isEmpty);
    },
  );

  test('new-document login can reuse instance IDs for a new member', () async {
    final fixture = await _InterruptionFixture.create();
    addTearDown(fixture.dispose);
    await fixture.resumeAfterGap();
    fixture.documentId = 'interruption-document-b';
    fixture.documentStartedAt = 2000;

    await fixture.publish('/kcsapi/api_start2/getData', <String, Object?>{});

    expect(fixture.account.current.isKnown, isFalse);
    await fixture.publish(
      '/kcsapi/api_port/port',
      _portData(
        memberId: 72002,
        equipped: true,
        inventoryInstances: <int>[501, 502, 701],
      ),
    );

    expect(fixture.account.current.memberId, 72002);
    expect(fixture.state.state.memberId, 72002);
    expect(fixture.state.state.combatState.isActive, isFalse);
    expect(
      fixture.state.state.slotItems.keys,
      unorderedEquals(<int>[501, 502, 701]),
    );
    expect(fixture.state.state.ships[102]!.slotIds, <int>[501]);
    expect(fixture.state.state.ships[102]!.extraSlotId, 502);

    await fixture.start();

    expect(fixture.battle.isDamageControlStateTrusted, isTrue);
    expect(fixture.warnings.single.ship.id, 102);
    expect(
      fixture.warnings.single.damageControlStatus,
      AdvanceDamageControlStatus.equipped,
    );
    expect(fixture.warnings.single.remainingDamageControls, <int, int>{
      42: 1,
      43: 1,
    });
  });

  test(
    'same-document capture session change cannot restore spent IDs',
    () async {
      final fixture = await _InterruptionFixture.create();
      addTearDown(fixture.dispose);
      await fixture.resumeAfterGap();
      fixture.captureSessionId = 'interruption-guard-reconnected';
      fixture.sequence = 0;

      await fixture.publish(
        '/kcsapi/api_port/port',
        _portData(equipped: true, inventoryInstances: <int>[501, 502, 701]),
      );
      await fixture.start(fleetId: 2);
      await fixture
          .publish('/kcsapi/api_get_member/ship_deck', <String, Object?>{
            'api_ship_data': _ships(
              revivedInstance: 501,
              location: _RevivalLocation.otherShip,
              healthy: true,
            ),
          });

      fixture.expectSpent(trusted: false, fleetId: 2);
    },
  );

  test(
    'post-gap clean real port need not contain equipment inventory',
    () async {
      final fixture = await _InterruptionFixture.create();
      addTearDown(fixture.dispose);
      await fixture.resumeAfterGap();
      final data = _portData(healthy: true)..remove('api_slot_item');

      await fixture.publish('/kcsapi/api_port/port', data);
      await fixture.start();

      expect(fixture.battle.isDamageControlStateTrusted, isTrue);
      expect(fixture.state.state.slotItems.keys, <int>[701]);
      expect(fixture.warnings, isEmpty);
    },
  );

  test(
    'without a gap verified port can change member with reused IDs',
    () async {
      final fixture = await _InterruptionFixture.create();
      addTearDown(fixture.dispose);

      await fixture.publish(
        '/kcsapi/api_port/port',
        _portData(
          memberId: 72002,
          equipped: true,
          inventoryInstances: <int>[501, 502, 701],
        ),
      );
      await fixture.start();

      expect(fixture.account.current.memberId, 72002);
      expect(fixture.state.state.memberId, 72002);
      expect(fixture.battle.isDamageControlStateTrusted, isTrue);
      expect(fixture.warnings.single.remainingDamageControls, <int, int>{
        42: 1,
        43: 1,
      });
    },
  );

  test('post-gap clean port supports an absent primary deck field', () async {
    final fixture = await _InterruptionFixture.create();
    addTearDown(fixture.dispose);
    await fixture.resumeAfterGap();
    final data = _portData(healthy: true);
    final ships = data['api_ship']! as List<Object?>;
    final damagedShip = ships.cast<Map<String, Object?>>().singleWhere(
      (ship) => ship['api_id'] == 102,
    );
    damagedShip['api_nowhp'] = 20;
    final decks = data.remove('api_deck_port')! as List<Object?>;
    (decks[0]! as Map<String, Object?>)['api_ship'] = <int>[101, 104];
    (decks[1]! as Map<String, Object?>)['api_ship'] = <int>[103, 102];
    data['api_deck'] = decks;

    await fixture.publish('/kcsapi/api_port/port', data);

    expect(
      fixture.state.state.fleets.singleWhere((fleet) => fleet.id == 1).shipIds,
      <int>[101, 104],
    );
    expect(
      fixture.state.state.fleets.singleWhere((fleet) => fleet.id == 2).shipIds,
      <int>[103, 102],
    );
    expect(fixture.state.state.ships[102]!.currentHp, 20);
    await fixture.start(fleetId: 2);

    expect(fixture.battle.isDamageControlStateTrusted, isTrue);
    expect(fixture.state.state.combatState.sortieFleetId, 2);
    expect(fixture.warnings, hasLength(1));
    expect(fixture.warnings.single.ship.id, 102);
    expect(fixture.warnings.single.fleetId, 2);
    expect(
      fixture.warnings.single.damageControlStatus,
      AdvanceDamageControlStatus.missing,
    );
    expect(fixture.warnings.single.hasConfirmedDamageControl, isFalse);
  });

  test('without a gap a full port remains authoritative', () async {
    final fixture = await _InterruptionFixture.create();
    addTearDown(fixture.dispose);

    await fixture.publish(
      '/kcsapi/api_port/port',
      _portData(equipped: true, inventoryInstances: <int>[501, 502, 701]),
    );

    expect(fixture.account.current.memberId, 71001);
    expect(fixture.state.state.combatState.isActive, isFalse);
    expect(fixture.state.state.ships[102]!.slotIds, <int>[501]);
    expect(fixture.state.state.ships[102]!.extraSlotId, 502);
    expect(
      fixture.state.state.slotItems.keys,
      unorderedEquals(<int>[501, 502, 701]),
    );
    expect(fixture.battle.warningSession.isActive, isFalse);

    await fixture.start();

    expect(fixture.battle.isDamageControlStateTrusted, isTrue);
    expect(
      fixture.warnings.single.damageControlStatus,
      AdvanceDamageControlStatus.equipped,
    );
  });

  test('gap invalidates a port already awaiting real quest storage', () async {
    final storage = _DelayedQuestStorage();
    final fixture = await _InterruptionFixture.create(storage: storage);
    addTearDown(fixture.dispose);
    fixture.questProgress!.resetSession();
    storage.holdNextRead();
    final beforeState = fixture.state.state;
    final beforeAccount = fixture.account.current;
    final pendingPort = fixture.publish(
      '/kcsapi/api_port/port',
      _portData(
        equipped: true,
        inventoryInstances: <int>[501, 502, 701],
        healthy: true,
      ),
    );
    await storage.readStarted.future.timeout(const Duration(seconds: 2));
    expect(fixture.pipeline.pendingEventCount, 1);
    expect(fixture.state.state, same(beforeState));

    fixture.interrupt();
    storage.release();
    await pendingPort;

    expect(fixture.account.current, same(beforeAccount));
    expect(fixture.state.state, same(beforeState));
    await fixture.next();
    fixture.expectSpent(trusted: false);
    await fixture.publish(
      '/kcsapi/api_get_member/slot_item',
      _items(<int>[501, 502, 701]),
    );
    await fixture.publish('/kcsapi/api_get_member/ship_deck', <String, Object?>{
      'api_ship_data': _ships(equipped: true, healthy: true),
    });
    fixture.expectSpent(trusted: false);
  });
}

final class _InterruptionFixture {
  _InterruptionFixture({this.storage});

  final _DelayedQuestStorage? storage;
  final account = AccountSession();
  late final GameStateController state;
  late final BattleController battle;
  late final GameApiEventPipeline pipeline;
  QuestProgressEngine? questProgress;
  var sequence = 0;
  var node = 1;
  var documentId = 'interruption-document-a';
  var captureSessionId = 'interruption-guard-session';
  double documentStartedAt = 1000;

  List<AdvanceWarningShip> get warnings => collectAdvanceWarningShips(
    state.state,
    damageControlStateTrusted: battle.isDamageControlStateTrusted,
  );

  static Future<_InterruptionFixture> create({
    _DelayedQuestStorage? storage,
  }) async {
    final fixture = _InterruptionFixture(storage: storage);
    if (storage != null) {
      fixture.questProgress = QuestProgressEngine(goals: {}, storage: storage);
    }
    fixture.state = GameStateController(
      accountSession: fixture.account,
      questProgress: fixture.questProgress,
    );
    await fixture.state.initialize();
    fixture.battle = BattleController(
      accountSession: fixture.account,
      gameState: () => fixture.state.state,
      waitForGameState: () => fixture.state.idle,
      onFriendlyHpUpdated: fixture.state.applyFriendlyBattleHp,
      onDamageControlConsumed: fixture.state.applyDamageControlConsumption,
      predictionExecutor: const ImmediateBattlePredictionExecutor(),
    );
    fixture.pipeline = GameApiEventPipeline(
      consumers: <GameApiEventConsumer>[
        fixture.account,
        fixture.state,
        fixture.battle,
      ],
      settleGameState: () async {
        await fixture.state.idle;
        await fixture.battle.idle;
        await fixture.state.idle;
      },
    );
    await fixture.publish('/kcsapi/api_start2/getData', <String, Object?>{});
    await fixture.publish(
      '/kcsapi/api_port/port',
      _portData(equipped: true, inventoryInstances: <int>[501, 502, 701]),
    );
    await fixture.start();
    await fixture.publish('/kcsapi/api_req_sortie/battle', <String, Object?>{
      'api_deck_id': 1,
      'api_f_nowhps': <int>[-1, 100, 20],
      'api_f_maxhps': <int>[-1, 100, 100],
      'api_e_nowhps': <int>[-1, 20],
      'api_e_maxhps': <int>[-1, 20],
      'api_ship_ke': <int>[-1, 501],
      'api_hougeki1': <String, Object?>{
        'api_at_eflag': <int>[1, 1, 1],
        'api_at_list': <int>[0, 0, 0],
        'api_df_list': <Object?>[
          <int>[1],
          <int>[1],
          <int>[1],
        ],
        'api_damage': <Object?>[
          <int>[20],
          <int>[20],
          <int>[80],
        ],
      },
    });
    expect(
      fixture.battle.current!.friendShips
          .singleWhere((ship) => ship.ownedShipId == 102)
          .usedDamageControlItemIds,
      <int>[42, 43],
    );
    fixture.expectSpent(trusted: true);
    return fixture;
  }

  void interrupt() {
    pipeline.invalidateQueuedEvents();
    battle.invalidateCaptureContinuity();
  }

  Future<void> resumeAfterGap() async {
    interrupt();
    await next();
    expectSpent(trusted: false);
  }

  Future<void> start({int fleetId = 1}) =>
      publish('/kcsapi/api_req_map/start', _node(node), fleetId: fleetId);

  Future<void> next({int fleetId = 1}) =>
      publish('/kcsapi/api_req_map/next', _node(++node), fleetId: fleetId);

  Future<void> publish(String path, Object? data, {int fleetId = 1}) async {
    final event = CapturedApiEvent(
      path: path,
      requestParams: <String, Object?>{'api_deck_id': '$fleetId'},
      responseBody: jsonEncode(<String, Object?>{
        'api_result': 1,
        'api_data': data,
      }),
      source: CaptureSource.xhr,
      sourceOrigin: 'https://w01y.kancolle-server.com',
      capturedAt: DateTime.utc(
        2026,
        10,
        23,
      ).add(Duration(milliseconds: ++sequence)),
      sequence: sequence,
      captureSessionId: captureSessionId,
      captureDocumentId: documentId,
      captureDocumentStartedAtEpochMs: documentStartedAt,
    );
    pipeline.add(event);
    await pipeline.idle;
    expect(state.lastError, isNull);
    expect(battle.lastError, isNull);
  }

  void expectSpent({required bool trusted, int fleetId = 1}) {
    expect(account.current.memberId, 71001);
    expect(state.state.memberId, 71001);
    expect(state.state.combatState.isActive, isTrue);
    expect(state.state.combatState.sortieFleetId, fleetId);
    expect(state.state.ships[fleetId == 1 ? 102 : 104]!.currentHp, 20);
    expect(state.state.slotItems.keys, <int>[701]);
    for (final ship in state.state.ships.values) {
      expect(ship.slotIds, isNot(contains(501)));
      expect(ship.slotIds, isNot(contains(502)));
      expect(ship.extraSlotId, isNot(501));
      expect(ship.extraSlotId, isNot(502));
    }
    expect(battle.isDamageControlStateTrusted, trusted);
    expect(battle.warningSession.isMuted, isFalse);
    expect(warnings.single.ship.id, fleetId == 1 ? 102 : 104);
    expect(
      warnings.single.damageControlStatus,
      trusted
          ? AdvanceDamageControlStatus.missing
          : AdvanceDamageControlStatus.unknown,
    );
    expect(warnings.single.hasConfirmedDamageControl, isFalse);
  }

  void dispose() {
    storage?.release();
    battle.dispose();
    state.dispose();
    account.dispose();
  }
}

Map<String, Object?> _node(int node) => <String, Object?>{
  'api_maparea_id': 1,
  'api_mapinfo_no': 1,
  'api_no': node,
};

Map<String, Object?> _portData({
  int memberId = 71001,
  bool equipped = false,
  bool healthy = false,
  int? revivedInstance,
  _RevivalLocation? location,
  List<int> inventoryInstances = const <int>[701],
}) => <String, Object?>{
  'api_basic': <String, Object?>{'api_member_id': memberId},
  'api_ship': _ships(
    equipped: equipped,
    healthy: healthy,
    revivedInstance: revivedInstance,
    location: location,
  ),
  'api_slot_item': _items(inventoryInstances),
  'api_combined_flag': 0,
  'api_deck_port': <Object?>[
    <String, Object?>{
      'api_id': 1,
      'api_name': 'Main',
      'api_ship': <int>[101, 102],
    },
    <String, Object?>{
      'api_id': 2,
      'api_name': 'Second',
      'api_ship': <int>[103, 104],
    },
  ],
};

List<Object?> _ships({
  bool equipped = false,
  bool healthy = false,
  int? revivedInstance,
  _RevivalLocation? location,
}) => <Object?>[
  for (final shipId in <int>[101, 102, 103, 104])
    <String, Object?>{
      'api_id': shipId,
      'api_ship_id': shipId,
      'api_lv': 50,
      'api_nowhp': !healthy && (shipId == 102 || shipId == 104) ? 20 : 100,
      'api_maxhp': 100,
      'api_slot': <int>[
        if (shipId == 102)
          equipped
              ? 501
              : location == _RevivalLocation.ordinary
              ? revivedInstance!
              : -1,
        if (shipId == 104) 701,
        if (shipId == 104 && location == _RevivalLocation.otherShip)
          revivedInstance!,
      ],
      'api_slot_ex': shipId == 102
          ? equipped
                ? 502
                : location == _RevivalLocation.extra
                ? revivedInstance!
                : -1
          : -1,
    },
];

List<Object?> _items(List<int> instanceIds) => <Object?>[
  for (final instanceId in instanceIds)
    <String, Object?>{
      'api_id': instanceId,
      'api_slotitem_id': <int, int>{501: 42, 502: 43, 701: 1}[instanceId]!,
    },
];

final class _DelayedQuestStorage implements QuestProgressStorage {
  final values = <int, String>{};
  Completer<void>? _readGate;
  var readStarted = Completer<void>();

  void holdNextRead() {
    _readGate = Completer<void>();
    readStarted = Completer<void>();
  }

  void release() {
    final gate = _readGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<String?> read(int account) async {
    final gate = _readGate;
    if (gate != null) {
      if (!readStarted.isCompleted) readStarted.complete();
      await gate.future;
      _readGate = null;
    }
    return values[account];
  }

  @override
  Future<void> write(int account, String value) async =>
      values[account] = value;
}
