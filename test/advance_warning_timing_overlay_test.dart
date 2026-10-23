import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
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
import 'package:yahagi_kancolle_browser/src/widgets/top_notice.dart';

import 'fixtures/kcsapi_fixtures.dart';

void main() {
  for (final timing in AdvanceWarningTimingSettings.values) {
    for (final display in AdvanceWarningDisplayMode.values) {
      for (final equipped in <bool>[false, true]) {
        testWidgets(
          '$timing $display equipped=$equipped respects selected stages',
          (tester) async {
            final fixture = await _TimingFixture.create(
              tester,
              timing: timing,
              display: display,
              equipment: equipped ? <int>[42, 43] : <int>[],
            );
            await fixture.navigate(tester, start: true);
            if (timing.afterAdvance) {
              fixture.expectPresentation(equipped: equipped, display: display);
            } else {
              expect(find.byType(AlertDialog), findsNothing);
              expect(find.text('大破舰已携带损管'), findsNothing);
            }
            await fixture.closePresentation(tester);
            final alertsBefore = fixture.alerts.alerts.length;

            await fixture.result(tester);

            if (timing.postBattle) {
              fixture.expectPresentation(equipped: equipped, display: display);
              expect(fixture.alerts.alerts, hasLength(alertsBefore + 1));
              if (!equipped ||
                  display == AdvanceWarningDisplayMode.alwaysConfirm) {
                expect(find.textContaining('已在大破状态下选择进击'), findsNothing);
              }
              await fixture.closePresentation(tester);
            } else {
              expect(find.byType(AlertDialog), findsNothing);
              expect(find.text('大破舰已携带损管'), findsNothing);
              expect(fixture.alerts.alerts, hasLength(alertsBefore));
            }
            final alertsAfterResult = fixture.alerts.alerts.length;
            await fixture.navigate(tester);
            if (timing.afterAdvance) {
              fixture.expectPresentation(equipped: equipped, display: display);
            } else {
              expect(find.byType(AlertDialog), findsNothing);
              expect(find.text('大破舰已携带损管'), findsNothing);
            }
            expect(
              fixture.alerts.alerts,
              hasLength(alertsAfterResult + (timing.afterAdvance ? 1 : 0)),
            );
          },
        );
      }
    }
  }

  for (final display in AdvanceWarningDisplayMode.values) {
    for (final equipped in <bool>[false, true]) {
      testWidgets(
        'result only keeps its active $display equipped=$equipped presentation across advance',
        (tester) async {
          final fixture = await _TimingFixture.create(
            tester,
            timing: AdvanceWarningTimingSettings.battleOnly,
            display: display,
            equipment: equipped ? <int>[42, 43] : <int>[],
          );
          await fixture.navigate(tester, start: true);
          expect(find.byType(AlertDialog), findsNothing);
          expect(find.text('大破舰已携带损管'), findsNothing);
          expect(fixture.alerts.alerts, isEmpty);
          await fixture.result(tester);
          fixture.expectPresentation(equipped: equipped, display: display);
          final alertsBefore = fixture.alerts.alerts.length;
          await fixture.navigate(tester);
          fixture.expectPresentation(equipped: equipped, display: display);
          expect(fixture.alerts.alerts, hasLength(alertsBefore));
          await fixture.closePresentation(tester);
          await fixture.navigate(tester);
          expect(find.byType(AlertDialog), findsNothing);
          expect(find.text('大破舰已携带损管'), findsNothing);
          expect(fixture.alerts.alerts, hasLength(alertsBefore));
        },
      );
    }
  }

  testWidgets(
    'result-only advance does not restart the existing notice timer',
    (tester) async {
      final fixture = await _TimingFixture.create(
        tester,
        timing: AdvanceWarningTimingSettings.battleOnly,
        display: AdvanceWarningDisplayMode.smart,
        equipment: <int>[42, 43],
      );
      await fixture.result(tester);
      expect(find.text('大破舰已携带损管'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await fixture.navigate(tester);
      expect(find.text('大破舰已携带损管'), findsOneWidget);
      expect(fixture.alerts.alerts, hasLength(1));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('大破舰已携带损管'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(fixture.alerts.alerts, hasLength(1));
    },
  );

  testWidgets(
    'result-only navigation still records an explicit terminal node',
    (tester) async {
      final fixture = await _TimingFixture.create(
        tester,
        timing: AdvanceWarningTimingSettings.battleOnly,
      );
      await fixture.navigate(tester, start: true, next: 0);
      await fixture.result(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(fixture.alerts.alerts, isEmpty);
      await fixture.navigate(tester, next: 1, boss: true);
      expect(find.byType(AlertDialog), findsNothing);
      await fixture.result(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(fixture.alerts.alerts, hasLength(1));
    },
  );

  for (final path in <String>[
    '/kcsapi/api_req_sortie/battleresult',
    '/kcsapi/api_req_combined_battle/battleresult',
  ]) {
    testWidgets(
      'KCA $path repeats after acknowledgement and deduplicates wire',
      (tester) async {
        final fixture = await _TimingFixture.create(tester);
        await fixture.result(tester, path: path);
        expect(find.byType(AlertDialog), findsOneWidget);
        final count = fixture.alerts.alerts.length;
        await fixture.emit(tester, fixture.lastEvent!);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(fixture.alerts.alerts, hasLength(count));
        await fixture.closePresentation(tester);
        await fixture.navigate(tester);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(fixture.alerts.alerts, hasLength(count + 1));
      },
    );
  }

  testWidgets('KCA unknown and depleted ships never downgrade to gold', (
    tester,
  ) async {
    final fixture = await _TimingFixture.create(
      tester,
      display: AdvanceWarningDisplayMode.smart,
      equipment: <int>[42, 43],
    );
    fixture.trusted = false;
    await fixture.result(tester);
    expect(find.text('损管状态未知，请核对游戏内装备'), findsOneWidget);
    expect(find.text('大破舰已携带损管'), findsNothing);
    await fixture.closePresentation(tester);
    fixture.trusted = true;
    fixture.state = _timingState(<int>[43]);
    await fixture.result(tester);
    expect(find.text('大破舰已携带损管'), findsOneWidget);
    await fixture.closePresentation(tester);
    fixture.state = _timingState(<int>[]);
    await fixture.result(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('未携带损管'), findsOneWidget);
    await fixture.closePresentation(tester);
    await fixture.navigate(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('大破舰已携带损管'), findsNothing);
  });

  testWidgets('KCA mute covers results and advances and resets at new sortie', (
    tester,
  ) async {
    final fixture = await _TimingFixture.create(tester);
    await fixture.result(tester);
    await tester.tap(find.byKey(const Key('muteCurrentSortieWarning')));
    await tester.pumpAndSettle();
    final count = fixture.alerts.alerts.length;
    await fixture.result(tester);
    await fixture.navigate(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(fixture.alerts.alerts, hasLength(count));
    await fixture.navigate(tester, start: true);
    expect(fixture.session.isMuted, isFalse);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('KCA master off and practice or failed results remain quiet', (
    tester,
  ) async {
    final fixture = await _TimingFixture.create(tester);
    await fixture.result(
      tester,
      path: '/kcsapi/api_req_practice/battle_result',
    );
    await fixture.emit(
      tester,
      kcsapiEvent(
        '/kcsapi/api_req_sortie/battleresult',
        const <String, Object?>{},
        apiResult: 0,
        sequence: ++fixture.sequence,
      ),
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(fixture.alerts.alerts, isEmpty);
    await fixture.settings.setBattleWarningMode(BattleWarningMode.off);
    await fixture.result(tester);
    await fixture.navigate(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(fixture.alerts.alerts, isEmpty);
  });

  testWidgets('only an explicit terminal map suppresses KCA result, not next', (
    tester,
  ) async {
    final fixture = await _TimingFixture.create(tester);
    await fixture.navigate(tester, start: true, next: 0);
    await fixture.closePresentation(tester);
    final count = fixture.alerts.alerts.length;
    await fixture.result(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(fixture.alerts.alerts, hasLength(count));
    await fixture.navigate(tester, next: 1, boss: true);
    await fixture.closePresentation(tester);
    await fixture.result(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('timing changes latch until the next sortie', (tester) async {
    final fixture = await _TimingFixture.create(
      tester,
      timing: AdvanceWarningTimingSettings.advanceOnly,
    );
    await fixture.navigate(tester, start: true);
    await fixture.closePresentation(tester);
    await fixture.settings.setAdvanceWarningTimings(
      AdvanceWarningTimingSettings.battleAndAdvance,
    );
    await fixture.result(tester);
    expect(find.byType(AlertDialog), findsNothing);
    await fixture.navigate(tester, start: true);
    await fixture.closePresentation(tester);
    await fixture.result(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await fixture.settings.setAdvanceWarningTimings(
      AdvanceWarningTimingSettings.advanceOnly,
    );
    expect(find.byType(AlertDialog), findsOneWidget);
    await fixture.closePresentation(tester);
    await fixture.result(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  for (final timing in AdvanceWarningTimingSettings.values) {
    final changedTiming = timing == AdvanceWarningTimingSettings.advanceOnly
        ? AdvanceWarningTimingSettings.battleAndAdvance
        : AdvanceWarningTimingSettings.advanceOnly;
    testWidgets('shared sortie keeps $timing across overlay remount', (
      tester,
    ) async {
      final fixture = await _TimingFixture.create(tester, timing: timing);
      await fixture.navigate(tester, start: true);
      await fixture.closePresentation(tester);
      final generation = fixture.session.generation;
      final alertsBefore = fixture.alerts.alerts.length;
      await fixture.settings.setAdvanceWarningTimings(changedTiming);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      await fixture.mount(tester);
      await fixture.result(tester);

      expect(fixture.session.generation, generation);
      expect(fixture.session.timings, timing);
      expect(
        find.byType(AlertDialog),
        timing.postBattle ? findsOneWidget : findsNothing,
      );
      expect(find.text('大破舰已携带损管'), findsNothing);
      expect(
        fixture.alerts.alerts,
        hasLength(alertsBefore + (timing.postBattle ? 1 : 0)),
      );
    });

    testWidgets('pending $timing start survives change to $changedTiming', (
      tester,
    ) async {
      await _expectPendingStartResult(
        tester,
        timing: timing,
        changedTiming: changedTiming,
      );
    });

    testWidgets(
      'pending $timing start stays frozen while warnings toggle off',
      (tester) async {
        await _expectPendingStartResult(
          tester,
          timing: timing,
          changedTiming: changedTiming,
          toggleWarnings: true,
        );
      },
    );
  }

  testWidgets('rejected KCA result cannot display until the gate accepts', (
    tester,
  ) async {
    final fixture = await _TimingFixture.create(
      tester,
      display: AdvanceWarningDisplayMode.smart,
      equipment: <int>[42, 43],
    );
    final rejected = <CapturedApiEvent>[];
    fixture.safetyAccepted = (event, state) {
      rejected.add(event);
      expectSync(state, same(fixture.state));
      return false;
    };
    await fixture.result(
      tester,
      path: '/kcsapi/api_req_combined_battle/battleresult',
    );
    expect(rejected, <CapturedApiEvent>[fixture.lastEvent!]);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('大破舰已携带损管'), findsNothing);
    expect(fixture.alerts.alerts, isEmpty);

    fixture.safetyAccepted = (event, state) => true;
    await fixture.result(
      tester,
      path: '/kcsapi/api_req_combined_battle/battleresult',
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('大破舰已携带损管'), findsOneWidget);
    expect(fixture.alerts.alerts, hasLength(1));
  });

  testWidgets('pending KCA result survives the delayed start notification', (
    tester,
  ) async {
    await _expectPendingStartResult(
      tester,
      timing: AdvanceWarningTimingSettings.battleAndAdvance,
    );
  });

  testWidgets('standalone KCA start keeps its timing while loading state', (
    tester,
  ) async {
    await _expectPendingStartResult(
      tester,
      timing: AdvanceWarningTimingSettings.battleAndAdvance,
      changedTiming: AdvanceWarningTimingSettings.advanceOnly,
      sharedSession: false,
    );
  });

  testWidgets('new KCA start outranks the previous POI latch before loading', (
    tester,
  ) async {
    final fixture = await _TimingFixture.create(
      tester,
      timing: AdvanceWarningTimingSettings.advanceOnly,
    );
    await fixture.navigate(tester, start: true);
    await fixture.closePresentation(tester);
    await fixture.settings.setAdvanceWarningTimings(
      AdvanceWarningTimingSettings.battleAndAdvance,
    );
    final count = fixture.alerts.alerts.length;
    final pendingStart = Completer<GameState>();
    final pendingResult = Completer<GameState>();
    fixture.deferSortieStart = true;
    fixture.pendingState = pendingStart.future;
    fixture.port.add(
      kcsapiEvent('/kcsapi/api_req_map/start', const {
        'api_maparea_id': 1,
        'api_mapinfo_no': 1,
        'api_no': 1,
        'api_next': 1,
      }, sequence: ++fixture.sequence),
    );
    await tester.pump();
    fixture.pendingState = pendingResult.future;
    fixture.port.add(
      kcsapiEvent('/kcsapi/api_req_sortie/battleresult', const {
        'api_win_rank': 'A',
      }, sequence: ++fixture.sequence),
    );
    await tester.pump();
    pendingResult.complete(_timingState(<int>[]));
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    expect(fixture.alerts.alerts, hasLength(count));
    fixture.session.startSortie();
    pendingStart.complete(_timingState(<int>[], healthy: true));
    await tester.pumpAndSettle();
    expect(
      fixture.session.timings,
      AdvanceWarningTimingSettings.battleAndAdvance,
    );
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(fixture.alerts.alerts, hasLength(count + 1));
  });

  testWidgets(
    'pending terminal map metadata suppresses its queued KCA result',
    (tester) async {
      final fixture = await _TimingFixture.create(tester);
      final pendingStart = Completer<GameState>();
      final pendingResult = Completer<GameState>();
      fixture.pendingState = pendingStart.future;
      fixture.port.add(
        kcsapiEvent('/kcsapi/api_req_map/start', <String, Object?>{
          'api_maparea_id': 1,
          'api_mapinfo_no': 1,
          'api_no': 1,
          'api_next': 0,
        }, sequence: ++fixture.sequence),
      );
      await tester.pump();
      fixture.pendingState = pendingResult.future;
      fixture.port.add(
        kcsapiEvent(
          '/kcsapi/api_req_sortie/battleresult',
          const <String, Object?>{'api_win_rank': 'A'},
          sequence: ++fixture.sequence,
        ),
      );
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
      expect(fixture.alerts.alerts, isEmpty);

      pendingStart.complete(_timingState(<int>[], healthy: true));
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
      expect(fixture.alerts.alerts, isEmpty);
      pendingResult.complete(_timingState(<int>[]));
      await tester.pumpAndSettle();
      expect(
        fixture.session.timings,
        AdvanceWarningTimingSettings.battleAndAdvance,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('大破舰已携带损管'), findsNothing);
      expect(fixture.alerts.alerts, isEmpty);

      fixture.pendingState = null;
      await fixture.navigate(tester, next: 1);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(fixture.alerts.alerts, hasLength(1));
    },
  );

  testWidgets('an open KCA dialog updates ships without another vibration', (
    tester,
  ) async {
    final fixture = await _TimingFixture.create(tester);
    await fixture.result(tester);
    final count = fixture.alerts.alerts.length;
    fixture.state = _timingState(<int>[], multiple: true);
    await fixture.result(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('时雨'), findsOneWidget);
    expect(find.text('夕立'), findsOneWidget);
    expect(fixture.alerts.alerts, hasLength(count));
  });

  for (final boundary in <String>['account', 'gap', 'next', 'port']) {
    testWidgets('pending KCA result cannot outlive $boundary', (tester) async {
      final fixture = await _TimingFixture.create(tester);
      final pending = Completer<GameState>();
      fixture.pendingState = pending.future;
      fixture.port.add(
        kcsapiEvent(
          '/kcsapi/api_req_sortie/battleresult',
          const <String, Object?>{},
          sequence: ++fixture.sequence,
        ),
      );
      await tester.pump();
      fixture.pendingState = null;
      if (boundary == 'account') {
        fixture.account.reset();
      } else if (boundary == 'gap') {
        fixture.capture.clearCapturedEvents();
      } else if (boundary == 'next') {
        fixture.state = _timingState(
          <int>[],
        ).copyWith(ships: const <int, OwnedShip>{});
        await fixture.navigate(tester);
      } else {
        await fixture.emit(
          tester,
          kcsapiEvent(
            '/kcsapi/api_port/port',
            const <String, Object?>{},
            sequence: ++fixture.sequence,
          ),
        );
      }
      pending.complete(_timingState(<int>[]));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(fixture.alerts.alerts, isEmpty);
    });
  }

  for (final terminal in <bool>[false, true]) {
    testWidgets(
      'result-only next discards a pending result and records terminal=$terminal',
      (tester) async {
        final fixture = await _TimingFixture.create(
          tester,
          timing: AdvanceWarningTimingSettings.battleOnly,
        );
        final pendingResult = Completer<GameState>();
        fixture.pendingState = pendingResult.future;
        await fixture.result(tester);
        fixture.pendingState = null;
        fixture.state = _timingState(<int>[], healthy: true);
        await fixture.navigate(tester, next: terminal ? 0 : 1);

        pendingResult.complete(_timingState(<int>[], multiple: true));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('大破舰已携带损管'), findsNothing);
        expect(fixture.alerts.alerts, isEmpty);
        expect(
          fixture.session.timings,
          AdvanceWarningTimingSettings.battleOnly,
        );

        fixture.state = _timingState(<int>[], multiple: true);
        await fixture.result(tester);
        expect(
          find.byType(AlertDialog),
          terminal ? findsNothing : findsOneWidget,
        );
        expect(fixture.alerts.alerts, hasLength(terminal ? 0 : 1));
        await fixture.closePresentation(tester);
        fixture.state = _timingState(<int>[], healthy: true);
        await fixture.navigate(tester, next: 1);
        fixture.state = _timingState(<int>[], multiple: true);
        await fixture.result(tester);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('时雨'), findsOneWidget);
        expect(find.text('夕立'), findsOneWidget);
        expect(fixture.alerts.alerts, hasLength(terminal ? 1 : 2));
      },
    );
  }

  for (final timing in AdvanceWarningTimingSettings.values) {
    for (final changedTiming in AdvanceWarningTimingSettings.values) {
      if (changedTiming == timing) continue;
      testWidgets(
        'pending enabled $timing stage keeps its latch after $changedTiming is selected',
        (tester) async {
          final fixture = await _TimingFixture.create(
            tester,
            timing: timing,
            display: AdvanceWarningDisplayMode.smart,
            equipment: <int>[43],
          );
          fixture.state = _timingState(<int>[43], healthy: true);
          await fixture.navigate(tester, start: true);
          expect(fixture.session.timings, timing);
          expect(fixture.alerts.alerts, isEmpty);
          final pending = Completer<GameState>();
          fixture.pendingState = pending.future;
          if (timing.postBattle) {
            await fixture.result(tester);
          } else {
            await fixture.navigate(tester);
          }
          await fixture.settings.setAdvanceWarningTimings(changedTiming);
          pending.complete(_timingState(<int>[43], multiple: true));
          await tester.pumpAndSettle();

          expect(fixture.session.timings, timing);
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(find.text('时雨'), findsOneWidget);
          expect(find.text('夕立'), findsOneWidget);
          expect(find.text('大破舰已携带损管'), findsNothing);
          expect(fixture.alerts.alerts, hasLength(1));
          await fixture.closePresentation(tester);
          fixture.pendingState = null;
          fixture.state = _timingState(<int>[]);
          await fixture.navigate(tester);
          expect(
            find.byType(AlertDialog),
            timing.afterAdvance ? findsOneWidget : findsNothing,
          );
          expect(
            fixture.alerts.alerts,
            hasLength(1 + (timing.afterAdvance ? 1 : 0)),
          );
          await fixture.closePresentation(tester);
          fixture.state = _timingState(<int>[], healthy: true);
          await fixture.navigate(tester, start: true);
          expect(fixture.session.timings, changedTiming);
          fixture.state = _timingState(<int>[]);
          final alertsBeforeResult = fixture.alerts.alerts.length;
          await fixture.result(tester);
          expect(
            find.byType(AlertDialog),
            changedTiming.postBattle ? findsOneWidget : findsNothing,
          );
          expect(
            fixture.alerts.alerts,
            hasLength(alertsBeforeResult + (changedTiming.postBattle ? 1 : 0)),
          );
        },
      );
    }

    for (final display in AdvanceWarningDisplayMode.values) {
      for (final boundary in <String>['account', 'gap']) {
        testWidgets(
          'active $timing $display presentation cannot outlive $boundary',
          (tester) async {
            final fixture = await _TimingFixture.create(
              tester,
              timing: timing,
              display: display,
              equipment: <int>[42, 43],
            );
            if (timing.postBattle) {
              await fixture.result(tester);
            } else {
              await fixture.navigate(tester, start: true);
            }
            fixture.expectPresentation(equipped: true, display: display);
            expect(fixture.alerts.alerts, hasLength(1));

            if (boundary == 'account') {
              fixture.account.selectMember(2002);
              fixture.state = fixture.state.copyWith(memberId: 2002);
            } else {
              fixture.capture.clearCapturedEvents();
            }
            await tester.pumpAndSettle();
            expect(find.byType(AlertDialog), findsNothing);
            expect(find.text('大破舰已携带损管'), findsNothing);
            fixture.noticeEnabled = false;
            await fixture.mount(tester);
            await tester.pumpAndSettle();
            expect(find.byType(AlertDialog), findsNothing);
            expect(find.text('大破舰已携带损管'), findsNothing);
            expect(fixture.alerts.alerts, hasLength(1));

            fixture.noticeEnabled = true;
            await fixture.mount(tester);
            if (timing.postBattle) {
              await fixture.result(tester);
            } else {
              await fixture.navigate(tester, start: true);
            }
            fixture.expectPresentation(equipped: true, display: display);
            expect(fixture.alerts.alerts, hasLength(2));
          },
        );
      }
    }
  }

  for (final boundary in <String>['start', 'port']) {
    testWidgets(
      'result-only pending result cannot return after a new $boundary',
      (tester) async {
        final fixture = await _TimingFixture.create(
          tester,
          timing: AdvanceWarningTimingSettings.battleOnly,
          display: AdvanceWarningDisplayMode.smart,
          equipment: <int>[43],
        );
        final pendingResult = Completer<GameState>();
        fixture.pendingState = pendingResult.future;
        await fixture.result(tester);
        fixture.pendingState = null;
        fixture.state = _timingState(<int>[43], healthy: true);
        if (boundary == 'start') {
          await fixture.navigate(tester, start: true, next: 1);
        } else {
          await fixture.emit(
            tester,
            kcsapiEvent(
              '/kcsapi/api_port/port',
              const <String, Object?>{},
              sequence: ++fixture.sequence,
            ),
          );
        }
        pendingResult.complete(_timingState(<int>[43]));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('大破舰已携带损管'), findsNothing);
        expect(fixture.alerts.alerts, isEmpty);

        fixture.state = _timingState(<int>[], multiple: true);
        await fixture.result(tester);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('时雨'), findsOneWidget);
        expect(find.text('夕立'), findsOneWidget);
        expect(find.text('大破舰已携带损管'), findsNothing);
        expect(fixture.alerts.alerts, hasLength(1));
      },
    );
  }

  for (final timing in AdvanceWarningTimingSettings.values) {
    for (final expiry in <bool>[false, true]) {
      testWidgets(
        'ended notice expiry=$expiry cannot revive after display upgrade in $timing',
        (tester) async {
          final fixture = await _TimingFixture.create(
            tester,
            timing: timing,
            display: AdvanceWarningDisplayMode.smart,
            equipment: <int>[43],
          );
          if (timing.postBattle) {
            await fixture.result(tester);
          } else {
            await fixture.navigate(tester, start: true);
          }
          expect(find.text('大破舰已携带损管'), findsOneWidget);
          expect(fixture.alerts.alerts, hasLength(1));
          if (expiry) {
            await tester.pump(const Duration(seconds: 10));
          } else {
            await tester.tap(find.text('大破舰已携带损管'));
          }
          await tester.pumpAndSettle();
          expect(find.text('大破舰已携带损管'), findsNothing);
          await fixture.settings.setAdvanceWarningDisplayMode(
            AdvanceWarningDisplayMode.alwaysConfirm,
          );
          fixture.noticeEnabled = false;
          await fixture.mount(tester);
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(fixture.alerts.alerts, hasLength(1));
          if (timing.postBattle) {
            await fixture.result(tester);
          } else {
            await fixture.navigate(tester);
          }
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(fixture.alerts.alerts, hasLength(2));
        },
      );
    }
  }

  for (final expiry in [false, true]) {
    testWidgets('disabled advance preserves completion expiry=$expiry', (
      tester,
    ) async {
      final fixture = await _TimingFixture.create(
        tester,
        timing: AdvanceWarningTimingSettings.battleOnly,
        display: AdvanceWarningDisplayMode.smart,
        equipment: <int>[42, 43],
      );
      await fixture.result(tester);
      await fixture.navigate(tester);
      expect(find.text('大破舰已携带损管'), findsOneWidget);
      expect(fixture.alerts.alerts, hasLength(1));
      if (expiry) {
        await tester.pump(const Duration(seconds: 10));
      } else {
        await tester.tap(find.text('大破舰已携带损管'));
      }
      await tester.pumpAndSettle();
      fixture.noticeEnabled = false;
      await fixture.mount(tester);
      await fixture.settings.setAdvanceWarningDisplayMode(
        AdvanceWarningDisplayMode.alwaysConfirm,
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      fixture.state = _timingState(<int>[], multiple: true);
      await fixture.result(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('时雨'), findsOneWidget);
      expect(find.text('夕立'), findsOneWidget);
      expect(find.text('大破舰已携带损管'), findsNothing);
      expect(fixture.alerts.alerts, hasLength(2));
    });
  }

  testWidgets(
    'expired result-only notice cannot return when its host becomes unavailable',
    (tester) async {
      final fixture = await _TimingFixture.create(
        tester,
        timing: AdvanceWarningTimingSettings.battleOnly,
        display: AdvanceWarningDisplayMode.smart,
        equipment: <int>[43],
      );
      await fixture.result(tester);
      expect(find.text('大破舰已携带损管'), findsOneWidget);
      expect(fixture.alerts.alerts, hasLength(1));
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.text('大破舰已携带损管'), findsNothing);

      fixture.noticeEnabled = false;
      await fixture.mount(tester);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('大破舰已携带损管'), findsNothing);
      expect(fixture.alerts.alerts, hasLength(1));

      await fixture.result(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(fixture.alerts.alerts, hasLength(2));
    },
  );

  testWidgets(
    'rejected result-only notice cannot fall back after its host becomes unavailable',
    (tester) async {
      final fixture = await _TimingFixture.create(
        tester,
        timing: AdvanceWarningTimingSettings.battleOnly,
        display: AdvanceWarningDisplayMode.smart,
        equipment: <int>[43],
      );
      await fixture.result(tester);
      expect(find.text('大破舰已携带损管'), findsOneWidget);
      expect(fixture.alerts.alerts, hasLength(1));

      fixture.safetyAccepted = (event, state) => false;
      fixture.noticeEnabled = false;
      await fixture.mount(tester);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.text('大破舰已携带损管'), findsNothing);
      expect(fixture.alerts.alerts, hasLength(1));

      fixture.safetyAccepted = (event, state) => true;
      await fixture.result(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('大破舰已携带损管'), findsNothing);
      expect(fixture.alerts.alerts, hasLength(2));
    },
  );
}

Future<void> _expectPendingStartResult(
  WidgetTester tester, {
  required AdvanceWarningTimingSettings timing,
  AdvanceWarningTimingSettings? changedTiming,
  bool sharedSession = true,
  bool toggleWarnings = false,
}) async {
  final fixture = await _TimingFixture.create(
    tester,
    timing: timing,
    sharedSession: sharedSession,
  );
  final pendingStart = Completer<GameState>();
  final pendingResult = Completer<GameState>();
  fixture.deferSortieStart = true;
  fixture.pendingState = pendingStart.future;
  fixture.port.add(
    kcsapiEvent('/kcsapi/api_req_map/start', <String, Object?>{
      'api_maparea_id': 1,
      'api_mapinfo_no': 1,
      'api_no': 1,
      'api_next': 1,
    }, sequence: ++fixture.sequence),
  );
  await tester.pump();
  if (toggleWarnings) {
    await fixture.settings.setBattleWarningMode(BattleWarningMode.off);
  }
  if (changedTiming != null) {
    await fixture.settings.setAdvanceWarningTimings(changedTiming);
  }
  if (toggleWarnings) {
    await fixture.settings.setBattleWarningMode(BattleWarningMode.confirm);
  }
  fixture.pendingState = pendingResult.future;
  fixture.port.add(
    kcsapiEvent('/kcsapi/api_req_sortie/battleresult', const <String, Object?>{
      'api_win_rank': 'A',
    }, sequence: ++fixture.sequence),
  );
  await tester.pump();
  expect(find.byType(AlertDialog), findsNothing);
  expect(fixture.alerts.alerts, isEmpty);

  fixture.session.startSortie();
  pendingStart.complete(_timingState(<int>[], healthy: true));
  await tester.pump();
  expect(find.byType(AlertDialog), findsNothing);
  expect(fixture.alerts.alerts, isEmpty);
  pendingResult.complete(_timingState(<int>[]));
  await tester.pumpAndSettle();
  if (sharedSession) expect(fixture.session.timings, timing);
  expect(
    find.byType(AlertDialog),
    timing.postBattle ? findsOneWidget : findsNothing,
  );
  expect(find.text('大破舰已携带损管'), findsNothing);
  expect(fixture.alerts.alerts, hasLength(timing.postBattle ? 1 : 0));
  await fixture.closePresentation(tester);
  final alertsBeforeAdvance = fixture.alerts.alerts.length;
  fixture.pendingState = null;
  await fixture.navigate(tester);
  if (sharedSession) expect(fixture.session.timings, timing);
  expect(
    find.byType(AlertDialog),
    timing.afterAdvance ? findsOneWidget : findsNothing,
  );
  expect(
    fixture.alerts.alerts,
    hasLength(alertsBeforeAdvance + (timing.afterAdvance ? 1 : 0)),
  );
}

GameState _timingState(
  List<int> equipment, {
  bool multiple = false,
  bool healthy = false,
}) => GameState(
  memberId: 1001,
  hasEquipmentInventory: true,
  masterShips: const <int, MasterShip>{
    1: MasterShip(id: 1, name: '旗舰', shipTypeId: 2),
    2: MasterShip(id: 2, name: '时雨', shipTypeId: 2),
    3: MasterShip(id: 3, name: '夕立', shipTypeId: 2),
  },
  ships: <int, OwnedShip>{
    1: const OwnedShip(id: 1, masterId: 1, level: 99, currentHp: 20, maxHp: 20),
    2: OwnedShip(
      id: 2,
      masterId: 2,
      level: 99,
      currentHp: healthy ? 20 : 5,
      maxHp: 20,
      slotIds: <int>[
        for (var index = 0; index < equipment.length; index++) 100 + index,
      ],
    ),
    if (multiple)
      3: OwnedShip(
        id: 3,
        masterId: 3,
        level: 99,
        currentHp: healthy ? 20 : 5,
        maxHp: 20,
      ),
  },
  slotItems: <int, OwnedSlotItem>{
    for (var index = 0; index < equipment.length; index++)
      100 + index: OwnedSlotItem(
        id: 100 + index,
        masterSlotItemId: equipment[index],
      ),
  },
  fleets: <Fleet>[
    Fleet(id: 1, name: '第一舰队', shipIds: <int>[1, 2, if (multiple) 3]),
  ],
  combatState: const CombatState(
    sortieFleetId: 1,
    mapArea: 1,
    mapInfo: 1,
    currentNode: 1,
    isActive: true,
  ),
);

class _TimingFixture {
  _TimingFixture(this.settings);
  final SafetySettingsController settings;
  final account = AccountSession(initialMemberId: 1001);
  final session = SortieWarningSession();
  final port = _TimingPort();
  final notices = TopNoticeController();
  final alerts = _TimingAlerts();
  late final GameCaptureController capture;
  GameState state = _timingState(<int>[]);
  Future<GameState>? pendingState;
  bool Function(CapturedApiEvent, GameState)? safetyAccepted;
  CapturedApiEvent? lastEvent;
  var sequence = 0;
  var trusted = true;
  var deferSortieStart = false;
  var sharedSession = true;
  var noticeEnabled = true;

  static Future<_TimingFixture> create(
    WidgetTester tester, {
    AdvanceWarningTimingSettings timing =
        AdvanceWarningTimingSettings.battleAndAdvance,
    AdvanceWarningDisplayMode display = AdvanceWarningDisplayMode.alwaysConfirm,
    List<int> equipment = const <int>[],
    bool sharedSession = true,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'safety.advanceWarningTimings': jsonEncode(<String, bool>{
        'postBattle': timing.postBattle,
        'afterAdvance': timing.afterAdvance,
      }),
      'safety.advanceWarningDisplayMode': display.name,
    });
    final fixture =
        _TimingFixture(
            await SafetySettingsController.load(
              SharedPreferencesSafetySettingsStore(),
            ),
          )
          ..state = _timingState(equipment)
          ..sharedSession = sharedSession;
    fixture.capture = GameCaptureController(
      onAcceptedEvent: (event) {
        if (event.path == '/kcsapi/api_req_map/start' &&
            !fixture.deferSortieStart) {
          fixture.session.startSortie();
        } else if (event.path == '/kcsapi/api_port/port') {
          fixture.session.endSortie();
        }
      },
    );
    await fixture.capture.attach(fixture.port, enabled: true);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      fixture.capture.dispose();
      fixture.port.dispose();
      fixture.settings.dispose();
      fixture.session.dispose();
      fixture.notices.dispose();
      fixture.account.dispose();
    });
    await fixture.mount(tester);
    return fixture;
  }

  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: QuestCompletionDrawerHost(
        controller: notices,
        child: Column(
          children: <Widget>[
            const SizedBox(
              width: double.infinity,
              height: 44,
              child: QuestCompletionHeaderSlot(child: Text('顶栏')),
            ),
            Expanded(
              child: BattleResultWarningOverlay(
                accountSession: account,
                gameCaptureController: capture,
                loadSafetyState: () async => await pendingState ?? state,
                safetySettingsController: settings,
                damageControlStateTrusted: () => trusted,
                warningSession: sharedSession ? session : null,
                safetyEventAccepted: (event, state) =>
                    safetyAccepted?.call(event, state) ?? true,
                damageControlNoticeEnabled: () => noticeEnabled,
                damageAlertPort: alerts,
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> emit(WidgetTester tester, CapturedApiEvent event) async {
    lastEvent = event;
    port.add(event);
    await tester.pumpAndSettle();
  }

  Future<void> result(
    WidgetTester tester, {
    String path = '/kcsapi/api_req_sortie/battleresult',
  }) => emit(
    tester,
    kcsapiEvent(path, const <String, Object?>{
      'api_win_rank': 'S',
    }, sequence: ++sequence),
  );

  Future<void> navigate(
    WidgetTester tester, {
    bool start = false,
    int? next,
    bool boss = false,
  }) => emit(
    tester,
    kcsapiEvent(
      start ? '/kcsapi/api_req_map/start' : '/kcsapi/api_req_map/next',
      <String, Object?>{
        'api_maparea_id': 1,
        'api_mapinfo_no': 1,
        'api_no': 1,
        'api_next': ?next,
        if (boss) 'api_event_id': 5,
      },
      sequence: ++sequence,
    ),
  );

  void expectPresentation({
    required bool equipped,
    required AdvanceWarningDisplayMode display,
  }) {
    final gold = equipped && display == AdvanceWarningDisplayMode.smart;
    expect(find.byType(AlertDialog), gold ? findsNothing : findsOneWidget);
    expect(find.text('大破舰已携带损管'), gold ? findsOneWidget : findsNothing);
  }

  Future<void> closePresentation(WidgetTester tester) async {
    final confirm = find.byKey(const Key('acknowledgeAdvanceWarning'));
    if (confirm.evaluate().isNotEmpty) {
      await tester.tap(confirm);
    } else if (find.text('大破舰已携带损管').evaluate().isNotEmpty) {
      await tester.tap(find.text('大破舰已携带损管'));
    }
    await tester.pumpAndSettle();
  }
}

class _TimingPort implements GameCapturePort {
  final eventsController = StreamController<CapturedApiEvent>.broadcast(
    sync: true,
  );
  @override
  Stream<CapturedApiEvent> get events => eventsController.stream;
  void add(CapturedApiEvent event) => eventsController.add(event);
  @override
  Future<void> configure({
    required bool enabled,
    required String script,
  }) async {}
  @override
  Future<bool> isSupported() async => true;
  @override
  void dispose() => unawaited(eventsController.close());
}

class _TimingAlerts implements BattleDamageAlertPort {
  final alerts = <BattleDamageAlertSeverity>[];
  @override
  Future<void> alert(BattleDamageAlertSeverity severity) async =>
      alerts.add(severity);
}
