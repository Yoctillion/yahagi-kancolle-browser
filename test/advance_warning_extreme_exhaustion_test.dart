import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/account/account_session.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_damage_alert.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_models.dart';
import 'package:yahagi_kancolle_browser/src/battle/prediction/battle_prediction_executor.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/capture/advance_warning_details.dart';
import 'package:yahagi_kancolle_browser/src/capture/battle_result_warning_overlay.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_controller.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_port.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_api_event_pipeline.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_completion_drawer.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_store.dart';

void main() {
  for (final timing in AdvanceWarningTimingSettings.values) {
    _exhaustionCases(timing);
  }
}

void _exhaustionCases(AdvanceWarningTimingSettings timing) {
  for (final combined in <bool>[false, true]) {
    for (final display in AdvanceWarningDisplayMode.values) {
      for (var layout = 0; layout < 4; layout++) {
        testWidgets(
          'all wing ships exhaust interleaved controls and warn again timing=$timing combined=$combined display=$display layout=$layout',
          (tester) async {
            final fixture = await _ExhaustionFixture.mount(
              tester,
              combined: combined,
              timing: timing,
              display: display,
              layout: layout,
            );
            addTearDown(() => fixture.dispose(tester));
            final originalShips = fixture.shipSnapshot(healthy: true);
            final originalItems = fixture.itemSnapshot();

            await fixture.navigate(tester, start: true);
            fixture.expectOracle('initial inventory');
            if (timing.afterAdvance) {
              await fixture.expectEquippedDisplay(tester);
            } else {
              fixture.expectNoPresentation();
            }

            final firstBattle = await fixture.consume(tester, rounds: 1);
            fixture.expectOracle('one control per wing ship');
            expect(
              fixture.targets.map((ship) => ship.remaining.length),
              everyElement(2),
            );
            await fixture.result(tester);
            await fixture.navigate(tester);
            if (timing.afterAdvance ||
                (timing.postBattle &&
                    display == AdvanceWarningDisplayMode.smart)) {
              await fixture.expectEquippedDisplay(tester);
            } else {
              fixture.expectNoPresentation();
            }

            final finalBattle = await fixture.consume(tester, rounds: 2);
            fixture.expectOracle('every final control used in one battle');
            expect(
              fixture.targets.map((ship) => ship.remaining),
              everyElement(isEmpty),
            );
            expect(
              fixture.targets.map((ship) => ship.spent.length),
              everyElement(3),
            );
            await fixture.result(tester);
            await fixture.navigate(tester);
            if (timing.afterAdvance) {
              fixture.expectExhaustedDisplay();
              await fixture.acknowledge(tester);
            } else {
              fixture.expectNoPresentation();
            }

            await fixture.damageAgain(tester);
            fixture.expectOracle('all depleted wing ships damaged again');
            await fixture.result(
              tester,
              acknowledgeWarning: timing.afterAdvance,
            );
            final resultRoute = timing.afterAdvance
                ? null
                : ModalRoute.of(tester.element(find.byType(AlertDialog)));
            await fixture.navigate(tester);
            fixture.expectExhaustedDisplay();
            if (!timing.afterAdvance) {
              expect(
                ModalRoute.of(tester.element(find.byType(AlertDialog))),
                same(resultRoute),
              );
            }

            for (var sweep = 0; sweep < 4; sweep++) {
              final snapshots = <(String, Object?)>[
                ('/kcsapi/api_get_member/ship_deck', originalShips),
                ('/kcsapi/api_get_member/slot_item', originalItems),
              ];
              for (final snapshot
                  in (layout + sweep).isEven ? snapshots : snapshots.reversed) {
                await fixture.publish(tester, snapshot.$1, snapshot.$2);
                fixture.expectOracle('late healthy snapshot $sweep');
                fixture.expectExhaustedDisplay();
              }
            }

            final acceptedBeforeReplay = fixture.accepted.length;
            for (final obsolete in <CapturedApiEvent>[
              finalBattle,
              fixture.packet(
                '/kcsapi/api_get_member/ship_deck',
                originalShips,
                sequence: 11,
              ),
              firstBattle,
              fixture.packet(
                '/kcsapi/api_get_member/slot_item',
                originalItems,
                sequence: 12,
              ),
              finalBattle,
            ]) {
              fixture.port.add(obsolete);
              await fixture.settle(tester);
              fixture.expectOracle('rejected obsolete packet');
              fixture.expectExhaustedDisplay();
            }
            expect(fixture.accepted, hasLength(acceptedBeforeReplay));

            await fixture.acknowledge(tester);
            final alertsBeforeRepeat = fixture.alerts.severities.length;
            await fixture.navigate(tester);
            if (timing.afterAdvance) {
              fixture.expectExhaustedDisplay();
            } else {
              fixture.expectNoPresentation();
            }
            expect(
              fixture.alerts.severities,
              hasLength(alertsBeforeRepeat + (timing.afterAdvance ? 1 : 0)),
            );
            expect(fixture.safetyLoads, timing.postBattle ? 8 : 5);
            expect(fixture.battlePackets, 3);
            expect(
              fixture.targets.fold<int>(
                0,
                (total, ship) => total + ship.spent.length,
              ),
              fixture.targets.length * 3,
            );
            if (!timing.afterAdvance) {
              await fixture.damageAgain(tester);
              fixture.expectOracle('depleted ships warn at the next result');
              await fixture.result(tester, acknowledgeWarning: false);
              fixture.expectExhaustedDisplay();
            }
            await tester.tap(find.byKey(const Key('muteCurrentSortieWarning')));
            await tester.pumpAndSettle();
            fixture.expectMutedDisplay();
            final alertsBeforeMutedStages = fixture.alerts.severities.length;
            await fixture.damageAgain(tester);
            fixture.expectOracle('muted sortie still writes damage');
            await fixture.result(tester, muted: true);
            await fixture.navigate(tester);
            fixture.expectMutedDisplay();
            expect(
              fixture.alerts.severities,
              hasLength(alertsBeforeMutedStages),
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}

final class _ExhaustionShip {
  _ExhaustionShip({
    required this.id,
    required this.maxHp,
    required this.slots,
    required this.extra,
    required this.items,
    required List<int> controls,
    this.flagship = false,
  }) : remaining = List<int>.from(controls),
       hp = flagship ? maxHp : maxHp ~/ 5;

  final int id;
  final int maxHp;
  final List<int> slots;
  final int extra;
  final Map<int, int> items;
  final bool flagship;
  final List<int> remaining;
  final List<int> spent = <int>[];
  int hp;

  List<int> get currentSlots => <int>[
    for (final instance in slots) spent.contains(instance) ? -1 : instance,
  ];

  int get currentExtra => spent.contains(extra) ? -1 : extra;

  void consumeNext() {
    final instance = remaining.removeAt(0);
    spent.add(instance);
    hp = items[instance] == 42 ? maxHp ~/ 5 : maxHp;
  }
}

List<_ExhaustionShip> _fleetShips(bool combined, int layout) {
  final count = combined ? 12 : (layout.isEven ? 6 : 7);
  const typeOrders = <List<int>>[
    <int>[42, 43, 42],
    <int>[43, 42, 43],
    <int>[42, 42, 43],
    <int>[43, 43, 42],
  ];
  return <_ExhaustionShip>[
    for (var position = 0; position < count; position++)
      if (position == 0 || (combined && position == 6))
        _ExhaustionShip(
          id: 7000 + position,
          maxHp: 137,
          slots: const <int>[],
          extra: -1,
          items: const <int, int>{},
          controls: const <int>[],
          flagship: true,
        )
      else
        _wingShip(
          7000 + position,
          <int>[30, 37, 81, 101, 137][(position + layout) % 5],
          typeOrders[(position + layout) % typeOrders.length],
          layout,
        ),
  ];
}

_ExhaustionShip _wingShip(int shipId, int maxHp, List<int> types, int layout) {
  final first = shipId * 10 + 1;
  final second = shipId * 10 + 2;
  final inert = shipId * 10 + 3;
  final extra = shipId * 10 + 4;
  final slots = <List<int>>[
    <int>[inert, -1, first, second],
    <int>[first, inert, -1, second],
    <int>[-1, first, second, inert],
    <int>[first, second, inert, -1],
  ][layout];
  return _ExhaustionShip(
    id: shipId,
    maxHp: maxHp,
    slots: slots,
    extra: extra,
    items: <int, int>{
      first: types[0],
      second: types[1],
      inert: 1,
      extra: types[2],
    },
    controls: <int>[first, second, extra],
  );
}

final class _ExhaustionFixture {
  _ExhaustionFixture({
    required this.combined,
    required this.timing,
    required this.display,
    required this.layout,
  }) : ships = _fleetShips(combined, layout);

  final bool combined;
  final AdvanceWarningTimingSettings timing;
  final AdvanceWarningDisplayMode display;
  final int layout;
  final List<_ExhaustionShip> ships;
  final account = AccountSession(initialMemberId: 1001);
  final port = _ExhaustionCapturePort();
  final alerts = _ExhaustionAlertPort();
  final accepted = <CapturedApiEvent>[];
  late final GameStateController state;
  late final BattleController battle;
  late final GameApiEventPipeline pipeline;
  late final GameCaptureController capture;
  late final SafetySettingsController settings;
  var sequence = 40;
  var node = 0;
  var battlePackets = 0;
  var safetyLoads = 0;

  int get fleetId => !combined && layout.isOdd ? 3 : 1;

  List<_ExhaustionShip> get targets =>
      ships.where((ship) => !ship.flagship).toList();

  static Future<_ExhaustionFixture> mount(
    WidgetTester tester, {
    required bool combined,
    required AdvanceWarningTimingSettings timing,
    required AdvanceWarningDisplayMode display,
    required int layout,
  }) async {
    final fixture = _ExhaustionFixture(
      combined: combined,
      timing: timing,
      display: display,
      layout: layout,
    );
    fixture.state = GameStateController(
      accountSession: fixture.account,
      initialState: fixture.initialState(),
    );
    await fixture.state.initialize();
    fixture.settings = await SafetySettingsController.load(
      MemorySafetySettingsStore(),
    );
    await fixture.settings.setAdvanceWarningDisplayMode(display);
    await fixture.settings.setAdvanceWarningTimings(timing);
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
    fixture.capture = GameCaptureController(
      onAcceptedEvent: (event) {
        fixture.accepted.add(event);
        fixture.pipeline.add(event);
      },
      onCaptureInterrupted: () {
        fixture.pipeline.invalidateQueuedEvents();
        fixture.battle.invalidateCaptureContinuity();
      },
    );
    await fixture.capture.attach(fixture.port, enabled: true);
    await tester.pumpWidget(
      MaterialApp(
        home: QuestCompletionDrawerHost(
          child: Column(
            children: <Widget>[
              const SizedBox(
                height: 44,
                child: QuestCompletionHeaderSlot(child: SizedBox.expand()),
              ),
              Expanded(
                child: BattleResultWarningOverlay(
                  accountSession: fixture.account,
                  gameCaptureController: fixture.capture,
                  warningSession: fixture.battle.warningSession,
                  damageControlStateTrusted: () =>
                      fixture.battle.isDamageControlStateTrusted,
                  loadSafetyState: () async {
                    fixture.safetyLoads++;
                    await fixture.pipeline.dispatchIdle;
                    await fixture.battle.idle;
                    await fixture.state.idle;
                    return fixture.state.state;
                  },
                  safetyEventAccepted: (event, state) {
                    if (!fixture.pipeline.wasEventAccepted(event)) return false;
                    if (!isPostBattleSafetyEvent(event)) return true;
                    final currentBattle = fixture.battle.current;
                    final combat = state.combatState;
                    return currentBattle != null &&
                        fixture.battle.lastError == null &&
                        currentBattle.displayStage ==
                            BattleDisplayStage.result &&
                        !currentBattle.context.practice &&
                        combat.isActive &&
                        currentBattle.context.deckId == combat.sortieFleetId &&
                        currentBattle.context.mapAreaId == combat.mapArea &&
                        currentBattle.context.mapInfoNo == combat.mapInfo &&
                        currentBattle.context.node == combat.currentNode;
                  },
                  safetySettingsController: fixture.settings,
                  damageAlertPort: fixture.alerts,
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return fixture;
  }

  GameState initialState() => GameState(
    memberId: 1001,
    hasPortData: true,
    hasEquipmentInventory: true,
    combinedFleetType: combined
        ? CombinedFleetType.carrierTaskForce
        : CombinedFleetType.none,
    ships: <int, OwnedShip>{
      for (final ship in ships)
        ship.id: OwnedShip(
          id: ship.id,
          masterId: ship.id,
          level: 99,
          currentHp: ship.hp,
          maxHp: ship.maxHp,
          slotIds: ship.slots,
          extraSlotId: ship.extra,
        ),
    },
    slotItems: <int, OwnedSlotItem>{
      for (final ship in ships)
        for (final item in ship.items.entries)
          item.key: OwnedSlotItem(
            instanceId: item.key,
            masterSlotItemId: item.value,
          ),
    },
    fleets: <Fleet>[
      Fleet(
        id: fleetId,
        name: 'Exhaustion main',
        shipIds: (combined ? ships.take(6) : ships)
            .map((ship) => ship.id)
            .toList(),
        slotCount: combined ? 6 : ships.length,
      ),
      if (combined)
        Fleet(
          id: 2,
          name: 'Exhaustion escort',
          shipIds: ships.skip(6).map((ship) => ship.id).toList(),
        ),
    ],
  );

  Future<void> navigate(WidgetTester tester, {bool start = false}) async {
    final alertsBefore = alerts.severities.length;
    await publish(
      tester,
      start ? '/kcsapi/api_req_map/start' : '/kcsapi/api_req_map/next',
      <String, Object?>{
        'api_maparea_id': 1,
        'api_mapinfo_no': 1,
        'api_no': ++node,
      },
      requestParams: <String, Object?>{'api_deck_id': '$fleetId'},
    );
    if (!timing.afterAdvance) {
      expect(alerts.severities, hasLength(alertsBefore));
    }
  }

  Future<void> result(
    WidgetTester tester, {
    bool muted = false,
    bool acknowledgeWarning = true,
  }) async {
    final alertsBefore = alerts.severities.length;
    await publish(
      tester,
      combined
          ? '/kcsapi/api_req_combined_battle/battleresult'
          : '/kcsapi/api_req_sortie/battleresult',
      <String, Object?>{'api_win_rank': 'A', 'api_mvp': 1},
    );
    expect(battle.current!.displayStage, BattleDisplayStage.result);
    expectOracle('battle result preserves HP and consumed controls');
    if (!timing.postBattle) {
      expect(alerts.severities, hasLength(alertsBefore));
    } else if (muted) {
      expectMutedDisplay();
      expect(alerts.severities, hasLength(alertsBefore));
    } else {
      expect(alerts.severities, hasLength(alertsBefore + 1));
      if (targets.every((ship) => ship.remaining.isEmpty)) {
        expectExhaustedDisplay();
        if (acknowledgeWarning) await acknowledge(tester);
      } else {
        await expectEquippedDisplay(tester);
      }
    }
  }

  List<int> attackOrder(int round) {
    final positions = <int>[
      if (combined)
        for (var position = 1; position < 6; position++) ...<int>[
          position,
          position + 6,
        ]
      else
        for (var position = 1; position < ships.length; position++) position,
    ];
    final offset = (layout + round) % positions.length;
    final rotated = <int>[...positions.skip(offset), ...positions.take(offset)];
    return round.isEven ? rotated : rotated.reversed.toList();
  }

  Future<CapturedApiEvent> consume(
    WidgetTester tester, {
    required int rounds,
  }) async {
    final openingHp = ships.map((ship) => ship.hp).toList();
    final strikes = <(int, int)>[];
    for (var round = 0; round < rounds; round++) {
      for (final position in attackOrder(round)) {
        final ship = ships[position];
        strikes.add((position, ship.hp));
        ship.consumeNext();
        final recoveryDamage = ship.hp - ship.maxHp ~/ 5;
        if (recoveryDamage > 0) {
          strikes.add((position, recoveryDamage));
          ship.hp -= recoveryDamage;
        }
      }
    }
    return publishBattle(tester, openingHp, strikes);
  }

  Future<void> damageAgain(WidgetTester tester) async {
    final openingHp = ships.map((ship) => ship.hp).toList();
    final strikes = <(int, int)>[];
    for (final position in attackOrder(3)) {
      strikes.add((position, 1));
      ships[position].hp--;
    }
    await publishBattle(tester, openingHp, strikes);
  }

  Future<CapturedApiEvent> publishBattle(
    WidgetTester tester,
    List<int> openingHp,
    List<(int, int)> strikes,
  ) {
    battlePackets++;
    return publish(
      tester,
      combined
          ? '/kcsapi/api_req_combined_battle/battle'
          : '/kcsapi/api_req_sortie/battle',
      <String, Object?>{
        'api_deck_id': fleetId,
        'api_f_nowhps': <int>[-1, ...combined ? openingHp.take(6) : openingHp],
        'api_f_maxhps': <int>[
          -1,
          ...(combined ? ships.take(6) : ships).map((ship) => ship.maxHp),
        ],
        if (combined) 'api_f_nowhps_combined': <int>[-1, ...openingHp.skip(6)],
        if (combined)
          'api_f_maxhps_combined': <int>[
            -1,
            ...ships.skip(6).map((ship) => ship.maxHp),
          ],
        'api_e_nowhps': <int>[-1, 20],
        'api_e_maxhps': <int>[-1, 20],
        'api_ship_ke': <int>[-1, 501],
        'api_hougeki1': <String, Object?>{
          'api_at_eflag': List<int>.filled(strikes.length, 1),
          'api_at_list': List<int>.filled(strikes.length, 0),
          'api_df_list': <Object?>[
            for (final strike in strikes) <int>[strike.$1],
          ],
          'api_damage': <Object?>[
            for (final strike in strikes) <int>[strike.$2],
          ],
        },
      },
    );
  }

  CapturedApiEvent packet(
    String path,
    Object? data, {
    required int sequence,
    Map<String, Object?> requestParams = const <String, Object?>{},
  }) => CapturedApiEvent(
    path: path,
    requestParams: requestParams,
    responseBody: jsonEncode(<String, Object?>{
      'api_result': 1,
      'api_data': data,
    }),
    source: CaptureSource.xhr,
    sourceOrigin: 'https://example.invalid',
    capturedAt: DateTime.utc(2026, 10, 23).add(Duration(seconds: sequence)),
    sequence: sequence,
    captureSessionId: 'exhaustion-capture',
    captureDocumentId: 'exhaustion-document',
    captureDocumentStartedAtEpochMs: 1000,
  );

  Future<CapturedApiEvent> publish(
    WidgetTester tester,
    String path,
    Object? data, {
    Map<String, Object?> requestParams = const <String, Object?>{},
  }) async {
    final event = packet(
      path,
      data,
      sequence: ++sequence,
      requestParams: requestParams,
    );
    final countBefore = accepted.length;
    port.add(event);
    expect(accepted, hasLength(countBefore + 1));
    await settle(tester);
    return event;
  }

  Future<void> settle(WidgetTester tester) async {
    await pipeline.idle;
    await tester.pumpAndSettle();
    expect(state.lastError, isNull);
    expect(battle.lastError, isNull);
  }

  Map<String, Object?> shipSnapshot({bool healthy = false}) =>
      <String, Object?>{
        'api_ship_data': <Object?>[
          for (final ship in ships)
            <String, Object?>{
              'api_id': ship.id,
              'api_ship_id': ship.id,
              'api_lv': 99,
              'api_nowhp': healthy ? ship.maxHp : ship.hp,
              'api_maxhp': ship.maxHp,
              'api_slot': List<int>.from(ship.currentSlots),
              'api_slot_ex': ship.currentExtra,
            },
        ],
      };

  List<Object?> itemSnapshot() => <Object?>[
    for (final ship in ships)
      for (final item in ship.items.entries)
        if (!ship.spent.contains(item.key))
          <String, Object?>{'api_id': item.key, 'api_slotitem_id': item.value},
  ];

  void expectOracle(String reason) {
    expect(battle.isDamageControlStateTrusted, isTrue, reason: reason);
    expect(
      state.state.slotItems.keys,
      unorderedEquals(<int>[
        for (final ship in ships)
          for (final instance in ship.items.keys)
            if (!ship.spent.contains(instance)) instance,
      ]),
      reason: reason,
    );
    for (final ship in ships) {
      final actual = state.state.ships[ship.id]!;
      expect(actual.currentHp, ship.hp, reason: '$reason ship ${ship.id}');
      expect(actual.slotIds, ship.currentSlots, reason: reason);
      expect(actual.extraSlotId, ship.currentExtra, reason: reason);
      for (final instance in ship.spent) {
        expect(state.state.slotItems.containsKey(instance), isFalse);
        for (final otherShip in state.state.ships.values) {
          expect(otherShip.slotIds, isNot(contains(instance)), reason: reason);
          expect(otherShip.extraSlotId, isNot(instance), reason: reason);
        }
      }
      final prediction = battle.current!.friendShips.singleWhere(
        (snapshot) => snapshot.ownedShipId == ship.id,
      );
      expect(prediction.currentHp, ship.hp, reason: reason);
      if (battle.current!.displayStage == BattleDisplayStage.battle) {
        expect(prediction.usedDamageControlItemIds, <int>[
          for (final instance in ship.spent) ship.items[instance]!,
        ], reason: reason);
      }
    }
    final warnings = collectAdvanceWarningShips(
      state.state,
      damageControlStateTrusted: battle.isDamageControlStateTrusted,
    );
    expect(
      warnings.map((warning) => warning.ship.id),
      unorderedEquals(targets.map((ship) => ship.id)),
      reason: reason,
    );
    for (final warning in warnings) {
      final expected = ships.firstWhere((ship) => ship.id == warning.ship.id);
      final counts = <int, int>{};
      for (final instance in expected.remaining) {
        counts.update(
          expected.items[instance]!,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
      expect(warning.remainingDamageControls, counts, reason: reason);
      expect(
        warning.damageControlStatus,
        counts.isEmpty
            ? AdvanceDamageControlStatus.missing
            : AdvanceDamageControlStatus.equipped,
        reason: reason,
      );
    }
  }

  Future<void> expectEquippedDisplay(WidgetTester tester) async {
    if (display == AdvanceWarningDisplayMode.smart) {
      expect(find.text('大破舰已携带损管'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    } else {
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('未携带损管'), findsNothing);
      for (final ship in targets) {
        expect(find.text('#${ship.id}'), findsOneWidget);
      }
      await acknowledge(tester);
    }
  }

  void expectExhaustedDisplay() {
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('大破舰已携带损管'), findsNothing);
    expect(find.text('存在未携带损管的大破舰娘！'), findsOneWidget);
    expect(find.text('未携带损管'), findsNWidgets(targets.length));
    expect(find.textContaining('携带：应急修理'), findsNothing);
    for (final ship in targets) {
      expect(find.text('#${ship.id}'), findsOneWidget);
    }
    expect(battle.warningSession.isMuted, isFalse);
    expect(battle.warningSession.isActive, isTrue);
  }

  void expectMutedDisplay() {
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('大破舰已携带损管'), findsNothing);
    expect(battle.warningSession.isMuted, isTrue);
    expect(battle.warningSession.isActive, isTrue);
  }

  void expectNoPresentation() {
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('大破舰已携带损管'), findsNothing);
    expect(battle.warningSession.isMuted, isFalse);
    expect(battle.warningSession.isActive, isTrue);
  }

  Future<void> acknowledge(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('acknowledgeAdvanceWarning')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(battle.warningSession.isMuted, isFalse);
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    capture.dispose();
    port.dispose();
    battle.dispose();
    state.dispose();
    settings.dispose();
    account.dispose();
  }
}

final class _ExhaustionAlertPort implements BattleDamageAlertPort {
  final severities = <BattleDamageAlertSeverity>[];

  @override
  Future<void> alert(BattleDamageAlertSeverity severity) async =>
      severities.add(severity);
}

final class _ExhaustionCapturePort implements GameCapturePort {
  final _events = StreamController<CapturedApiEvent>.broadcast(sync: true);

  @override
  Stream<CapturedApiEvent> get events => _events.stream;

  void add(CapturedApiEvent event) => _events.add(event);

  @override
  Future<void> configure({
    required bool enabled,
    required String script,
  }) async {}

  @override
  Future<bool> isSupported() async => true;

  @override
  void dispose() => unawaited(_events.close());
}
