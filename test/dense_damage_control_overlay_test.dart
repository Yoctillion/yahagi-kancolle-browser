import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/main.dart';
import 'package:yahagi_kancolle_browser/src/audio/game_audio_controller.dart';
import 'package:yahagi_kancolle_browser/src/audio/game_audio_store.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_browser_controller.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_surface_viewport.dart';
import 'package:yahagi_kancolle_browser/src/browser/gadget_bypass_channel.dart';
import 'package:yahagi_kancolle_browser/src/browser/gadget_bypass_controller.dart';
import 'package:yahagi_kancolle_browser/src/browser/gadget_bypass_store.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_toolbar_controller.dart';
import 'package:yahagi_kancolle_browser/src/capture/capture_mode_controller.dart';
import 'package:yahagi_kancolle_browser/src/capture/capture_mode_store.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_controller.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
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

const _damageMessage = '大破舰已携带损管';
const _phoneLandscape = Size(844, 390);
const _phonePortrait = Size(390, 844);
const _overlay = Key('minimal-notice-overlay');

void main() {
  for (final position in MinimalResourcePosition.values) {
    final name = position == MinimalResourcePosition.panel
        ? 'minimal game page shows damage control in an overlay without moving the game'
        : 'minimal game page with ${position.name} resources shows damage control in an overlay without moving the game';
    testWidgets(name, (tester) async {
      await _pumpMinimalApp(
        tester,
        size: _phoneLandscape,
        resourcePosition: position,
      );
      await _expectOverlayNotice(tester, gameSurfaceLaidOut: true);
    });
  }

  testWidgets(
    'minimal workspace page shows damage control in an overlay instead of its header',
    (tester) async {
      await _pumpMinimalApp(tester, size: _phoneLandscape);
      final fleet = find.byKey(const Key('workspace-nav-fleet'));
      await tester.ensureVisible(fleet);
      await tester.tap(fleet);
      await _settle(tester);
      expect(find.byType(GameSurfaceViewport), findsNothing);
      await _expectOverlayNotice(tester, gameSurfaceLaidOut: false);
    },
  );

  testWidgets(
    'minimal portrait shows damage control in an overlay without moving the game',
    (tester) async {
      await _pumpMinimalApp(tester, size: _phonePortrait);
      await _expectOverlayNotice(tester, gameSurfaceLaidOut: true);
    },
  );

  testWidgets('minimal portrait damage control overlay stays below the notch', (
    tester,
  ) async {
    const safeTop = 47.0;
    tester.view.padding = const FakeViewPadding(top: safeTop);
    tester.view.viewPadding = const FakeViewPadding(top: safeTop);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await _pumpMinimalApp(tester, size: _phonePortrait);
    await _expectOverlayNotice(
      tester,
      gameSurfaceLaidOut: true,
      capsuleTopAtLeast: safeTop,
    );
  });

  testWidgets('HD minimal keeps damage control in its header', (tester) async {
    await _pumpMinimalApp(tester, size: const Size(1280, 800), hd: true);
    expect(find.byKey(const Key('yahagi-hd-label')), findsOneWidget);
    expect(find.byKey(_overlay), findsNothing);
    final shown = QuestCompletionDrawerHost.showDamageControlNotice(
      _hostContext(tester),
      _damageMessage,
    );
    await tester.pump();
    expect(await shown, isTrue);
    await _settle(tester);
    expect(find.text(_damageMessage), findsOneWidget);
    QuestCompletionDrawerHost.removeDamageControlNotice(_hostContext(tester));
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('minimal overlay leaves quest notices to their header slots', (
    tester,
  ) async {
    await _pumpMinimalApp(tester, size: _phoneLandscape);
    QuestCompletionDrawerHost.show(
      _hostContext(tester),
      _damageMessage,
      tone: TopNoticeTone.quest,
    );
    await _settle(tester);
    expect(find.text(_damageMessage), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(_overlay),
        matching: find.text(_damageMessage),
      ),
      findsNothing,
    );
    QuestCompletionDrawerHost.hide(_hostContext(tester));
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });
}

BuildContext _hostContext(WidgetTester tester) =>
    tester.element(find.byKey(const Key('workspace-content-expanded')));

Future<void> _expectOverlayNotice(
  WidgetTester tester, {
  required bool gameSurfaceLaidOut,
  double capsuleTopAtLeast = 0,
}) async {
  final surface = find.byType(GameSurfaceViewport);
  final surfaceBefore = gameSurfaceLaidOut ? tester.getRect(surface) : null;

  final shown = QuestCompletionDrawerHost.showDamageControlNotice(
    _hostContext(tester),
    _damageMessage,
  );
  await tester.pump();
  expect(await shown, isTrue);
  await _settle(tester);

  expect(find.text(_damageMessage), findsOneWidget);
  expect(
    find.descendant(
      of: find.byKey(_overlay),
      matching: find.text(_damageMessage),
    ),
    findsOneWidget,
  );
  final capsule = find
      .ancestor(of: find.text(_damageMessage), matching: find.byType(Container))
      .first;
  expect(tester.getSize(capsule).height, 34);
  expect(
    tester.getTopLeft(capsule).dy,
    greaterThanOrEqualTo(capsuleTopAtLeast),
  );
  expect(find.byType(AlertDialog), findsNothing);
  if (surfaceBefore != null) expect(tester.getRect(surface), surfaceBefore);

  await tester.pump(const Duration(seconds: 9));
  expect(find.text(_damageMessage), findsOneWidget);
  await tester.pump(const Duration(seconds: 2));
  await _settle(tester);
  expect(find.text(_damageMessage), findsNothing);
  expect(find.byType(AlertDialog), findsNothing);
  if (surfaceBefore != null) expect(tester.getRect(surface), surfaceBefore);
  expect(tester.takeException(), isNull);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _pumpMinimalApp(
  WidgetTester tester, {
  required Size size,
  MinimalResourcePosition resourcePosition = MinimalResourcePosition.panel,
  bool hd = false,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final previousTimerSetting = GameStateController.disableTimerForTest;
  GameStateController.disableTimerForTest = true;
  addTearDown(
    () => GameStateController.disableTimerForTest = previousTimerSetting,
  );
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final state = GameStateController();
  await state.initialize();
  final layout = await LayoutSettingsController.load(
    SharedPreferencesLayoutSettingsStore(),
  );
  await layout.setLocaleCode('zh');
  await layout.setUiDisplaySize(UiDisplaySize.minimal);
  await layout.setMinimalResourcePosition(resourcePosition);
  await layout.setHdEnabled(hd);
  final safety = await SafetySettingsController.load(
    MemorySafetySettingsStore(),
  );
  final notices = TopNoticeController();
  final battle = BattleController(gameState: () => state.state);
  final capture = GameCaptureController();
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
    await _settle(tester);
    capture.dispose();
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
      gameStateController: state,
      battleController: battle,
      audioController: audio,
      toolbarController: toolbar,
      headerNoticeController: notices,
      gameSurface: const ColoredBox(color: Colors.black),
    ),
  );
  await tester.pump(const Duration(milliseconds: 350));
  await _settle(tester);
}
