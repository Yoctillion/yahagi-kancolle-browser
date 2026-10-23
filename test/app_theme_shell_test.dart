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
import 'package:yahagi_kancolle_browser/src/browser/game_toolbar_controller.dart';
import 'package:yahagi_kancolle_browser/src/capture/capture_mode_controller.dart';
import 'package:yahagi_kancolle_browser/src/capture/capture_mode_store.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_controller.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/fleet/resource_grid.dart';
import 'package:yahagi_kancolle_browser/src/prototype_status_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/display_mode_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/display_mode_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/network_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/network_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_store.dart';

import 'package:yahagi_kancolle_browser/src/theme/app_theme.dart';
import 'package:yahagi_kancolle_browser/src/theme/app_palette.dart';

void main() {
  for (final (size, hd) in [
    for (final size in [
      const Size(1400, 850),
      const Size(844, 390),
      const Size(390, 844),
    ])
      for (final hd in [false, true]) (size, hd),
  ]) {
    testWidgets(
      'appearance changes preserve real shell, game state and geometry at $size HD $hd',
      (tester) async {
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
        final layout = await LayoutSettingsController.load(
          SharedPreferencesLayoutSettingsStore(),
        );
        await layout.setHdEnabled(hd);
        await layout.setWorkspaceMenuPosition('left');
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
            gameSurface: const _ThemeGameProbe(),
          ),
        );

        await tester.pump(const Duration(milliseconds: 350));
        final game = find.byType(_ThemeGameProbe);
        final shell = find.byType(YahagiShell);
        final gameStateBefore = tester.state(game);
        final shellStateBefore = tester.state(shell);
        final gameRect = tester.getRect(game);
        final header = find.byType(CompactResourceBar, skipOffstage: false);
        final headerRect = tester.getRect(header);
        final anchor = gameState.nozakiTimer.anchorAt;
        for (final theme in [
          AppThemeMode.seaSalt,
          AppThemeMode.skyBlue,
          AppThemeMode.dark,
        ]) {
          await layout.setAppThemeMode(theme);
          await tester.pump();
          expect(
            tester
                .widget<MaterialApp>(find.byType(MaterialApp))
                .theme
                ?.extension<AppPalette>()
                ?.mode,
            theme,
          );
          await tester.pump(const Duration(milliseconds: 350));
          expect(tester.state(game), same(gameStateBefore));
          expect(tester.state(shell), same(shellStateBefore));
          expect(tester.getRect(game), gameRect);
          expect(tester.getRect(header), headerRect);
          expect(gameState.nozakiTimer.anchorAt, anchor);
          expect(
            Theme.of(tester.element(game)).extension<AppPalette>()?.mode,
            theme,
          );
          expect(
            tester
                .widget<ColoredBox>(find.byKey(const Key('theme-game-pixels')))
                .color,
            const Color(0xff123456),
          );
          expect(find.byType(ColorFiltered), findsNothing);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

class _ThemeGameProbe extends StatefulWidget {
  const _ThemeGameProbe();
  @override
  State<_ThemeGameProbe> createState() => _ThemeGameProbeState();
}

class _ThemeGameProbeState extends State<_ThemeGameProbe> {
  @override
  Widget build(BuildContext context) =>
      const ColoredBox(key: Key('theme-game-pixels'), color: Color(0xff123456));
}
