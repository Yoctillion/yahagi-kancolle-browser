import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/account/account_session.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/prediction/battle_prediction_executor.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/bridge/native_game_capture_script.dart';
import 'package:yahagi_kancolle_browser/src/capture/advance_warning_details.dart';
import 'package:yahagi_kancolle_browser/src/capture/android_game_capture_port.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_controller.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_api_event_pipeline.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final path in <String>[
    '/kcsapi/api_port/port',
    '/kcsapi/api_start2/getData',
    '/kcsapi/api_req_map/next',
  ]) {
    test('bootstrap port anchors its document against older $path', () async {
      final fixture = await _BootstrapFixture.create();
      addTearDown(fixture.dispose);
      await fixture.exhaustWithoutLoginStart();
      await fixture.interrupt();
      await fixture.next();
      fixture.expectSpent(trusted: false);
      expect(
        fixture.accepted.where(
          (event) => event.path == '/kcsapi/api_start2/getData',
        ),
        isEmpty,
      );
      final beforeAccount = fixture.account.current;
      final beforeState = fixture.state.state;
      final beforeCaptureCount = fixture.capture.capturedCount;
      final beforeWarningGeneration = fixture.battle.warningSession.generation;
      final data = switch (path) {
        '/kcsapi/api_port/port' => _portData(memberId: 72002, equipped: true),
        '/kcsapi/api_req_map/next' => _nodeData(99),
        _ => <String, Object?>{},
      };

      await fixture.publish(path, data, document: 1, sequence: 900001);

      expect(fixture.account.current, same(beforeAccount));
      expect(fixture.state.state, same(beforeState));
      expect(fixture.capture.capturedCount, beforeCaptureCount);
      expect(fixture.battle.warningSession.generation, beforeWarningGeneration);
      fixture.expectSpent(trusted: false);
      await fixture.next();
      fixture.expectSpent(trusted: false);
    });
  }

  test('bootstrap newer-document login can reuse consumed instances', () async {
    final fixture = await _BootstrapFixture.create();
    addTearDown(fixture.dispose);
    await fixture.exhaustWithoutLoginStart();
    await fixture.interrupt();
    await fixture.next();
    fixture.expectSpent(trusted: false);
    final captureSession = fixture.capture.captureSessionId;

    await fixture.publish(
      '/kcsapi/api_start2/getData',
      <String, Object?>{},
      document: 3,
    );

    expect(fixture.account.current.isKnown, isFalse);
    fixture.document = 3;
    await fixture.publish(
      '/kcsapi/api_port/port',
      _portData(memberId: 72002, equipped: true),
    );
    expect(fixture.capture.captureSessionId, captureSession);
    expect(fixture.account.current.memberId, 72002);
    expect(fixture.state.state.memberId, 72002);
    expect(fixture.state.state.combatState.isActive, isFalse);
    expect(
      fixture.state.state.slotItems.keys,
      unorderedEquals(<int>[501, 502, 601, 602]),
    );
    expect(fixture.state.state.ships[102]!.slotIds, <int>[501]);
    expect(fixture.state.state.ships[102]!.extraSlotId, 502);
    expect(fixture.state.state.ships[103]!.slotIds, <int>[601]);
    expect(fixture.state.state.ships[103]!.extraSlotId, 602);

    await fixture.publish('/kcsapi/api_req_map/start', _nodeData(1));

    expect(fixture.battle.isDamageControlStateTrusted, isTrue);
    expect(fixture.warnings, hasLength(2));
    for (final warning in fixture.warnings) {
      expect(warning.damageControlStatus, AdvanceDamageControlStatus.equipped);
      expect(warning.remainingDamageControls, <int, int>{42: 1, 43: 1});
    }
    await fixture.fight();
    await fixture.next();
    fixture.expectSpent(memberId: 72002, trusted: true);
  });

  test('bootstrap legacy null-document capture remains compatible', () async {
    final fixture = await _BootstrapFixture.create(legacy: true);
    addTearDown(fixture.dispose);
    await fixture.exhaustWithoutLoginStart();
    expect(
      fixture.accepted.map((event) => event.captureDocumentId),
      everyElement(isNull),
    );
    await fixture.interrupt();
    await fixture.next();
    fixture.expectSpent(trusted: false);

    await fixture.publish(
      '/kcsapi/api_port/port',
      _portData(memberId: 71001, equipped: false, healthy: true),
    );

    expect(fixture.account.current.memberId, 71001);
    expect(fixture.state.state.combatState.isActive, isFalse);
    expect(fixture.state.state.slotItems, isEmpty);
    expect(fixture.warnings, isEmpty);
    await fixture.publish('/kcsapi/api_req_map/start', _nodeData(1));
    expect(fixture.battle.isDamageControlStateTrusted, isTrue);
    expect(fixture.warnings, isEmpty);
    expect(fixture.state.state.ships[102]!.currentHp, 100);
    expect(fixture.state.state.ships[103]!.currentHp, 100);
  });
}

final class _BootstrapFixture {
  _BootstrapFixture({required this.legacy});

  final bool legacy;
  final account = AccountSession();
  final accepted = <CapturedApiEvent>[];
  late final GameStateController state;
  late final BattleController battle;
  late final GameApiEventPipeline pipeline;
  late final GameCaptureController capture;
  late final MethodChannel channel;
  late final MethodChannelGameCapturePort port;
  var document = 2;
  var sequence = 0;
  var node = 1;
  static var _channelSequence = 0;

  List<AdvanceWarningShip> get warnings => collectAdvanceWarningShips(
    state.state,
    damageControlStateTrusted: battle.isDamageControlStateTrusted,
  );

  static Future<_BootstrapFixture> create({bool legacy = false}) async {
    final fixture = _BootstrapFixture(legacy: legacy);
    fixture.state = GameStateController(accountSession: fixture.account);
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
      decodeEnvelope: (body) async =>
          Map<String, Object?>.from(jsonDecode(body) as Map),
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
      'test/bootstrap_document/${++_channelSequence}',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(fixture.channel, (call) async {
          if (call.method == 'isSupported') return true;
          return null;
        });
    fixture.port = MethodChannelGameCapturePort(channel: fixture.channel);
    await fixture.capture.attach(
      fixture.port,
      enabled: true,
      script: nativeGameCaptureScript,
    );
    return fixture;
  }

  Future<void> publish(
    String path,
    Object? data, {
    int? document,
    int? sequence,
  }) async {
    final sourceDocument = document ?? this.document;
    final sourceSequence = sequence ?? ++this.sequence;
    await send(<String, Object?>{
      'version': 1,
      'kind': 'kcsapi_response',
      'method': 'POST',
      'path': path,
      'requestParams': <String, Object?>{'api_deck_id': '1'},
      'responseBody': jsonEncode(<String, Object?>{
        'api_result': 1,
        'api_data': data,
      }),
      'statusCode': 200,
      'transport': 'xhr',
      'sourceOrigin': 'https://w01y.kancolle-server.com',
      'capturedAt': DateTime.utc(
        2026,
        10,
        23,
      ).add(Duration(milliseconds: sourceSequence)).toIso8601String(),
      'sequence': sourceSequence,
      'captureSessionId': capture.captureSessionId,
      if (!legacy) 'captureDocumentId': '${sourceDocument * 1000}:bootstrap',
      if (!legacy) 'captureDocumentStartedAtEpochMs': sourceDocument * 1000,
    });
    await pipeline.idle;
    expect(state.lastError, isNull);
    expect(battle.lastError, isNull);
  }

  Future<void> send(Map<String, Object?> payload) async {
    final delivered = Completer<void>();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
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

  Future<void> exhaustWithoutLoginStart() async {
    await publish(
      '/kcsapi/api_port/port',
      _portData(memberId: 71001, equipped: true),
    );
    expect(accepted, hasLength(1));
    expect(accepted.single.path, '/kcsapi/api_port/port');
    expect(account.current.memberId, 71001);
    expect(state.state.memberId, 71001);
    await publish('/kcsapi/api_req_map/start', _nodeData(node));
    expect(battle.isDamageControlStateTrusted, isTrue);
    expect(warnings, hasLength(2));
    expect(
      warnings.every((warning) => warning.hasConfirmedDamageControl),
      isTrue,
    );
    await fight();
    await next();
    expectSpent(trusted: true);
  }

  Future<void> fight() async {
    await publish('/kcsapi/api_req_sortie/battle', <String, Object?>{
      'api_deck_id': 1,
      'api_f_nowhps': <int>[-1, 100, 20, 20],
      'api_f_maxhps': <int>[-1, 100, 100, 100],
      'api_e_nowhps': <int>[-1, 20],
      'api_e_maxhps': <int>[-1, 20],
      'api_ship_ke': <int>[-1, 501],
      'api_hougeki1': <String, Object?>{
        'api_at_eflag': List<int>.filled(6, 1),
        'api_at_list': List<int>.filled(6, 0),
        'api_df_list': <Object?>[
          for (final target in <int>[1, 2])
            for (var hit = 0; hit < 3; hit++) <int>[target],
        ],
        'api_damage': <Object?>[
          for (var target = 0; target < 2; target++)
            for (final damage in <int>[20, 20, 80]) <int>[damage],
        ],
      },
    });
    for (final shipId in <int>[102, 103]) {
      expect(
        battle.current!.friendShips
            .singleWhere((ship) => ship.ownedShipId == shipId)
            .usedDamageControlItemIds,
        <int>[42, 43],
      );
    }
  }

  Future<void> next() => publish('/kcsapi/api_req_map/next', _nodeData(++node));

  Future<void> interrupt() async {
    final before = capture.continuityGeneration;
    await send(<String, Object?>{'version': 1, 'kind': 'capture_interrupted'});
    await pipeline.idle;
    expect(capture.continuityGeneration, before + 1);
    expect(battle.isDamageControlStateTrusted, isFalse);
  }

  void expectSpent({int memberId = 71001, required bool trusted}) {
    expect(account.current.memberId, memberId);
    expect(state.state.memberId, memberId);
    expect(state.state.combatState.isActive, isTrue);
    expect(state.state.combatState.currentNode, node);
    expect(state.state.slotItems, isEmpty);
    expect(battle.isDamageControlStateTrusted, trusted);
    expect(battle.warningSession.isMuted, isFalse);
    expect(
      warnings.map((warning) => warning.ship.id),
      unorderedEquals(<int>[102, 103]),
    );
    for (final warning in warnings) {
      expect(warning.ship.currentHp, 20);
      expect(warning.ship.slotIds, <int>[-1]);
      expect(warning.ship.extraSlotId, -1);
      expect(warning.remainingDamageControls, isEmpty);
      expect(warning.hasConfirmedDamageControl, isFalse);
      expect(
        warning.damageControlStatus,
        trusted
            ? AdvanceDamageControlStatus.missing
            : AdvanceDamageControlStatus.unknown,
      );
    }
  }

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

Map<String, Object?> _nodeData(int node) => <String, Object?>{
  'api_maparea_id': 1,
  'api_mapinfo_no': 1,
  'api_no': node,
};

Map<String, Object?> _portData({
  required int memberId,
  required bool equipped,
  bool healthy = false,
}) => <String, Object?>{
  'api_basic': <String, Object?>{'api_member_id': memberId},
  'api_ship': <Object?>[
    for (final shipId in <int>[101, 102, 103])
      <String, Object?>{
        'api_id': shipId,
        'api_ship_id': shipId,
        'api_lv': 50,
        'api_nowhp': healthy || shipId == 101 ? 100 : 20,
        'api_maxhp': 100,
        'api_slot': <int>[
          if (shipId != 101) equipped ? 501 + (shipId - 102) * 100 : -1,
        ],
        'api_slot_ex': shipId != 101 && equipped
            ? 502 + (shipId - 102) * 100
            : -1,
      },
  ],
  'api_deck_port': <Object?>[
    <String, Object?>{
      'api_id': 1,
      'api_name': 'Main',
      'api_ship': <int>[101, 102, 103],
    },
  ],
  'api_slot_item': <Object?>[
    if (equipped)
      for (final instanceId in <int>[501, 502, 601, 602])
        <String, Object?>{
          'api_id': instanceId,
          'api_slotitem_id': instanceId.isOdd ? 42 : 43,
        },
  ],
};
