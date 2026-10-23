import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/account/account_session.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_damage_alert.dart';
import 'package:yahagi_kancolle_browser/src/battle/prediction/battle_prediction_executor.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/capture/battle_result_warning_overlay.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_controller.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_port.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_api_event_pipeline.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_completion_drawer.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_store.dart';

enum _SnapshotOrder { shipsFirst, itemsFirst }

void main() {
  for (final combined in <bool>[false, true]) {
    for (final display in AdvanceWarningDisplayMode.values) {
      for (final order
          in display == AdvanceWarningDisplayMode.smart
              ? _SnapshotOrder.values
              : <_SnapshotOrder>[_SnapshotOrder.shipsFirst]) {
        testWidgets(
          'capture to warning consumes 42 then 43 and rejects healthy inventory resurrection combined=$combined display=$display order=$order',
          (tester) async {
            final fixture = await _EndToEndFixture.mount(
              tester,
              combined: combined,
              display: display,
            );
            addTearDown(() => fixture.dispose(tester));

            await fixture.start(tester);
            expect(fixture.battle.isDamageControlStateTrusted, isTrue);
            expect(fixture.target.slotIds, <int>[501]);
            expect(fixture.target.extraSlotId, 502);
            expect(fixture.retained.slotIds, <int>[601]);
            expect(fixture.retained.extraSlotId, 602);
            await fixture.expectEquippedDisplay(tester, bothShips: true);

            await fixture.fight(tester, openingHp: 20, damage: 20);
            expect(fixture.target.currentHp, 20);
            expect(fixture.target.slotIds, <int>[-1]);
            expect(fixture.target.extraSlotId, 502);
            expect(fixture.state.state.slotItems.containsKey(501), isFalse);
            expect(fixture.state.state.slotItems[502]?.masterSlotItemId, 43);
            expect(
              fixture.battle.current!.friendMain[1].usedDamageControlItemIds,
              <int>[42],
            );
            await fixture.advance(tester);
            await fixture.expectEquippedDisplay(tester, bothShips: true);

            await fixture.fight(tester, openingHp: 20, damage: 20);
            expect(fixture.target.currentHp, 100);
            expect(fixture.target.extraSlotId, -1);
            expect(
              fixture.state.state.slotItems.keys,
              unorderedEquals(<int>[601, 602]),
            );
            expect(
              fixture.battle.current!.friendMain[1].usedDamageControlItemIds,
              <int>[42, 43],
            );
            await fixture.advance(tester);
            await fixture.expectEquippedDisplay(tester, bothShips: false);

            await fixture.fight(tester, openingHp: 100, damage: 80);
            expect(fixture.target.currentHp, 20);
            expect(fixture.retained.currentHp, 20);
            expect(fixture.hpWritebacks, greaterThanOrEqualTo(3));
            expect(fixture.consumptionWritebacks, greaterThanOrEqualTo(2));
            expect(fixture.battle.isDamageControlStateTrusted, isTrue);
            await fixture.advance(tester);
            fixture.expectExhaustedDisplay();

            final acceptedBeforeLate = fixture.accepted.length;
            final latePackets = <(String, Object?)>[
              (
                '/kcsapi/api_get_member/ship_deck',
                fixture.oldHealthyShipSnapshot,
              ),
              ('/kcsapi/api_get_member/slot_item', fixture.oldItemSnapshot),
            ];
            for (final packet
                in order == _SnapshotOrder.shipsFirst
                    ? latePackets
                    : latePackets.reversed) {
              await fixture.publish(tester, packet.$1, packet.$2);
              fixture.expectExhaustedDisplay();
              expect(fixture.target.currentHp, 20);
              expect(fixture.target.slotIds, <int>[-1]);
              expect(fixture.target.extraSlotId, -1);
              expect(fixture.state.state.slotItems.containsKey(501), isFalse);
              expect(fixture.state.state.slotItems.containsKey(502), isFalse);
            }
            expect(fixture.accepted, hasLength(acceptedBeforeLate + 2));
            expect(
              fixture.accepted[acceptedBeforeLate + 1].sequence,
              greaterThan(fixture.accepted[acceptedBeforeLate - 1].sequence),
            );
            expect(fixture.retained.currentHp, 20);
            expect(fixture.retained.slotIds, <int>[601]);
            expect(fixture.retained.extraSlotId, 602);

            await tester.tap(
              find.byKey(const Key('acknowledgeAdvanceWarning')),
            );
            await tester.pumpAndSettle();
            expect(find.byType(AlertDialog), findsNothing);
            expect(fixture.battle.warningSession.isMuted, isFalse);
            final alertsBeforeRepeat = fixture.alerts.severities.length;
            await fixture.advance(tester);
            fixture.expectExhaustedDisplay();
            expect(
              fixture.alerts.severities,
              hasLength(alertsBeforeRepeat + 1),
            );
            expect(fixture.safetyLoads, 5);
            expect(fixture.state.lastError, isNull);
            expect(fixture.battle.lastError, isNull);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}

final class _EndToEndFixture {
  _EndToEndFixture({required this.combined, required this.display}) {
    initial = _initialState(combined: combined);
    oldHealthyShipSnapshot = <String, Object?>{
      'api_ship_data': <Object?>[
        for (final ship in initial.ships.values)
          <String, Object?>{
            'api_id': ship.id,
            'api_ship_id': ship.masterId,
            'api_lv': ship.level,
            'api_nowhp': ship.id == 1001 ? 100 : ship.currentHp,
            'api_maxhp': ship.maxHp,
            'api_slot': ship.slotIds,
            'api_slot_ex': ship.extraSlotId,
          },
      ],
    };
    oldItemSnapshot = <Object?>[
      for (final item in initial.slotItems.values)
        <String, Object?>{
          'api_id': item.instanceId,
          'api_slotitem_id': item.masterSlotItemId,
        },
    ];
  }

  final bool combined;
  final AdvanceWarningDisplayMode display;
  final account = AccountSession(initialMemberId: 1001);
  final port = _EndToEndCapturePort();
  final alerts = _EndToEndDamageAlerts();
  final accepted = <CapturedApiEvent>[];
  late final GameState initial;
  late final Map<String, Object?> oldHealthyShipSnapshot;
  late final List<Object?> oldItemSnapshot;
  late final GameStateController state;
  late final BattleController battle;
  late final GameApiEventPipeline pipeline;
  late final GameCaptureController capture;
  late final SafetySettingsController settings;
  var _sequence = 0;
  var _node = 1;
  var hpWritebacks = 0;
  var consumptionWritebacks = 0;
  var safetyLoads = 0;

  OwnedShip get target => state.state.ships[1001]!;
  OwnedShip get retained => state.state.ships[combined ? 2001 : 1002]!;

  static Future<_EndToEndFixture> mount(
    WidgetTester tester, {
    required bool combined,
    required AdvanceWarningDisplayMode display,
  }) async {
    final fixture = _EndToEndFixture(combined: combined, display: display);
    fixture.state = GameStateController(
      accountSession: fixture.account,
      initialState: fixture.initial,
    );
    await fixture.state.initialize();
    fixture.settings = await SafetySettingsController.load(
      MemorySafetySettingsStore(),
    );
    await fixture.settings.setAdvanceWarningDisplayMode(display);
    fixture.battle = BattleController(
      accountSession: fixture.account,
      gameState: () => fixture.state.state,
      waitForGameState: () => fixture.state.idle,
      onFriendlyHpUpdated: (hp, capturedAt) {
        fixture.hpWritebacks++;
        fixture.state.applyFriendlyBattleHp(hp, capturedAt);
      },
      onDamageControlConsumed: (consumed, capturedAt) {
        fixture.consumptionWritebacks++;
        fixture.state.applyDamageControlConsumption(consumed, capturedAt);
      },
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

  Future<void> start(WidgetTester tester) => publish(
    tester,
    '/kcsapi/api_req_map/start',
    _nodeData(_node),
    requestParams: const <String, Object?>{'api_deck_id': '1'},
  );

  Future<void> advance(WidgetTester tester) =>
      publish(tester, '/kcsapi/api_req_map/next', _nodeData(++_node));

  Future<void> fight(
    WidgetTester tester, {
    required int openingHp,
    required int damage,
  }) => publish(
    tester,
    combined
        ? '/kcsapi/api_req_combined_battle/battle_water'
        : '/kcsapi/api_req_sortie/battle',
    <String, Object?>{
      'api_deck_id': 1,
      'api_f_nowhps': <int>[-1, 100, openingHp, if (!combined) 20],
      'api_f_maxhps': <int>[-1, 100, 100, if (!combined) 100],
      if (combined) 'api_f_nowhps_combined': <int>[-1, 100, 20],
      if (combined) 'api_f_maxhps_combined': <int>[-1, 100, 100],
      'api_e_nowhps': <int>[-1, 20],
      'api_e_maxhps': <int>[-1, 20],
      'api_ship_ke': <int>[-1, 501],
      'api_hougeki1': <String, Object?>{
        'api_at_eflag': <int>[1],
        'api_at_list': <int>[0],
        'api_df_list': <Object?>[
          <int>[1],
        ],
        'api_damage': <Object?>[
          <int>[damage],
        ],
      },
    },
  );

  Future<void> publish(
    WidgetTester tester,
    String path,
    Object? data, {
    Map<String, Object?> requestParams = const <String, Object?>{},
  }) async {
    final acceptedBefore = accepted.length;
    port.add(
      CapturedApiEvent(
        path: path,
        requestParams: requestParams,
        responseBody: jsonEncode(<String, Object?>{
          'api_result': 1,
          'api_data': data,
        }),
        source: CaptureSource.xhr,
        sourceOrigin: 'https://example.invalid',
        capturedAt: DateTime.utc(2026, 10, 23, 0, 0, ++_sequence),
        sequence: _sequence,
        captureSessionId: 'end-to-end-capture',
        captureDocumentId: 'end-to-end-document',
        captureDocumentStartedAtEpochMs: 1000,
      ),
    );
    expect(accepted, hasLength(acceptedBefore + 1));
    await pipeline.idle;
    await tester.pumpAndSettle();
    expect(state.lastError, isNull);
    expect(battle.lastError, isNull);
  }

  Future<void> expectEquippedDisplay(
    WidgetTester tester, {
    required bool bothShips,
  }) async {
    if (display == AdvanceWarningDisplayMode.smart) {
      expect(find.text('大破舰已携带损管'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    } else {
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('大破舰已携带损管'), findsNothing);
      expect(find.text('未携带损管'), findsNothing);
      expect(find.text('#1001'), bothShips ? findsOneWidget : findsNothing);
      expect(find.text('#${retained.id}'), findsOneWidget);
      await tester.tap(find.byKey(const Key('acknowledgeAdvanceWarning')));
      await tester.pumpAndSettle();
      expect(battle.warningSession.isMuted, isFalse);
    }
  }

  void expectExhaustedDisplay() {
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('大破舰已携带损管'), findsNothing);
    expect(find.text('存在未携带损管的大破舰娘！'), findsOneWidget);
    expect(find.text('#1001'), findsOneWidget);
    expect(find.text('#${retained.id}'), findsOneWidget);
    expect(find.text('未携带损管'), findsOneWidget);
    expect(find.text('携带：应急修理要员 ×1、应急修理女神 ×1'), findsOneWidget);
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

GameState _initialState({required bool combined}) => GameState(
  memberId: 1001,
  hasPortData: true,
  hasEquipmentInventory: true,
  combinedFleetType: combined
      ? CombinedFleetType.surfaceTaskForce
      : CombinedFleetType.none,
  ships: <int, OwnedShip>{
    for (final shipId in <int>[
      1000,
      1001,
      if (combined) 2000,
      combined ? 2001 : 1002,
    ])
      shipId: OwnedShip(
        id: shipId,
        masterId: shipId,
        level: 50,
        currentHp: shipId % 1000 == 0 ? 100 : 20,
        maxHp: 100,
        slotIds: shipId == 1001
            ? const <int>[501]
            : shipId % 1000 == 0
            ? const <int>[]
            : const <int>[601],
        extraSlotId: shipId == 1001
            ? 502
            : shipId % 1000 == 0
            ? -1
            : 602,
      ),
  },
  slotItems: const <int, OwnedSlotItem>{
    501: OwnedSlotItem(instanceId: 501, masterSlotItemId: 42),
    502: OwnedSlotItem(instanceId: 502, masterSlotItemId: 43),
    601: OwnedSlotItem(instanceId: 601, masterSlotItemId: 42),
    602: OwnedSlotItem(instanceId: 602, masterSlotItemId: 43),
  },
  fleets: <Fleet>[
    Fleet(id: 1, name: 'Main', shipIds: <int>[1000, 1001, if (!combined) 1002]),
    if (combined)
      const Fleet(id: 2, name: 'Escort', shipIds: <int>[2000, 2001]),
  ],
);

Map<String, Object?> _nodeData(int node) => <String, Object?>{
  'api_maparea_id': 1,
  'api_mapinfo_no': 1,
  'api_no': node,
};

final class _EndToEndDamageAlerts implements BattleDamageAlertPort {
  final severities = <BattleDamageAlertSeverity>[];

  @override
  Future<void> alert(BattleDamageAlertSeverity severity) async =>
      severities.add(severity);
}

final class _EndToEndCapturePort implements GameCapturePort {
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
