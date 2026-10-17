import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/main.dart';
import 'package:yahagi_kancolle_browser/src/audio/game_audio_controller.dart';
import 'package:yahagi_kancolle_browser/src/audio/game_audio_store.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/browser/gadget_bypass_channel.dart';
import 'package:yahagi_kancolle_browser/src/browser/gadget_bypass_controller.dart';
import 'package:yahagi_kancolle_browser/src/browser/gadget_bypass_store.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_browser_controller.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_fullscreen_exit_dialog.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_toolbar_controller.dart';
import 'package:yahagi_kancolle_browser/src/capture/capture_mode_controller.dart';
import 'package:yahagi_kancolle_browser/src/capture/capture_mode_store.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_controller.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/fleet/resource_grid.dart';
import 'package:yahagi_kancolle_browser/src/layout/hd_bottom_strip.dart';
import 'package:yahagi_kancolle_browser/src/performance/second_tick_scope.dart';
import 'package:yahagi_kancolle_browser/src/prototype_status_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/display_mode_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/display_mode_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/network_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/network_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_store.dart';

void main() {
  for (final (hd, menuPosition) in [
    for (final hd in [false, true])
      for (final position in ['left', 'bottom']) (hd, position),
  ]) {
    testWidgets('fullscreen mutes hidden panels and preserves game tickers '
        '(HD $hd, menu $menuPosition)', (tester) async {
      SharedPreferences.setMockInitialValues({
        exitFullscreenSkipConfirmationKey: true,
      });
      final previousTimerSetting = GameStateController.disableTimerForTest;
      GameStateController.disableTimerForTest = true;
      addTearDown(
        () => GameStateController.disableTimerForTest = previousTimerSetting,
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 850);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final layout = await LayoutSettingsController.load(
        SharedPreferencesLayoutSettingsStore(),
      );
      await layout.setHdEnabled(hd);
      await layout.setWorkspaceMenuPosition(menuPosition);
      final gameState = GameStateController();
      final timerAnchor = DateTime.now().toUtc().subtract(
        const Duration(minutes: 2),
      );
      gameState.nozakiTimer.reset(timerAnchor);
      final battle = BattleController(gameState: () => gameState.state);
      final toolbar = GameToolbarController();
      final capture = GameCaptureController();
      final browser = GameBrowserController();
      final status = PrototypeStatusController();
      final network = NetworkSettingsController(
        store: SharedPreferencesNetworkSettingsStore(),
      );
      final bypass = GadgetBypassController(
        store: SharedPreferencesGadgetBypassStore(),
        port: MethodChannelGadgetBypassPort(),
      );
      final safety = await SafetySettingsController.load(
        MemorySafetySettingsStore(),
      );
      final display = await DisplayModeController.load(
        MemoryDisplayModeStore(),
      );
      final mode = await CaptureModeController.load(
        SharedPreferencesCaptureModeStore(),
      );
      final audio = await GameAudioController.load(
        SharedPreferencesGameAudioStore(),
      );
      for (final notifier in <ChangeNotifier>[
        layout,
        gameState,
        battle,
        toolbar,
        capture,
        browser,
        status,
        network,
        bypass,
        safety,
        display,
        mode,
        audio,
      ]) {
        addTearDown(notifier.dispose);
      }

      var gameTicks = 0;
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
          gameStateController: gameState,
          battleController: battle,
          audioController: audio,
          toolbarController: toolbar,
          gameSurface: _GameTickerProbe(onTick: () => gameTicks++),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final panel = find.byKey(
        const Key('workspace-information-panel'),
        skipOffstage: false,
      );
      final panelElement = tester.element(panel);
      final gameElement = tester.element(find.byType(_GameTickerProbe));
      final header = find.byType(CompactResourceBar, skipOffstage: false);
      final headerElement = tester.element(header);
      final headerTick = tester.element(
        find.descendant(
          of: header,
          matching: find.byType(SecondTickBuilder, skipOffstage: false),
        ),
      );
      final navigationTick = tester.element(
        find.ancestor(
          of: find.byKey(
            const Key('workspace-navigation-list'),
            skipOffstage: false,
          ),
          matching: find.byType(SecondTickBuilder, skipOffstage: false),
        ),
      );
      final hdStrip = find.byType(HdBottomStrip, skipOffstage: false);
      final hdElement = hd ? tester.element(hdStrip) : null;
      expect(TickerMode.valuesOf(panelElement).enabled, isTrue);
      expect(TickerMode.valuesOf(headerElement).enabled, isTrue);
      expect(TickerMode.valuesOf(navigationTick).enabled, isTrue);
      if (hdElement != null) {
        expect(TickerMode.valuesOf(hdElement).enabled, isTrue);
      }

      await tester.tap(find.byKey(const Key('yahagi-brand-button')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('game-enter-fullscreen')));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const Key('workspace-information-panel')),
        findsNothing,
      );
      expect(TickerMode.valuesOf(panelElement).enabled, isFalse);
      expect(TickerMode.valuesOf(headerElement).enabled, isFalse);
      expect(TickerMode.valuesOf(navigationTick).enabled, isFalse);
      if (hdElement != null) {
        expect(TickerMode.valuesOf(hdElement).enabled, isFalse);
      }
      expect(TickerMode.valuesOf(gameElement).enabled, isTrue);
      final ticksBefore = gameTicks;
      await tester.pump(const Duration(milliseconds: 16));
      expect(gameTicks, greaterThan(ticksBefore));

      final hiddenHeaderChild = _builtChild(headerTick);
      final hiddenNavigationChild = _builtChild(navigationTick);
      await tester.pump(const Duration(seconds: 2));
      expect(_builtChild(headerTick), same(hiddenHeaderChild));
      expect(_builtChild(navigationTick), same(hiddenNavigationChild));
      expect(gameState.nozakiTimer.anchorAt, timerAnchor);

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.element(panel), same(panelElement));
      expect(tester.element(find.byType(_GameTickerProbe)), same(gameElement));
      expect(TickerMode.valuesOf(panelElement).enabled, isTrue);
      expect(tester.element(header), same(headerElement));
      expect(TickerMode.valuesOf(headerElement).enabled, isTrue);
      expect(TickerMode.valuesOf(navigationTick).enabled, isTrue);
      final restoredHeaderChild = _builtChild(headerTick);
      final restoredNavigationChild = _builtChild(navigationTick);
      await tester.pump(const Duration(seconds: 1));
      expect(_builtChild(headerTick), isNot(same(restoredHeaderChild)));
      expect(_builtChild(navigationTick), isNot(same(restoredNavigationChild)));
      expect(gameState.nozakiTimer.anchorAt, timerAnchor);
      if (hdElement != null) {
        expect(tester.element(hdStrip), same(hdElement));
        expect(TickerMode.valuesOf(hdElement).enabled, isTrue);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

Widget _builtChild(Element element) {
  late Widget child;
  element.visitChildElements((element) => child = element.widget);
  return child;
}

class _GameTickerProbe extends StatefulWidget {
  const _GameTickerProbe({required this.onTick});
  final VoidCallback onTick;

  @override
  State<_GameTickerProbe> createState() => _GameTickerProbeState();
}

class _GameTickerProbeState extends State<_GameTickerProbe>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..addListener(widget.onTick);

  @override
  void initState() {
    super.initState();
    _animation.repeat();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.black);
}
