import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Exercise the actual SharedPreferences cache when platform writes fail.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/settings/display_mode_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/display_mode_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/camera_avoidance_settings.dart';
import 'package:yahagi_kancolle_browser/src/settings/camera_avoidance_settings_section.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/screen_settings_page.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  for (final throwsOnWrite in [false, true]) {
    for (final hadSavedValue in [false, true]) {
      test('platform write failure restores cached settings '
          '($throwsOnWrite, $hadSavedValue)', () async {
        final platform = _ControlledPreferencesStore({
          if (hadSavedValue)
            'flutter.layout_camera_avoidance_v1':
                '{"enabled":true,"distance":42}',
        });
        SharedPreferencesStorePlatform.instance = platform;
        final controller = await LayoutSettingsController.load(
          SharedPreferencesLayoutSettingsStore(),
        );
        addTearDown(controller.dispose);
        platform.failWrites = true;
        platform.throwsOnWrite = throwsOnWrite;
        await controller.setCameraAvoidanceDistance(88);
        expect(controller.cameraAvoidanceDistance, hadSavedValue ? 42 : 0);
        final restored = await LayoutSettingsController.load(
          SharedPreferencesLayoutSettingsStore(),
        );
        addTearDown(restored.dispose);
        expect(restored.cameraAvoidanceEnabled, hadSavedValue);
        expect(restored.cameraAvoidanceDistance, hadSavedValue ? 42 : 0);
        platform.failWrites = false;
        await controller.setCameraAvoidanceDistance(24);
        await (await SharedPreferences.getInstance()).reload();
        expect(
          await SharedPreferencesLayoutSettingsStore()
              .loadCameraAvoidanceSettings()
              .then((settings) => settings.distance),
          24,
        );
      });
    }
  }

  test('old settings stores load disabled with a zero distance', () async {
    final controller = await LayoutSettingsController.load(_LegacyStore());
    addTearDown(controller.dispose);
    expect(controller.cameraAvoidanceEnabled, isFalse);
    expect(controller.cameraAvoidanceDistance, 0);
    await controller.setCameraAvoidanceEnabled(true);
    await controller.setCameraAvoidanceDistance(42);
    expect(controller.cameraAvoidanceEnabled, isTrue);
    expect(controller.cameraAvoidanceDistance, 42);
  });

  test(
    'settings persist together and disabling retains the distance',
    () async {
      final controller = await LayoutSettingsController.load(
        SharedPreferencesLayoutSettingsStore(),
      );
      addTearDown(controller.dispose);
      await controller.setCameraAvoidanceDistance(51);
      await controller.setCameraAvoidanceEnabled(true);
      await controller.setCameraAvoidanceEnabled(false);
      expect(controller.cameraAvoidanceDistance, 51);
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString('layout_camera_avoidance_v1')!), {
        'enabled': false,
        'distance': 51,
      });
      final restored = await LayoutSettingsController.load(
        SharedPreferencesLayoutSettingsStore(),
      );
      addTearDown(restored.dispose);
      expect(restored.cameraAvoidanceEnabled, isFalse);
      expect(restored.cameraAvoidanceDistance, 51);
      await restored.setCameraAvoidanceEnabled(true);
      expect(restored.cameraAvoidanceDistance, 51);
    },
  );

  test('corrupt preferences normalize without breaking startup', () async {
    for (final value in <Object>[
      3,
      false,
      'invalid json',
      '[]',
      'null',
      '{"enabled":"true","distance":"40"}',
      '{"enabled":true,"distance":1e999}',
    ]) {
      SharedPreferences.setMockInitialValues({
        'layout_camera_avoidance_v1': value,
      });
      final controller = await LayoutSettingsController.load(
        SharedPreferencesLayoutSettingsStore(),
      );
      expect(controller.cameraAvoidanceDistance, 0, reason: '$value');
      expect(
        controller.cameraAvoidanceEnabled,
        value == '{"enabled":true,"distance":1e999}',
        reason: '$value',
      );
      controller.dispose();
    }
    for (final (raw, expected) in [(-9, 0), (400, 120), (37.5, 37.5)]) {
      SharedPreferences.setMockInitialValues({
        'layout_camera_avoidance_v1': jsonEncode({
          'enabled': true,
          'distance': raw,
        }),
      });
      final controller = await LayoutSettingsController.load(
        SharedPreferencesLayoutSettingsStore(),
      );
      expect(controller.cameraAvoidanceDistance, expected);
      controller.dispose();
    }
  });

  test(
    'distance setters normalize and notify only effective changes',
    () async {
      final controller = await LayoutSettingsController.load(_LegacyStore());
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);
      for (final invalid in [
        double.nan,
        double.infinity,
        -double.infinity,
        -1.0,
      ]) {
        await controller.setCameraAvoidanceDistance(invalid);
      }
      expect(notifications, 0);
      await controller.setCameraAvoidanceDistance(125);
      expect(controller.cameraAvoidanceDistance, 120);
      expect(notifications, 1);
      await controller.setCameraAvoidanceDistance(120);
      expect(notifications, 1);
    },
  );

  test('rapid changes preview immediately and save in order', () async {
    final store = _DelayedCameraStore();
    final controller = await LayoutSettingsController.load(store);
    addTearDown(controller.dispose);
    final first = controller.setCameraAvoidanceEnabled(true);
    await Future<void>.delayed(Duration.zero);
    final second = controller.setCameraAvoidanceDistance(64);
    final third = controller.setCameraAvoidanceEnabled(false);
    expect(controller.cameraAvoidanceEnabled, isFalse);
    expect(controller.cameraAvoidanceDistance, 64);
    expect(store.pending, hasLength(1));
    store.pending[0].complete();
    await first;
    await Future<void>.delayed(Duration.zero);
    expect(store.pending, hasLength(2));
    store.pending[1].complete();
    await second;
    await Future<void>.delayed(Duration.zero);
    expect(store.pending, hasLength(3));
    store.pending[2].complete();
    await third;
    expect(store.saved.map((s) => (s.enabled, s.distance)), [
      (true, 0),
      (true, 64),
      (false, 64),
    ]);
  });

  test(
    'save failure restores the last durable settings and queue recovers',
    () async {
      final store = _DelayedCameraStore();
      final controller = await LayoutSettingsController.load(store);
      addTearDown(controller.dispose);
      final failed = controller.setCameraAvoidanceDistance(82);
      await Future<void>.delayed(Duration.zero);
      store.pending[0].completeError(StateError('disk unavailable'));
      await failed;
      expect(controller.cameraAvoidanceDistance, 0);
      final recovered = controller.setCameraAvoidanceDistance(29);
      await Future<void>.delayed(Duration.zero);
      store.pending[1].complete();
      await recovered;
      expect(controller.cameraAvoidanceDistance, 29);
    },
  );

  test('an old save failure cannot undo a newer live edit', () async {
    final store = _DelayedCameraStore();
    final controller = await LayoutSettingsController.load(store);
    addTearDown(controller.dispose);
    final old = controller.setCameraAvoidanceEnabled(true);
    await Future<void>.delayed(Duration.zero);
    final latest = controller.setCameraAvoidanceDistance(72);
    store.pending[0].completeError(StateError('old request failed'));
    await old;
    await Future<void>.delayed(Duration.zero);
    expect(controller.cameraAvoidanceEnabled, isTrue);
    expect(controller.cameraAvoidanceDistance, 72);
    store.pending[1].complete();
    await latest;
    expect(store.saved.single.enabled, isTrue);
    expect(store.saved.single.distance, 72);
  });

  test(
    'pending saves finish safely after the controller is disposed',
    () async {
      final store = _DelayedCameraStore();
      final controller = await LayoutSettingsController.load(store);
      final save = controller.setCameraAvoidanceDistance(30);
      await Future<void>.delayed(Duration.zero);
      controller.dispose();
      store.pending.single.completeError(StateError('late failure'));
      await save;
      await controller.setCameraAvoidanceDistance(50);
      await controller.setCameraAvoidanceEnabled(true);
      expect(store.pending, hasLength(1));
    },
  );

  test(
    'thousands of mixed edits persist the final normalized snapshot',
    () async {
      final random = Random(641783);
      final controller = await LayoutSettingsController.load(
        SharedPreferencesLayoutSettingsStore(),
      );
      addTearDown(controller.dispose);
      var enabled = false;
      var distance = 0.0;
      final saves = <Future<void>>[];
      for (var index = 0; index < 2000; index++) {
        if (random.nextInt(4) == 0) {
          enabled = random.nextBool();
          saves.add(controller.setCameraAvoidanceEnabled(enabled));
        } else {
          final value = random.nextDouble() * 220 - 50;
          distance = value.clamp(0, 120);
          saves.add(controller.setCameraAvoidanceDistance(value));
        }
        expect(controller.cameraAvoidanceEnabled, enabled);
        expect(controller.cameraAvoidanceDistance, distance);
      }
      await Future.wait(saves);
      final restored = await LayoutSettingsController.load(
        SharedPreferencesLayoutSettingsStore(),
      );
      addTearDown(restored.dispose);
      expect(restored.cameraAvoidanceEnabled, enabled);
      expect(restored.cameraAvoidanceDistance, distance);
    },
  );

  testWidgets('screen settings expose camera avoidance disabled by default', (
    tester,
  ) async {
    final controller = await LayoutSettingsController.load(
      SharedPreferencesLayoutSettingsStore(),
    );
    final display = await DisplayModeController.load(MemoryDisplayModeStore());
    addTearDown(controller.dispose);
    addTearDown(display.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScreenSettingsPage(
          layoutSettingsController: controller,
          displayModeController: display,
        ),
      ),
    );

    final toggle = find.byKey(const Key('settings-camera-avoidance-switch'));
    expect(toggle, findsOneWidget);
    expect(tester.widget<Switch>(toggle).value, isFalse);
    expect(find.text('摄像头避让'), findsOneWidget);
    expect(find.text('调整摄像头一侧的界面留白，翻转屏幕时自动换边。'), findsOneWidget);
    expect(
      find.byKey(const Key('settings-camera-avoidance-distance-slider')),
      findsNothing,
    );
  });

  for (final locale in AppLocalizations.supportedLocales) {
    for (final width in [180.0, 320.0, 900.0]) {
      testWidgets('one live distance slider fits $locale at $width px', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(() => tester.view.resetPhysicalSize());
        addTearDown(() => tester.view.resetDevicePixelRatio());
        final controller = await LayoutSettingsController.load(
          SharedPreferencesLayoutSettingsStore(),
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: CameraAvoidanceSettingsSection(controller: controller),
                ),
              ),
            ),
          ),
        );
        final toggle = find.byKey(
          const Key('settings-camera-avoidance-switch'),
        );
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        final slider = find.byKey(
          const Key('settings-camera-avoidance-distance-slider'),
        );
        expect(find.byType(Slider), findsOneWidget);
        expect(tester.widget<Slider>(slider).min, 0);
        expect(tester.widget<Slider>(slider).max, 120);
        await tester.ensureVisible(slider);
        final gesture = await tester.startGesture(tester.getCenter(slider));
        await gesture.moveBy(Offset(width / 8, 0));
        await tester.pump();
        expect(controller.cameraAvoidanceDistance, greaterThan(0));
        expect(find.textContaining('px'), findsWidgets);
        await gesture.up();
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(slider, findsNothing);
        expect(controller.cameraAvoidanceDistance, greaterThan(0));
        expect(tester.takeException(), isNull);
      });
    }
  }
}

class _DelayedCameraStore extends SharedPreferencesLayoutSettingsStore {
  final pending = <Completer<void>>[];
  final saved = <CameraAvoidanceSettings>[];

  @override
  Future<void> saveCameraAvoidanceSettings(
    CameraAvoidanceSettings settings,
  ) async {
    final completion = Completer<void>();
    pending.add(completion);
    await completion.future;
    saved.add(settings);
  }
}

class _ControlledPreferencesStore extends InMemorySharedPreferencesStore {
  _ControlledPreferencesStore(super.data) : super.withData();

  bool failWrites = false;
  bool throwsOnWrite = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (failWrites) {
      if (throwsOnWrite) throw StateError('disk unavailable');
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}

class _LegacyStore implements LayoutSettingsStore {
  @override
  Future<double> loadGameAreaRatio() async => .7;
  @override
  Future<double> loadInformationPanelWidth() async => 300;
  @override
  Future<bool> loadAutoZoom() async => true;
  @override
  Future<bool> loadEnhancedDamagePulse() async => false;
  @override
  Future<bool> loadWorkspaceMenuOnRight() async => false;
  @override
  Future<List<String>> loadDashboardCardOrder() async =>
      LayoutSettingsStore.defaultDashboardCardOrder;
  @override
  Future<List<String>> loadDashboardCardCollapsed() async => [];
  @override
  Future<List<String>> loadDashboardCardHidden() async => [];
  @override
  Future<String?> loadFontFamily() async => null;
  @override
  Future<String?> loadLocaleCode() async => null;
  @override
  Future<void> saveFontFamily(String? fontFamily) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
