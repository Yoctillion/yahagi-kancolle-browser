import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Exercise the real SharedPreferences cache as well as failed platform writes.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'rapid selections persist in selection order despite slow earlier writes',
    () async {
      final store = _DelayedThemeStore();
      final controller = await LayoutSettingsController.load(store);
      addTearDown(controller.dispose);
      final first = controller.setAppThemeMode(AppThemeMode.seaSalt);
      final second = controller.setAppThemeMode(AppThemeMode.skyBlue);
      expect(controller.appThemeMode, AppThemeMode.skyBlue);
      await Future.wait([first, second]);
      expect(store.saved, AppThemeMode.skyBlue);
      expect(store.maximumConcurrentWrites, 1);
    },
  );

  test(
    'a theme change requested by a listener remains the latest selection',
    () async {
      final store = _DelayedThemeStore();
      final controller = await LayoutSettingsController.load(store);
      addTearDown(controller.dispose);
      Future<void>? listenerSelection;
      controller.addListener(() {
        if (controller.appThemeMode == AppThemeMode.seaSalt &&
            listenerSelection == null) {
          listenerSelection = controller.setAppThemeMode(AppThemeMode.skyBlue);
        }
      });
      await controller.setAppThemeMode(AppThemeMode.seaSalt);
      await listenerSelection;
      expect(controller.appThemeMode, AppThemeMode.skyBlue);
      expect(store.saved, AppThemeMode.skyBlue);
    },
  );

  test(
    'a failed latest selection rolls back to the last saved theme and can retry',
    () async {
      final store = _DelayedThemeStore();
      final controller = await LayoutSettingsController.load(store);
      addTearDown(controller.dispose);
      await controller.setAppThemeMode(AppThemeMode.seaSalt);
      store.failing = AppThemeMode.skyBlue;
      await expectLater(
        controller.setAppThemeMode(AppThemeMode.skyBlue),
        completes,
      );
      expect(controller.appThemeMode, AppThemeMode.seaSalt);
      expect(store.saved, AppThemeMode.seaSalt);
      store.failing = null;
      await controller.setAppThemeMode(AppThemeMode.skyBlue);
      expect(store.saved, AppThemeMode.skyBlue);
      expect(controller.appThemeMode, AppThemeMode.skyBlue);
    },
  );

  test(
    'a failed earlier selection does not discard a newer successful choice',
    () async {
      final store = _DelayedThemeStore()..failing = AppThemeMode.seaSalt;
      final controller = await LayoutSettingsController.load(store);
      addTearDown(controller.dispose);
      await expectLater(
        Future.wait([
          controller.setAppThemeMode(AppThemeMode.seaSalt),
          controller.setAppThemeMode(AppThemeMode.skyBlue),
        ]),
        completes,
      );
      expect(store.saved, AppThemeMode.skyBlue);
      expect(controller.appThemeMode, AppThemeMode.skyBlue);
    },
  );

  test(
    'theme read errors preserve startup and use the original appearance',
    () async {
      final controller = await LayoutSettingsController.load(
        _UnreadableThemeStore(),
      );
      addTearDown(controller.dispose);
      expect(controller.appThemeMode, AppThemeMode.dark);
    },
  );

  test(
    'an in-flight failed write can finish after controller disposal',
    () async {
      final store = _DelayedThemeStore()..failing = AppThemeMode.seaSalt;
      final controller = await LayoutSettingsController.load(store);
      final pending = controller.setAppThemeMode(AppThemeMode.seaSalt);
      controller.dispose();
      await expectLater(pending, completes);
    },
  );

  for (final throwsOnWrite in [false, true]) {
    test(
      'failed platform write restores durable theme and cache ($throwsOnWrite)',
      () async {
        final platform = _FailingThemePreferences({
          'flutter.app_theme_mode': 'seaSalt',
          'flutter.layout_locale_code': 'ja',
        })..throwsOnWrite = throwsOnWrite;
        SharedPreferencesStorePlatform.instance = platform;
        final controller = await LayoutSettingsController.load(
          SharedPreferencesLayoutSettingsStore(),
        );
        addTearDown(controller.dispose);
        expect(controller.appThemeMode, AppThemeMode.seaSalt);
        platform.fail = true;
        await expectLater(
          controller.setAppThemeMode(AppThemeMode.skyBlue),
          completes,
        );
        expect(controller.appThemeMode, AppThemeMode.seaSalt);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('app_theme_mode'), 'seaSalt');
        expect(prefs.getString('layout_locale_code'), 'ja');
        final restored = await LayoutSettingsController.load(
          SharedPreferencesLayoutSettingsStore(),
        );
        addTearDown(restored.dispose);
        expect(restored.appThemeMode, AppThemeMode.seaSalt);
        await prefs.reload();
        expect(prefs.getString('app_theme_mode'), 'seaSalt');
        platform.fail = false;
        await controller.setAppThemeMode(AppThemeMode.skyBlue);
        await prefs.reload();
        expect(prefs.getString('app_theme_mode'), 'skyBlue');
      },
    );
  }
}

class _DelayedThemeStore extends SharedPreferencesLayoutSettingsStore {
  AppThemeMode saved = AppThemeMode.dark;
  AppThemeMode? failing;
  int activeWrites = 0;
  int maximumConcurrentWrites = 0;
  @override
  Future<AppThemeMode> loadAppThemeMode() async => saved;
  @override
  Future<void> saveAppThemeMode(AppThemeMode mode) async {
    activeWrites++;
    if (activeWrites > maximumConcurrentWrites) {
      maximumConcurrentWrites = activeWrites;
    }
    try {
      await Future<void>.delayed(
        Duration(milliseconds: mode == AppThemeMode.seaSalt ? 20 : 1),
      );
      if (mode == failing) throw StateError('Simulated theme write failure');
      saved = mode;
    } finally {
      activeWrites--;
    }
  }
}

class _UnreadableThemeStore extends SharedPreferencesLayoutSettingsStore {
  @override
  Future<AppThemeMode> loadAppThemeMode() async =>
      throw StateError('Simulated theme read failure');
}

class _FailingThemePreferences extends InMemorySharedPreferencesStore {
  _FailingThemePreferences(super.data) : super.withData();
  bool fail = false;
  bool throwsOnWrite = false;
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (fail && key == 'flutter.app_theme_mode') {
      if (throwsOnWrite) throw StateError('Simulated theme platform failure');
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}
