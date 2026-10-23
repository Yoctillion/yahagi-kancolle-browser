import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/main.dart';
import 'package:yahagi_kancolle_browser/src/account/account_session.dart';
import 'package:yahagi_kancolle_browser/src/audio/game_audio_controller.dart';
import 'package:yahagi_kancolle_browser/src/audio/game_audio_store.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/prediction/battle_prediction_executor.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/browser/gadget_bypass_channel.dart';
import 'package:yahagi_kancolle_browser/src/browser/gadget_bypass_controller.dart';
import 'package:yahagi_kancolle_browser/src/browser/gadget_bypass_store.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_browser_controller.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_toolbar_controller.dart';
import 'package:yahagi_kancolle_browser/src/capture/capture_mode_controller.dart';
import 'package:yahagi_kancolle_browser/src/capture/capture_mode_store.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_controller.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_port.dart';
import 'package:yahagi_kancolle_browser/src/fleet/resource_grid.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_api_event_pipeline.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/notice/game_info_notice_controller.dart';
import 'package:yahagi_kancolle_browser/src/prototype_status_controller.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_completion_drawer.dart';
import 'package:yahagi_kancolle_browser/src/settings/display_mode_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/display_mode_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/network_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/network_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/ui_display_size.dart';
import 'package:yahagi_kancolle_browser/src/widgets/top_notice.dart';

import 'damage_control_briefing_sync_test.dart' show createSortieState;
import 'fixtures/kcsapi_fixtures.dart';

const _damageMessage = '大破舰已携带损管';
const _damageAlertChannel = MethodChannel(
  'app.yahagi.kancollebrowser/battle_damage_alert',
);

void main() {
  for (final uiSize in <UiDisplaySize>[
    UiDisplaySize.normal,
    UiDisplaySize.compact,
  ]) {
    testWidgets(
      'real $uiSize header reserves notice height before its first notice and after toolbar changes',
      (tester) async {
        final fixture = await _RealHeaderFixture.create(tester, uiSize: uiSize);

        expect(find.byType(CompactResourceBar), findsOneWidget);
        expect(find.byKey(const Key('quest-completion-drawer')), findsNothing);
        for (final toolbarVisible in <bool>[false, true, false]) {
          if (toolbarVisible) {
            fixture.toolbar.reveal();
          } else {
            fixture.toolbar.collapse();
          }
          await _pumpHeader(tester);
          expect(
            tester.getSize(fixture.slot).height,
            closeTo(topHeaderHeight(uiSize) - 1, 0.01),
            reason: 'An empty real header must already fit its 34px notice.',
          );
          final shown = QuestCompletionDrawerHost.showDamageControlNotice(
            fixture.slotContext(tester),
            _damageMessage,
          );
          await tester.pump();
          expect(await shown, isTrue, reason: 'toolbar=$toolbarVisible');
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text(_damageMessage), findsOneWidget);
          expect(find.byType(AlertDialog), findsNothing);
          expect(tester.getSize(_capsule()).height, 34);
          QuestCompletionDrawerHost.removeDamageControlNotice(
            fixture.slotContext(tester),
          );
          await _pumpHeader(tester);
          expect(find.text(_damageMessage), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );

    for (final equipmentId in <int>[42, 43]) {
      for (final postBattle in <bool>[false, true]) {
        testWidgets(
          'real $uiSize header first smart notice gear=$equipmentId postBattle=$postBattle stays gold for ten seconds',
          (tester) async {
            final fixture = await _RealHeaderFixture.create(
              tester,
              uiSize: uiSize,
              equipmentId: equipmentId,
              postBattle: postBattle,
            );
            expect(find.byType(CompactResourceBar), findsOneWidget);
            expect(
              find.byKey(const Key('quest-completion-drawer')),
              findsNothing,
            );
            expect(find.byType(AlertDialog), findsNothing);
            expect(fixture.notices.notices, isEmpty);

            await fixture.start(tester);
            expect(fixture.battle.isDamageControlStateTrusted, isTrue);
            if (postBattle) {
              expect(find.text(_damageMessage), findsNothing);
              await fixture.finishBattle(tester);
            }

            expect(find.byType(AlertDialog), findsNothing);
            expect(find.text(_damageMessage), findsOneWidget);
            expect(fixture.state.state.ships[1002]!.currentHp, 20);
            expect(
              fixture.state.state.slotItems[501]!.masterSlotItemId,
              equipmentId,
            );
            final capsule = _capsule();
            expect(tester.getSize(capsule).height, 34);
            final decoration =
                tester.widget<Container>(capsule).decoration! as BoxDecoration;
            expect(
              (decoration.border! as Border).top.color,
              const Color(0xffd4a85f).withValues(alpha: 0.35),
            );
            await tester.pump(const Duration(seconds: 9));
            expect(find.text(_damageMessage), findsOneWidget);
            expect(find.byType(AlertDialog), findsNothing);
            await tester.pump(const Duration(seconds: 2));
            await _pumpHeader(tester);
            expect(find.text(_damageMessage), findsNothing);
            expect(find.byType(AlertDialog), findsNothing);
            expect(fixture.battle.warningSession.isMuted, isFalse);
            expect(fixture.state.lastError, isNull);
            expect(fixture.battle.lastError, isNull);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets(
      'real $uiSize header shares capsule geometry across quest improvement development and damage control',
      (tester) async {
        final fixture = await _RealHeaderFixture.create(tester, uiSize: uiSize);
        final geometries = <({Size contentSize, TextStyle? style})>[];
        for (final kind in <String>[
          'quest',
          'improvement',
          'development',
          'damage',
        ]) {
          final context = fixture.slotContext(tester);
          switch (kind) {
            case 'quest':
              QuestCompletionDrawerHost.show(context, _damageMessage);
            case 'improvement':
            case 'development':
              fixture.gameInfo.postNotice(
                message: _damageMessage,
                tone: TopNoticeTone.success,
              );
            case 'damage':
              final shown = QuestCompletionDrawerHost.showDamageControlNotice(
                context,
                _damageMessage,
              );
              await tester.pump();
              expect(await shown, isTrue);
          }
          await _pumpHeader(tester);
          final capsule = _capsule();
          final size = tester.getSize(capsule);
          final text = tester.widget<Text>(find.text(_damageMessage));
          final icons = find.descendant(
            of: capsule,
            matching: find.byType(Icon),
          );
          expect(icons, kind == 'damage' ? findsNothing : findsOneWidget);
          expect(size.height, 34, reason: kind);
          expect(text.style?.fontSize, 13, reason: kind);
          expect(
            tester.widget<Container>(capsule).padding,
            const EdgeInsets.symmetric(horizontal: 10),
            reason: kind,
          );
          final switcher = tester.widget<AnimatedSwitcher>(
            find
                .ancestor(of: capsule, matching: find.byType(AnimatedSwitcher))
                .first,
          );
          expect(
            switcher.duration,
            const Duration(milliseconds: 240),
            reason: kind,
          );
          expect(
            switcher.reverseDuration,
            const Duration(milliseconds: 200),
            reason: kind,
          );
          geometries.add((
            contentSize: Size(
              size.width - (kind == 'damage' ? 0 : 24),
              size.height,
            ),
            style: text.style,
          ));
          final decoration =
              tester.widget<Container>(capsule).decoration! as BoxDecoration;
          expect(
            decoration.borderRadius,
            BorderRadius.circular(8),
            reason: kind,
          );
          QuestCompletionDrawerHost.hide(context);
          QuestCompletionDrawerHost.removeDamageControlNotice(context);
          await _pumpHeader(tester);
        }
        for (final geometry in geometries.skip(1)) {
          expect(geometry.contentSize, geometries.first.contentSize);
          expect(geometry.style, geometries.first.style);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Finder _capsule() => find
    .ancestor(of: find.text(_damageMessage), matching: find.byType(Container))
    .first;

Future<void> _pumpHeader(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

final class _RealHeaderFixture {
  _RealHeaderFixture({
    required this.state,
    required this.battle,
    required this.pipeline,
    required this.capture,
    required this.port,
    required this.toolbar,
    required this.notices,
    required this.gameInfo,
    required this.postBattle,
  });

  final GameStateController state;
  final BattleController battle;
  final GameApiEventPipeline pipeline;
  final GameCaptureController capture;
  final _CapturePort port;
  final GameToolbarController toolbar;
  final TopNoticeController notices;
  final GameInfoNoticeController gameInfo;
  final bool postBattle;
  int _sequence = 0;

  Finder get slot => find.byType(QuestCompletionHeaderSlot);

  BuildContext slotContext(WidgetTester tester) => tester.element(slot);

  static Future<_RealHeaderFixture> create(
    WidgetTester tester, {
    required UiDisplaySize uiSize,
    int equipmentId = 43,
    bool postBattle = false,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final previousTimerSetting = GameStateController.disableTimerForTest;
    GameStateController.disableTimerForTest = true;
    addTearDown(
      () => GameStateController.disableTimerForTest = previousTimerSetting,
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 850);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_damageAlertChannel, (_) async => null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_damageAlertChannel, null);
    });

    final account = AccountSession(initialMemberId: 1001);
    final state = GameStateController(
      accountSession: account,
      initialState: createSortieState(
        ships: <OwnedShip>[
          const OwnedShip(
            id: 1001,
            masterId: 101,
            level: 50,
            currentHp: 100,
            maxHp: 100,
          ),
          OwnedShip(
            id: 1002,
            masterId: 102,
            level: 50,
            currentHp: postBattle ? 100 : 20,
            maxHp: 100,
            slotIds: const <int>[501],
          ),
        ],
        slotItems: <OwnedSlotItem>[
          OwnedSlotItem(instanceId: 501, masterSlotItemId: equipmentId),
        ],
      ).copyWith(memberId: 1001, hasEquipmentInventory: true),
    );
    await state.initialize();
    final safety = await SafetySettingsController.load(
      MemorySafetySettingsStore(),
    );
    await safety.setAdvanceWarningDisplayMode(AdvanceWarningDisplayMode.smart);
    await safety.setAdvanceWarningTimings(
      postBattle
          ? AdvanceWarningTimingSettings.battleOnly
          : AdvanceWarningTimingSettings.advanceOnly,
    );
    final layout = await LayoutSettingsController.load(
      SharedPreferencesLayoutSettingsStore(),
    );
    await layout.setLocaleCode('zh');
    await layout.setUiDisplaySize(uiSize);
    final notices = TopNoticeController();
    final gameInfo = GameInfoNoticeController(
      stateProvider: () => state.state,
      layoutSettingsController: layout,
      topNoticeController: notices,
      accountSession: account,
    );
    final battle = BattleController(
      accountSession: account,
      gameState: () => state.state,
      waitForGameState: () => state.idle,
      onFriendlyHpUpdated: state.applyFriendlyBattleHp,
      onDamageControlConsumed: state.applyDamageControlConsumption,
      predictionExecutor: const ImmediateBattlePredictionExecutor(),
    );
    final pipeline = GameApiEventPipeline(
      consumers: <GameApiEventConsumer>[account, state, battle, gameInfo],
      settleGameState: () async {
        await state.idle;
        await battle.idle;
        await state.idle;
      },
    );
    final capture = GameCaptureController(onAcceptedEvent: pipeline.add);
    final port = _CapturePort();
    await capture.attach(port, enabled: true);
    final toolbar = GameToolbarController();
    final browser = GameBrowserController();
    final status = PrototypeStatusController();
    final network = NetworkSettingsController(
      store: SharedPreferencesNetworkSettingsStore(),
    );
    final bypass = GadgetBypassController(
      store: SharedPreferencesGadgetBypassStore(),
      port: MethodChannelGadgetBypassPort(),
    );
    final display = await DisplayModeController.load(MemoryDisplayModeStore());
    final mode = await CaptureModeController.load(
      SharedPreferencesCaptureModeStore(),
    );
    final audio = await GameAudioController.load(
      SharedPreferencesGameAudioStore(),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpHeader(tester);
      capture.dispose();
      port.dispose();
      gameInfo.dispose();
      for (final notifier in <ChangeNotifier>[
        battle,
        state,
        toolbar,
        browser,
        status,
        network,
        bypass,
        safety,
        display,
        mode,
        audio,
        notices,
        layout,
        account,
      ]) {
        notifier.dispose();
      }
    });
    await tester.pumpWidget(
      YahagiApp(
        layoutSettingsController: layout,
        networkSettingsController: network,
        gadgetBypassController: bypass,
        safetySettingsController: safety,
        displayModeController: display,
        controller: status,
        browserController: browser,
        captureModeController: mode,
        gameCaptureController: capture,
        gameApiEventPipeline: pipeline,
        gameStateController: state,
        battleController: battle,
        audioController: audio,
        toolbarController: toolbar,
        headerNoticeController: notices,
        gameInfoNoticeController: gameInfo,
        gameSurface: const SizedBox.expand(
          key: Key('real-header-game-surface'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));
    return _RealHeaderFixture(
      state: state,
      battle: battle,
      pipeline: pipeline,
      capture: capture,
      port: port,
      toolbar: toolbar,
      notices: notices,
      gameInfo: gameInfo,
      postBattle: postBattle,
    );
  }

  Future<void> start(WidgetTester tester) => publish(
    tester,
    '/kcsapi/api_req_map/start',
    const <String, Object?>{
      'api_maparea_id': 1,
      'api_mapinfo_no': 1,
      'api_no': 1,
      'api_next': 1,
    },
    requestParams: const <String, Object?>{'api_deck_id': '1'},
  );

  Future<void> finishBattle(WidgetTester tester) async {
    await publish(tester, '/kcsapi/api_req_sortie/battle', <String, Object?>{
      'api_deck_id': 1,
      'api_f_nowhps': const <int>[-1, 100, 100],
      'api_f_maxhps': const <int>[-1, 100, 100],
      'api_e_nowhps': const <int>[-1, 20],
      'api_e_maxhps': const <int>[-1, 20],
      'api_ship_ke': const <int>[-1, 501],
      'api_hougeki1': <String, Object?>{
        'api_at_eflag': const <int>[1],
        'api_at_list': const <int>[0],
        'api_df_list': const <Object?>[
          <int>[1],
        ],
        'api_damage': const <Object?>[
          <num>[80],
        ],
      },
    });
    await publish(
      tester,
      '/kcsapi/api_req_sortie/battleresult',
      const <String, Object?>{'api_win_rank': 'A', 'api_mvp': 1},
    );
  }

  Future<void> publish(
    WidgetTester tester,
    String path,
    Object? data, {
    Map<String, Object?> requestParams = const <String, Object?>{},
  }) async {
    port.add(
      kcsapiEvent(
        path,
        data,
        sequence: ++_sequence,
        requestParams: requestParams,
      ),
    );
    await pipeline.idle;
    await _pumpHeader(tester);
  }
}

final class _CapturePort implements GameCapturePort {
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
