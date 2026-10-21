import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Inject a failed platform write while retaining the real preferences cache.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/account/account_session.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_calculation.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_calendar_view.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_controller.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_page.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_state.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_store.dart';

import 'fixtures/kcsapi_fixtures.dart';

DateTime _jst(int year, int month, int day, int hour, [int minute = 0]) =>
    DateTime.utc(
      year,
      month,
      day,
      hour,
      minute,
    ).subtract(const Duration(hours: 9));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test(
    'two owners survive 519 days, leap February, 17 calendar months and restarts',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final session = AccountSession(initialMemberId: 1001);
      final store = SharedPreferencesSenkaStore(
        preferences,
        accountSession: session,
      );
      var now = _jst(2027, 8, 1, 6);
      var controller = SenkaController(
        store: store,
        accountSession: session,
        now: () => now,
      );
      addTearDown(() {
        controller.dispose();
        session.dispose();
      });
      await controller.initialize();
      final experience = <int, int>{1001: 1000000, 2002: 3000000};
      final monthTotals = <String, double>{};
      var dates = 0;
      for (
        var date = DateTime.utc(2027, 8, 1);
        date.isBefore(DateTime.utc(2029, 1, 1));
        date = date.add(const Duration(days: 1))
      ) {
        now = _jst(date.year, date.month, date.day, 6);
        final month = '${date.year}-${date.month.toString().padLeft(2, '0')}';
        for (final owner in [1001, 2002]) {
          session.selectMember(owner);
          await controller.idle;
          controller.refreshForCurrentTime();
          if (dates == 0) {
            controller.cycleQuestReward(854);
            controller.cycleQuestReward(854);
            controller.cycleQuestReward(947);
            controller.cycleQuestReward(947);
            controller.cycleQuestReward(949);
            controller.cycleQuestReward(949);
          }
          for (final xp in [experience[owner]!, experience[owner]! + 10000]) {
            controller.accept(
              kcsapiEvent('/kcsapi/api_get_member/basic', {
                'api_member_id': owner,
                'api_experience': xp,
              }, capturedAt: now),
            );
            await controller.idle;
          }
          experience[owner] = experience[owner]! + 10000;
          final modelKey = '$owner/$month';
          monthTotals[modelKey] = (monthTotals[modelKey] ?? 0) + 7;
          expect(controller.state.monthKey, month, reason: '$owner / $date');
          expect(
            controller.state.monthExperienceSenka,
            closeTo(monthTotals[modelKey]!, 1e-8),
            reason: '$owner / $date',
          );
          expect(
            controller.state.day(date).experience,
            7,
            reason: '$owner / $date',
          );
          expect(
            controller.state.days.keys.every(
              (key) => key.startsWith('$month-'),
            ),
            isTrue,
          );
          expect(
            controller.state.questStatuses[949],
            SenkaRewardStatus.completed,
          );
          expect(
            controller.state.questStatuses[854] == SenkaRewardStatus.completed,
            date.isBefore(DateTime.utc(2027, 9, 1)),
          );
          expect(
            controller.state.questStatuses[947] == SenkaRewardStatus.completed,
            date.isBefore(DateTime.utc(2028, 6, 1)),
          );
          final archived = await store.loadForAccount(owner);
          expect(
            archived!.monthExperienceSenka,
            controller.state.monthExperienceSenka,
          );
        }
        dates++;
        if (dates % 17 == 0) {
          controller.dispose();
          controller = SenkaController(
            store: store,
            accountSession: session,
            now: () => now,
          );
          await controller.initialize();
          expect(
            controller.state.monthExperienceSenka,
            monthTotals['2002/$month'],
          );
        }
      }
      expect(dates, 519);
      expect(monthTotals.keys, hasLength(34));
      expect(monthTotals['1001/2028-02'], 29 * 7);
      expect(monthTotals['2002/2028-12'], 31 * 7);
    },
  );

  test(
    'daily target and calendar progress survive a real store reload and next-day refresh',
    () async {
      final session = AccountSession(initialMemberId: 1001);
      final store = SharedPreferencesSenkaStore(
        await SharedPreferences.getInstance(),
        accountSession: session,
      );
      var now = _jst(2028, 2, 1, 6);
      var controller = SenkaController(
        store: store,
        accountSession: session,
        now: () => now,
      );
      addTearDown(() {
        controller.dispose();
        session.dispose();
      });
      await controller.initialize();
      controller.setTargetSenka(290);
      controller.accept(
        kcsapiEvent('/kcsapi/api_get_member/basic', {
          'api_member_id': 1001,
          'api_experience': 1000000,
        }, capturedAt: now),
      );
      await controller.idle;
      controller.accept(
        kcsapiEvent('/kcsapi/api_get_member/basic', {
          'api_member_id': 1001,
          'api_experience': 1010000,
        }, capturedAt: now),
      );
      await controller.idle;
      var result = SenkaCalculationResult.fromState(controller.state, now: now);
      expect(result.dailyRequired, 10);
      expect(result.todayRemaining, 3);
      controller.dispose();
      controller = SenkaController(
        store: store,
        accountSession: session,
        now: () => now,
      );
      await controller.initialize();
      result = SenkaCalculationResult.fromState(controller.state, now: now);
      expect(result.dailyRequired, 10);
      expect(result.todayRemaining, 3);
      now = _jst(2028, 2, 2, 2);
      controller.refreshForCurrentTime();
      await controller.idle;
      result = SenkaCalculationResult.fromState(controller.state, now: now);
      expect(result.dailyRequired, closeTo(283 / 28, 1e-8));
      expect(result.todayRemaining, result.dailyRequired);
      expect(controller.state.day(DateTime.utc(2028, 2, 1)).experience, 7);
    },
  );

  test(
    'all refresh boundaries are strictly in the future across two years',
    () {
      for (var year = 2027; year <= 2028; year++) {
        for (var month = 1; month <= 12; month++) {
          final lastDay = DateTime.utc(year, month + 1, 0).day;
          for (final day in [1, lastDay]) {
            for (final hour in [2, 5, if (day == lastDay) 22]) {
              final boundary = _jst(year, month, day, hour);
              expect(
                senkaNextRefreshInstant(
                  boundary.subtract(const Duration(microseconds: 1)),
                ),
                boundary,
              );
              expect(
                senkaNextRefreshInstant(boundary).isAfter(boundary),
                isTrue,
              );
            }
          }
          expect(senkaAvailableDays(_jst(year, month, lastDay, 21, 59)), 1);
          final nextMonthDays = DateTime.utc(year, month + 2, 0).day;
          expect(
            senkaAvailableDays(_jst(year, month, lastDay, 22)),
            nextMonthDays,
          );
          expect(
            senkaAvailableDays(_jst(year, month + 1, 1, 1, 59)),
            nextMonthDays,
          );
          expect(
            senkaAvailableDays(_jst(year, month + 1, 1, 2)),
            DateTime.utc(year, month + 2, 0).day,
          );
        }
      }
    },
  );

  test(
    'editing while legacy account migration awaits its native write preserves archived data',
    () async {
      final session = AccountSession(initialMemberId: 1001);
      final raw = jsonEncode(
        SenkaState.forMonth('2026-08')
            .copyWith(
              memberId: 1001,
              targetSenka: 3000,
              days: const {
                '2026-08-09': SenkaDayRecord(experience: 70, eo: 75),
              },
              questStatuses: const {949: SenkaRewardStatus.completed},
              rankingHistory: {
                'player': [
                  SenkaRankingSnapshot(
                    rank: 500,
                    senka: 1000,
                    capturedAt: _jst(2026, 8, 9, 15),
                    localSenkaAtCapture: 145,
                  ),
                ],
              },
            )
            .toJson(),
      );
      final previousPlatform = SharedPreferencesStorePlatform.instance;
      final delayedPlatform = _DelayedMigrationPreferencesStore({
        'flutter.senka.archive.v1': raw,
      });
      SharedPreferencesStorePlatform.instance = delayedPlatform;
      addTearDown(() {
        SharedPreferencesStorePlatform.instance = previousPlatform;
        SharedPreferences.resetStatic();
      });
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesSenkaStore(
        preferences,
        accountSession: session,
      );
      final controller = SenkaController(
        store: store,
        accountSession: session,
        now: () => _jst(2026, 8, 10, 6),
      );
      addTearDown(() {
        controller.dispose();
        session.dispose();
      });
      final initialization = controller.initialize();
      await delayedPlatform.started.future;
      controller.setTargetSenka(3200);
      delayedPlatform.release.complete();
      await initialization;
      await controller.idle;
      final archived = (await store.loadForAccount(1001))!;
      expect(archived.targetSenka, 3200);
      expect(archived.day(DateTime.utc(2026, 8, 9)).experience, 70);
      expect(archived.rankingHistory['player'], hasLength(1));
      expect(archived.questStatuses[949], SenkaRewardStatus.completed);
      expect(preferences.getString('senka.archive.v1'), raw);
    },
  );

  test(
    'platform rejection of a preference write is reported as an unsuccessful save',
    () async {
      final previousPlatform = SharedPreferencesStorePlatform.instance;
      SharedPreferencesStorePlatform.instance = _RejectingPreferencesStore();
      addTearDown(() {
        SharedPreferencesStorePlatform.instance = previousPlatform;
        SharedPreferences.resetStatic();
      });
      final session = AccountSession(initialMemberId: 1001);
      final preferences = await SharedPreferences.getInstance();
      final controller = SenkaController(
        store: SharedPreferencesSenkaStore(
          preferences,
          accountSession: session,
        ),
        accountSession: session,
        now: () => _jst(2026, 8, 10, 6),
      );
      addTearDown(() {
        controller.dispose();
        session.dispose();
      });
      await controller.initialize();
      expect(await controller.setBaseSenka(123.45), isFalse);
      expect(controller.hasPersistenceError, isTrue);
      await preferences.reload();
      expect(preferences.getString('account.1001.senka.archive.v1'), isNull);
    },
  );

  test(
    'finite but overflowing manual base input cannot poison the in-memory state',
    () async {
      final controller = SenkaController(
        store: _MemoryStore(),
        now: () => _jst(2026, 8, 10, 6),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      await controller.setBaseSenka(12.34);
      await controller.setBaseSenka(double.maxFinite);
      expect(controller.monthBaseSenka.isFinite, isTrue);
      expect(() => jsonEncode(controller.state.toJson()), returnsNormally);
    },
  );

  test(
    'invalid numeric day records from valid JSON cannot poison later account saves',
    () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        'account.1001.senka.archive.v1',
        jsonEncode({
          'monthKey': '2026-08',
          'memberId': 1001,
          'experienceTrackingVersion': 1,
          'days': {
            '2026-08-09': {'experience': 'NaN', 'eo': -75},
          },
          'targetSenka': 'Infinity',
        }),
      );
      final session = AccountSession(initialMemberId: 1001);
      final controller = SenkaController(
        store: SharedPreferencesSenkaStore(
          preferences,
          accountSession: session,
        ),
        accountSession: session,
        now: () => _jst(2026, 8, 10, 6),
      );
      addTearDown(() {
        controller.dispose();
        session.dispose();
      });
      await controller.initialize();
      expect(controller.state.monthRecorded.isFinite, isTrue);
      expect(controller.state.targetSenka.isFinite, isTrue);
      controller.setTargetSenka(3000);
      await controller.idle;
      expect(controller.hasPersistenceError, isFalse);
    },
  );

  test(
    'out-of-month and invalid calendar keys do not contribute to this month total',
    () {
      final state = SenkaState.fromJson({
        'monthKey': '2026-08',
        'experienceTrackingVersion': 1,
        'days': {
          '2026-08-10': {'experience': 7},
          '2026-07-31': {'experience': 100},
          '2026-08-99': {'experience': 200},
          'garbage': {'experience': 300},
        },
      });
      expect(state.monthExperienceSenka, 7);
      expect(state.days.keys, ['2026-08-10']);
    },
  );

  testWidgets(
    'JST evening calendar still shows tomorrow as an unrecorded future date',
    (tester) async {
      if (DateTime(2026, 8, 11).timeZoneOffset != const Duration(hours: 9)) {
        return;
      }
      await tester.pumpWidget(
        _app(
          SenkaCalendarView(
            state: SenkaState.forMonth('2026-08'),
            now: _jst(2026, 8, 10, 23),
            compact: false,
          ),
        ),
      );
      final tomorrow = find.byKey(const Key('calendar-cell-11'));
      expect(
        find.descendant(of: tomorrow, matching: find.text('-')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tomorrow, matching: find.text('0.0')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'opening the senka page after a hidden month boundary refreshes state immediately',
    (tester) async {
      final openedAt = DateTime.now().toUtc();
      final currentMonth = parseSenkaMonthKey(currentSenkaMonthKey(openedAt))!;
      var now = _jst(currentMonth.year, currentMonth.month - 1, 15, 21);
      final controller = SenkaController(store: _MemoryStore(), now: () => now);
      addTearDown(controller.dispose);
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await controller.initialize();
      controller.setTargetSenka(3000);
      await controller.idle;
      now = openedAt;
      await tester.pumpWidget(
        _app(SenkaPage(controller: controller, mode: SenkaCenterMode.calendar)),
      );
      await tester.pump();
      expect(controller.state.monthKey, currentSenkaMonthKey(openedAt));
      expect(
        find.text('${currentMonth.year}年${currentMonth.month}月战果日历'),
        findsOneWidget,
      );
    },
  );
}

Widget _app(Widget body) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: body),
);

class _DelayedMigrationPreferencesStore extends InMemorySharedPreferencesStore {
  _DelayedMigrationPreferencesStore(super.data) : super.withData();
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
    return super.setValue(valueType, key, value);
  }
}

class _RejectingPreferencesStore extends InMemorySharedPreferencesStore {
  _RejectingPreferencesStore() : super.empty();
  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      false;
}

class _MemoryStore implements SenkaStore {
  SenkaState? state;
  @override
  Future<SenkaState?> load() async => state;
  @override
  Future<void> save(SenkaState value) async {
    state = value;
  }
}
