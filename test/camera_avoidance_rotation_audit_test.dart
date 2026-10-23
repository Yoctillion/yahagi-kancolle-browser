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
import 'package:yahagi_kancolle_browser/src/browser/game_fullscreen_controls.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_surface_viewport.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_toolbar_controller.dart';
import 'package:yahagi_kancolle_browser/src/browser/native_game_surface_slot.dart';
import 'package:yahagi_kancolle_browser/src/browser/native_game_webview_contract.dart';
import 'package:yahagi_kancolle_browser/src/capture/capture_mode_controller.dart';
import 'package:yahagi_kancolle_browser/src/capture/capture_mode_store.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_controller.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/game_webview.dart';
import 'package:yahagi_kancolle_browser/src/layout/camera_avoidance.dart';
import 'package:yahagi_kancolle_browser/src/native_activity_game_surface.dart';
import 'package:yahagi_kancolle_browser/src/prototype_status_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/display_mode_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/display_mode_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/network_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/network_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_store.dart';

const _channel = MethodChannel('app.yahagi.kancollebrowser/game_fullscreen');
const _positionKey = 'game_fullscreen_exit_position';
const _probeKey = Key('rotation-audit-game');

void main() {
  testWidgets(
    'corner camera 180 degree turn follows the full portrait IME window',
    (tester) async {
      final audit = _CornerAudit();
      _restoreCornerView(tester);
      await audit.pump(
        tester,
        const Size(400, 900),
        const Rect.fromLTWH(0, 0, 30, 30),
      );
      expect(audit.insets, const EdgeInsets.only(top: 48));
      await audit.pump(
        tester,
        const Size(400, 660),
        const Rect.fromLTWH(0, 0, 30, 30),
        ime: 240,
      );
      expect(audit.insets, const EdgeInsets.only(top: 48));
      await audit.pump(
        tester,
        const Size(400, 660),
        const Rect.fromLTWH(370, 870, 30, 30),
        ime: 240,
      );
      expect(audit.edges, {CameraAvoidanceEdge.bottom});
      expect(audit.insets, const EdgeInsets.only(bottom: 48));
      expect(audit.synchronizationInsets, const EdgeInsets.only(bottom: 48));
      final slot = tester.getRect(find.byKey(_cornerSlotKey));
      expect(audit.bounds.last.top, slot.top);
      expect(audit.bounds.last.height, slot.height);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'corner camera quarter turn uses full portrait axis under a short IME surface',
    (tester) async {
      final audit = _CornerAudit();
      _restoreCornerView(tester);
      await audit.pump(
        tester,
        const Size(900, 400),
        const Rect.fromLTWH(0, 0, 30, 30),
      );
      expect(audit.insets, const EdgeInsets.only(left: 48));
      await audit.pump(
        tester,
        const Size(900, 160),
        const Rect.fromLTWH(0, 0, 30, 30),
        ime: 240,
      );
      expect(audit.insets, const EdgeInsets.only(left: 48));
      // Rotate the full 900x400 window clockwise to 400x900. The keyboard
      // leaves a 400x300 landscape-shaped surface, but the camera is on top.
      await audit.pump(
        tester,
        const Size(400, 300),
        const Rect.fromLTWH(370, 0, 30, 30),
        ime: 600,
      );
      expect(audit.edges, {CameraAvoidanceEdge.top});
      expect(audit.insets, const EdgeInsets.only(top: 48));
      expect(audit.synchronizationInsets, const EdgeInsets.only(top: 48));
      final slot = tester.getRect(find.byKey(_cornerSlotKey));
      expect(audit.bounds.last.top, slot.top);
      expect(audit.bounds.last.height, slot.height);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'near-square real quarter turn swaps width before resolving corner axis',
    (tester) async {
      final audit = _CornerAudit();
      _restoreCornerView(tester);
      await audit.pump(
        tester,
        const Size(800, 801),
        const Rect.fromLTWH(0, 0, 30, 30),
      );
      expect(audit.insets, const EdgeInsets.only(top: 48));
      await audit.pump(
        tester,
        const Size(800, 799),
        const Rect.fromLTWH(0, 0, 30, 30),
        ime: 2,
      );
      expect(audit.insets, const EdgeInsets.only(top: 48));
      // Full-window dimensions are now 801x800, with the top-left cutout
      // rotated to top-right. One pixel of IME shrink must not undo that turn.
      await audit.pump(
        tester,
        const Size(801, 799),
        const Rect.fromLTWH(771, 0, 30, 30),
        ime: 1,
      );
      expect(audit.edges, {CameraAvoidanceEdge.right});
      expect(audit.insets, const EdgeInsets.only(right: 48));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final hd in [false, true]) {
    for (final dpr in [1.0, 2.625]) {
      testWidgets(
        'real shell restores latest rotated geometry and game click HD=$hd DPR=$dpr',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          final oldTimer = GameStateController.disableTimerForTest;
          GameStateController.disableTimerForTest = true;
          addTearDown(() => GameStateController.disableTimerForTest = oldTimer);
          tester.view.devicePixelRatio = dpr;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDisplayFeatures);
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            _channel,
            (_) async => null,
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(_channel, null),
          );

          final harness = await _RotationApp.load();
          for (final notifier in harness.notifiers) {
            addTearDown(notifier.dispose);
          }
          await harness.layout.setHdEnabled(hd);
          await harness.layout.setWorkspaceMenuPosition('right');
          await harness.layout.setCameraAvoidanceDistance(72);
          await harness.layout.setCameraAvoidanceEnabled(true);
          _window(tester, const Size(390, 844), CameraAvoidanceEdge.top);
          await tester.pumpWidget(harness.app);
          await _settle(tester);
          final normalPortrait = tester.getRect(find.byKey(_probeKey));
          final state = tester.state(find.byType(_RotationGame));
          final nativeState = tester.state(
            find.byType(NativeActivityGameSurface),
          );
          final slotState = tester.state(find.byType(NativeGameSurfaceSlot));

          _window(tester, const Size(844, 390), CameraAvoidanceEdge.left);
          await _settle(tester);
          harness.app.toolbarController.reveal();
          await _settle(tester);
          tester
              .widget<GameBrowserToolbar>(
                find.byType(GameBrowserToolbar, skipOffstage: false),
              )
              .onEnterFullscreen!();
          await _settle(tester);
          expect(
            tester
                .widget<GameSurfaceViewport>(find.byType(GameSurfaceViewport))
                .fullscreen,
            isTrue,
          );

          // Include 180-degree same-size changes and 90-degree size changes.
          for (final frame in [
            (const Size(844, 390), CameraAvoidanceEdge.right),
            (const Size(390, 844), CameraAvoidanceEdge.bottom),
            (const Size(390, 844), CameraAvoidanceEdge.top),
            (const Size(844, 390), CameraAvoidanceEdge.left),
            (const Size(390, 844), CameraAvoidanceEdge.top),
          ]) {
            _window(tester, frame.$1, frame.$2);
            await _settle(tester);
            await _expectBoundsAndClick(tester, harness);
            expect(tester.state(find.byType(_RotationGame)), same(state));
            expect(
              tester.state(find.byType(NativeActivityGameSurface)),
              same(nativeState),
            );
            expect(
              tester.state(find.byType(NativeGameSurfaceSlot)),
              same(slotState),
            );
          }
          tester
              .widget<GameFullscreenControls>(
                find.byType(GameFullscreenControls),
              )
              .onExit();
          harness.app.toolbarController.collapse();
          await _settle(tester);
          expect(
            tester
                .widget<GameSurfaceViewport>(find.byType(GameSurfaceViewport))
                .fullscreen,
            isFalse,
          );
          _rectClose(tester.getRect(find.byKey(_probeKey)), normalPortrait);
          await _expectBoundsAndClick(tester, harness);

          final game = tester.getRect(find.byKey(_probeKey));
          final localTarget = Offset(game.width * .37, game.height * .61);
          final count = harness.clicks.length;
          await tester.tapAt(game.topLeft + localTarget);
          expect(harness.clicks.length, count + 1);
          expect(harness.clicks.last.dx, closeTo(localTarget.dx, .001));
          expect(harness.clicks.last.dy, closeTo(localTarget.dy, .001));
          expect(tester.state(find.byType(_RotationGame)), same(state));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }

  testWidgets('native queued geometry skips superseded frames after exit', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final configs = <Map>[];
    final first = Completer<void>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
      call,
    ) async {
      configs.add(call.arguments as Map);
      if (configs.length == 1) await first.future;
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        null,
      ),
    );
    final frame = ValueNotifier((true, const EdgeInsets.only(left: 80)));
    addTearDown(frame.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder(
          valueListenable: frame,
          builder: (context, value, child) => Padding(
            padding: value.$2,
            child: GameFullscreenControls(
              active: value.$1,
              useNativeOverlay: true,
              onExit: () {},
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(configs, hasLength(1));
    frame.value = (true, const EdgeInsets.only(right: 80));
    await tester.pump();
    frame.value = (false, const EdgeInsets.only(right: 80));
    await tester.pump();
    first.complete();
    await tester.pumpAndSettle();
    expect(configs.last['active'], false);
    expect(
      configs.skip(1).where((config) => config['active'] == true),
      isEmpty,
      reason:
          'a queued old fullscreen frame must not re-enable the native '
          'button after the widget has already exited',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'native moved from old camera frame cannot change current anchor',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        _positionKey: <String>['0.5', '0.0'],
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final configs = <Map>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
        call,
      ) async {
        configs.add(call.arguments as Map);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _channel,
          null,
        ),
      );
      final inset = ValueNotifier(const EdgeInsets.only(left: 80));
      addTearDown(inset.dispose);
      var exits = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder(
            valueListenable: inset,
            builder: (context, value, child) => CameraAvoidanceScope(
              enabled: true,
              windowSize: const Size(1000, 600),
              insets: value,
              child: Padding(padding: value, child: child),
            ),
            child: GameFullscreenControls(
              active: true,
              useNativeOverlay: true,
              onExit: () => exits++,
              confirmExit: (_) async => true,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final oldFrame = Map.of(configs.last);
      expect(oldFrame['x'], 523.0);
      inset.value = const EdgeInsets.only(right: 80);
      await tester.pumpAndSettle();
      expect(configs.last['x'], 443.0);
      // The native UI emits these coordinates in its previous camera frame;
      // delivery may follow Flutter's already completed same-size rotation.
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        _channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('moved', {
            'x': oldFrame['x'],
            'y': oldFrame['y'],
            if (oldFrame['geometryRevision'] != null)
              'geometryRevision': oldFrame['geometryRevision'],
          }),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
      expect(
        configs.last['x'],
        443.0,
        reason:
            'old global coordinates cannot be interpreted in the new '
            'local viewport and persisted as a different anchor',
      );
      final saved = (await SharedPreferences.getInstance()).getStringList(
        _positionKey,
      )!;
      expect(double.parse(saved[0]), closeTo(.5, .0001));
      expect(double.parse(saved[1]), 0);
      await _nativeEvent(tester, 'exit', {
        'geometryRevision': oldFrame['geometryRevision'],
      });
      expect(exits, 0, reason: 'an old native tap cannot exit the new frame');
      await _nativeEvent(tester, 'moved', {
        'x': 600.0,
        'y': 0.0,
        'geometryRevision': configs.last['geometryRevision'],
      });
      expect(
        configs.last['x'],
        600.0,
        reason: 'the current frame must still accept native drags',
      );
      await _nativeEvent(tester, 'exit', {
        'geometryRevision': configs.last['geometryRevision'],
      });
      expect(exits, 1, reason: 'the current frame must still accept exit taps');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Flutter drag survives camera swap and cancels on fullscreen exit',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        _positionKey: <String>['0.5', '0.0'],
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final frame = ValueNotifier((true, const EdgeInsets.only(left: 80)));
      addTearDown(frame.dispose);
      var exits = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder(
            valueListenable: frame,
            builder: (context, value, child) => CameraAvoidanceScope(
              enabled: true,
              windowSize: const Size(1000, 600),
              insets: value.$2,
              child: Padding(
                padding: value.$2,
                child: GameFullscreenControls(
                  active: value.$1,
                  onExit: () => exits++,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byKey(const Key('game-exit-fullscreen'));
      final controlState = tester.state(find.byType(GameFullscreenControls));
      final drag = await tester.startGesture(tester.getCenter(button));
      await drag.moveBy(const Offset(-80, 180));
      await tester.pump();
      frame.value = (true, const EdgeInsets.only(right: 80));
      await tester.pump();
      await drag.moveBy(const Offset(-600, 70));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      final rect = tester.getRect(button);
      expect(rect.left, 0);
      expect(rect.right, lessThanOrEqualTo(920));
      expect(rect.top, inInclusiveRange(0, 566));
      expect(exits, 0);
      final savedBeforeExit = (await SharedPreferences.getInstance())
          .getStringList(_positionKey)!;

      final interrupted = await tester.startGesture(tester.getCenter(button));
      await interrupted.moveBy(const Offset(90, -40));
      await tester.pump();
      frame.value = (false, const EdgeInsets.only(right: 80));
      await tester.pump();
      await interrupted.up();
      await tester.pump();
      expect(button, findsNothing);
      frame.value = (true, const EdgeInsets.only(right: 80));
      await tester.pumpAndSettle();
      _rectClose(tester.getRect(button), rect);
      expect(
        (await SharedPreferences.getInstance()).getStringList(_positionKey),
        savedBeforeExit,
      );
      expect(
        tester.state(find.byType(GameFullscreenControls)),
        same(controlState),
      );
      expect(exits, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'native hint disappearance keeps the current drag geometry stamp',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        _positionKey: <String>['0.5', '0.0'],
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final configs = <Map>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
        call,
      ) async {
        configs.add(call.arguments as Map);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GameFullscreenControls(
            active: true,
            useNativeOverlay: true,
            onExit: () {},
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final stamp = configs.last['geometryRevision'];
      expect(stamp, isA<num>());
      expect(configs.last['hint'], isNotEmpty);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(configs.last['hint'], isEmpty);
      expect(
        configs.last['geometryRevision'],
        stamp,
        reason: 'removing hint text does not change the native drag geometry',
      );
      await _nativeEvent(tester, 'moved', {
        'x': 300.0,
        'y': 0.0,
        'geometryRevision': stamp,
      });
      expect(configs.last['x'], 300.0);
      final saved = (await SharedPreferences.getInstance()).getStringList(
        _positionKey,
      )!;
      expect(double.parse(saved[0]), closeTo(300 / 966, .0001));
      expect(double.parse(saved[1]), 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

const _cornerSlotKey = Key('rotation-corner-slot');

void _restoreCornerView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewInsets);
}

class _CornerAudit {
  EdgeInsets insets = EdgeInsets.zero;
  EdgeInsets? synchronizationInsets;
  Set<CameraAvoidanceEdge> edges = {};
  final bounds = <NativeGameWebViewBounds>[];

  Future<void> _onBounds(NativeGameWebViewBounds value) async =>
      bounds.add(value);
  Future<void> _onVisible(bool value) async {}

  Future<void> pump(
    WidgetTester tester,
    Size size,
    Rect cutout, {
    double ime = 0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.viewInsets = FakeViewPadding(bottom: ime);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQueryData(
            size: size,
            viewInsets: EdgeInsets.only(bottom: ime),
            displayFeatures: [
              DisplayFeature(
                bounds: cutout,
                type: DisplayFeatureType.cutout,
                state: DisplayFeatureState.unknown,
              ),
            ],
          ),
          child: CameraAvoidanceViewport(
            enabled: true,
            distance: 48,
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) {
            final scope = CameraAvoidanceScope.maybeOf(context)!;
            insets = scope.insets;
            synchronizationInsets = scope.synchronizationInsets;
            edges = scope.cutoutEdges;
            return NativeGameSurfaceSlot(
              key: _cornerSlotKey,
              onBoundsChanged: _onBounds,
              onVisibilityChanged: _onVisible,
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }
}

Future<void> _nativeEvent(
  WidgetTester tester,
  String method,
  Map<String, Object?> arguments,
) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    _channel.name,
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
    (_) {},
  );
  await tester.pumpAndSettle();
}

void _window(WidgetTester tester, Size size, CameraAvoidanceEdge edge) {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  final rect = switch (edge) {
    CameraAvoidanceEdge.left => Rect.fromLTWH(4, size.height / 2 - 12, 24, 24),
    CameraAvoidanceEdge.right => Rect.fromLTWH(
      size.width - 28,
      size.height / 2 - 12,
      24,
      24,
    ),
    CameraAvoidanceEdge.top => Rect.fromLTWH(size.width / 2 - 12, 4, 24, 24),
    CameraAvoidanceEdge.bottom => Rect.fromLTWH(
      size.width / 2 - 12,
      size.height - 28,
      24,
      24,
    ),
  };
  tester.view.displayFeatures = [
    DisplayFeature(
      bounds: rect,
      type: DisplayFeatureType.cutout,
      state: DisplayFeatureState.unknown,
    ),
  ];
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
  await tester.pump();
}

void _rectClose(Rect actual, Rect expected) {
  expect(actual.left, closeTo(expected.left, .001));
  expect(actual.top, closeTo(expected.top, .001));
  expect(actual.width, closeTo(expected.width, .001));
  expect(actual.height, closeTo(expected.height, .001));
}

Future<void> _expectBoundsAndClick(
  WidgetTester tester,
  _RotationApp harness,
) async {
  final game = tester.getRect(find.byKey(_probeKey));
  final scope = tester.widget<CameraAvoidanceScope>(
    find.byType(CameraAvoidanceScope),
  );
  final safe = Rect.fromLTWH(
    scope.insets.left,
    scope.insets.top,
    scope.windowSize.width - scope.insets.horizontal,
    scope.windowSize.height - scope.insets.vertical,
  );
  expect(game.width / game.height, closeTo(1200 / 720, .0001));
  expect(game.left, greaterThanOrEqualTo(safe.left - .001));
  expect(game.top, greaterThanOrEqualTo(safe.top - .001));
  expect(game.right, lessThanOrEqualTo(safe.right + .001));
  expect(game.bottom, lessThanOrEqualTo(safe.bottom + .001));
  final native = harness.bounds.last;
  _rectClose(
    Rect.fromLTWH(native.left, native.top, native.width, native.height),
    game,
  );
  expect(native.devicePixelRatio, tester.view.devicePixelRatio);
  final count = harness.clicks.length;
  final local = Offset(game.width * .41, game.height * .57);
  await tester.tapAt(game.topLeft + local);
  expect(harness.clicks.length, count + 1);
  expect(harness.clicks.last.dx, closeTo(local.dx, .001));
  expect(harness.clicks.last.dy, closeTo(local.dy, .001));
  expect(tester.takeException(), isNull);
}

class _RotationApp {
  _RotationApp(this.app, this.layout, this.notifiers, this.bounds, this.clicks);
  final YahagiApp app;
  final LayoutSettingsController layout;
  final List<ChangeNotifier> notifiers;
  final List<NativeGameWebViewBounds> bounds;
  final List<Offset> clicks;

  static Future<_RotationApp> load() async {
    final layout = await LayoutSettingsController.load(
      SharedPreferencesLayoutSettingsStore(),
    );
    final gameState = GameStateController();
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
    final clicks = <Offset>[];
    final nativePort = _RotationNativePort(bounds);
    final observer = YahagiGameRouteObserver();
    return _RotationApp(
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
        gameRouteObserver: observer,
        gameSurface: _RotationGame(
          onClick: clicks.add,
          child: NativeActivityGameSurface(
            statusController: status,
            browserController: browser,
            toolbarController: toolbar,
            routeObserver: observer,
            portFactory: () => nativePort,
            startupOrchestrator: _RotationStartup(),
          ),
        ),
      ),
      layout,
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
      clicks,
    );
  }
}

class _RotationGame extends StatefulWidget {
  const _RotationGame({required this.child, required this.onClick});
  final Widget child;
  final ValueChanged<Offset> onClick;
  @override
  State<_RotationGame> createState() => _RotationGameState();
}

class _RotationGameState extends State<_RotationGame> {
  @override
  Widget build(BuildContext context) => GestureDetector(
    key: _probeKey,
    behavior: HitTestBehavior.opaque,
    onTapDown: (details) => widget.onClick(details.localPosition),
    child: widget.child,
  );
}

class _RotationNativePort implements NativeActivityGameWebViewPort {
  _RotationNativePort(this.bounds);
  final List<NativeGameWebViewBounds> bounds;
  final _events = StreamController<NativeGameWebViewEvent>.broadcast(
    sync: true,
  );
  @override
  Stream<NativeGameWebViewEvent> get events => _events.stream;
  @override
  Future<int> create() async => 7;
  @override
  Future<void> setBounds(NativeGameWebViewBounds value) async =>
      bounds.add(value);
  @override
  Future<void> setVisible(bool visible) async {}
  @override
  Future<void> dispose() async => _events.close();
  @override
  Future<void> loadUri(Uri uri) async {}
  @override
  Future<void> showLocalHome() async {}
  @override
  Future<void> reload() async {}
  @override
  Future<GameFrameReloadResult> reloadGameFrame() async =>
      GameFrameReloadResult.reloaded;
  @override
  Future<bool> canGoBack() async => false;
  @override
  Future<void> goBack() async {}
  @override
  Future<void> runJavaScript(String javascript) async {}
  @override
  Future<void> fitGameScreen() async {}
  @override
  Future<void> clearCache() async {}
  @override
  Future<void> clearSession() async {}
}

class _RotationStartup implements GameSurfaceStartupOrchestrator {
  @override
  Future<GameSurfaceNetworkResult> applyNetworkSettings() async =>
      const GameSurfaceNetworkResult.success();
  @override
  Future<void> runCaptureStartup({
    required Future<void> Function() waitForSurface,
    required bool Function() isActive,
    required Future<void> Function() navigate,
  }) async {
    await waitForSurface();
    if (isActive()) await navigate();
  }

  @override
  Future<void> prepareCapture() async {}
  @override
  Future<void> attachAudioPortOnce() async {}
  @override
  Future<bool> attachFrameRatePlatformPort() async => true;
  @override
  void dispose() {}
}
