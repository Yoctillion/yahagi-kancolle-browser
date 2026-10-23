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
  testWidgets('queued old port completion cannot cancel a new start warning', (
    tester,
  ) async {
    final fixture = await _SharedSessionFixture.create(tester);
    addTearDown(fixture.dispose);

    fixture.capturePort.add(
      kcsapiEvent('/kcsapi/api_port/port', const {}, sequence: 1),
    );
    fixture.capturePort.add(
      kcsapiEvent('/kcsapi/api_req_map/start', const {}, sequence: 2),
    );
    expect(fixture.safetyChecks, 1);

    fixture.session.endSortie();
    fixture.session.startSortie();
    fixture.safetyState.complete(_heavySortieState);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(fixture.alerts.alerts, <BattleDamageAlertSeverity>[
      BattleDamageAlertSeverity.heavy,
    ]);
  });

  testWidgets('port without a new start cancels a pending old sortie warning', (
    tester,
  ) async {
    final fixture = await _SharedSessionFixture.create(tester);
    addTearDown(fixture.dispose);

    fixture.capturePort.add(
      kcsapiEvent('/kcsapi/api_req_map/next', const {}, sequence: 1),
    );
    expect(fixture.safetyChecks, 1);
    fixture.capturePort.add(
      kcsapiEvent('/kcsapi/api_port/port', const {}, sequence: 2),
    );
    fixture.session.endSortie();
    fixture.safetyState.complete(_heavySortieState);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(fixture.alerts.alerts, isEmpty);
    expect(fixture.session.isActive, isFalse);
  });
}

const _heavySortieState = GameState(
  memberId: 1001,
  hasEquipmentInventory: true,
  ships: <int, OwnedShip>{
    1: OwnedShip(id: 1, masterId: 100, level: 50, currentHp: 20, maxHp: 20),
    2: OwnedShip(id: 2, masterId: 101, level: 50, currentHp: 2, maxHp: 20),
  },
  fleets: <Fleet>[
    Fleet(id: 1, name: 'First', shipIds: <int>[1, 2]),
  ],
  combatState: CombatState(isActive: true, sortieFleetId: 1),
);

class _SharedSessionFixture {
  final capturePort = _CapturePort();
  final captureController = GameCaptureController();
  final session = SortieWarningSession()..startSortie();
  final accountSession = AccountSession(initialMemberId: 1001);
  final alerts = _AlertPort();
  final safetyState = Completer<GameState>();
  late final SafetySettingsController settings;
  int safetyChecks = 0;

  static Future<_SharedSessionFixture> create(WidgetTester tester) async {
    final fixture = _SharedSessionFixture();
    await fixture.captureController.attach(fixture.capturePort, enabled: true);
    fixture.settings = await SafetySettingsController.load(
      MemorySafetySettingsStore(),
    );
    await fixture.settings.setBattleWarningMode(BattleWarningMode.confirm);
    await tester.pumpWidget(
      MaterialApp(
        home: BattleResultWarningOverlay(
          accountSession: fixture.accountSession,
          gameCaptureController: fixture.captureController,
          warningSession: fixture.session,
          loadSafetyState: () {
            fixture.safetyChecks += 1;
            return fixture.safetyState.future;
          },
          damageControlStateTrusted: () => true,
          safetySettingsController: fixture.settings,
          damageAlertPort: fixture.alerts,
          child: const SizedBox.expand(),
        ),
      ),
    );
    return fixture;
  }

  void dispose() {
    captureController.dispose();
    capturePort.dispose();
    settings.dispose();
    accountSession.dispose();
    session.dispose();
  }
}

class _AlertPort implements BattleDamageAlertPort {
  final alerts = <BattleDamageAlertSeverity>[];

  @override
  Future<void> alert(BattleDamageAlertSeverity severity) async {
    alerts.add(severity);
  }
}

class _CapturePort implements GameCapturePort {
  final _events = StreamController<CapturedApiEvent>.broadcast(sync: true);

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
