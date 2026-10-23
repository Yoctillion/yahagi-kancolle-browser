import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_calculation.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_ledger.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_state.dart';

void main() {
  test(
    'version one days stay intact while a new EXP anchor is established',
    () {
      var state = SenkaState.fromJson({
        'monthKey': '2026-08',
        'experienceTrackingVersion': 1,
        'latestExperience': 1000000,
        'days': {
          '2026-08-09': {'experience': 70},
        },
      });
      state = _observe(state, 1010000, _jst(2026, 8, 10, 12));
      expect(state.day(DateTime.utc(2026, 8, 9)).experience, 70);
      expect(state.day(DateTime.utc(2026, 8, 10)).experience, 7);
      state = SenkaState.fromJson(jsonDecode(jsonEncode(state.toJson())));
      state = _observe(state, 1020000, _jst(2026, 8, 10, 16));
      expect(state.monthExperienceSenka, 84);
      expect(state.day(DateTime.utc(2026, 8, 9)).experience, 70);
      expect(state.day(DateTime.utc(2026, 8, 10)).experience, 14);
    },
  );

  test('late EXP after a reload refines both active and archived month', () {
    var state = SenkaState.forMonth('2026-08');
    state = _observe(state, 1000000, _jst(2026, 8, 31, 10));
    state = migrateSenkaStateToMonth(state, '2026-09');
    state = _observe(state, 1020000, _jst(2026, 9, 1, 3));
    state = SenkaState.fromJson(jsonDecode(jsonEncode(state.toJson())));
    state = _observe(state, 1010000, _jst(2026, 8, 31, 13));
    expect(state.monthExperienceSenka, 7);
    expect(state.day(DateTime.utc(2026, 9, 1)).experience, 7);
    expect(state.monthArchives['2026-08']!.monthExperienceSenka, 7);
    final reloaded = SenkaState.fromJson(
      jsonDecode(jsonEncode(state.toJson())),
    );
    expect(reloaded.monthExperienceSenka, 7);
    expect(reloaded.monthArchives['2026-08']!.monthExperienceSenka, 7);
  });

  test('late prior-day EXP refines the current daily target baseline', () {
    var state = SenkaState.forMonth('2026-08').copyWith(targetSenka: 220);
    state = _observe(state, 1000000, _jst(2026, 8, 9, 21));
    final now = _jst(2026, 8, 10, 16);
    state = ensureSenkaDailyTarget(state, now);
    state = _observe(state, 1020000, now);
    expect(state.dailyProjectedSenkaAtStart, 0);
    state = _observe(state, 1010000, _jst(2026, 8, 10, 1));
    expect(state.day(DateTime.utc(2026, 8, 9)).experience, 7);
    expect(state.day(DateTime.utc(2026, 8, 10)).experience, 7);
    expect(state.dailyTargetDateKey, '2026-08-10');
    expect(state.dailyProjectedSenkaAtStart, 7);
    final result = SenkaCalculationResult.fromState(state, now: now);
    expect(result.dailyRequired, closeTo(213 / 22, 1e-8));
    expect(result.todayRemaining, closeTo(213 / 22 - 7, 1e-8));
  });
}

SenkaState _observe(SenkaState state, int experience, DateTime at) =>
    observeSenkaExperience(
      state,
      experience,
      at,
      sortieResult: false,
      returnedToPort: false,
    );

DateTime _jst(int year, int month, int day, int hour) =>
    DateTime.utc(year, month, day, hour).subtract(const Duration(hours: 9));
