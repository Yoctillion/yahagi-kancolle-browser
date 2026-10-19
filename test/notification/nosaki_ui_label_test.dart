import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/notification/game_notification_coordinator.dart';
import 'package:yahagi_kancolle_browser/src/settings/notification_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/notification_settings_store.dart';

import '../nosaki_sparkle_calculator_test.dart' show buildNosakiTestState;
import 'game_notification_coordinator_test.dart' show FakeNotificationPort;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final scenario in <(String, String, String, String)>[
    (
      'en',
      'Nosaki morale training almost complete',
      'Nosaki morale training complete',
      '✨ Nosaki morale training',
    ),
    ('ko', '노사키 반짝이 작업 완료 임박', '노사키 반짝이 작업 완료', '✨ 노사키 반짝이 작업'),
  ]) {
    test(
      '${scenario.$1} Nosaki notification UI preserves the fleet name',
      () async {
        SharedPreferences.setMockInitialValues({});
        final settings = NotificationSettingsController(
          store: SharedPreferencesNotificationSettingsStore(),
        );
        await settings.initialize();
        await settings.setMoralePreemptSeconds(60);
        addTearDown(settings.dispose);

        const fleetName = '野埼 · Custom fleet';
        final base = buildNosakiTestState(companionConds: [49, 54]);
        final state = base.copyWith(
          fleets: [
            Fleet(id: 1, name: fleetName, shipIds: base.fleets.single.shipIds),
          ],
        );
        final controller = GameStateController(initialState: state);
        addTearDown(controller.dispose);
        final port = FakeNotificationPort();
        final now = DateTime.utc(2026, 10, 18, 12);
        final coordinator = GameNotificationCoordinator(
          gameStateController: controller,
          settingsController: settings,
          notificationPort: port,
          nowProvider: () => now,
          nosakiSparkleStartedAtProvider: () => now,
          localeCodeProvider: () => scenario.$1,
        );
        addTearDown(coordinator.dispose);
        coordinator.start();
        await Future<void>.delayed(Duration.zero);

        expect(
          port.scheduledAlarms['morale_1_nosaki_preempt']?.title,
          '${scenario.$2} · $fleetName',
        );
        expect(
          port.scheduledAlarms['morale_1_nosaki']?.title,
          '${scenario.$3} · $fleetName',
        );
        final ongoing = port.latestSnapshot!.ongoingItems.singleWhere(
          (item) => item.id == 'morale:1',
        );
        expect(
          ongoing.title,
          scenario.$1 == 'en'
              ? '${scenario.$4} · $fleetName (→ morale 54)'
              : '${scenario.$4} $fleetName (→ 컨디션 54)',
        );
        expect(state.masterShips[996]!.name, '野埼');
        expect(state.masterShips[1002]!.name, '野埼改');
      },
    );
  }
}
