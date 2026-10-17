import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/src/audio/game_audio_controller.dart';
import 'package:yahagi_kancolle_browser/src/audio/game_audio_store.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_models.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/capture/capture_mode_controller.dart';
import 'package:yahagi_kancolle_browser/src/capture/capture_mode_store.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_controller.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_port.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_api_decoder.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_api_event_pipeline.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/game_webview.dart';
import 'package:yahagi_kancolle_browser/src/settings/network_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/network_settings_store.dart';

import 'fixtures/kcsapi_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final recoveryCount in [1, 3]) {
    test('real prophet pipeline survives $recoveryCount WebView replacements '
        'with one Dart capture port and rejects retired documents', () async {
      final fixture = await _ProphetRecoveryFixture.create();
      addTearDown(fixture.dispose);
      await fixture.startAndPredict(damage: 4, node: 1);
      fixture.expectPrediction(damage: 4, node: 1);
      final captureSessionId = fixture.capture.captureSessionId;

      for (var recovery = 1; recovery <= recoveryCount; recovery++) {
        final retiredDocument = fixture.port.currentDocument;
        final originalSession = fixture.battle.session;
        fixture.port.replaceWebView();
        await fixture.startAndPredict(damage: 4 + recovery, node: recovery + 1);

        expect(fixture.capture.captureSessionId, captureSessionId);
        expect(fixture.port.configureCount, recovery + 1);
        expect(fixture.battle.session, isNot(same(originalSession)));
        fixture.expectPrediction(damage: 4 + recovery, node: recovery + 1);
        expect(
          fixture.state.state.masterShips[101]!.name,
          'Recovered document $recovery',
        );

        // Native callbacks can already be queued when the old WebView dies.
        // They retain the SAME capture session but an older document identity.
        final predictedBattle = fixture.battle.current;
        final gameState = fixture.state.state;
        final timingCount = fixture.observer.timings.length;
        fixture.port.deliverQueuedResponse(
          retiredDocument,
          start2Event,
          sequence: 101,
        );
        fixture.port.deliverQueuedResponse(
          retiredDocument,
          portEvent,
          sequence: 102,
        );
        fixture.port.deliverQueuedResponse(
          retiredDocument,
          _battleEvent(damage: 19),
          sequence: 103,
        );
        await fixture.pipeline.idle;

        expect(fixture.battle.current, same(predictedBattle));
        expect(fixture.state.state, same(gameState));
        expect(
          fixture.observer.timings.skip(timingCount).map((e) => e.success),
          [false, false, false],
        );
        fixture.expectPrediction(damage: 4 + recovery, node: recovery + 1);
      }

      expect(fixture.port.factoryCount, 1);
      expect(fixture.port.subscriptionCount, 1);
      expect(fixture.capture.capturedCount, 4 + recoveryCount * 7);
      expect(fixture.pipeline.pendingEventCount, 0);
    });
  }

  test('replacement cannot produce predictions until startup rebinds '
      'the same capture port to its new WebView', () async {
    final fixture = await _ProphetRecoveryFixture.create();
    addTearDown(fixture.dispose);
    await fixture.startAndPredict(damage: 4, node: 1);
    fixture.expectPrediction(damage: 4, node: 1);
    final priorPrediction = fixture.battle.current;

    fixture.port.replaceWebView();
    // Plain settings reconciliation intentionally uses the unchanged config.
    // This reproduces the old failure boundary: a port is not a WebView.
    await fixture.orchestrator.prepareCapture();
    expect(fixture.port.configureCount, 1);
    expect(fixture.port.emitResponse(start2Event), isFalse);
    expect(fixture.port.emitResponse(portEvent), isFalse);
    expect(fixture.port.emitResponse(mapStartEvent), isFalse);
    expect(fixture.port.emitResponse(_battleEvent(damage: 9)), isFalse);
    await fixture.pipeline.idle;
    expect(fixture.capture.capturedCount, 4);
    expect(fixture.battle.current, same(priorPrediction));

    await fixture.startAndPredict(damage: 9, node: 2);
    expect(fixture.port.configureCount, 2);
    expect(fixture.capture.capturedCount, 8);
    fixture.expectPrediction(damage: 9, node: 2);
  });

  test('recovered document start2 and battle emitted during navigation '
      'wait for capture installation', () async {
    final fixture = await _ProphetRecoveryFixture.create();
    addTearDown(fixture.dispose);
    await fixture.startAndPredict(damage: 4, node: 1);
    fixture.port.replaceWebView();

    final configureEntered = Completer<void>();
    final releaseConfigure = Completer<void>();
    fixture.port.configureEntered = configureEntered;
    fixture.port.configureGate = releaseConfigure.future;
    var navigationStarted = false;
    final recovery = fixture.startAndPredict(
      damage: 11,
      node: 3,
      onNavigate: () => navigationStarted = true,
    );
    await configureEntered.future;
    expect(navigationStarted, isFalse);
    expect(fixture.port.emitResponse(start2Event), isFalse);
    expect(fixture.capture.capturedCount, 4);

    releaseConfigure.complete();
    await recovery;
    expect(navigationStarted, isTrue);
    expect(fixture.port.configureCount, 2);
    expect(fixture.capture.capturedCount, 8);
    fixture.expectPrediction(damage: 11, node: 3);
  });
}

final class _ProphetRecoveryFixture {
  _ProphetRecoveryFixture._({
    required this.port,
    required this.state,
    required this.battle,
    required this.pipeline,
    required this.observer,
    required this.capture,
    required this.orchestrator,
    required this.network,
    required this.mode,
    required this.audio,
  });

  final _GenerationBoundCapturePort port;
  final GameStateController state;
  final BattleController battle;
  final GameApiEventPipeline pipeline;
  final _RecordingPipelineObserver observer;
  final GameCaptureController capture;
  final DefaultGameSurfaceStartupOrchestrator orchestrator;
  final NetworkSettingsController network;
  final CaptureModeController mode;
  final GameAudioController audio;

  static Future<_ProphetRecoveryFixture> create() async {
    final port = _GenerationBoundCapturePort();
    final state = GameStateController();
    await state.initialize();
    // Use production defaults, including isolate decoding and prediction.
    final battle = BattleController(
      gameState: () => state.state,
      waitForGameState: () => state.idle,
      onFriendlyHpUpdated: state.applyFriendlyBattleHp,
    );
    final observer = _RecordingPipelineObserver();
    final pipeline = GameApiEventPipeline(
      consumers: [state, battle],
      observer: observer,
      settleGameState: () async {
        await state.idle;
        await battle.idle;
        await state.idle;
      },
    );
    final capture = GameCaptureController(onAcceptedEvent: pipeline.add);
    final mode = await CaptureModeController.load(
      SharedPreferencesCaptureModeStore(),
    );
    final audio = await GameAudioController.load(
      SharedPreferencesGameAudioStore(),
    );
    final network = NetworkSettingsController(
      store: SharedPreferencesNetworkSettingsStore(),
    );
    final orchestrator = DefaultGameSurfaceStartupOrchestrator(
      networkSettingsController: network,
      captureModeController: mode,
      audioController: audio,
      gameCaptureController: capture,
      frameRateSettingsController: null,
      capturePortFactory: () {
        port.factoryCount++;
        return port;
      },
    );
    return _ProphetRecoveryFixture._(
      port: port,
      state: state,
      battle: battle,
      pipeline: pipeline,
      observer: observer,
      capture: capture,
      orchestrator: orchestrator,
      network: network,
      mode: mode,
      audio: audio,
    );
  }

  Future<void> startAndPredict({
    required int damage,
    required int node,
    void Function()? onNavigate,
  }) async {
    await orchestrator.runCaptureStartup(
      waitForSurface: () async {},
      isActive: () => true,
      navigate: () async {
        onNavigate?.call();
        final masters = Map<String, Object?>.from(
          GameApiDecoder.decodeEventData(start2Event) as Map,
        );
        masters['api_mst_ship'] = [
          for (final raw in masters['api_mst_ship'] as List)
            {
              ...raw as Map,
              if (raw['api_id'] == 101)
                'api_name': 'Recovered document ${port.generation}',
            },
        ];
        final map = Map<String, Object?>.from(
          GameApiDecoder.decodeEventData(mapStartEvent) as Map,
        );
        map['api_no'] = node;
        // The restarted script's sequence resets to 1. Send a burst to exercise
        // the real reducer -> asynchronous prediction -> HP writeback queue.
        for (final event in [
          kcsapiEvent(start2Event.path, masters),
          portEvent,
          kcsapiEvent(
            mapStartEvent.path,
            map,
            requestParams: mapStartEvent.requestParams,
          ),
          _battleEvent(damage: damage),
        ]) {
          expect(
            port.emitResponse(event),
            isTrue,
            reason: 'generation ${port.generation}: ${event.path}',
          );
        }
      },
    );
    await pipeline.idle;
  }

  void expectPrediction({required int damage, required int node}) {
    expect(capture.state, GameCaptureState.capturing);
    expect(capture.errorMessage, isNull);
    expect(state.lastError, isNull);
    expect(battle.lastError, isNull);
    expect(battle.current, isNotNull);
    expect(battle.current!.displayStage, BattleDisplayStage.battle);
    expect(battle.current!.context.node, node);
    expect(battle.current!.enemyMain.single.currentHp, 20 - damage);
    expect(battle.current!.friendMain.map((ship) => ship.currentHp), [25, 8]);
    expect(state.state.ships[9001]!.currentHp, 25);
    expect(state.state.combatState.currentNode, node);
    expect(battle.session!.isConfirmed, isTrue);
  }

  Future<void> dispose() async {
    await pipeline.idle;
    capture.dispose();
    orchestrator.dispose();
    battle.dispose();
    state.dispose();
    audio.dispose();
    mode.dispose();
    network.dispose();
    await port.closed;
  }
}

CapturedApiEvent _battleEvent({required int damage}) =>
    kcsapiEvent('/kcsapi/api_req_sortie/battle', {
      'api_deck_id': 1,
      'api_formation': [1, 1, 1],
      'api_f_nowhps': [28, 8],
      'api_f_maxhps': [30, 15],
      'api_e_nowhps': [20],
      'api_e_maxhps': [20],
      'api_ship_ke': [501],
      'api_ship_lv': [1],
      'api_hougeki1': {
        'api_at_eflag': [0, 1],
        'api_at_list': [0, 0],
        'api_df_list': [
          [0],
          [0],
        ],
        'api_damage': [
          [damage],
          [3],
        ],
      },
    });

typedef _CaptureDocument = ({String sessionId, String id, double startedAt});

// Only the native WebView boundary is simulated. A Dart port/stream survives
// renderer death, but the document-start script belongs to one WebView instance.
final class _GenerationBoundCapturePort implements GameCapturePort {
  final StreamController<CapturedApiEvent> _events =
      StreamController<CapturedApiEvent>.broadcast(sync: true);
  int generation = 0;
  int? _installedGeneration;
  _CaptureDocument? _installedDocument;
  int _sequence = 0;
  int configureCount = 0;
  int factoryCount = 0;
  int subscriptionCount = 0;
  Completer<void>? configureEntered;
  Future<void>? configureGate;
  Future<void> closed = Future<void>.value();

  _CaptureDocument get currentDocument => _installedDocument!;

  @override
  Stream<CapturedApiEvent> get events {
    subscriptionCount++;
    return _events.stream;
  }

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<void> configure({
    required bool enabled,
    required String script,
  }) async {
    configureCount++;
    configureEntered?.complete();
    configureEntered = null;
    await configureGate;
    if (!enabled) {
      _installedGeneration = null;
      _installedDocument = null;
      return;
    }
    final sessionId = RegExp(
      "const captureSessionId = '([^']+)'",
    ).firstMatch(script)?.group(1);
    if (sessionId == null) throw StateError('no capture session in script');
    _installedGeneration = generation;
    _installedDocument = (
      sessionId: sessionId,
      id: 'webview-document-$generation',
      startedAt:
          DateTime.utc(2026, 9, 22).millisecondsSinceEpoch.toDouble() +
          generation * 1000,
    );
    _sequence = 0;
  }

  void replaceWebView() => generation++;

  bool emitResponse(CapturedApiEvent event) {
    if (_installedGeneration != generation) return false;
    deliverQueuedResponse(currentDocument, event, sequence: ++_sequence);
    return true;
  }

  void deliverQueuedResponse(
    _CaptureDocument document,
    CapturedApiEvent event, {
    required int sequence,
  }) {
    // Cross the actual Android wire decoder too, rather than providing a
    // prepared envelope that would bypass the pipeline's decoding path.
    _events.add(
      AndroidCaptureEvent.decode({
            'version': 1,
            'kind': 'kcsapi_response',
            'method': event.method,
            'path': event.path,
            'requestParams': event.requestParams,
            'responseBodyBytes': utf8.encode('svdata=${event.responseBody}'),
            'statusCode': 200,
            'transport': 'xhr',
            'sourceOrigin': event.sourceOrigin,
            'capturedAt': DateTime.fromMillisecondsSinceEpoch(
              document.startedAt.toInt() + sequence,
              isUtc: true,
            ).toIso8601String(),
            'sequence': sequence,
            'captureSessionId': document.sessionId,
            'captureDocumentId': document.id,
            'captureDocumentStartedAtEpochMs': document.startedAt,
          })
          as CapturedApiEvent,
    );
  }

  @override
  void dispose() => closed = _events.close();
}

final class _RecordingPipelineObserver implements GameApiPipelineObserver {
  final List<GameApiTiming> timings = [];

  @override
  void onCompleted(GameApiTiming timing) => timings.add(timing);
}
