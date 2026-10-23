import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/account/account_session.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
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

enum _ReplacementKind { warningSession, accountSession, captureController }

void main() {
  for (final kind in _ReplacementKind.values) {
    testWidgets(
      'replacing $kind closes a warning safely during widget update',
      (tester) async {
        final account = AccountSession(initialMemberId: 1001);
        final replacementAccount = AccountSession(initialMemberId: 1001);
        final capture = GameCaptureController();
        final replacementCapture = GameCaptureController();
        final capturePort = _StaticCapturePort();
        final replacementCapturePort = _StaticCapturePort();
        await capture.attach(capturePort, enabled: true);
        await replacementCapture.attach(replacementCapturePort, enabled: true);
        final session = SortieWarningSession();
        final replacementSession = SortieWarningSession();
        final replace = ValueNotifier<bool>(false);
        final settings = await SafetySettingsController.load(
          MemorySafetySettingsStore(),
        );
        await settings.setBattleWarningMode(BattleWarningMode.confirm);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          replace.dispose();
          session.dispose();
          replacementSession.dispose();
          settings.dispose();
          capture.dispose();
          replacementCapture.dispose();
          capturePort.dispose();
          replacementCapturePort.dispose();
          account.dispose();
          replacementAccount.dispose();
        });
        await tester.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<bool>(
              valueListenable: replace,
              builder: (context, replaced, child) {
                return BattleResultWarningOverlay(
                  accountSession:
                      replaced && kind == _ReplacementKind.accountSession
                      ? replacementAccount
                      : account,
                  gameCaptureController:
                      replaced && kind == _ReplacementKind.captureController
                      ? replacementCapture
                      : capture,
                  warningSession:
                      replaced && kind == _ReplacementKind.warningSession
                      ? replacementSession
                      : session,
                  loadSafetyState: () async => _activeSortie,
                  damageControlStateTrusted: () => true,
                  safetySettingsController: settings,
                  damageAlertPort: const _StaticDamageAlertPort(),
                  child: const SizedBox.expand(),
                );
              },
            ),
          ),
        );
        capturePort.add(kcsapiEvent('/kcsapi/api_req_map/next', const {}));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);

        replace.value = true;
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(AlertDialog), findsNothing);
      },
    );
  }

  testWidgets('capture interruption cancels a pending advance safety result', (
    tester,
  ) async {
    final account = AccountSession(initialMemberId: 1001);
    final battle = BattleController(
      accountSession: account,
      gameState: () => _activeSortie,
    );
    final capture = GameCaptureController(
      onCaptureInterrupted: battle.invalidateCaptureContinuity,
    );
    final capturePort = _StaticCapturePort();
    await capture.attach(capturePort, enabled: true);
    final stateReady = Completer<GameState>();
    final settings = await SafetySettingsController.load(
      MemorySafetySettingsStore(),
    );
    await settings.setBattleWarningMode(BattleWarningMode.confirm);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      settings.dispose();
      capture.dispose();
      capturePort.dispose();
      battle.dispose();
      account.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: BattleResultWarningOverlay(
          accountSession: account,
          gameCaptureController: capture,
          warningSession: battle.warningSession,
          loadSafetyState: () => stateReady.future,
          damageControlStateTrusted: () => battle.isDamageControlStateTrusted,
          safetySettingsController: settings,
          damageAlertPort: const _StaticDamageAlertPort(),
          child: const SizedBox.expand(),
        ),
      ),
    );
    capturePort.add(kcsapiEvent('/kcsapi/api_req_map/next', const {}));
    await capture.configure(enabled: false);
    stateReady.complete(_activeSortie);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(battle.warningSession.isActive, isFalse);
  });
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

final class _StaticDamageAlertPort implements BattleDamageAlertPort {
  const _StaticDamageAlertPort();

  @override
  Future<void> alert(BattleDamageAlertSeverity severity) async {}
}

final class _StaticCapturePort implements GameCapturePort {
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
