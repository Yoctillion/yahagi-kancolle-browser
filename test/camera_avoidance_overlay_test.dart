import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_fullscreen_controls.dart';
import 'package:yahagi_kancolle_browser/src/layout/camera_avoidance.dart';

void main() {
  const channel = MethodChannel('app.yahagi.kancollebrowser/game_fullscreen');

  testWidgets(
    'an exhausted safe viewport restores normal mode without a native pixel leaking outside',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(40, 80);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final configs = <Map>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        configs.add(call.arguments as Map);
        if ((call.arguments as Map)['active'] == false) {
          throw PlatformException(code: 'fullscreen_control_unavailable');
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      var exits = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: CameraAvoidanceScope(
            enabled: true,
            windowSize: const Size(40, 80),
            insets: const EdgeInsets.symmetric(horizontal: 10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: MediaQuery(
                data: const MediaQueryData(
                  size: Size(20, 80),
                  viewPadding: EdgeInsets.only(left: 32),
                ),
                child: GameFullscreenControls(
                  active: true,
                  useNativeOverlay: true,
                  onExit: () => exits++,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(exits, 1);
      expect(configs.last['active'], false);
      expect(configs.last['width'], 0);
      expect(configs.last['minX'], 30);
      expect(configs.last['maxX'], 30);
      await tester.pump();
      expect(exits, 1, reason: 'report an unavailable target once');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'tiny native exit targets shrink to the remaining safe viewport and keep drag coordinates',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final configs = <Map>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        configs.add(call.arguments as Map);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      for (final scenario in [
        (
          size: const Size(40, 80),
          insets: const EdgeInsets.symmetric(horizontal: 10),
          safePadding: EdgeInsets.zero,
          buttonSize: const Size(20, 34),
          moved: const Offset(10, 23),
          anchor: const Offset(1, .5),
        ),
        (
          size: const Size(80, 40),
          insets: const EdgeInsets.symmetric(vertical: 10),
          safePadding: EdgeInsets.zero,
          buttonSize: const Size(34, 20),
          moved: const Offset(23, 10),
          anchor: const Offset(.5, 0),
        ),
        (
          size: const Size(40, 80),
          insets: const EdgeInsets.symmetric(horizontal: 10),
          safePadding: const EdgeInsets.fromLTRB(5, 4, 7, 70),
          buttonSize: const Size(8, 6),
          moved: const Offset(15, 4),
          anchor: const Offset(1, 0),
        ),
      ]) {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = scenario.size;
        final viewport = Size(
          scenario.size.width - scenario.insets.horizontal,
          scenario.size.height - scenario.insets.vertical,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: CameraAvoidanceScope(
              enabled: true,
              windowSize: scenario.size,
              insets: scenario.insets,
              child: Padding(
                padding: scenario.insets,
                child: MediaQuery(
                  data: MediaQueryData(
                    size: viewport,
                    viewPadding: scenario.safePadding,
                  ),
                  child: GameFullscreenControls(
                    active: true,
                    useNativeOverlay: true,
                    onExit: () {},
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(configs.last['width'], scenario.buttonSize.width);
        expect(configs.last['height'], scenario.buttonSize.height);
        final safeBounds = Rect.fromLTWH(
          scenario.insets.left + scenario.safePadding.left,
          scenario.insets.top + scenario.safePadding.top,
          viewport.width - scenario.safePadding.horizontal,
          viewport.height - scenario.safePadding.vertical,
        );
        final config = configs.last;
        expect(config['minX'], safeBounds.left);
        expect(config['minY'], safeBounds.top);
        expect(
          (config['maxX'] as double) + (config['width'] as double),
          safeBounds.right,
        );
        expect(
          (config['maxY'] as double) + (config['height'] as double),
          safeBounds.bottom,
        );
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('moved', {
              'x': scenario.moved.dx,
              'y': scenario.moved.dy,
            }),
          ),
          (_) {},
        );
        await tester.pumpAndSettle();
        expect(configs.last['x'], scenario.moved.dx);
        expect(configs.last['y'], scenario.moved.dy);
        final saved = (await SharedPreferences.getInstance()).getStringList(
          'game_fullscreen_exit_position',
        )!;
        expect(double.parse(saved.first), scenario.anchor.dx);
        expect(double.parse(saved.last), scenario.anchor.dy);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'native controls follow manual camera distance on all edges and screen sizes',
    (tester) async {
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final configs = <Map>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        configs.add(call.arguments as Map);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      for (final scenario in [
        (
          size: const Size(915, 412),
          cutout: const Rect.fromLTWH(0, 180, 32, 52),
          padding: const EdgeInsets.only(left: 32, bottom: 24),
          edge: CameraAvoidanceEdge.left,
        ),
        (
          size: const Size(844, 390),
          cutout: const Rect.fromLTWH(812, 169, 32, 52),
          padding: const EdgeInsets.only(right: 32, bottom: 24),
          edge: CameraAvoidanceEdge.right,
        ),
        (
          size: const Size(344, 740),
          cutout: const Rect.fromLTWH(146, 0, 52, 32),
          padding: const EdgeInsets.only(top: 32, bottom: 24),
          edge: CameraAvoidanceEdge.top,
        ),
        (
          size: const Size(800, 1280),
          cutout: const Rect.fromLTWH(374, 1248, 52, 32),
          padding: const EdgeInsets.only(bottom: 32),
          edge: CameraAvoidanceEdge.bottom,
        ),
      ]) {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = scenario.size * 2.5;
        for (final distance in [0.0, 64.0, 0.0]) {
          final expected = EdgeInsets.fromLTRB(
            scenario.edge == CameraAvoidanceEdge.left ? distance : 0,
            scenario.edge == CameraAvoidanceEdge.top ? distance : 0,
            scenario.edge == CameraAvoidanceEdge.right ? distance : 0,
            scenario.edge == CameraAvoidanceEdge.bottom ? distance : 0,
          );
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: scenario.size,
                  devicePixelRatio: 2.5,
                  viewPadding: scenario.padding,
                  displayFeatures: [
                    DisplayFeature(
                      bounds: scenario.cutout,
                      type: DisplayFeatureType.cutout,
                      state: DisplayFeatureState.unknown,
                    ),
                  ],
                ),
                child: CameraAvoidanceViewport(
                  enabled: true,
                  distance: distance,
                  child: GameFullscreenControls(
                    active: true,
                    useNativeOverlay: true,
                    onExit: () {},
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final config = configs.last;
          expect(config['minX'], expected.left);
          expect(config['minY'], expected.top);
          expect(config['maxX'], scenario.size.width - expected.right - 34);
          expect(
            config['maxY'],
            scenario.size.height -
                expected.bottom -
                34 -
                (scenario.edge == CameraAvoidanceEdge.bottom ? 0 : 24),
          );
          expect(config['contentLeft'], expected.left);
          expect(config['contentTop'], expected.top);
          expect(
            config['contentWidth'],
            scenario.size.width - expected.horizontal,
          );
          expect(
            config['contentHeight'],
            scenario.size.height - expected.vertical,
          );
          expect(config['scale'], 2.5);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'native exit bounds include viewport and nested widget origins after layout',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final configs = <Map>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        configs.add(call.arguments as Map);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final insets = ValueNotifier(const EdgeInsets.only(left: 90));
      addTearDown(insets.dispose);
      const controlsKey = Key('native-controls');
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<EdgeInsets>(
            valueListenable: insets,
            builder: (context, value, child) => CameraAvoidanceScope(
              insets: value,
              windowSize: const Size(1000, 600),
              enabled: true,
              child: Padding(padding: value, child: child),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(11, 17, 23, 29),
              child: GameFullscreenControls(
                key: controlsKey,
                active: true,
                useNativeOverlay: true,
                onExit: () {},
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(controlsKey)), const Offset(101, 17));
      expect(configs.last['minX'], 101.0);
      expect(configs.last['minY'], 17.0);
      expect(configs.last['maxX'], 943.0);
      expect(configs.last['maxY'], 537.0);
      expect(configs.last['x'], 943.0);
      expect(configs.last['y'], 17.0);
      expect(configs.last['contentLeft'], 90.0);
      expect(configs.last['contentTop'], 0.0);
      expect(configs.last['contentWidth'], 910.0);
      expect(configs.last['contentHeight'], 600.0);

      // A 180-degree rotation can change only the consumed edge, leaving this
      // widget's size unchanged. The native position must use the new frame.
      final previousCalls = configs.length;
      insets.value = const EdgeInsets.only(right: 90);
      await tester.pumpAndSettle();
      expect(configs.length, greaterThan(previousCalls));
      expect(tester.getTopLeft(find.byKey(controlsKey)), const Offset(11, 17));
      expect(configs.last['minX'], 11.0);
      expect(configs.last['maxX'], 853.0);
      expect(configs.last['x'], 853.0);
      expect(configs.last['contentLeft'], 0.0);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'native drag uses window coordinates and saves a local fractional anchor',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final configs = <Map>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        configs.add(call.arguments as Map);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Padding(
            padding: const EdgeInsets.only(left: 100, top: 60),
            child: GameFullscreenControls(
              active: true,
              useNativeOverlay: true,
              onExit: () {},
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('moved', {'x': 100.0, 'y': 313.0}),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
      final saved = (await SharedPreferences.getInstance()).getStringList(
        'game_fullscreen_exit_position',
      )!;
      expect(saved.first, '0.0');
      expect(double.parse(saved.last), closeTo(0.5, 0.0001));
      expect(configs.last['x'], 100.0);
      expect(configs.last['y'], 313.0);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
