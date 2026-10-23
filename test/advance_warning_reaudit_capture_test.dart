import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/account/account_session.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/prediction/battle_prediction_executor.dart';
import 'package:yahagi_kancolle_browser/src/capture/advance_warning_details.dart';
import 'package:yahagi_kancolle_browser/src/capture/android_game_capture_port.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_controller.dart';
import 'package:yahagi_kancolle_browser/src/game_state/combat_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_api_decoder.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_api_event_pipeline.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native malformed and limited packets revoke real pipeline trust',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final malformedPackets = <Map<String, Object?> Function()>[
        () => <String, Object?>{'version': 1, 'kind': 'capture_interrupted'},
        () =>
            fixture.native('/kcsapi/api_req_sortie/battle', _battleData)
              ..remove('responseBody'),
        () => fixture.native('/kcsapi/api_req_sortie/battle', _battleData)
          ..remove('responseBody')
          ..['responseBodyBytes'] = Uint8List.fromList(<int>[0xff]),
        () =>
            fixture.native('/kcsapi/api_req_sortie/battle', _battleData)
              ..['sequence'] = 0,
        () =>
            fixture.native('/kcsapi/api_req_sortie/battle', _battleData)
              ..['captureDocumentStartedAtEpochMs'] = -1,
        () =>
            fixture.native('/kcsapi/api_req_sortie/battle', _battleData)
              ..['responseBody'] = List<String>.filled(4097, 'x').join(),
      ];

      for (final packet in malformedPackets) {
        await fixture.publish(
          '/kcsapi/api_port/port',
          _portData(equipped: true),
        );
        await fixture.start();
        expect(fixture.battle.isDamageControlStateTrusted, isTrue);
        expect(
          fixture.warning.damageControlStatus,
          AdvanceDamageControlStatus.equipped,
        );
        final previousGeneration = fixture.capture.continuityGeneration;

        await fixture.send(packet());
        expect(fixture.capture.continuityGeneration, previousGeneration + 1);
        expect(fixture.battle.isDamageControlStateTrusted, isFalse);
        expect(
          fixture.warning.damageControlStatus,
          AdvanceDamageControlStatus.unknown,
        );

        await fixture.publish('/kcsapi/api_port/port', <String, Object?>{
          'api_basic': <String, Object?>{'api_member_id': 1001},
          'api_slot_item': <Object?>[
            <String, Object?>{'api_id': 501, 'api_slotitem_id': 42},
          ],
        });
        await fixture.publish('/kcsapi/api_get_member/ship3', <String, Object?>{
          'api_ship_data': _shipData(equipped: true),
        });
        await fixture.publish('/kcsapi/api_get_member/slot_item', <Object?>[
          <String, Object?>{'api_id': 501, 'api_slotitem_id': 42},
        ]);
        await fixture.start();
        expect(fixture.battle.isDamageControlStateTrusted, isFalse);
        expect(
          fixture.warning.damageControlStatus,
          AdvanceDamageControlStatus.unknown,
        );
        expect(fixture.warning.remainingDamageControls, isEmpty);
      }
    },
  );

  test(
    'interruption during background port decode cannot restore old equipment trust',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final fixture = await _Fixture.create(
        decoder: (body) async {
          final envelope = GameApiDecoder.decodeEnvelope(body);
          if (envelope['gate'] == true) {
            started.complete();
            await release.future;
          }
          return envelope;
        },
        threshold: 1,
      );
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        await fixture.dispose();
      });
      await fixture.start();
      await fixture.send(
        fixture.native(
          '/kcsapi/api_port/port',
          _portData(equipped: true),
          gate: true,
        ),
      );
      await started.future;

      fixture.capture.clearCapturedEvents();
      release.complete();
      await fixture.pipeline.idle;
      await fixture.start();

      expect(fixture.battle.isDamageControlStateTrusted, isFalse);
      expect(
        fixture.warning.damageControlStatus,
        AdvanceDamageControlStatus.unknown,
      );
      await fixture.publish(
        '/kcsapi/api_port/port',
        _portData(equipped: false),
      );
      await fixture.start();
      expect(fixture.battle.isDamageControlStateTrusted, isTrue);
      expect(
        fixture.warning.damageControlStatus,
        AdvanceDamageControlStatus.missing,
      );
      expect(fixture.state.state.slotItems, isEmpty);
    },
  );

  test(
    'failed advances preserve consumed equipment and the current sortie mute',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.start();
      await fixture.publish('/kcsapi/api_req_sortie/battle', _battleData);
      expect(fixture.state.state.ships[2]!.slotIds, <int>[-1]);
      expect(fixture.state.state.slotItems, isEmpty);
      expect(
        fixture.warning.damageControlStatus,
        AdvanceDamageControlStatus.missing,
      );
      fixture.battle.warningSession.muteCurrentSortie();
      final sortieGeneration = fixture.battle.warningSession.generation;

      for (var attempt = 0; attempt < 32; attempt++) {
        await fixture.publish('/kcsapi/api_req_map/next', _mapData, result: 0);
        expect(fixture.battle.warningSession.generation, sortieGeneration);
        expect(fixture.battle.warningSession.isMuted, isTrue);
        expect(fixture.battle.isDamageControlStateTrusted, isTrue);
        expect(fixture.state.state.ships[2]!.slotIds, <int>[-1]);
        expect(fixture.state.state.slotItems, isEmpty);
      }
      await fixture.publish('/kcsapi/api_req_map/next', _mapData);
      expect(
        fixture.warning.damageControlStatus,
        AdvanceDamageControlStatus.missing,
      );
    },
  );

  test(
    'failed and malformed reset packets retain consumption tombstones',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.start();
      await fixture.publish('/kcsapi/api_req_sortie/battle', _battleData);
      expect(
        fixture.warning.damageControlStatus,
        AdvanceDamageControlStatus.missing,
      );

      await fixture.publish('/kcsapi/api_req_map/start', _mapData, result: 0);
      await fixture.publish('/kcsapi/api_req_map/start', <Object?>[]);
      await fixture.publish('/kcsapi/api_port/port', <Object?>[]);
      await fixture.publish(
        '/kcsapi/api_start2/getData',
        <Object?>[],
        result: 0,
      );
      await fixture.publish('/kcsapi/api_get_member/slot_item', <Object?>[
        <String, Object?>{'api_id': 501, 'api_slotitem_id': 42},
      ]);
      final delayedShips = _shipData(equipped: true);
      (delayedShips[1]! as Map<String, Object?>)['api_nowhp'] = 100;
      await fixture.publish('/kcsapi/api_get_member/ship3', <String, Object?>{
        'api_ship_data': delayedShips,
      });

      expect(fixture.warning.ship.currentHp, 20);
      expect(
        fixture.warning.damageControlStatus,
        AdvanceDamageControlStatus.missing,
      );
      expect(fixture.state.state.slotItems, isEmpty);
    },
  );

  test(
    'consumed instances stay removed when delayed ships move them into expansion slots',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.start();
      await fixture.publish('/kcsapi/api_req_sortie/battle', _battleData);
      final delayedShips = _shipData(equipped: false);
      final delayedWingman = delayedShips[1]! as Map<String, Object?>;
      delayedWingman['api_nowhp'] = 100;
      delayedWingman['api_slot_ex'] = 501;
      await fixture.publish('/kcsapi/api_get_member/ship3', <String, Object?>{
        'api_ship_data': delayedShips,
      });
      expect(fixture.warning.ship.extraSlotId, -1);
      expect(fixture.warning.ship.currentHp, 20);

      final delayedFlagship = delayedShips[0]! as Map<String, Object?>;
      delayedWingman['api_nowhp'] = 20;
      delayedWingman['api_slot_ex'] = -1;
      delayedFlagship['api_slot_ex'] = 501;
      await fixture.publish('/kcsapi/api_get_member/ship3', <String, Object?>{
        'api_ship_data': delayedShips,
      });
      expect(fixture.state.state.ships[1]!.extraSlotId, -1);
      expect(
        fixture.warning.damageControlStatus,
        AdvanceDamageControlStatus.missing,
      );
      expect(fixture.state.state.slotItems, isEmpty);
    },
  );

  test(
    'fresh port and account snapshots release tombstones and preserve valid HP updates',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.start();
      await fixture.publish('/kcsapi/api_req_sortie/battle', _battleData);
      final healedShips = _shipData(equipped: false);
      (healedShips[1]! as Map<String, Object?>)['api_nowhp'] = 100;
      await fixture.publish('/kcsapi/api_get_member/ship3', <String, Object?>{
        'api_ship_data': healedShips,
      });
      expect(fixture.state.state.ships[2]!.currentHp, 100);

      for (final memberId in <int>[1001, 1002]) {
        final snapshot = _portData(equipped: true)
          ..['api_basic'] = <String, Object?>{'api_member_id': memberId};
        await fixture.publish('/kcsapi/api_port/port', snapshot);
        await fixture.start();
        expect(fixture.account.current.memberId, memberId);
        expect(
          fixture.warning.damageControlStatus,
          AdvanceDamageControlStatus.equipped,
        );
        expect(fixture.warning.remainingDamageControls, <int, int>{42: 1});
        await fixture.publish('/kcsapi/api_req_sortie/battle', _battleData);
        expect(
          fixture.warning.damageControlStatus,
          AdvanceDamageControlStatus.missing,
        );
      }
    },
  );

  test(
    'retired documents stay rejected past the document history limit',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      for (var document = 1; document <= 70; document++) {
        await fixture.publish(
          '/kcsapi/api_start2/getData',
          <String, Object?>{},
          document: document,
        );
        await fixture.publish(
          '/kcsapi/api_port/port',
          _portData(equipped: false),
          document: document,
        );
        await fixture.start(document: document);
        expect(
          fixture.warning.damageControlStatus,
          AdvanceDamageControlStatus.missing,
        );
      }
      for (final staleDocument in <int>[1, 2, 64, 69]) {
        await fixture.publish(
          '/kcsapi/api_start2/getData',
          <String, Object?>{},
          document: staleDocument,
        );
        await fixture.publish(
          '/kcsapi/api_port/port',
          _portData(equipped: true),
          document: staleDocument,
        );
        await fixture.publish('/kcsapi/api_get_member/ship3', <String, Object?>{
          'api_ship_data': _shipData(equipped: true),
        }, document: staleDocument);
        await fixture.publish('/kcsapi/api_get_member/slot_item', <Object?>[
          <String, Object?>{'api_id': 501, 'api_slotitem_id': 42},
        ], document: staleDocument);
        expect(fixture.account.current.memberId, 1001);
        expect(
          fixture.warning.damageControlStatus,
          AdvanceDamageControlStatus.missing,
        );
        expect(fixture.state.state.slotItems, isEmpty);
      }
    },
  );
}

const _mapData = <String, Object?>{
  'api_maparea_id': 1,
  'api_mapinfo_no': 1,
  'api_no': 1,
};

const _battleData = <String, Object?>{
  'api_deck_id': 1,
  'api_f_nowhps': <int>[-1, 100, 20],
  'api_f_maxhps': <int>[-1, 100, 100],
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
      <int>[20],
    ],
  },
};

List<Object?> _shipData({required bool equipped}) => <Object?>[
  <String, Object?>{
    'api_id': 1,
    'api_ship_id': 1,
    'api_lv': 50,
    'api_nowhp': 100,
    'api_maxhp': 100,
    'api_slot': <int>[],
    'api_slot_ex': -1,
  },
  <String, Object?>{
    'api_id': 2,
    'api_ship_id': 2,
    'api_lv': 50,
    'api_nowhp': 20,
    'api_maxhp': 100,
    'api_slot': <int>[equipped ? 501 : -1],
    'api_slot_ex': -1,
  },
];

Map<String, Object?> _portData({required bool equipped}) => <String, Object?>{
  'api_basic': <String, Object?>{'api_member_id': 1001},
  'api_ship': _shipData(equipped: equipped),
  'api_deck_port': <Object?>[
    <String, Object?>{
      'api_id': 1,
      'api_name': 'Main',
      'api_ship': <int>[1, 2],
    },
  ],
  'api_slot_item': <Object?>[
    if (equipped) <String, Object?>{'api_id': 501, 'api_slotitem_id': 42},
  ],
};

final class _Fixture {
  _Fixture(
    this.account,
    this.state,
    this.battle,
    this.pipeline,
    this.capture,
    this.port,
    this.channel,
  );

  final AccountSession account;
  final GameStateController state;
  final BattleController battle;
  final GameApiEventPipeline pipeline;
  final GameCaptureController capture;
  final MethodChannelGameCapturePort port;
  final MethodChannel channel;
  var sequence = 0;
  static var channelSequence = 0;

  AdvanceWarningShip get warning => collectAdvanceWarningShips(
    state.state,
    damageControlStateTrusted: battle.isDamageControlStateTrusted,
  ).single;

  static Future<_Fixture> create({
    GameApiEnvelopeDecoder? decoder,
    int threshold = 64 * 1024,
  }) async {
    final account = AccountSession(initialMemberId: 1001);
    final state = GameStateController(
      accountSession: account,
      initialState: const GameState(
        memberId: 1001,
        hasPortData: true,
        hasEquipmentInventory: true,
        ships: <int, OwnedShip>{
          1: OwnedShip(
            id: 1,
            masterId: 1,
            level: 50,
            currentHp: 100,
            maxHp: 100,
          ),
          2: OwnedShip(
            id: 2,
            masterId: 2,
            level: 50,
            currentHp: 20,
            maxHp: 100,
            slotIds: <int>[501],
          ),
        },
        fleets: <Fleet>[
          Fleet(id: 1, name: 'Main', shipIds: <int>[1, 2]),
        ],
        slotItems: <int, OwnedSlotItem>{
          501: OwnedSlotItem(instanceId: 501, masterSlotItemId: 42),
        },
        combatState: CombatState.empty,
      ),
    );
    await state.initialize();
    final battle = BattleController(
      accountSession: account,
      gameState: () => state.state,
      waitForGameState: () => state.idle,
      onFriendlyHpUpdated: state.applyFriendlyBattleHp,
      onDamageControlConsumed: state.applyDamageControlConsumption,
      predictionExecutor: const ImmediateBattlePredictionExecutor(),
    );
    final pipeline = GameApiEventPipeline(
      consumers: <GameApiEventConsumer>[account, state, battle],
      decodeEnvelope: decoder,
      backgroundThresholdBytes: threshold,
      settleGameState: () async {
        await state.idle;
        await battle.idle;
        await state.idle;
      },
    );
    final capture = GameCaptureController(
      maxResponseBytes: 4096,
      onAcceptedEvent: pipeline.add,
      onCaptureInterrupted: () {
        pipeline.invalidateQueuedEvents();
        battle.invalidateCaptureContinuity();
      },
    );
    final channel = MethodChannel('test/reaudit_capture/${++channelSequence}');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'isSupported') return true;
          return null;
        });
    final port = MethodChannelGameCapturePort(channel: channel);
    await capture.attach(port, enabled: true);
    return _Fixture(account, state, battle, pipeline, capture, port, channel);
  }

  Map<String, Object?> native(
    String path,
    Object? data, {
    int result = 1,
    bool gate = false,
    int? document,
  }) => <String, Object?>{
    'version': 1,
    'kind': 'kcsapi_response',
    'method': 'POST',
    'path': path,
    'requestParams': <String, Object?>{'api_deck_id': '1'},
    'responseBody': jsonEncode(<String, Object?>{
      'api_result': result,
      'api_data': data,
      if (gate) 'gate': true,
    }),
    'statusCode': 200,
    'transport': 'xhr',
    'sourceOrigin': 'https://w01y.kancolle-server.com',
    'capturedAt': DateTime.utc(2026, 10, 23).toIso8601String(),
    'sequence': ++sequence,
    if (document != null) 'captureDocumentId': 'document-$document',
    if (document != null) 'captureDocumentStartedAtEpochMs': document * 1000,
  };

  Future<void> send(Map<String, Object?> payload) async {
    final delivered = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('onCaptureEvent', payload),
          ),
          (_) => delivered.complete(),
        );
    await delivered.future;
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> publish(
    String path,
    Object? data, {
    int result = 1,
    int? document,
  }) async {
    await send(native(path, data, result: result, document: document));
    await pipeline.idle;
  }

  Future<void> start({int? document}) =>
      publish('/kcsapi/api_req_map/start', _mapData, document: document);

  Future<void> dispose() async {
    await pipeline.idle;
    capture.dispose();
    port.dispose();
    battle.dispose();
    state.dispose();
    account.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  }
}
