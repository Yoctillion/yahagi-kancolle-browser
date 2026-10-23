import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/account/account_session.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_damage_alert.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_models.dart';
import 'package:yahagi_kancolle_browser/src/battle/prediction/battle_prediction_executor.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/bridge/native_game_capture_script.dart';
import 'package:yahagi_kancolle_browser/src/capture/advance_warning_details.dart';
import 'package:yahagi_kancolle_browser/src/capture/android_game_capture_port.dart';
import 'package:yahagi_kancolle_browser/src/capture/battle_result_warning_overlay.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_controller.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_port.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_api_event_pipeline.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_completion_drawer.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_store.dart';

enum _Interruption { nativeSignal, clear, streamError, streamClose }

void main() {
  _postBattleHeaderLossCases();
  for (final timing in AdvanceWarningTimingSettings.values) {
    _lateBoundaryCases(timing);
    _postInterruptionDamageCases(timing);
    _accountStreamCases(timing);
  }
}

void _postBattleHeaderLossCases() {
  for (final combined in <bool>[false, true]) {
    for (final hideAfterNext in <bool>[false, true]) {
      testWidgets(
        'real pipeline header loss respects result freshness and later exhaustion combined=$combined hideAfterNext=$hideAfterNext',
        (tester) async {
          final fixture = await _AccountStreamFixture.mount(
            tester,
            combined: combined,
            timing: AdvanceWarningTimingSettings.battleOnly,
          );
          addTearDown(() => fixture.dispose(tester));
          final oracle = _FleetOracle(combined: combined);
          final overlay = tester.widget<BattleResultWarningOverlay>(
            find.byType(BattleResultWarningOverlay),
          );
          await fixture.login(tester, oracle, memberId: 71001, document: 1);
          await fixture.publish(
            tester,
            '/kcsapi/api_get_member/ship_deck',
            <String, Object?>{
              'api_ship_data': fixture.ships(equipped: true, healthy: true),
            },
          );
          oracle.targetHp = 100;
          fixture.expectOracle(oracle);
          await fixture.start(tester, oracle);
          await fixture.publish(
            tester,
            fixture.battlePath,
            fixture.battleData(oracle, damage: 80),
          );
          oracle.targetHp = 20;
          fixture.expectOracle(oracle);
          expect(oracle.usedControls, 0);
          expect(fixture.consumptionWritebacks, 0);
          for (final target in oracle.targets) {
            expect(
              fixture.battle.current!.friendShips
                  .singleWhere((ship) => ship.ownedShipId == target)
                  .usedDamageControlItemIds,
              isEmpty,
            );
          }
          await fixture.result(tester, oracle);
          final resultEvent = fixture.accepted.last;
          expect(fixture.pipeline.wasEventAccepted(resultEvent), isTrue);
          expect(
            fixture.battle.current!.displayStage,
            BattleDisplayStage.result,
          );
          expect(find.text('大破舰已携带损管'), findsOneWidget);
          expect(find.byType(AlertDialog), findsNothing);

          if (hideAfterNext) {
            await fixture.next(tester, oracle);
            expect(
              fixture.battle.current!.displayStage,
              BattleDisplayStage.navigation,
            );
            expect(fixture.pipeline.wasEventAccepted(resultEvent), isTrue);
            fixture.expectPresentation(oracle);
          }
          final alertsBeforeHeaderLoss = fixture.alerts.severities.length;
          fixture.headerVisible.value = false;
          await tester.pumpAndSettle();
          expect(
            tester.widget<BattleResultWarningOverlay>(
              find.byType(BattleResultWarningOverlay),
            ),
            same(overlay),
          );
          expect(
            find.byType(QuestCompletionHeaderSlot, skipOffstage: false),
            findsOneWidget,
          );
          expect(find.text('大破舰已携带损管'), findsNothing);
          expect(fixture.alerts.severities, hasLength(alertsBeforeHeaderLoss));
          if (hideAfterNext) {
            expect(
              fixture.battle.current!.displayStage,
              BattleDisplayStage.navigation,
            );
            expect(find.byType(AlertDialog), findsNothing);
          } else {
            expect(
              fixture.battle.current!.displayStage,
              BattleDisplayStage.result,
            );
            expect(find.byType(AlertDialog), findsOneWidget);
            expect(find.text('未携带损管'), findsNothing);
            for (final target in oracle.targets) {
              expect(find.text('#$target'), findsOneWidget);
            }
            await fixture.acknowledge(tester);
            await fixture.next(tester, oracle);
          }
          fixture.headerVisible.value = true;
          await tester.pumpAndSettle();
          expect(
            tester.widget<BattleResultWarningOverlay>(
              find.byType(BattleResultWarningOverlay),
            ),
            same(overlay),
          );
          expect(find.byType(AlertDialog), findsNothing);
          expect(find.text('大破舰已携带损管'), findsNothing);
          fixture.expectOracle(oracle);

          await fixture.exhaust(tester, oracle, alreadyStarted: true);
          expect(oracle.usedControls, 2);
          expect(oracle.targetHp, 20);
          expect(fixture.state.state.slotItems, isEmpty);
          await fixture.publish(
            tester,
            fixture.battlePath,
            fixture.battleData(oracle, damage: 0),
          );
          await fixture.publish(tester, fixture.resultPath, <String, Object?>{
            'api_win_rank': 'A',
            'api_mvp': 1,
          });
          expect(
            fixture.battle.current!.displayStage,
            BattleDisplayStage.result,
          );
          fixture.expectOracle(oracle);
          fixture.expectPresentation(oracle, resultStage: true);
          expect(find.text('大破舰已携带损管'), findsNothing);
          expect(find.text('未携带损管'), findsNWidgets(oracle.targets.length));
          expect(fixture.nativeApiPackets, 18);
          expect(fixture.accepted, hasLength(18));
          expect(fixture.pipeline.pendingEventCount, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

void _accountStreamCases(AdvanceWarningTimingSettings timing) {
  for (final combined in <bool>[false, true]) {
    for (final interruption in _Interruption.values) {
      for (final seedOffset in <int>[0, 97, 20261023]) {
        final baselineSeed =
            17 + interruption.index * 19 + (combined ? 101 : 0);
        final seed = baselineSeed + seedOffset;
        final damageParts = seedOffset == 0
            ? 1
            : seedOffset == 97
            ? 2
            : 3;
        testWidgets(
          'native multi-account exhaustion survives $interruption timing=$timing combined=$combined seed=$seed offset=$seedOffset',
          (tester) async {
            final fixture = await _AccountStreamFixture.mount(
              tester,
              combined: combined,
              timing: timing,
              gameSeed: seed,
              damageParts: damageParts,
            );
            addTearDown(() => fixture.dispose(tester));
            final oracle = _FleetOracle(combined: combined);
            final random = Random(seed);
            final firstSession = fixture.capture.captureSessionId;

            await fixture.login(tester, oracle, memberId: 71001, document: 1);
            await fixture.exhaust(tester, oracle);
            fixture.expectPresentation(oracle);

            await fixture.login(tester, oracle, memberId: 72002, document: 2);
            expect(fixture.capture.captureSessionId, firstSession);
            fixture.expectOracle(oracle);
            expect(
              fixture.state.state.slotItems.keys,
              unorderedEquals(<int>[501, 502, 601, 602]),
            );
            await fixture.start(tester, oracle);
            fixture.expectPresentation(oracle);

            final obsoletePackets = fixture.obsoletePackets(
              session: firstSession,
              document: 1,
              memberId: 71001,
            );
            final baselinePackets = List<Map<String, Object?>>.from(
              obsoletePackets,
            )..shuffle(Random(baselineSeed));
            obsoletePackets.shuffle(random);
            if (seedOffset != 0) {
              expect(
                obsoletePackets.map((packet) => packet['path']),
                isNot(
                  orderedEquals(
                    baselinePackets.map((packet) => packet['path']),
                  ),
                ),
                reason:
                    'the new game seed changes delivered obsolete packet order',
              );
            }
            for (final packet in obsoletePackets) {
              await fixture.reject(tester, packet, oracle);
              fixture.expectPresentation(oracle);
            }

            await fixture.exhaust(tester, oracle, alreadyStarted: true);
            await fixture.contradictorySnapshots(tester, oracle, random);
            fixture.expectPresentation(oracle);

            if (timing.postBattle && timing.afterAdvance) {
              await fixture.acknowledge(tester);
            }
            final alertsBeforeQueuedResults = fixture.alerts.severities.length;
            fixture.holdDecoder();
            await fixture.queue(
              tester,
              fixture.native(
                '/kcsapi/api_get_member/ship_deck',
                <String, Object?>{
                  'api_ship_data': fixture.ships(equipped: true, healthy: true),
                },
                hold: true,
              ),
            );
            expect(fixture.decoderHeld, isTrue);
            final queuedBeforeGap = fixture.obsoletePackets(
              session: firstSession,
              document: 2,
              memberId: 71001,
              freshSequence: true,
            );
            for (final packet in queuedBeforeGap) {
              await fixture.queue(tester, packet);
            }
            expect(
              fixture.pipeline.pendingEventCount,
              greaterThanOrEqualTo(queuedBeforeGap.length),
            );
            final generationBeforeGap = fixture.capture.continuityGeneration;

            await fixture.interrupt(tester, interruption);
            oracle.trusted = false;
            expect(
              fixture.capture.continuityGeneration,
              greaterThan(generationBeforeGap),
            );
            fixture.releaseDecoder();
            await fixture.settle(tester);
            fixture.expectOracle(oracle);
            if (timing.postBattle) {
              expect(find.byType(AlertDialog), findsNothing);
              expect(find.text('大破舰已携带损管'), findsNothing);
              expect(
                fixture.alerts.severities,
                hasLength(alertsBeforeQueuedResults),
              );
            }

            if (interruption == _Interruption.streamError ||
                interruption == _Interruption.streamClose) {
              expect(fixture.capture.state, GameCaptureState.error);
              final acceptedBeforeDeadStream = fixture.accepted.length;
              await fixture.queue(
                tester,
                fixture.native(
                  '/kcsapi/api_port/port',
                  fixture.portData(71001, equipped: true),
                ),
              );
              expect(fixture.accepted, hasLength(acceptedBeforeDeadStream));
              await fixture.reconnect(tester);
            }

            if (timing.postBattle) {
              await fixture.publish(
                tester,
                fixture.battlePath,
                fixture.battleData(oracle, damage: 0),
              );
              fixture.expectOracle(oracle);
              await fixture.result(tester, oracle);
            }
            await fixture.next(tester, oracle);
            fixture.expectPresentation(oracle);
            await fixture.contradictorySnapshots(tester, oracle, random);
            await fixture.next(tester, oracle);
            fixture.expectPresentation(oracle);

            final rejectedResets = <String>[
              '/kcsapi/api_start2/getData',
              '/kcsapi/api_port/port',
              '/kcsapi/api_req_map/start',
              '/kcsapi/api_req_sortie/battle',
              if (timing.postBattle) fixture.resultPath,
            ];
            for (final path in rejectedResets..shuffle(random)) {
              for (final sequence in <int>[fixture.currentSequence, 1]) {
                await fixture.reject(
                  tester,
                  fixture.native(
                    path,
                    fixture.portData(71001, equipped: true),
                    sequence: sequence,
                  ),
                  oracle,
                );
                fixture.expectPresentation(oracle);
              }
            }

            fixture.pipeline.invalidatePendingEvents(waitForLoginStart: true);
            fixture.account.reset();
            await fixture.capture.invalidateSession();
            expect(fixture.capture.captureSessionId, isNot(firstSession));
            await fixture.login(tester, oracle, memberId: 71001, document: 3);
            fixture.expectOracle(oracle);
            expect(
              fixture.state.state.slotItems.keys,
              unorderedEquals(<int>[501, 502, 601, 602]),
            );
            await fixture.exhaust(tester, oracle);
            fixture.expectPresentation(oracle);

            final retiredPackets = <Map<String, Object?>>[
              ...fixture.obsoletePackets(
                session: firstSession,
                document: 1,
                memberId: 71001,
              ),
              ...fixture.obsoletePackets(
                session: firstSession,
                document: 2,
                memberId: 72002,
              ),
            ]..shuffle(random);
            for (final packet in retiredPackets) {
              await fixture.reject(tester, packet, oracle);
              fixture.expectPresentation(oracle);
            }
            await fixture.contradictorySnapshots(tester, oracle, random);
            fixture.expectPresentation(oracle);

            if (combined && interruption == _Interruption.nativeSignal) {
              await fixture.burst(tester, oracle, firstSession, random);
              fixture.expectOracle(oracle);
              fixture.expectPresentation(oracle);
            }

            if (timing.afterAdvance) await fixture.acknowledge(tester);
            final alertsBeforeRepeat = fixture.alerts.severities.length;
            await fixture.next(tester, oracle);
            fixture.expectPresentation(oracle);
            expect(
              fixture.alerts.severities,
              hasLength(alertsBeforeRepeat + (timing.afterAdvance ? 1 : 0)),
            );
            expect(fixture.hpWritebacks, greaterThanOrEqualTo(9));
            expect(fixture.consumptionWritebacks, greaterThanOrEqualTo(6));
            expect(fixture.inspectedBattlePackets, 9);
            expect(fixture.inspectedStrikes, 18 * damageParts);
            final deadStreamPacket =
                interruption == _Interruption.streamError ||
                    interruption == _Interruption.streamClose
                ? 1
                : 0;
            final burstGroups =
                combined && interruption == _Interruption.nativeSignal
                ? 256
                : 0;
            expect(
              fixture.nativeApiPackets,
              76 +
                  (timing.postBattle ? 17 : 0) +
                  deadStreamPacket +
                  burstGroups * (timing.postBattle ? 9 : 8),
            );
            expect(
              fixture.accepted,
              hasLength(47 + (timing.postBattle ? 12 : 0) + burstGroups * 3),
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}

void _postInterruptionDamageCases(AdvanceWarningTimingSettings timing) {
  for (final combined in <bool>[false, true]) {
    testWidgets(
      'post-gap damage after both controls are consumed writes HP and warns timing=$timing combined=$combined',
      (tester) async {
        final fixture = await _AccountStreamFixture.mount(
          tester,
          combined: combined,
          timing: timing,
        );
        addTearDown(() => fixture.dispose(tester));
        final oracle = _FleetOracle(combined: combined);
        await fixture.login(tester, oracle, memberId: 71001, document: 1);

        await fixture.exhaust(tester, oracle, interruptBeforeRedamage: true);

        fixture.expectOracle(oracle);
        fixture.expectPresentation(oracle);
        expect(oracle.usedControls, 2);
        expect(oracle.targetHp, 20);
        expect(fixture.battle.isDamageControlStateTrusted, isFalse);
        expect(
          find.byType(AlertDialog),
          timing.afterAdvance ? findsOneWidget : findsNothing,
        );
        expect(find.text('大破舰已携带损管'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'post-gap lethal damage after both controls preserves one HP and warns timing=$timing combined=$combined',
      (tester) async {
        final fixture = await _AccountStreamFixture.mount(
          tester,
          combined: combined,
          timing: timing,
        );
        addTearDown(() => fixture.dispose(tester));
        final oracle = _FleetOracle(combined: combined);
        await fixture.login(tester, oracle, memberId: 71001, document: 1);

        await fixture.exhaust(
          tester,
          oracle,
          interruptBeforeRedamage: true,
          postDamage: 150,
        );

        fixture.expectOracle(oracle);
        fixture.expectPresentation(oracle);
        expect(oracle.usedControls, 2);
        expect(oracle.targetHp, 1);
        expect(fixture.battle.isDamageControlStateTrusted, isFalse);
        expect(
          find.byType(AlertDialog),
          timing.afterAdvance ? findsOneWidget : findsNothing,
        );
        expect(find.text('大破舰已携带损管'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'post-gap healthy opening HP cannot heal exhausted heavy ships timing=$timing combined=$combined',
      (tester) async {
        final fixture = await _AccountStreamFixture.mount(
          tester,
          combined: combined,
          timing: timing,
        );
        addTearDown(() => fixture.dispose(tester));
        final oracle = _FleetOracle(combined: combined);
        await fixture.login(tester, oracle, memberId: 71001, document: 1);
        await fixture.exhaust(tester, oracle);
        await fixture.interrupt(tester, _Interruption.nativeSignal);
        oracle.trusted = false;
        await fixture.next(tester, oracle);
        fixture.expectPresentation(oracle);
        final healthyOpening = _FleetOracle(combined: combined)
          ..usedControls = 2
          ..targetHp = 100;

        if (timing.postBattle && timing.afterAdvance) {
          await fixture.acknowledge(tester);
        }
        await fixture.publish(
          tester,
          combined
              ? '/kcsapi/api_req_combined_battle/battle_water'
              : '/kcsapi/api_req_sortie/battle',
          fixture.battleData(healthyOpening, damage: 0),
        );

        fixture.expectOracle(oracle);
        expect(oracle.targetHp, 20);
        expect(fixture.battle.isDamageControlStateTrusted, isFalse);
        await fixture.result(tester, oracle);
        await fixture.next(tester, oracle);
        fixture.expectPresentation(oracle);
        expect(
          find.byType(AlertDialog),
          timing.afterAdvance ? findsOneWidget : findsNothing,
        );
        expect(find.text('大破舰已携带损管'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

void _lateBoundaryCases(AdvanceWarningTimingSettings timing) {
  for (final path in <String>[
    '/kcsapi/api_port/port',
    '/kcsapi/api_start2/getData',
    '/kcsapi/api_req_map/start',
  ]) {
    testWidgets(
      'late same-scope boundary after interruption preserves $path timing=$timing',
      (tester) async {
        final fixture = await _AccountStreamFixture.mount(
          tester,
          combined: false,
          timing: timing,
        );
        addTearDown(() => fixture.dispose(tester));
        final oracle = _FleetOracle(combined: false);
        await fixture.login(tester, oracle, memberId: 71001, document: 1);
        await fixture.exhaust(tester, oracle);
        await fixture.interrupt(tester, _Interruption.nativeSignal);
        oracle.trusted = false;
        await fixture.next(tester, oracle);
        fixture.expectPresentation(oracle);
        final data = path == '/kcsapi/api_port/port'
            ? fixture.portData(71001, equipped: true)
            : path == '/kcsapi/api_req_map/start'
            ? _nodeData(1)
            : <String, Object?>{};
        await fixture.queue(tester, fixture.native(path, data));
        await fixture.settle(tester);
        if (path == '/kcsapi/api_req_map/start') {
          await fixture.contradictorySnapshots(tester, oracle, Random(31415));
        }
        fixture.expectOracle(oracle);
        fixture.expectPresentation(oracle);
        await fixture.next(tester, oracle);
        fixture.expectPresentation(oracle);
      },
    );
  }
}

final class _FleetOracle {
  _FleetOracle({required this.combined});

  final bool combined;
  int memberId = 0;
  int targetHp = 20;
  int usedControls = 0;
  bool trusted = false;
  bool active = false;

  List<int> get targets => <int>[102, combined ? 108 : 103];
  List<int> get fleetIds => <int>[
    for (var index = 0; index < (combined ? 12 : 3); index++) 101 + index,
  ];

  void login(int member) {
    memberId = member;
    targetHp = 20;
    usedControls = 0;
    trusted = false;
    active = false;
  }

  void consumeRound() {
    usedControls++;
    targetHp = usedControls == 1 ? 20 : 100;
  }

  Set<int> get remainingInstances => <int>{
    if (usedControls == 0) ...<int>[501, 601],
    if (usedControls < 2) ...<int>[502, 602],
  };
}

final class _AccountStreamFixture {
  _AccountStreamFixture({
    required this.combined,
    required this.timing,
    int gameSeed = 0,
    this.damageParts = 1,
  }) : attackRandom = Random(gameSeed);

  final bool combined;
  final AdvanceWarningTimingSettings timing;
  final int damageParts;
  final Random attackRandom;
  final account = AccountSession();
  final accepted = <CapturedApiEvent>[];
  final alerts = _DamageAlerts();
  final ports = <_FaultableNativePort>[];
  final sequences = <(String, int), int>{};
  final headerVisible = ValueNotifier<bool>(true);
  late final GameStateController state;
  late final BattleController battle;
  late final GameApiEventPipeline pipeline;
  late final GameCaptureController capture;
  late final SafetySettingsController settings;
  late final MethodChannel channel;
  late final MethodChannelGameCapturePort nativePort;
  Completer<void>? _decoderGate;
  bool decoderHeld = false;
  int document = 1;
  int node = 1;
  int hpWritebacks = 0;
  int consumptionWritebacks = 0;
  int nativeApiPackets = 0;
  int inspectedBattlePackets = 0;
  int inspectedStrikes = 0;
  bool resultNoticeExpected = false;
  static int _channelSequence = 0;

  int get currentSequence =>
      sequences[(capture.captureSessionId, document)] ?? 0;

  String get battlePath => combined
      ? '/kcsapi/api_req_combined_battle/battle_water'
      : '/kcsapi/api_req_sortie/battle';

  String get resultPath => combined
      ? '/kcsapi/api_req_combined_battle/battleresult'
      : '/kcsapi/api_req_sortie/battleresult';

  static Future<_AccountStreamFixture> mount(
    WidgetTester tester, {
    required bool combined,
    required AdvanceWarningTimingSettings timing,
    int gameSeed = 0,
    int damageParts = 1,
  }) async {
    final fixture = _AccountStreamFixture(
      combined: combined,
      timing: timing,
      gameSeed: gameSeed,
      damageParts: damageParts,
    );
    fixture.state = GameStateController(accountSession: fixture.account);
    await fixture.state.initialize();
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
      backgroundThresholdBytes: 1,
      decodeEnvelope: (body) async {
        final envelope = Map<String, Object?>.from(jsonDecode(body) as Map);
        if (envelope['test_hold_decode'] == true) {
          fixture.decoderHeld = true;
          await fixture._decoderGate!.future;
        }
        return envelope;
      },
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
    fixture.channel = MethodChannel(
      'test/extreme_account_stream/${++_channelSequence}',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(fixture.channel, (call) async {
          if (call.method == 'isSupported') return true;
          return null;
        });
    fixture.nativePort = MethodChannelGameCapturePort(channel: fixture.channel);
    await fixture.reconnect(tester);
    fixture.settings = await SafetySettingsController.load(
      MemorySafetySettingsStore(),
    );
    await fixture.settings.setAdvanceWarningDisplayMode(
      AdvanceWarningDisplayMode.smart,
    );
    await fixture.settings.setAdvanceWarningTimings(timing);
    await tester.pumpWidget(
      MaterialApp(
        home: QuestCompletionDrawerHost(
          child: Column(
            children: <Widget>[
              ValueListenableBuilder<bool>(
                valueListenable: fixture.headerVisible,
                builder: (context, visible, child) =>
                    Offstage(offstage: !visible, child: child),
                child: const SizedBox(
                  height: 44,
                  child: QuestCompletionHeaderSlot(child: SizedBox.expand()),
                ),
              ),
              Expanded(
                child: BattleResultWarningOverlay(
                  accountSession: fixture.account,
                  gameCaptureController: fixture.capture,
                  warningSession: fixture.battle.warningSession,
                  damageControlStateTrusted: () =>
                      fixture.battle.isDamageControlStateTrusted,
                  loadSafetyState: () async {
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

  Future<void> reconnect(WidgetTester tester) async {
    final port = _FaultableNativePort(nativePort);
    ports.add(port);
    var completed = false;
    Object? configurationError;
    unawaited(
      capture
          .attach(port, enabled: true, script: nativeGameCaptureScript)
          .then<void>(
            (_) => completed = true,
            onError: (Object error, StackTrace stackTrace) {
              configurationError = error;
              completed = true;
            },
          ),
    );
    for (var attempt = 0; attempt < 20 && !completed; attempt++) {
      await tester.pump();
    }
    expect(
      completed,
      isTrue,
      reason:
          'native capture configuration did not settle: ${port.phase}, ${capture.state}, ${capture.errorMessage}',
    );
    expect(configurationError, isNull);
    expect(capture.errorMessage, isNull);
    expect(
      capture.state,
      anyOf(GameCaptureState.ready, GameCaptureState.capturing),
    );
  }

  Map<String, Object?> native(
    String path,
    Object? data, {
    String? session,
    int? documentId,
    int? sequence,
    bool hold = false,
  }) {
    final captureSession = session ?? capture.captureSessionId;
    final captureDocument = documentId ?? document;
    final scope = (captureSession, captureDocument);
    final nextSequence = sequence ?? (sequences[scope] ?? 0) + 1;
    if (sequence == null) sequences[scope] = nextSequence;
    return <String, Object?>{
      'version': 1,
      'kind': 'kcsapi_response',
      'method': 'POST',
      'path': path,
      'requestParams': <String, Object?>{'api_deck_id': '1'},
      'responseBody':
          'svdata=${jsonEncode(<String, Object?>{'api_result': 1, 'api_data': data, if (hold) 'test_hold_decode': true})}',
      'statusCode': 200,
      'transport': nextSequence.isEven ? 'fetch' : 'xhr',
      'sourceOrigin': 'https://w01y.kancolle-server.com',
      'capturedAt': DateTime.utc(
        2026,
        10,
        23,
      ).add(Duration(milliseconds: nextSequence)).toIso8601String(),
      'sequence': nextSequence,
      'captureSessionId': captureSession,
      'captureDocumentId': 'extreme-document-$captureDocument',
      'captureDocumentStartedAtEpochMs': captureDocument * 1000,
    };
  }

  Future<void> queue(WidgetTester tester, Map<String, Object?> payload) async {
    await deliverNative(payload);
    await tester.pump();
  }

  Future<void> deliverNative(Map<String, Object?> payload) {
    if (payload['kind'] == 'kcsapi_response') nativeApiPackets++;
    final delivered = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('onCaptureEvent', payload),
          ),
          (_) => delivered.complete(),
        );
    return delivered.future;
  }

  Future<void> settle(WidgetTester tester) async {
    await pipeline.idle;
    await tester.pumpAndSettle();
    expect(state.lastError, isNull);
    expect(battle.lastError, isNull);
  }

  Future<void> publish(WidgetTester tester, String path, Object? data) async {
    final acceptedBefore = accepted.length;
    await queue(tester, native(path, data));
    expect(accepted, hasLength(acceptedBefore + 1));
    await settle(tester);
  }

  Future<void> reject(
    WidgetTester tester,
    Map<String, Object?> packet,
    _FleetOracle oracle,
  ) async {
    final acceptedBefore = accepted.length;
    final accountBefore = account.current;
    final alertsBefore = alerts.severities.length;
    await queue(tester, packet);
    await settle(tester);
    expect(accepted, hasLength(acceptedBefore), reason: '${packet['path']}');
    expect(account.current, same(accountBefore));
    expect(alerts.severities, hasLength(alertsBefore));
    expectOracle(oracle);
  }

  Future<void> login(
    WidgetTester tester,
    _FleetOracle oracle, {
    required int memberId,
    required int document,
  }) async {
    this.document = document;
    node = 1;
    resultNoticeExpected = false;
    await publish(tester, '/kcsapi/api_start2/getData', <String, Object?>{});
    await publish(
      tester,
      '/kcsapi/api_port/port',
      portData(memberId, equipped: true),
    );
    oracle.login(memberId);
    expectOracle(oracle);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('大破舰已携带损管'), findsNothing);
  }

  Future<void> start(WidgetTester tester, _FleetOracle oracle) async {
    await publish(tester, '/kcsapi/api_req_map/start', _nodeData(node));
    oracle.active = true;
    oracle.trusted = true;
    expectOracle(oracle);
    expectPresentation(oracle);
  }

  Future<void> next(WidgetTester tester, _FleetOracle oracle) async {
    final alertsBefore = alerts.severities.length;
    await publish(tester, '/kcsapi/api_req_map/next', _nodeData(++node));
    expectOracle(oracle);
    if (!timing.afterAdvance) {
      expect(alerts.severities, hasLength(alertsBefore));
    }
  }

  Future<void> result(WidgetTester tester, _FleetOracle oracle) async {
    if (!timing.postBattle) return;
    final alertsBefore = alerts.severities.length;
    await publish(tester, resultPath, <String, Object?>{
      'api_win_rank': 'A',
      'api_mvp': 1,
    });
    expect(battle.current!.displayStage, BattleDisplayStage.result);
    expectOracle(oracle);
    resultNoticeExpected =
        oracle.targetHp <= 25 && oracle.trusted && oracle.usedControls < 2;
    expectPresentation(oracle, resultStage: true);
    expect(
      alerts.severities,
      hasLength(alertsBefore + (oracle.targetHp <= 25 ? 1 : 0)),
    );
    if (oracle.targetHp <= 25 &&
        (!oracle.trusted || oracle.usedControls == 2)) {
      await acknowledge(tester);
    }
  }

  Future<void> acknowledge(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('acknowledgeAdvanceWarning')));
    await tester.pumpAndSettle();
    resultNoticeExpected = false;
    expect(find.byType(AlertDialog), findsNothing);
    expect(battle.warningSession.isMuted, isFalse);
  }

  Future<void> exhaust(
    WidgetTester tester,
    _FleetOracle oracle, {
    bool alreadyStarted = false,
    bool interruptBeforeRedamage = false,
    int postDamage = 80,
  }) async {
    if (!alreadyStarted) await start(tester, oracle);
    for (var round = 0; round < 2; round++) {
      await publish(
        tester,
        combined
            ? '/kcsapi/api_req_combined_battle/battle_water'
            : '/kcsapi/api_req_sortie/battle',
        battleData(oracle, damage: oracle.targetHp),
      );
      expectAcceptedStrikes(oracle, damage: oracle.targetHp);
      oracle.consumeRound();
      expectOracle(oracle);
      for (final target in oracle.targets) {
        expect(
          battle.current!.friendShips
              .singleWhere((ship) => ship.ownedShipId == target)
              .usedDamageControlItemIds,
          round == 0 ? <int>[42] : <int>[42, 43],
        );
      }
      await result(tester, oracle);
      await next(tester, oracle);
      expectPresentation(oracle);
    }
    if (interruptBeforeRedamage) {
      expect(oracle.usedControls, 2);
      expect(oracle.targetHp, 100);
      await interrupt(tester, _Interruption.nativeSignal);
      oracle.trusted = false;
      expectOracle(oracle);
    }
    await publish(
      tester,
      combined
          ? '/kcsapi/api_req_combined_battle/battle_water'
          : '/kcsapi/api_req_sortie/battle',
      battleData(oracle, damage: postDamage),
    );
    expectAcceptedStrikes(oracle, damage: postDamage);
    oracle.targetHp = (100 - postDamage).clamp(1, 100).toInt();
    expectOracle(oracle);
    await result(tester, oracle);
    await next(tester, oracle);
    expectPresentation(oracle);
  }

  Future<void> contradictorySnapshots(
    WidgetTester tester,
    _FleetOracle oracle,
    Random random,
  ) async {
    final operations = <(String, Object?)>[
      ('/kcsapi/api_get_member/slot_item', items(equipped: true)),
      (
        '/kcsapi/api_get_member/ship3',
        <String, Object?>{
          'api_ship_data': ships(equipped: true, healthy: true, relocate: true),
        },
      ),
      (
        '/kcsapi/api_get_member/ship_deck',
        <String, Object?>{
          'api_ship_data': ships(equipped: true, healthy: true),
        },
      ),
    ]..shuffle(random);
    for (final operation in operations) {
      await publish(tester, operation.$1, operation.$2);
      expectOracle(oracle);
      expectPresentation(oracle);
    }
  }

  Future<void> burst(
    WidgetTester tester,
    _FleetOracle oracle,
    String retiredSession,
    Random random,
  ) async {
    const groupCount = 256;
    final packetsPerGroup = timing.postBattle ? 9 : 8;
    const expectedAccepted = groupCount * 3;
    final expectedRejected = groupCount * (packetsPerGroup - 3);
    final acceptedBefore = accepted.length;
    final capturedBefore = capture.capturedCount;
    final packets = <Map<String, Object?>>[];
    final staleBattle = battleData(_FleetOracle(combined: combined), damage: 0);
    for (var group = 0; group < groupCount; group++) {
      final rejected = <Map<String, Object?>>[
        native(
          '/kcsapi/api_start2/getData',
          <String, Object?>{},
          documentId: 1,
          sequence: 1000000 + group,
        ),
        native(
          '/kcsapi/api_port/port',
          portData(72002, equipped: true),
          session: retiredSession,
          documentId: 2,
          sequence: 1100000 + group,
        ),
        native(
          '/kcsapi/api_req_map/next',
          _nodeData(999),
          sequence: currentSequence,
        ),
        native(
          '/kcsapi/api_port/port',
          portData(72002, equipped: true),
          sequence: 1,
        ),
        native(
          '/kcsapi/api_req_combined_battle/battle_water',
          staleBattle,
          documentId: 2,
          sequence: 1200000 + group,
        ),
        if (timing.postBattle)
          native(
            resultPath,
            <String, Object?>{'api_win_rank': 'A', 'api_mvp': 1},
            documentId: 2,
            sequence: 1300000 + group,
          ),
      ]..shuffle(random);
      final currentOperations = <(String, Object?)>[
        (
          '/kcsapi/api_get_member/ship_deck',
          <String, Object?>{
            'api_ship_data': ships(
              equipped: true,
              healthy: true,
              relocate: group.isOdd,
            ),
          },
        ),
        ('/kcsapi/api_get_member/slot_item', items(equipped: true)),
        ('/kcsapi/api_req_map/next', _nodeData(++node)),
      ];
      packets.addAll(rejected.take(2));
      packets.add(native(currentOperations[0].$1, currentOperations[0].$2));
      packets.addAll(rejected.skip(2).take(2));
      packets.add(native(currentOperations[1].$1, currentOperations[1].$2));
      packets.addAll(rejected.skip(4));
      packets.add(native(currentOperations[2].$1, currentOperations[2].$2));
    }
    expect(packets, hasLength(groupCount * packetsPerGroup));
    expect(packets.length, expectedAccepted + expectedRejected);
    await Future.wait<void>(<Future<void>>[
      for (final packet in packets) deliverNative(packet),
    ]);
    await tester.pump();
    await settle(tester);
    expect(
      accepted.length - acceptedBefore,
      expectedAccepted,
      reason:
          '${packets.length} packets: $expectedAccepted current snapshots/maps, $expectedRejected obsolete/duplicate',
    );
    expect(capture.capturedCount - capturedBefore, expectedAccepted);
    expect(pipeline.pendingEventCount, 0);
    expect(oracle.memberId, 71001);
    expect(oracle.usedControls, 2);
    expect(oracle.trusted, isTrue);
    expectOracle(oracle);
    expectPresentation(oracle);
  }

  List<Map<String, Object?>> obsoletePackets({
    required String session,
    required int document,
    required int memberId,
    bool freshSequence = false,
  }) {
    final staleOracle = _FleetOracle(combined: combined);
    final operations = <(String, Object?)>[
      ('/kcsapi/api_start2/getData', <String, Object?>{}),
      ('/kcsapi/api_port/port', portData(memberId, equipped: true)),
      (
        '/kcsapi/api_get_member/ship_deck',
        <String, Object?>{
          'api_ship_data': ships(equipped: true, healthy: true),
        },
      ),
      ('/kcsapi/api_get_member/slot_item', items(equipped: true)),
      ('/kcsapi/api_req_map/start', _nodeData(99)),
      ('/kcsapi/api_req_map/next', _nodeData(100)),
      (
        combined
            ? '/kcsapi/api_req_combined_battle/battle_water'
            : '/kcsapi/api_req_sortie/battle',
        battleData(staleOracle, damage: 0),
      ),
      if (timing.postBattle)
        (resultPath, <String, Object?>{'api_win_rank': 'A', 'api_mvp': 1}),
    ];
    return <Map<String, Object?>>[
      for (var index = 0; index < operations.length; index++)
        native(
          operations[index].$1,
          operations[index].$2,
          session: session,
          documentId: document,
          sequence: freshSequence ? null : 900000 + index,
        ),
    ];
  }

  void holdDecoder() {
    _decoderGate = Completer<void>();
    decoderHeld = false;
  }

  void releaseDecoder() {
    final gate = _decoderGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  Future<void> interrupt(
    WidgetTester tester,
    _Interruption interruption,
  ) async {
    resultNoticeExpected = false;
    switch (interruption) {
      case _Interruption.nativeSignal:
        await queue(tester, <String, Object?>{
          'version': 1,
          'kind': 'capture_interrupted',
        });
      case _Interruption.clear:
        capture.clearCapturedEvents();
      case _Interruption.streamError:
        ports.last.fail();
      case _Interruption.streamClose:
        ports.last.closeEvents();
    }
    await tester.pump();
  }

  void expectOracle(_FleetOracle oracle) {
    expect(account.current.memberId, oracle.memberId);
    expect(state.state.memberId, oracle.memberId);
    expect(state.state.combatState.isActive, oracle.active);
    expect(battle.isDamageControlStateTrusted, oracle.trusted);
    expect(state.state.hasEquipmentInventory, isTrue);
    expect(
      state.state.slotItems.keys,
      unorderedEquals(oracle.remainingInstances),
    );
    for (var index = 0; index < oracle.targets.length; index++) {
      final ship = state.state.ships[oracle.targets[index]]!;
      expect(ship.currentHp, oracle.targetHp);
      expect(ship.slotIds, <int>[
        oracle.usedControls == 0 ? 501 + index * 100 : -1,
      ]);
      expect(
        ship.extraSlotId,
        oracle.usedControls < 2 ? 502 + index * 100 : -1,
      );
    }
    if (!oracle.active || oracle.targetHp > 25) return;
    final warnings = collectAdvanceWarningShips(
      state.state,
      damageControlStateTrusted: battle.isDamageControlStateTrusted,
    );
    expect(
      warnings.map((warning) => warning.ship.id),
      unorderedEquals(oracle.targets),
    );
    final expectedStatus = !oracle.trusted
        ? AdvanceDamageControlStatus.unknown
        : oracle.usedControls == 2
        ? AdvanceDamageControlStatus.missing
        : AdvanceDamageControlStatus.equipped;
    expect(
      warnings.map((warning) => warning.damageControlStatus),
      everyElement(expectedStatus),
    );
  }

  void expectPresentation(_FleetOracle oracle, {bool resultStage = false}) {
    final stageEnabled = resultStage ? timing.postBattle : timing.afterAdvance;
    if (!stageEnabled) {
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.text('大破舰已携带损管'),
        resultNoticeExpected ? findsOneWidget : findsNothing,
      );
    } else if (oracle.targetHp > 25) {
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('大破舰已携带损管'), findsNothing);
    } else if (oracle.trusted && oracle.usedControls < 2) {
      expect(find.text('大破舰已携带损管'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    } else {
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('大破舰已携带损管'), findsNothing);
      for (final target in oracle.targets) {
        expect(find.text('#$target'), findsOneWidget);
      }
      expect(battle.warningSession.isMuted, isFalse);
    }
  }

  List<Object?> ships({
    required bool equipped,
    bool healthy = false,
    bool relocate = false,
  }) {
    final model = _FleetOracle(combined: combined);
    return <Object?>[
      for (final shipId in model.fleetIds)
        <String, Object?>{
          'api_id': shipId,
          'api_ship_id': shipId,
          'api_lv': 60,
          'api_nowhp': !healthy && model.targets.contains(shipId) ? 20 : 100,
          'api_maxhp': 100,
          'api_slot': <int>[
            if (model.targets.contains(shipId))
              equipped
                  ? 501 +
                        (relocate
                                ? 1 - model.targets.indexOf(shipId)
                                : model.targets.indexOf(shipId)) *
                            100
                  : -1,
          ],
          'api_slot_ex': equipped && model.targets.contains(shipId)
              ? 502 +
                    (relocate
                            ? 1 - model.targets.indexOf(shipId)
                            : model.targets.indexOf(shipId)) *
                        100
              : -1,
        },
    ];
  }

  List<Object?> items({required bool equipped}) => <Object?>[
    if (equipped)
      for (final instance in <int>[501, 502, 601, 602])
        <String, Object?>{
          'api_id': instance,
          'api_slotitem_id': instance.isOdd ? 42 : 43,
        },
  ];

  Map<String, Object?> portData(
    int memberId, {
    required bool equipped,
  }) => <String, Object?>{
    'api_basic': <String, Object?>{'api_member_id': memberId},
    'api_ship': ships(equipped: equipped),
    'api_slot_item': items(equipped: equipped),
    'api_combined_flag': combined ? 2 : 0,
    'api_deck_port': <Object?>[
      <String, Object?>{
        'api_id': 1,
        'api_name': 'Main',
        'api_ship': <int>[
          for (var index = 0; index < (combined ? 6 : 3); index++) 101 + index,
        ],
      },
      if (combined)
        <String, Object?>{
          'api_id': 2,
          'api_name': 'Escort',
          'api_ship': <int>[107, 108, 109, 110, 111, 112],
        },
    ],
  };

  Map<String, Object?> battleData(_FleetOracle oracle, {required int damage}) {
    final openingHp = <int>[
      for (final shipId in oracle.fleetIds)
        oracle.targets.contains(shipId) ? oracle.targetHp : 100,
    ];
    final strikes = <(int, int)>[];
    for (var part = 0; part < damageParts; part++) {
      final targets = <int>[1, combined ? 7 : 2];
      if (damageParts > 1) targets.shuffle(attackRandom);
      final partDamage = part == damageParts - 1
          ? damage - (damage ~/ damageParts) * (damageParts - 1)
          : damage ~/ damageParts;
      for (final target in targets) {
        strikes.add((target, partDamage));
      }
    }
    return <String, Object?>{
      'api_deck_id': 1,
      'api_f_nowhps': <int>[-1, ...combined ? openingHp.take(6) : openingHp],
      'api_f_maxhps': <int>[-1, ...List<int>.filled(combined ? 6 : 3, 100)],
      if (combined) 'api_f_nowhps_combined': <int>[-1, ...openingHp.skip(6)],
      if (combined)
        'api_f_maxhps_combined': <int>[-1, 100, 100, 100, 100, 100, 100],
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
    };
  }

  void expectAcceptedStrikes(_FleetOracle oracle, {required int damage}) {
    final event = accepted.last;
    expect(event.path, battlePath);
    final envelope = jsonDecode(event.responseBody) as Map;
    final data = envelope['api_data'] as Map;
    final shelling = data['api_hougeki1'] as Map;
    final defenders = shelling['api_df_list'] as List;
    final damages = shelling['api_damage'] as List;
    expect(defenders, hasLength(damageParts * oracle.targets.length));
    expect(damages, hasLength(defenders.length));
    expect(shelling['api_at_eflag'], everyElement(1));
    expect(shelling['api_at_list'], hasLength(defenders.length));
    for (var part = 0; part < damageParts; part++) {
      expect(
        defenders
            .skip(part * oracle.targets.length)
            .take(oracle.targets.length)
            .map((defender) => (defender as List).single),
        unorderedEquals(<int>[1, combined ? 7 : 2]),
        reason: 'every attack layer reaches each target once before the next',
      );
    }
    for (final target in <int>[1, combined ? 7 : 2]) {
      final targetDamages = <int>[
        for (var index = 0; index < defenders.length; index++)
          if ((defenders[index] as List).single == target)
            ((damages[index] as List).single as num).toInt(),
      ];
      expect(targetDamages, hasLength(damageParts));
      expect(
        targetDamages.fold<int>(0, (total, amount) => total + amount),
        damage,
      );
      var prefixDamage = 0;
      for (final amount in targetDamages.take(damageParts - 1)) {
        prefixDamage += amount;
        expect(
          prefixDamage,
          lessThan(oracle.targetHp),
          reason: 'only the final hit may consume a control for target $target',
        );
      }
      if (damage == oracle.targetHp) {
        expect(prefixDamage + targetDamages.last, oracle.targetHp);
      }
    }
    inspectedBattlePackets++;
    inspectedStrikes += defenders.length;
  }

  Future<void> dispose(WidgetTester tester) async {
    releaseDecoder();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    capture.dispose();
    for (final port in ports) {
      port.dispose();
    }
    nativePort.dispose();
    battle.dispose();
    state.dispose();
    settings.dispose();
    account.dispose();
    headerVisible.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  }
}

Map<String, Object?> _nodeData(int node) => <String, Object?>{
  'api_maparea_id': 1,
  'api_mapinfo_no': 1,
  'api_no': node,
};

final class _DamageAlerts implements BattleDamageAlertPort {
  final severities = <BattleDamageAlertSeverity>[];

  @override
  Future<void> alert(BattleDamageAlertSeverity severity) async =>
      severities.add(severity);
}

final class _FaultableNativePort
    implements GameCapturePort, GameCaptureContinuityPort {
  _FaultableNativePort(this.source) {
    _sourceEvents = source.events.listen((event) {
      if (!_events.isClosed) _events.add(event);
    });
    _sourceInterruptions = source.interruptions.listen((_) {
      if (!_interruptions.isClosed) _interruptions.add(null);
    });
  }

  final MethodChannelGameCapturePort source;
  String phase = 'created';
  final _events = StreamController<CapturedApiEvent>(
    sync: true,
    onCancel: () async {},
  );
  final _interruptions = StreamController<void>(
    sync: true,
    onCancel: () async {},
  );
  late final StreamSubscription<CapturedApiEvent> _sourceEvents;
  late final StreamSubscription<void> _sourceInterruptions;

  @override
  Stream<CapturedApiEvent> get events => _events.stream;

  @override
  Stream<void> get interruptions => _interruptions.stream;

  void fail() => _events.addError(StateError('seeded native stream failure'));

  void closeEvents() => unawaited(_events.close());

  @override
  Future<bool> isSupported() async {
    phase = 'checking support';
    final supported = await source.isSupported();
    phase = 'support checked';
    return supported;
  }

  @override
  Future<void> configure({
    required bool enabled,
    required String script,
  }) async {
    phase = 'configuring';
    await source.configure(enabled: enabled, script: script);
    phase = 'configured';
  }

  @override
  void dispose() {
    unawaited(_sourceEvents.cancel());
    unawaited(_sourceInterruptions.cancel());
    if (!_events.isClosed) unawaited(_events.close());
    if (!_interruptions.isClosed) unawaited(_interruptions.close());
  }
}
