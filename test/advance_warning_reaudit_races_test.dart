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
import 'package:yahagi_kancolle_browser/src/quest/quest_completion_drawer.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_store.dart';

enum _Snapshot { equipped, exhausted, healthy }

enum _Presentation { awaitingHeaderFrame, visibleHeader, existingDialog }

enum _Boundary { account, captureClear, captureSession, captureStream, session }

void main() {
  for (final snapshot in _Snapshot.values) {
    testWidgets(
      'pending raw start followed only by shared end rejects $snapshot',
      (tester) async {
        final fixture = await _RaceFixture.mount(tester);
        addTearDown(() => fixture.dispose(tester));
        fixture.advance(sequence: 1, path: '/kcsapi/api_req_map/start');
        fixture.session.endSortie();
        fixture.requests.single.complete(_state(snapshot));
        await tester.pumpAndSettle();

        expect(find.text('大破舰已携带损管'), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        expect(fixture.alerts.severities, isEmpty);
        expect(fixture.session.isActive, isFalse);
      },
    );
  }

  for (final display in AdvanceWarningDisplayMode.values) {
    testWidgets(
      'queued old port and latest shared start retain exhausted fleet in $display',
      (tester) async {
        final fixture = await _RaceFixture.mount(tester);
        addTearDown(() => fixture.dispose(tester));
        await fixture.settings.setAdvanceWarningDisplayMode(display);
        fixture.advance(sequence: 1, path: '/kcsapi/api_port/port');
        fixture.advance(sequence: 2, path: '/kcsapi/api_req_map/start');
        expect(fixture.requests, hasLength(1));
        fixture.session.endSortie();
        fixture.session.startSortie();
        fixture.requests.single.complete(_state(_Snapshot.equipped));
        await tester.pumpAndSettle();
        expect(
          find.byType(AlertDialog),
          display == AdvanceWarningDisplayMode.smart
              ? findsNothing
              : findsOneWidget,
        );
        expect(fixture.alerts.severities, hasLength(1));

        fixture.advance(sequence: 3);
        fixture.requests.last.complete(_state(_Snapshot.exhausted));
        await tester.pumpAndSettle();

        _expectExhaustedFleet();
        expect(fixture.session.isActive, isTrue);
        expect(fixture.session.isMuted, isFalse);
        expect(
          fixture.alerts.severities,
          hasLength(display == AdvanceWarningDisplayMode.smart ? 2 : 1),
        );
      },
    );
  }

  for (final path in <String>[
    '/kcsapi/api_port/port',
    '/kcsapi/api_start2/getData',
  ]) {
    testWidgets('unseen lower sequence $path cannot clear exhausted fleet', (
      tester,
    ) async {
      final fixture = await _RaceFixture.mount(tester);
      addTearDown(() => fixture.dispose(tester));
      fixture.advance(sequence: 50);
      fixture.requests.single.complete(_state(_Snapshot.exhausted));
      await tester.pumpAndSettle();
      _expectExhaustedFleet();

      fixture.advance(sequence: 2, path: path);
      await tester.pumpAndSettle();

      _expectExhaustedFleet();
      expect(fixture.alerts.severities, hasLength(1));
      expect(fixture.session.isActive, isTrue);
    });
  }

  for (final obsolete in <_Snapshot>[_Snapshot.equipped, _Snapshot.healthy]) {
    testWidgets(
      'unseen lower advance cannot replace exhausted fleet with $obsolete',
      (tester) async {
        final fixture = await _RaceFixture.mount(tester);
        addTearDown(() => fixture.dispose(tester));
        fixture.advance(sequence: 50);
        fixture.requests.single.complete(_state(_Snapshot.exhausted));
        await tester.pumpAndSettle();
        fixture.advance(sequence: 2);
        if (fixture.requests.length > 1) {
          fixture.requests.last.complete(_state(obsolete));
        }
        await tester.pumpAndSettle();

        _expectExhaustedFleet();
        expect(fixture.requests, hasLength(1));
        expect(fixture.alerts.severities, hasLength(1));
      },
    );
  }

  testWidgets(
    'an evicted old advance cannot turn exhausted fleet into a capsule',
    (tester) async {
      final fixture = await _RaceFixture.mount(tester);
      addTearDown(() => fixture.dispose(tester));
      fixture.advance(sequence: 1);
      fixture.requests.single.complete(_state(_Snapshot.exhausted));
      await tester.pumpAndSettle();
      for (var sequence = 2; sequence <= 515; sequence++) {
        fixture.advance(
          sequence: sequence,
          path: '/kcsapi/api_get_member/ship2',
        );
      }
      fixture.advance(sequence: 1);
      if (fixture.requests.length > 1) {
        fixture.requests.last.complete(_state(_Snapshot.equipped));
      }
      await tester.pumpAndSettle();

      _expectExhaustedFleet();
      expect(fixture.requests, hasLength(1));
      expect(fixture.alerts.severities, hasLength(1));
    },
  );

  for (final path in <String>[
    '/kcsapi/api_port/port',
    '/kcsapi/api_start2/getData',
  ]) {
    testWidgets(
      'retired document high sequence $path cannot clear new exhausted fleet',
      (tester) async {
        final fixture = await _RaceFixture.mount(tester);
        addTearDown(() => fixture.dispose(tester));
        fixture.advance(sequence: 1, path: '/kcsapi/api_start2/getData');
        fixture.advance(
          sequence: 1,
          document: 'document-b',
          path: '/kcsapi/api_start2/getData',
        );
        fixture.advance(sequence: 2, document: 'document-b');
        fixture.requests.single.complete(_state(_Snapshot.exhausted));
        await tester.pumpAndSettle();
        _expectExhaustedFleet();

        fixture.advance(sequence: 999, path: path);
        await tester.pumpAndSettle();

        _expectExhaustedFleet();
        expect(fixture.requests, hasLength(1));
        expect(fixture.session.isActive, isTrue);
      },
    );
  }

  testWidgets(
    'retired document advance cannot invalidate pending new exhausted fleet',
    (tester) async {
      final fixture = await _RaceFixture.mount(tester);
      addTearDown(() => fixture.dispose(tester));
      fixture.advance(sequence: 1, path: '/kcsapi/api_start2/getData');
      fixture.advance(
        sequence: 1,
        document: 'document-b',
        path: '/kcsapi/api_start2/getData',
      );
      fixture.advance(sequence: 2, document: 'document-b');
      final currentDocumentResult = fixture.requests.single;
      fixture.advance(sequence: 999);
      if (fixture.requests.length > 1) {
        fixture.requests.last.complete(GameState.empty);
      }
      currentDocumentResult.complete(_state(_Snapshot.exhausted));
      await tester.pumpAndSettle();

      _expectExhaustedFleet();
      expect(fixture.requests, hasLength(1));
      expect(fixture.alerts.severities, hasLength(1));
    },
  );

  for (final snapshot in _Snapshot.values) {
    testWidgets(
      'ending a shared sortie rejects pending $snapshot without reviving it',
      (tester) async {
        final fixture = await _RaceFixture.mount(tester);
        addTearDown(() => fixture.dispose(tester));
        fixture.advance(sequence: 1);
        final oldGeneration = fixture.session.generation;
        fixture.session.endSortie();
        expect(fixture.session.generation, greaterThan(oldGeneration));

        fixture.requests.single.complete(_state(snapshot));
        await tester.pumpAndSettle();

        expect(find.text('大破舰已携带损管'), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        expect(fixture.alerts.severities, isEmpty);
        expect(fixture.session.isActive, isFalse);
        expect(fixture.session.isMuted, isFalse);
      },
    );
  }

  for (final snapshot in _Snapshot.values) {
    testWidgets(
      'a new shared sortie rejects the previous muted sortie pending $snapshot',
      (tester) async {
        final fixture = await _RaceFixture.mount(tester);
        addTearDown(() => fixture.dispose(tester));
        fixture.session.muteCurrentSortie();
        fixture.advance(sequence: 1);
        expect(fixture.requests, hasLength(1));
        fixture.session.startSortie();

        fixture.requests.single.complete(_state(snapshot));
        await tester.pumpAndSettle();

        expect(find.text('大破舰已携带损管'), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        expect(fixture.alerts.severities, isEmpty);
        expect(fixture.session.isActive, isTrue);
        expect(fixture.session.isMuted, isFalse);
        fixture.advance(sequence: 2);
        fixture.requests.last.complete(_state(_Snapshot.exhausted));
        await tester.pumpAndSettle();
        _expectExhaustedFleet();
      },
    );
  }

  for (final restart in <bool>[false, true]) {
    testWidgets(
      'raw start stops tolerating shared changes after load before host frame restart=$restart',
      (tester) async {
        final fixture = await _RaceFixture.mount(tester);
        addTearDown(() => fixture.dispose(tester));
        fixture.advance(sequence: 1, path: '/kcsapi/api_req_map/start');
        fixture.session.endSortie();
        fixture.session.startSortie();
        fixture.requests.single.complete(_state(_Snapshot.equipped));
        await tester.idle();
        expect(fixture.alerts.severities, isEmpty);

        if (restart) {
          fixture.session.startSortie();
        } else {
          fixture.session.endSortie();
        }
        await tester.pumpAndSettle();

        expect(find.text('大破舰已携带损管'), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        expect(fixture.alerts.severities, isEmpty);
        expect(fixture.session.isActive, restart);
      },
    );

    testWidgets(
      'shared generation change during host endOfFrame rejects capsule restart=$restart',
      (tester) async {
        final fixture = await _RaceFixture.mount(tester);
        addTearDown(() => fixture.dispose(tester));
        fixture.advance(sequence: 1);
        fixture.requests.single.complete(_state(_Snapshot.equipped));
        await tester.idle();
        expect(fixture.alerts.severities, isEmpty);

        if (restart) {
          fixture.session.startSortie();
        } else {
          fixture.session.endSortie();
        }
        await tester.pumpAndSettle();

        expect(find.text('大破舰已携带损管'), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        expect(fixture.alerts.severities, isEmpty);
        expect(fixture.session.isActive, restart);
      },
    );
  }

  for (final presentation in _Presentation.values) {
    for (final identity in <String>['document', 'capture session']) {
      testWidgets(
        'exhausted fleet replaces $presentation with reused sequence in new $identity',
        (tester) async {
          final fixture = await _RaceFixture.mount(tester);
          addTearDown(() => fixture.dispose(tester));
          if (presentation == _Presentation.existingDialog) {
            await fixture.settings.setAdvanceWarningDisplayMode(
              AdvanceWarningDisplayMode.alwaysConfirm,
            );
          }
          fixture.advance(sequence: 7);
          fixture.requests.single.complete(_state(_Snapshot.equipped));
          if (presentation == _Presentation.awaitingHeaderFrame) {
            await tester.idle();
          } else {
            await tester.pumpAndSettle();
          }
          fixture.advance(sequence: 8);
          final obsoleteEquipped = fixture.requests.last;
          final document = identity == 'document' ? 'document-b' : 'document-a';
          final captureSession = identity == 'capture session'
              ? 'capture-b'
              : 'capture-a';
          fixture.advance(
            sequence: 8,
            document: document,
            captureSession: captureSession,
          );
          expect(fixture.requests, hasLength(3));
          fixture.requests.last.complete(_state(_Snapshot.exhausted));
          obsoleteEquipped.complete(_state(_Snapshot.equipped));
          fixture.headerVisible.value = false;
          await tester.pumpAndSettle();

          _expectExhaustedFleet();
          expect(
            fixture.alerts.severities,
            hasLength(presentation == _Presentation.visibleHeader ? 2 : 1),
          );
          fixture.advance(
            sequence: 8,
            document: document,
            captureSession: captureSession,
          );
          expect(fixture.requests, hasLength(3));
          expect(fixture.session.isMuted, isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final boundary in _Boundary.values) {
    for (final obsolete in <_Snapshot>[_Snapshot.equipped, _Snapshot.healthy]) {
      testWidgets(
        '$boundary discards pending $obsolete before reused sequence warns for exhausted fleet',
        (tester) async {
          final fixture = await _RaceFixture.mount(tester);
          addTearDown(() => fixture.dispose(tester));
          fixture.advance(sequence: 7);
          final oldResult = fixture.requests.single;
          await fixture.crossBoundary(boundary, tester);
          fixture.advance(
            sequence: 7,
            document: 'document-b',
            captureSession: 'capture-b',
          );
          expect(fixture.requests, hasLength(2));
          fixture.requests.last.complete(
            _state(
              _Snapshot.exhausted,
              memberId: fixture.account.current.memberId,
            ),
          );
          await tester.pumpAndSettle();
          _expectExhaustedFleet();
          oldResult.complete(_state(obsolete));
          await tester.pumpAndSettle();

          _expectExhaustedFleet();
          expect(fixture.alerts.severities, hasLength(1));
          expect(fixture.activeSession.value.isMuted, isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final action in <String>['confirm', 'mute']) {
    testWidgets(
      'old $action callback cannot dismiss or mute the new exhausted sortie',
      (tester) async {
        final fixture = await _RaceFixture.mount(tester);
        addTearDown(() => fixture.dispose(tester));
        fixture.advance(sequence: 1);
        fixture.requests.single.complete(_state(_Snapshot.exhausted));
        await tester.pumpAndSettle();
        _expectExhaustedFleet();
        final oldConfirm = tester
            .widget<FilledButton>(
              find.byKey(const Key('acknowledgeAdvanceWarning')),
            )
            .onPressed!;
        final oldMute = tester
            .widget<FilledButton>(
              find.byKey(const Key('muteCurrentSortieWarning')),
            )
            .onPressed!;
        fixture.advance(sequence: 2);
        final previousSortieResult = fixture.requests.last;
        if (action == 'confirm') {
          oldConfirm();
        } else {
          oldMute();
        }
        await tester.pumpAndSettle();
        fixture.session.startSortie();
        fixture.advance(sequence: 1, document: 'document-b');
        fixture.requests.last.complete(_state(_Snapshot.exhausted));
        await tester.pumpAndSettle();
        previousSortieResult.complete(_state(_Snapshot.equipped));
        oldConfirm();
        oldMute();
        await tester.pumpAndSettle();

        _expectExhaustedFleet();
        expect(fixture.session.isMuted, isFalse);
        await tester.tap(find.byKey(const Key('acknowledgeAdvanceWarning')));
        await tester.pumpAndSettle();
        expect(fixture.session.isMuted, isFalse);
        fixture.advance(sequence: 2, document: 'document-b');
        fixture.requests.last.complete(_state(_Snapshot.exhausted));
        await tester.pumpAndSettle();
        _expectExhaustedFleet();
        await tester.tap(find.byKey(const Key('muteCurrentSortieWarning')));
        await tester.pumpAndSettle();
        expect(fixture.session.isMuted, isTrue);
        fixture.advance(sequence: 3, document: 'document-b');
        fixture.requests.last.complete(_state(_Snapshot.exhausted));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('大破舰已携带损管'), findsNothing);
        expect(fixture.alerts.severities, hasLength(3));
      },
    );
  }
}

void _expectExhaustedFleet() {
  expect(find.byType(AlertDialog), findsOneWidget);
  expect(find.text('大破舰已携带损管'), findsNothing);
  expect(find.text('未携带损管'), findsOneWidget);
  expect(find.text('损管状态未知，请核对游戏内装备'), findsOneWidget);
  expect(find.text('携带：应急修理女神 ×1'), findsOneWidget);
  expect(find.text('#2'), findsOneWidget);
  expect(find.text('#3'), findsOneWidget);
  expect(find.text('#4'), findsOneWidget);
}

GameState _state(_Snapshot snapshot, {int memberId = 1001}) {
  final healthy = snapshot == _Snapshot.healthy;
  final equipped = snapshot == _Snapshot.equipped;
  return GameState(
    memberId: memberId,
    hasPortData: true,
    hasEquipmentInventory: true,
    combatState: const CombatState(isActive: true, sortieFleetId: 1),
    ships: <int, OwnedShip>{
      1: const OwnedShip(
        id: 1,
        masterId: 1,
        level: 50,
        currentHp: 20,
        maxHp: 20,
      ),
      2: OwnedShip(
        id: 2,
        masterId: 2,
        level: 50,
        currentHp: healthy ? 20 : 2,
        maxHp: 20,
        slotIds: equipped ? const <int>[501, 502] : const <int>[],
      ),
      3: OwnedShip(
        id: 3,
        masterId: 3,
        level: 50,
        currentHp: healthy ? 20 : 3,
        maxHp: 20,
        extraSlotId: 503,
      ),
      4: OwnedShip(
        id: 4,
        masterId: 4,
        level: 50,
        currentHp: healthy ? 20 : 4,
        maxHp: 20,
        slotIds: const <int>[504],
      ),
    },
    slotItems: <int, OwnedSlotItem>{
      if (equipped) ...const <int, OwnedSlotItem>{
        501: OwnedSlotItem(instanceId: 501, masterSlotItemId: 42),
        502: OwnedSlotItem(instanceId: 502, masterSlotItemId: 42),
        504: OwnedSlotItem(instanceId: 504, masterSlotItemId: 42),
      },
      503: const OwnedSlotItem(instanceId: 503, masterSlotItemId: 43),
    },
    fleets: const <Fleet>[
      Fleet(id: 1, name: 'First', shipIds: <int>[1, 2, 3, 4]),
    ],
  );
}

final class _RaceFixture {
  _RaceFixture() {
    capture = GameCaptureController(onCaptureInterrupted: session.endSortie);
    activeSession = ValueNotifier(session);
  }

  final account = AccountSession(initialMemberId: 1001);
  final session = SortieWarningSession()..startSortie();
  late final GameCaptureController capture;
  late final ValueNotifier<SortieWarningSession> activeSession;
  final replacementSessions = <SortieWarningSession>[];
  final port = _RaceCapturePort();
  final alerts = _RaceDamageAlerts();
  final requests = <Completer<GameState>>[];
  final startedDocuments = <(String, String)>{};
  final headerVisible = ValueNotifier<bool>(true);
  late final SafetySettingsController settings;

  static Future<_RaceFixture> mount(WidgetTester tester) async {
    final fixture = _RaceFixture();
    fixture.settings = await SafetySettingsController.load(
      MemorySafetySettingsStore(),
    );
    await fixture.settings.setAdvanceWarningDisplayMode(
      AdvanceWarningDisplayMode.smart,
    );
    await fixture.capture.attach(fixture.port, enabled: true);
    await tester.pumpWidget(
      MaterialApp(
        home: QuestCompletionDrawerHost(
          child: Column(
            children: <Widget>[
              ValueListenableBuilder<bool>(
                valueListenable: fixture.headerVisible,
                builder: (context, visible, child) => SizedBox(
                  height: 44,
                  child: Offstage(offstage: !visible, child: child),
                ),
                child: const QuestCompletionHeaderSlot(
                  child: SizedBox.expand(),
                ),
              ),
              Expanded(
                child: ValueListenableBuilder<SortieWarningSession>(
                  valueListenable: fixture.activeSession,
                  builder: (context, session, child) =>
                      BattleResultWarningOverlay(
                        accountSession: fixture.account,
                        warningSession: session,
                        gameCaptureController: fixture.capture,
                        loadSafetyState: () {
                          final request = Completer<GameState>();
                          fixture.requests.add(request);
                          return request.future;
                        },
                        damageControlStateTrusted: () => true,
                        safetySettingsController: fixture.settings,
                        damageAlertPort: fixture.alerts,
                        child: const SizedBox.expand(),
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return fixture;
  }

  Future<void> crossBoundary(_Boundary boundary, WidgetTester tester) async {
    switch (boundary) {
      case _Boundary.account:
        account.selectMember(1002);
      case _Boundary.captureClear:
        capture.clearCapturedEvents();
      case _Boundary.captureSession:
        await capture.invalidateSession();
      case _Boundary.captureStream:
        port.interrupt();
      case _Boundary.session:
        final replacement = SortieWarningSession()..startSortie();
        replacementSessions.add(replacement);
        activeSession.value = replacement;
        await tester.pump();
    }
  }

  void advance({
    required int sequence,
    String document = 'document-a',
    String captureSession = 'capture-a',
    String path = '/kcsapi/api_req_map/next',
  }) {
    final newDocument = startedDocuments.add((captureSession, document));
    if (newDocument && path != '/kcsapi/api_start2/getData') {
      emitCaptureEvent(
        sequence: 1,
        document: document,
        captureSession: captureSession,
        path: '/kcsapi/api_start2/getData',
      );
    }
    emitCaptureEvent(
      sequence: sequence + 1,
      document: document,
      captureSession: captureSession,
      path: path,
    );
  }

  void emitCaptureEvent({
    required int sequence,
    required String document,
    required String captureSession,
    required String path,
  }) => port.add(
    CapturedApiEvent(
      path: path,
      responseBody: '{"api_result":1,"api_data":{}}',
      source: CaptureSource.xhr,
      capturedAt: DateTime.utc(2026, 10, 23),
      sequence: sequence,
      captureSessionId: captureSession,
      captureDocumentId: document,
      captureDocumentStartedAtEpochMs: document == 'document-a' ? 1 : 2,
    ),
  );

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    capture.dispose();
    port.dispose();
    settings.dispose();
    headerVisible.dispose();
    activeSession.dispose();
    for (final replacement in replacementSessions) {
      replacement.dispose();
    }
    session.dispose();
    account.dispose();
  }
}

final class _RaceDamageAlerts implements BattleDamageAlertPort {
  final severities = <BattleDamageAlertSeverity>[];

  @override
  Future<void> alert(BattleDamageAlertSeverity severity) async =>
      severities.add(severity);
}

final class _RaceCapturePort
    implements GameCapturePort, GameCaptureContinuityPort {
  final _events = StreamController<CapturedApiEvent>.broadcast(sync: true);
  final _interruptions = StreamController<void>.broadcast(sync: true);

  @override
  Stream<CapturedApiEvent> get events => _events.stream;

  @override
  Stream<void> get interruptions => _interruptions.stream;

  void add(CapturedApiEvent event) => _events.add(event);

  void interrupt() => _interruptions.add(null);

  @override
  Future<void> configure({
    required bool enabled,
    required String script,
  }) async {}

  @override
  Future<bool> isSupported() async => true;

  @override
  void dispose() {
    unawaited(_events.close());
    unawaited(_interruptions.close());
  }
}
