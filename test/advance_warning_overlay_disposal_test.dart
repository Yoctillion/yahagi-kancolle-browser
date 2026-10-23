import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/account/account_session.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_damage_alert.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/capture/battle_result_warning_overlay.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_controller.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_port.dart';
import 'package:yahagi_kancolle_browser/src/capture/sortie_warning_session.dart';
import 'package:yahagi_kancolle_browser/src/game_state/combat_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_store.dart';

import 'fixtures/kcsapi_fixtures.dart';

void main() {
  for (final shared in [false, true]) {
    testWidgets(
      'removing an overlay closes its open warning with shared session $shared',
      (tester) async {
        final account = AccountSession(initialMemberId: 1001);
        final capture = GameCaptureController();
        final port = _DisposalCapturePort();
        await capture.attach(port, enabled: true);
        final settings = await SafetySettingsController.load(
          MemorySafetySettingsStore(),
        );
        await settings.setBattleWarningMode(BattleWarningMode.confirm);
        final session = shared ? SortieWarningSession() : null;
        final visible = ValueNotifier<bool>(true);
        final navigatorKey = GlobalKey<NavigatorState>();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          visible.dispose();
          session?.dispose();
          settings.dispose();
          capture.dispose();
          port.dispose();
          account.dispose();
        });
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigatorKey,
            home: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (context, showOverlay, child) {
                if (!showOverlay) return const SizedBox.expand();
                return BattleResultWarningOverlay(
                  accountSession: account,
                  gameCaptureController: capture,
                  loadSafetyState: () async => _activeSortie,
                  safetySettingsController: settings,
                  damageAlertPort: const _DisposalDamageAlertPort(),
                  damageControlStateTrusted: () => true,
                  warningSession: session,
                  child: const SizedBox.expand(),
                );
              },
            ),
          ),
        );
        final originalNavigator = navigatorKey.currentState;
        port.add(kcsapiEvent('/kcsapi/api_req_map/next', const {}));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        final oldMuteButtonPosition = tester.getCenter(find.text('此次出击不再提醒'));
        final oldMuteCallback = tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '此次出击不再提醒'))
            .onPressed!;
        await tester.tap(find.text('确认了解'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        oldMuteCallback();
        await tester.pumpAndSettle();
        port.add(
          kcsapiEvent('/kcsapi/api_req_map/next', const {}, sequence: 2),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (session != null) expect(session.isMuted, isFalse);

        visible.value = false;
        await tester.pumpAndSettle();

        expect(navigatorKey.currentState, same(originalNavigator));
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('此次出击不再提醒'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tapAt(oldMuteButtonPosition);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
        if (session != null) expect(session.isMuted, isFalse);
      },
    );
  }
}

const _activeSortie = GameState(
  memberId: 1001,
  hasEquipmentInventory: true,
  ships: {
    101: OwnedShip(id: 101, masterId: 1, level: 99, currentHp: 20, maxHp: 20),
    102: OwnedShip(id: 102, masterId: 2, level: 99, currentHp: 2, maxHp: 20),
  },
  fleets: [
    Fleet(id: 1, name: '第一舰队', shipIds: [101, 102]),
  ],
  combatState: CombatState(sortieFleetId: 1, isActive: true),
);

final class _DisposalDamageAlertPort implements BattleDamageAlertPort {
  const _DisposalDamageAlertPort();

  @override
  Future<void> alert(BattleDamageAlertSeverity severity) async {}
}

final class _DisposalCapturePort implements GameCapturePort {
  final StreamController<CapturedApiEvent> _events =
      StreamController<CapturedApiEvent>.broadcast(sync: true);

  @override
  Stream<CapturedApiEvent> get events => _events.stream;

  void add(CapturedApiEvent event) => _events.add(event);

  @override
  Future<void> configure({
    required bool enabled,
    required String script,
  }) async {}

  @override
  Future<bool> isSupported() async => true;

  @override
  void dispose() => unawaited(_events.close());
}
