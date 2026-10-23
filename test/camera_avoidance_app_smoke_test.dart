import 'dart:math' as math;
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:yahagi_kancolle_browser/src/browser/game_browser_toolbar.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_fullscreen_controls.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_surface_viewport.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_toolbar_controller.dart';
import 'package:yahagi_kancolle_browser/src/browser/native_game_surface_slot.dart';
import 'package:yahagi_kancolle_browser/src/browser/native_game_webview_contract.dart';
import 'package:yahagi_kancolle_browser/src/capture/capture_mode_controller.dart';
import 'package:yahagi_kancolle_browser/src/capture/capture_mode_store.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_controller.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/layout/camera_avoidance.dart';
import 'package:yahagi_kancolle_browser/src/prototype_status_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/display_mode_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/display_mode_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/network_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/network_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_store.dart';

// Geometry fixtures exercise Flutter's real app tree and native bounds slot.
// They are deterministic simulated windows, not claims of physical-device runs.
void main() {
  for (final dpr in [1.0, 2.625, 3.5]) {
    testWidgets(
      'YahagiApp preserves shell and game through 16 camera scenarios at DPR $dpr',
      (tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final previousTimerSetting = GameStateController.disableTimerForTest;
        GameStateController.disableTimerForTest = true;
        addTearDown(
          () => GameStateController.disableTimerForTest = previousTimerSetting,
        );
        tester.view.devicePixelRatio = dpr;
        tester.view.physicalSize = const Size(844, 390) * dpr;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDisplayFeatures);

        final harness = await _AppHarness.load();
        for (final notifier in harness.notifiers) {
          addTearDown(notifier.dispose);
        }
        await tester.pumpWidget(harness.app);
        await _settleGeometry(tester);
        final shell = find.byType(YahagiShell);
        final game = find.byType(_CameraGameProbe);
        final slot = find.byType(NativeGameSurfaceSlot);
        final shellState = tester.state(shell);
        final gameState = tester.state(game);
        final slotState = tester.state(slot);
        final timerAnchor = harness.gameState.nozakiTimer.anchorAt;
        var checkedScenarios = 0;
        final escapedGameBounds = <String>[];

        for (var index = 0; index < 16; index++) {
          final edge = CameraAvoidanceEdge.values[index % 4];
          final landscape =
              edge == CameraAvoidanceEdge.left ||
              edge == CameraAvoidanceEdge.right;
          final size = landscape ? const Size(844, 390) : const Size(390, 844);
          final block = index ~/ 4;
          final hd = block.isOdd;
          final menu = [
            'top',
            'bottom',
            'left',
            'right',
          ][(index + block * 2) % 4];
          final distance = [0.0, 1.0, 48.0, 120.0][(index + block) % 4];
          final reason =
              'DPR $dpr case $index: $size $edge HD $hd '
              'menu $menu distance $distance';
          tester.view.physicalSize = size * dpr;

          // TestFlutterView.displayFeatures and DisplayFeature.bounds use
          // logical pixels. Start with a physical-pixel fixture and convert at
          // that boundary, just as the engine does before exposing features.
          final physicalCutout = _physicalCutout(size * dpr, edge, dpr);
          tester.view.displayFeatures = [
            DisplayFeature(
              bounds: Rect.fromLTRB(
                physicalCutout.left / dpr,
                physicalCutout.top / dpr,
                physicalCutout.right / dpr,
                physicalCutout.bottom / dpr,
              ),
              type: DisplayFeatureType.cutout,
              state: DisplayFeatureState.unknown,
            ),
          ];
          await harness.layout.setHdEnabled(hd);
          await harness.layout.setWorkspaceMenuPosition(menu);
          await harness.layout.setCameraAvoidanceDistance(distance);
          await harness.layout.setCameraAvoidanceEnabled(false);
          await _settleGeometry(tester);
          _expectAppGeometry(
            tester,
            harness,
            size,
            Offset.zero & size,
            EdgeInsets.zero,
            '$reason initial disabled baseline',
            escapedGameBounds,
          );
          // Existing width-priority layouts may crop a raw game surface:
          // 844x390 HD/right menu has game.top == -2.795 while disabled.
          // Disabling must restore that baseline and keep its rendered clip
          // inside the window, rather than silently changing the old layout.
          final disabledGameRect = tester.getRect(game);
          await harness.layout.setCameraAvoidanceEnabled(true);
          await _settleGeometry(tester);
          final insets = _expectedInsets(size, edge, distance);
          final expected = Rect.fromLTWH(
            insets.left,
            insets.top,
            size.width - insets.horizontal,
            size.height - insets.vertical,
          );
          _expectAppGeometry(
            tester,
            harness,
            size,
            expected,
            insets,
            reason,
            escapedGameBounds,
          );
          final enabledGameRect = tester.getRect(game);

          await harness.layout.setCameraAvoidanceEnabled(false);
          await _settleGeometry(tester);
          _expectAppGeometry(
            tester,
            harness,
            size,
            Offset.zero & size,
            EdgeInsets.zero,
            '$reason disabled',
            escapedGameBounds,
          );
          expect(
            harness.layout.cameraAvoidanceDistance,
            distance,
            reason: reason,
          );
          _expectRect(
            tester.getRect(game),
            disabledGameRect,
            '$reason restores disabled baseline',
          );

          await harness.layout.setCameraAvoidanceEnabled(true);
          await _settleGeometry(tester);
          _expectAppGeometry(
            tester,
            harness,
            size,
            expected,
            insets,
            '$reason restored',
            escapedGameBounds,
          );
          _expectRect(
            tester.getRect(game),
            enabledGameRect,
            '$reason restored game',
          );
          expect(tester.state(shell), same(shellState), reason: reason);
          expect(tester.state(game), same(gameState), reason: reason);
          expect(tester.state(slot), same(slotState), reason: reason);
          expect(
            harness.gameState.nozakiTimer.anchorAt,
            timerAnchor,
            reason: reason,
          );
          expect(tester.takeException(), isNull, reason: reason);
          checkedScenarios++;
        }
        expect(checkedScenarios, 16);
        expect(
          escapedGameBounds,
          isEmpty,
          reason: 'All 16 scenarios were checked',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('real app fullscreen fits a height-constrained cutout viewport', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final previousTimerSetting = GameStateController.disableTimerForTest;
    GameStateController.disableTimerForTest = true;
    addTearDown(
      () => GameStateController.disableTimerForTest = previousTimerSetting,
    );
    const size = Size(640, 300);
    const dpr = 2.625;
    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = size * dpr;
    final physicalCutout = _physicalCutout(
      size * dpr,
      CameraAvoidanceEdge.top,
      dpr,
    );
    tester.view.displayFeatures = [
      DisplayFeature(
        bounds: Rect.fromLTRB(
          physicalCutout.left / dpr,
          physicalCutout.top / dpr,
          physicalCutout.right / dpr,
          physicalCutout.bottom / dpr,
        ),
        type: DisplayFeatureType.cutout,
        state: DisplayFeatureState.unknown,
      ),
    ];
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDisplayFeatures);
    const channel = MethodChannel('app.yahagi.kancollebrowser/game_fullscreen');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final harness = await _AppHarness.load();
    for (final notifier in harness.notifiers) {
      addTearDown(notifier.dispose);
    }
    await harness.layout.setHdEnabled(true);
    await harness.layout.setWorkspaceMenuPosition('right');
    await tester.pumpWidget(harness.app);
    harness.app.toolbarController.reveal();
    await _settleGeometry(tester);
    final shell = find.byType(YahagiShell);
    final game = find.byType(_CameraGameProbe);
    final shellState = tester.state(shell);
    final gameState = tester.state(game);
    final slotState = tester.state(find.byType(NativeGameSurfaceSlot));
    final toolbar = tester.widget<GameBrowserToolbar>(
      find.byType(GameBrowserToolbar, skipOffstage: false),
    );
    expect(toolbar.onEnterFullscreen, isNotNull);
    toolbar.onEnterFullscreen!();
    await _settleGeometry(tester);
    expect(
      tester
          .widget<GameSurfaceViewport>(find.byType(GameSurfaceViewport))
          .fullscreen,
      isTrue,
    );
    final disabledBaseline = tester.getRect(game);
    final escapedGameBounds = <String>[];
    // This injected probe has no browser port for fullscreen fit recovery.
    // Record its initial geometry; each camera change below must then cause
    // NativeGameSurfaceSlot to report the actual new geometry on its own.
    await harness.layout.setCameraAvoidanceDistance(120);
    await harness.layout.setCameraAvoidanceEnabled(true);
    await _settleGeometry(tester);
    final insets = _expectedInsets(size, CameraAvoidanceEdge.top, 120);
    final expected = Rect.fromLTWH(
      0,
      insets.top,
      size.width,
      size.height - insets.vertical,
    );
    _expectAppGeometry(
      tester,
      harness,
      size,
      expected,
      insets,
      'fullscreen enabled height-constrained camera viewport',
      escapedGameBounds,
    );
    expect(tester.getRect(game).height, lessThanOrEqualTo(expected.height));
    await harness.layout.setCameraAvoidanceEnabled(false);
    await _settleGeometry(tester);
    _expectAppGeometry(
      tester,
      harness,
      size,
      Offset.zero & size,
      EdgeInsets.zero,
      'fullscreen disabled restores clipping baseline',
      escapedGameBounds,
    );
    _expectRect(
      tester.getRect(game),
      disabledBaseline,
      'fullscreen disabled baseline',
    );
    await harness.layout.setCameraAvoidanceEnabled(true);
    await _settleGeometry(tester);
    _expectAppGeometry(
      tester,
      harness,
      size,
      expected,
      insets,
      'fullscreen restored',
      escapedGameBounds,
    );
    expect(tester.state(shell), same(shellState));
    expect(tester.state(game), same(gameState));
    expect(tester.state(find.byType(NativeGameSurfaceSlot)), same(slotState));
    expect(escapedGameBounds, isEmpty);
    expect(tester.takeException(), isNull);
    tester
        .widget<GameFullscreenControls>(find.byType(GameFullscreenControls))
        .onExit();
    await _settleGeometry(tester);
    expect(
      tester
          .widget<GameSurfaceViewport>(find.byType(GameSurfaceViewport))
          .fullscreen,
      isFalse,
    );
    expect(tester.state(game), same(gameState));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _settleGeometry(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
  await tester.pump();
}

Rect _physicalCutout(Size physicalSize, CameraAvoidanceEdge edge, double dpr) {
  final gap = 4 * dpr;
  final diameter = 24 * dpr;
  return switch (edge) {
    CameraAvoidanceEdge.left => Rect.fromLTWH(
      gap,
      (physicalSize.height - diameter) / 2,
      diameter,
      diameter,
    ),
    CameraAvoidanceEdge.right => Rect.fromLTWH(
      physicalSize.width - gap - diameter,
      (physicalSize.height - diameter) / 2,
      diameter,
      diameter,
    ),
    CameraAvoidanceEdge.top => Rect.fromLTWH(
      (physicalSize.width - diameter) / 2,
      gap,
      diameter,
      diameter,
    ),
    CameraAvoidanceEdge.bottom => Rect.fromLTWH(
      (physicalSize.width - diameter) / 2,
      physicalSize.height - gap - diameter,
      diameter,
      diameter,
    ),
  };
}

EdgeInsets _expectedInsets(
  Size size,
  CameraAvoidanceEdge edge,
  double distance,
) {
  // These fixtures have one cutout; one edge can consume up to half an axis.
  final horizontal = math.min(distance, size.width / 2);
  final vertical = math.min(distance, size.height / 2);
  return switch (edge) {
    CameraAvoidanceEdge.left => EdgeInsets.only(left: horizontal),
    CameraAvoidanceEdge.right => EdgeInsets.only(right: horizontal),
    CameraAvoidanceEdge.top => EdgeInsets.only(top: vertical),
    CameraAvoidanceEdge.bottom => EdgeInsets.only(bottom: vertical),
  };
}

void _expectAppGeometry(
  WidgetTester tester,
  _AppHarness harness,
  Size size,
  Rect expected,
  EdgeInsets insets,
  String reason,
  List<String> escapedGameBounds,
) {
  final shell = find.byType(YahagiShell);
  final scope = tester.widget<CameraAvoidanceScope>(
    find.byType(CameraAvoidanceScope),
  );
  expect(scope.windowSize, size, reason: reason);
  expect(scope.insets, insets, reason: reason);
  expect(scope.enabled, harness.layout.cameraAvoidanceEnabled, reason: reason);
  _expectRect(tester.getRect(shell), expected, '$reason shell');
  expect(
    MediaQuery.sizeOf(tester.element(shell)),
    expected.size,
    reason: reason,
  );
  final gameRect = tester.getRect(find.byType(_CameraGameProbe));
  for (final value in [
    gameRect.left,
    gameRect.top,
    gameRect.width,
    gameRect.height,
  ]) {
    expect(value.isFinite, isTrue, reason: reason);
  }
  expect(gameRect.width, greaterThan(0), reason: reason);
  expect(gameRect.height, greaterThan(0), reason: reason);
  expect(
    gameRect.width / gameRect.height,
    closeTo(1200 / 720, .0001),
    reason: reason,
  );
  final clipRect = tester.getRect(find.byType(GameSurfaceViewport));
  _expectContained(clipRect, expected, '$reason game viewport');
  final renderedRect = gameRect.intersect(clipRect);
  expect(renderedRect.isEmpty, isFalse, reason: reason);
  _expectContained(renderedRect, expected, '$reason rendered game');
  if (scope.enabled &&
      (gameRect.left < expected.left - .001 ||
          gameRect.top < expected.top - .001 ||
          gameRect.right > expected.right + .001 ||
          gameRect.bottom > expected.bottom + .001)) {
    escapedGameBounds.add('$reason: game $gameRect outside $expected');
  }
  expect(harness.bounds, isNotEmpty, reason: reason);
  final reported = harness.bounds.last;
  _expectRect(
    Rect.fromLTWH(reported.left, reported.top, reported.width, reported.height),
    gameRect,
    '$reason native slot',
  );
  expect(
    reported.devicePixelRatio,
    tester.view.devicePixelRatio,
    reason: reason,
  );
  expect(tester.takeException(), isNull, reason: reason);
}

void _expectContained(Rect actual, Rect container, String reason) {
  expect(
    actual.left,
    greaterThanOrEqualTo(container.left - .001),
    reason: reason,
  );
  expect(
    actual.top,
    greaterThanOrEqualTo(container.top - .001),
    reason: reason,
  );
  expect(
    actual.right,
    lessThanOrEqualTo(container.right + .001),
    reason: reason,
  );
  expect(
    actual.bottom,
    lessThanOrEqualTo(container.bottom + .001),
    reason: reason,
  );
}

void _expectRect(Rect actual, Rect expected, String reason) {
  expect(actual.left, closeTo(expected.left, .001), reason: reason);
  expect(actual.top, closeTo(expected.top, .001), reason: reason);
  expect(actual.width, closeTo(expected.width, .001), reason: reason);
  expect(actual.height, closeTo(expected.height, .001), reason: reason);
}

class _AppHarness {
  _AppHarness(
    this.app,
    this.layout,
    this.gameState,
    this.notifiers,
    this.bounds,
  );

  final YahagiApp app;
  final LayoutSettingsController layout;
  final GameStateController gameState;
  final List<ChangeNotifier> notifiers;
  final List<NativeGameWebViewBounds> bounds;

  static Future<_AppHarness> load() async {
    final layout = await LayoutSettingsController.load(
      SharedPreferencesLayoutSettingsStore(),
    );
    final gameState = GameStateController();
    gameState.nozakiTimer.reset(
      DateTime.now().toUtc().subtract(const Duration(minutes: 2)),
    );
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
    final display = await DisplayModeController.load(MemoryDisplayModeStore());
    final mode = await CaptureModeController.load(
      SharedPreferencesCaptureModeStore(),
    );
    final audio = await GameAudioController.load(
      SharedPreferencesGameAudioStore(),
    );
    final bounds = <NativeGameWebViewBounds>[];
    return _AppHarness(
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
        gameSurface: _CameraGameProbe(
          onBoundsChanged: (value) async => bounds.add(value),
        ),
      ),
      layout,
      gameState,
      [
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
      ],
      bounds,
    );
  }
}

class _CameraGameProbe extends StatefulWidget {
  const _CameraGameProbe({required this.onBoundsChanged});
  final Future<void> Function(NativeGameWebViewBounds) onBoundsChanged;
  @override
  State<_CameraGameProbe> createState() => _CameraGameProbeState();
}

class _CameraGameProbeState extends State<_CameraGameProbe> {
  @override
  Widget build(BuildContext context) => NativeGameSurfaceSlot(
    onBoundsChanged: widget.onBoundsChanged,
    onVisibilityChanged: (_) async {},
  );
}
