import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// The platform seam allows testing actual SharedPreferences cache rollback.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:yahagi_kancolle_browser/src/settings/app_exit_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'new installs enable exit confirmation without writing a preference',
    () async {
      final settings = await AppExitSettingsController.load();
      addTearDown(settings.dispose);

      expect(settings.enabled, isTrue);
      expect(settings.saving, isFalse);
      expect(settings.saveFailed, isFalse);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.containsKey(AppExitSettingsController.preferenceKey),
        isFalse,
      );
    },
  );

  test('existing users without the new key also get confirmation', () async {
    SharedPreferences.setMockInitialValues({
      'game.mouseWheelCompatibility': true,
    });
    final settings = await AppExitSettingsController.load();
    addTearDown(settings.dispose);

    expect(settings.enabled, isTrue);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('game.mouseWheelCompatibility'), isTrue);
  });

  test('disabling confirmation survives a platform reload', () async {
    final settings = await AppExitSettingsController.load();
    addTearDown(settings.dispose);
    await settings.setEnabled(false);
    await (await SharedPreferences.getInstance()).reload();
    final reloaded = await AppExitSettingsController.load();
    addTearDown(reloaded.dispose);

    expect(settings.enabled, isFalse);
    expect(reloaded.enabled, isFalse);
  });

  test('reenabling confirmation survives a platform reload', () async {
    SharedPreferences.setMockInitialValues({
      AppExitSettingsController.preferenceKey: false,
    });
    final settings = await AppExitSettingsController.load();
    addTearDown(settings.dispose);
    await settings.setEnabled(true);
    await (await SharedPreferences.getInstance()).reload();
    final reloaded = await AppExitSettingsController.load();
    addTearDown(reloaded.dispose);

    expect(reloaded.enabled, isTrue);
  });

  test(
    'loading and keeping the same value never resets a saved choice',
    () async {
      SharedPreferences.setMockInitialValues({
        AppExitSettingsController.preferenceKey: false,
      });
      final platform = _ControlledPreferencesStore({
        'flutter.${AppExitSettingsController.preferenceKey}': false,
      });
      SharedPreferencesStorePlatform.instance = platform;
      final settings = await AppExitSettingsController.load();
      addTearDown(settings.dispose);
      await settings.setEnabled(false);
      final reloaded = await AppExitSettingsController.load();
      addTearDown(reloaded.dispose);

      expect(reloaded.enabled, isFalse);
      expect(platform.writes, 0);
    },
  );

  for (final throwsOnWrite in [false, true]) {
    test(
      'failed write restores the enabled value and preference cache ($throwsOnWrite)',
      () async {
        final platform = _ControlledPreferencesStore({})
          ..failWrites = true
          ..throwsOnWrite = throwsOnWrite;
        SharedPreferencesStorePlatform.instance = platform;
        final settings = await AppExitSettingsController.load();
        addTearDown(settings.dispose);
        await settings.setEnabled(false);
        final reloaded = await AppExitSettingsController.load();
        addTearDown(reloaded.dispose);

        expect(settings.enabled, isTrue);
        expect(settings.saveFailed, isTrue);
        expect(settings.saving, isFalse);
        expect(reloaded.enabled, isTrue);

        platform.failWrites = false;
        await settings.setEnabled(false);
        expect(settings.enabled, isFalse);
        expect(settings.saveFailed, isFalse);
      },
    );
  }

  test(
    'pending writes keep the saved value and reject overlapping toggles',
    () async {
      final platform = _ControlledPreferencesStore({})
        ..writeGate = Completer<bool>();
      SharedPreferencesStorePlatform.instance = platform;
      final settings = await AppExitSettingsController.load();
      addTearDown(settings.dispose);
      final states = <(bool, bool)>[];
      settings.addListener(
        () => states.add((settings.enabled, settings.saving)),
      );

      final write = settings.setEnabled(false);
      expect(settings.saving, isTrue);
      expect(settings.enabled, isTrue);
      await settings.setEnabled(false);
      expect(platform.writes, 1);
      platform.writeGate!.complete(true);
      await write;

      expect(states, [(true, true), (false, false)]);
    },
  );
}

class _ControlledPreferencesStore extends InMemorySharedPreferencesStore {
  _ControlledPreferencesStore(super.data) : super.withData();

  bool failWrites = false;
  bool throwsOnWrite = false;
  int writes = 0;
  Completer<bool>? writeGate;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    writes++;
    if (failWrites) {
      if (throwsOnWrite) throw StateError('Disk write failed');
      return false;
    }
    if (writeGate != null && !await writeGate!.future) return false;
    return super.setValue(valueType, key, value);
  }
}
