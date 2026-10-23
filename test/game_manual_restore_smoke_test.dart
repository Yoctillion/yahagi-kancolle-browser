import 'dart:async';
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
import 'package:yahagi_kancolle_browser/src/browser/game_frame_reload_port.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_launch_config.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_page_alignment_script.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_surface_viewport.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_toolbar_controller.dart';
import 'package:yahagi_kancolle_browser/src/browser/native_game_webview_port.dart';
import 'package:yahagi_kancolle_browser/src/capture/capture_mode_controller.dart';
import 'package:yahagi_kancolle_browser/src/capture/capture_mode_store.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_controller.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/prototype_status_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/display_mode_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/display_mode_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/network_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/network_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_store.dart';

const _fitKey = Key('browser-fit-screen');
const _surfaceKey = Key('manual-restore-game-surface');
const _fitLabel = '修复显示（自适应屏幕）';
const _nativeChannel = MethodChannel('test/ooi_manual_restore/native_webview');

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final previousDisableTimer = GameStateController.disableTimerForTest;
    GameStateController.disableTimerForTest = true;
    binding.platformDispatcher.localeTestValue = const Locale('zh');
    binding.platformDispatcher.localesTestValue = const [Locale('zh')];
    addTearDown(() {
      GameStateController.disableTimerForTest = previousDisableTimer;
      binding.platformDispatcher.clearLocaleTestValue();
      binding.platformDispatcher.clearLocalesTestValue();
    });
  });

  testWidgets(
    'real shell restore button reaches native alignment across device geometry',
    (tester) async {
      final fixture = await _ShellFixture.mount(tester);
      final originalSurface = tester.element(find.byKey(_surfaceKey));

      // One mounted production shell is retained through rotation and folding.
      // Only the native transport is mocked; no toolbar callback is recreated.
      const geometries = <(String, Size, Rect?)>[
        ('phone portrait', Size(390, 844), null),
        ('phone landscape', Size(844, 390), null),
        ('tablet portrait', Size(800, 1280), null),
        ('tablet landscape', Size(1280, 800), null),
        ('foldable cover portrait', Size(360, 780), null),
        ('foldable cover landscape', Size(780, 360), null),
        ('short split window', Size(800, 300), null),
        ('compact split window', Size(500, 200), null),
        (
          'foldable unfolded portrait',
          Size(840, 1080),
          Rect.fromLTWH(415, 0, 10, 1080),
        ),
        (
          'foldable unfolded landscape',
          Size(1080, 840),
          Rect.fromLTWH(535, 0, 10, 840),
        ),
      ];

      for (final (name, size, hinge) in geometries) {
        _setGeometry(tester, size, hinge: hinge);
        await _settleGeometry(tester);
        expect(find.byType(YahagiShell), findsOneWidget, reason: name);
        expect(find.byType(GameBrowserToolbar), findsOneWidget, reason: name);
        expect(tester.element(find.byKey(_surfaceKey)), same(originalSurface));
        _expectVisibleRestoreButton(tester, size, reason: name);
        _expectCompleteGameSurface(tester, reason: name);

        final before = fixture.fitCalls.length;
        for (var press = 0; press < 4; press++) {
          await tester.tap(find.byKey(_fitKey));
          await tester.pump();
          _expectCompleteGameSurface(tester, reason: '$name restore $press');
        }
        expect(fixture.fitCalls.length, before + 4, reason: name);
        fixture.expectAlignmentPayload();
        fixture.expectNoNavigation(reason: name);
        expect(tester.takeException(), isNull, reason: name);
        final viewport = tester.getRect(find.byType(GameSurfaceViewport));
        final surface = tester.getRect(find.byKey(_surfaceKey));
        final verticalCrop =
            surface.top < viewport.top - 0.01 ||
            surface.bottom > viewport.bottom + 0.01;
        // Printed by the expanded test reporter into the smoke evidence log.
        debugPrint(
          'MANUAL_RESTORE $name ${size.width}x${size.height}: '
          'visible, four UI taps -> four native fits, no navigation; '
          'verticalCrop=$verticalCrop viewport=$viewport surface=$surface',
        );
      }

      // The setting can also request the opposite orientation while a window
      // keeps its dimensions (multi-window and foldable host behavior).
      for (final mode in [DisplayMode.portrait, DisplayMode.landscape]) {
        await fixture.display.setDisplayMode(mode);
        await _settleGeometry(tester);
        _expectVisibleRestoreButton(
          tester,
          const Size(1080, 840),
          reason: 'forced ${mode.name}',
        );
        final before = fixture.fitCalls.length;
        await tester.tap(find.byKey(_fitKey));
        await tester.pump();
        expect(fixture.fitCalls.length, before + 1);
        _expectCompleteGameSurface(
          tester,
          reason: 'forced ${mode.name} restore',
        );
        fixture.expectNoNavigation(reason: 'forced ${mode.name}');
        expect(tester.element(find.byKey(_surfaceKey)), same(originalSurface));
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('real shell restore is safe before a browser port is attached', (
    tester,
  ) async {
    final fixture = await _ShellFixture.mount(tester, attachPort: false);
    expect(fixture.browser.hasAttachedPort, isFalse);
    _expectVisibleRestoreButton(tester, const Size(390, 844));
    for (var press = 0; press < 4; press++) {
      await tester.tap(find.byKey(_fitKey));
      await tester.pump();
    }
    expect(fixture.fitCalls, isEmpty);
    fixture.expectNoNavigation(reason: 'no browser port');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'real shell restore handles a native port that has not been created',
    (tester) async {
      final fixture = await _ShellFixture.mount(tester, createNative: false);
      expect(fixture.browser.hasAttachedPort, isTrue);
      _expectVisibleRestoreButton(tester, const Size(390, 844));
      await tester.tap(find.byKey(_fitKey));
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: 'An early manual fit must not escape as an async error',
      );
      expect(fixture.fitCalls, isEmpty);
      fixture.expectNoNavigation(reason: 'native port not yet created');
      expect(find.text('网页或捕获状态异常，请在设置中查看诊断信息。'), findsOneWidget);

      // A later ready port must still accept another real button press.
      expect(await fixture.native.create(), _ShellFixture.generation);
      await tester.tap(find.byKey(_fitKey));
      await tester.pump();
      expect(fixture.fitCalls, hasLength(1));
      fixture.expectAlignmentPayload();
      fixture.expectNoNavigation(reason: 'native port became ready');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('real shell restore handles native failure and allows retry', (
    tester,
  ) async {
    final fixture = await _ShellFixture.mount(tester);
    final before = fixture.fitCalls.length;
    fixture.failFit = true;
    await tester.tap(find.byKey(_fitKey));
    await tester.pump();
    expect(fixture.fitCalls.length, before + 1);
    expect(
      tester.takeException(),
      isNull,
      reason: 'A platform fit failure must not escape the production callback',
    );
    fixture.expectNoNavigation(reason: 'native fit failed');
    expect(find.text('网页或捕获状态异常，请在设置中查看诊断信息。'), findsOneWidget);

    fixture.failFit = false;
    await tester.tap(find.byKey(_fitKey));
    await tester.pump();
    expect(fixture.fitCalls.length, before + 2);
    fixture.expectAlignmentPayload();
    fixture.expectNoNavigation(reason: 'retry after native fit failed');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a delayed restore failure is safe after the shell is disposed', (
    tester,
  ) async {
    final fixture = await _ShellFixture.mount(tester);
    final pending = Completer<void>();
    fixture.pendingFit = pending;
    final before = fixture.fitCalls.length;
    await tester.tap(find.byKey(_fitKey));
    await tester.pump();
    expect(fixture.fitCalls.length, before + 1);

    await tester.pumpWidget(const SizedBox.shrink());
    pending.completeError(PlatformException(code: 'disposed_restore_failure'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    fixture.expectNoNavigation(reason: 'fit failure after shell disposal');
  });
}

void _setGeometry(WidgetTester tester, Size size, {Rect? hinge}) {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = size * 2;
  tester.view.displayFeatures = [
    if (hinge != null)
      DisplayFeature(
        bounds: hinge,
        type: DisplayFeatureType.hinge,
        state: DisplayFeatureState.postureFlat,
      ),
  ];
}

Future<void> _settleGeometry(WidgetTester tester) async {
  await tester.pump();
  // Drain all four production geometry recovery timers (last at 800 ms).
  await tester.pump(const Duration(milliseconds: 1000));
  await tester.pump();
}

void _expectVisibleRestoreButton(
  WidgetTester tester,
  Size windowSize, {
  String? reason,
}) {
  final finder = find.byKey(_fitKey);
  expect(finder, findsOneWidget, reason: reason);
  expect(finder.hitTestable(), findsOneWidget, reason: reason);
  final button = tester.widget<IconButton>(finder);
  expect(button.tooltip, _fitLabel, reason: reason);
  expect(button.onPressed, isNotNull, reason: reason);
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(0), reason: reason);
  expect(rect.top, greaterThanOrEqualTo(0), reason: reason);
  expect(rect.right, lessThanOrEqualTo(windowSize.width), reason: reason);
  expect(rect.bottom, lessThanOrEqualTo(windowSize.height), reason: reason);
}

void _expectCompleteGameSurface(WidgetTester tester, {required String reason}) {
  final viewport = tester.getRect(find.byType(GameSurfaceViewport));
  final surface = tester.getRect(find.byKey(_surfaceKey));
  expect(
    surface.left,
    greaterThanOrEqualTo(viewport.left - 0.01),
    reason: reason,
  );
  expect(
    surface.top,
    greaterThanOrEqualTo(viewport.top - 0.01),
    reason: reason,
  );
  expect(
    surface.right,
    lessThanOrEqualTo(viewport.right + 0.01),
    reason: reason,
  );
  expect(
    surface.bottom,
    lessThanOrEqualTo(viewport.bottom + 0.01),
    reason: reason,
  );
  expect(
    surface.width / surface.height,
    closeTo(1200 / 720, 0.0001),
    reason: reason,
  );
}

final class _ShellFixture {
  _ShellFixture(this.native, this.browser, this.display, this.frameReload);

  static const generation = 41;
  final MethodChannelNativeGameWebViewPort native;
  final GameBrowserController browser;
  final DisplayModeController display;
  final _FrameReloadProbe frameReload;
  final calls = <MethodCall>[];
  bool failFit = false;
  Completer<void>? pendingFit;

  List<MethodCall> get fitCalls =>
      calls.where((call) => call.method == 'fitGameScreen').toList();

  static Future<_ShellFixture> mount(
    WidgetTester tester, {
    bool attachPort = true,
    bool createNative = true,
  }) async {
    _setGeometry(tester, const Size(390, 844));
    addTearDown(tester.view.reset);
    final frameReload = _FrameReloadProbe();
    final native = MethodChannelNativeGameWebViewPort(
      channel: _nativeChannel,
      eventStream: const Stream<Object?>.empty(),
      frameReloadPort: frameReload,
    );
    final browser = GameBrowserController(
      port: attachPort ? native : null,
      homeUri: GameLaunchConfig.ooiEntry,
    );
    final display = await DisplayModeController.load(MemoryDisplayModeStore());
    final fixture = _ShellFixture(native, browser, display, frameReload);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_nativeChannel, (call) async {
      fixture.calls.add(call);
      if (call.method == 'create') return generation;
      if (call.method == 'fitGameScreen') await fixture.pendingFit?.future;
      if (call.method == 'fitGameScreen' && fixture.failFit) {
        throw PlatformException(code: 'manual_restore_smoke_failure');
      }
      return null;
    });
    addTearDown(() async {
      await native.dispose();
      messenger.setMockMethodCallHandler(_nativeChannel, null);
    });
    if (createNative) expect(await native.create(), generation);

    final layout = await LayoutSettingsController.load(
      SharedPreferencesLayoutSettingsStore(),
      systemLocaleCode: 'zh',
    );
    await layout.setLocaleCode('zh');
    await layout.setHdEnabled(false);
    final network = NetworkSettingsController(
      store: SharedPreferencesNetworkSettingsStore(),
    );
    final gadget = GadgetBypassController(
      store: SharedPreferencesGadgetBypassStore(),
      port: MethodChannelGadgetBypassPort(),
    );
    final safety = await SafetySettingsController.load(
      MemorySafetySettingsStore(),
    );
    final status = PrototypeStatusController();
    final captureMode = await CaptureModeController.load(
      SharedPreferencesCaptureModeStore(),
    );
    final audio = await GameAudioController.load(
      SharedPreferencesGameAudioStore(),
    );
    final toolbar = GameToolbarController();
    final capture = GameCaptureController();
    final game = GameStateController();
    final battle = BattleController(gameState: () => game.state);
    addTearDown(() {
      battle.dispose();
      game.dispose();
      capture.dispose();
      toolbar.dispose();
      audio.dispose();
      captureMode.dispose();
      status.dispose();
      safety.dispose();
      gadget.dispose();
      network.dispose();
      layout.dispose();
      display.dispose();
      browser.dispose();
    });

    await tester.pumpWidget(
      YahagiApp(
        layoutSettingsController: layout,
        networkSettingsController: network,
        gadgetBypassController: gadget,
        safetySettingsController: safety,
        displayModeController: display,
        controller: status,
        browserController: browser,
        captureModeController: captureMode,
        audioController: audio,
        toolbarController: toolbar,
        gameCaptureController: capture,
        gameStateController: game,
        battleController: battle,
        gameSurface: const ColoredBox(key: _surfaceKey, color: Colors.black),
      ),
    );
    await _settleGeometry(tester);
    expect(
      find.byKey(_fitKey).hitTestable(),
      findsNothing,
      reason: 'The real header toolbar starts collapsed',
    );
    await tester.tap(find.byKey(const Key('yahagi-brand-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(toolbar.isVisible, isTrue);
    _expectVisibleRestoreButton(tester, const Size(390, 844));
    expect(tester.takeException(), isNull);
    // Dispose the production shell before any of its controller tear downs.
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    return fixture;
  }

  void expectAlignmentPayload() {
    expect(fitCalls, isNotEmpty);
    for (final call in fitCalls) {
      expect(call.arguments, <String, Object?>{
        'generationId': generation,
        'javascript': gamePageAlignmentScript,
      });
    }
  }

  void expectNoNavigation({required String reason}) {
    expect(browser.homeUri, GameLaunchConfig.ooiEntry, reason: reason);
    expect(
      browser.displayAddress,
      GameLaunchConfig.ooiEntry.toString(),
      reason: reason,
    );
    expect(
      calls.where(
        (call) => const {
          'reload',
          'loadUri',
          'goBack',
          'showLocalHome',
          'clearSession',
        }.contains(call.method),
      ),
      isEmpty,
      reason: reason,
    );
    expect(frameReload.calls, 0, reason: reason);
  }
}

final class _FrameReloadProbe implements GameFrameReloadPort {
  int calls = 0;

  @override
  Future<void> configure() async {}

  @override
  Future<GameFrameReloadResult> reload() async {
    calls++;
    return GameFrameReloadResult.reloaded;
  }
}
