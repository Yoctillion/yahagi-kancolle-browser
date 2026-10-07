import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_calculation.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_state.dart';

void main() {
  test('剩余天数只按年月日计算而不依赖本地时区时长', () {
    expect(senkaRemainingDaysInMonth(2026, 3, 8), 24);
    expect(senkaRemainingDaysInMonth(2026, 11, 1), 30);
    expect(senkaRemainingDaysInMonth(2028, 2, 28), 2);
  });

  test('按计划奖励与当月进度计算目标差额和含当天日均', () {
    final state = SenkaState.forMonth('2026-08').copyWith(
      targetSenka: 3000,
      calculatorCurrentSenka: 1000,
      eoStatuses: const {
        15: SenkaRewardStatus.planned,
        25: SenkaRewardStatus.completed,
      },
      questStatuses: const {
        854: SenkaRewardStatus.planned,
        947: SenkaRewardStatus.planned,
        949: SenkaRewardStatus.deferred,
      },
      days: const {
        '2026-08-10': SenkaDayRecord(experience: 3.85, eo: 75, quest: 0),
        '2026-08-09': SenkaDayRecord(experience: 7),
      },
    );

    final result = SenkaCalculationResult.fromState(
      state,
      now: DateTime.utc(2026, 8, 10, 3),
    );

    expect(result.plannedEo, 75);
    expect(result.plannedQuest, 830);
    expect(result.projected, 1905);
    expect(result.gap, 1095);
    expect(result.over, 0);
    expect(result.percentage, closeTo(63.5, 0.0001));
    expect(result.remainingDays, 22);
    expect(result.unsettledSenka, 0);
    expect(result.dailyRequired, closeTo(1098.85 / 22, 0.0001));
    expect(result.todayRemaining, closeTo(1098.85 / 22 - 3.85, 0.0001));
  });

  test('超过目标时差额与每日需求归零并报告超额', () {
    final state = SenkaState.forMonth(
      '2026-08',
    ).copyWith(targetSenka: 1000, calculatorCurrentSenka: 1200);

    final result = SenkaCalculationResult.fromState(
      state,
      now: DateTime.utc(2026, 8, 31, 3),
    );

    expect(result.projected, 1200);
    expect(result.gap, 0);
    expect(result.over, 200);
    expect(result.percentage, 120);
    expect(result.remainingDays, 1);
    expect(result.dailyRequired, 0);
    expect(result.todayRemaining, 0);
  });

  test('有日初目标时当月目标被额外奖励达成也不再要求经验战果', () {
    final state = SenkaState.forMonth('2026-08').copyWith(
      targetSenka: 1220,
      calculatorCurrentSenka: 1000,
      calculatorLocalSenkaAtSet: 0,
      dailyTargetDateKey: '2026-08-10',
      dailyProjectedSenkaAtStart: 1000,
      days: const {'2026-08-10': SenkaDayRecord(experience: 4, eo: 250)},
    );
    final result = SenkaCalculationResult.fromState(
      state,
      now: DateTime.utc(2026, 8, 10, 3),
    );
    expect(result.projected, 1254);
    expect(result.gap, 0);
    expect(result.dailyRequired, 0);
    expect(result.todayRemaining, 0);
  });

  test('月底当月目标被任务奖励达成时今日剩余归零', () {
    final state = SenkaState.forMonth('2026-08').copyWith(
      targetSenka: 1020,
      calculatorCurrentSenka: 1000,
      calculatorLocalSenkaAtSet: 0,
      dailyTargetDateKey: '2026-08-31',
      dailyProjectedSenkaAtStart: 1000,
      days: const {'2026-08-31': SenkaDayRecord(experience: 4, quest: 80)},
    );
    final result = SenkaCalculationResult.fromState(
      state,
      now: DateTime.utc(2026, 8, 31, 3),
    );
    expect(result.projected, 1084);
    expect(result.gap, 0);
    expect(result.dailyRequired, 0);
    expect(result.todayRemaining, 0);
  });

  test('当天进度仅抵扣当天剩余需求', () {
    final state = SenkaState.forMonth('2026-02').copyWith(
      targetSenka: 280,
      days: const {'2026-02-01': SenkaDayRecord(experience: 4)},
    );

    final result = SenkaCalculationResult.fromState(
      state,
      now: DateTime.utc(2026, 2, 1, 3),
    );

    expect(result.remainingDays, 28);
    expect(result.dailyRequired, 10);
    expect(result.todayRemaining, 6);
  });

  test('预计战果包含最新排名之后尚未结算的本地增量', () {
    final state = SenkaState.forMonth('2026-08').copyWith(
      targetSenka: 2000,
      calculatorCurrentSenka: 1000,
      days: const {
        '2026-08-09': SenkaDayRecord(experience: 40),
        '2026-08-10': SenkaDayRecord(experience: 10),
      },
      rankingHistory: {
        'player': [
          SenkaRankingSnapshot(
            rank: 500,
            senka: 1000,
            capturedAt: DateTime.utc(2026, 8, 9, 6),
            localSenkaAtCapture: 40,
          ),
        ],
      },
    );

    final result = SenkaCalculationResult.fromState(
      state,
      now: DateTime.utc(2026, 8, 10, 3),
    );

    expect(result.unsettledSenka, 10);
    expect(result.projected, 1010);
    expect(result.gap, 990);
  });

  test('排名刷新前后保持由日初缺口确定的今日目标', () {
    SenkaState stateWithSnapshot({
      required double current,
      required double localAtCapture,
      required DateTime capturedAt,
    }) => SenkaState.forMonth('2026-08').copyWith(
      targetSenka: 1220,
      calculatorCurrentSenka: current,
      days: const {'2026-08-10': SenkaDayRecord(experience: 10)},
      rankingHistory: {
        'player': [
          SenkaRankingSnapshot(
            rank: 500,
            senka: current,
            capturedAt: capturedAt,
            localSenkaAtCapture: localAtCapture,
          ),
        ],
      },
    );

    final beforeRefresh = SenkaCalculationResult.fromState(
      stateWithSnapshot(
        current: 1000,
        localAtCapture: 0,
        capturedAt: DateTime.utc(2026, 8, 9, 6),
      ),
      now: DateTime.utc(2026, 8, 10, 3),
    );
    final afterRefresh = SenkaCalculationResult.fromState(
      stateWithSnapshot(
        current: 1010,
        localAtCapture: 10,
        capturedAt: DateTime.utc(2026, 8, 10, 6),
      ),
      now: DateTime.utc(2026, 8, 10, 7),
    );

    expect(beforeRefresh.dailyRequired, 10);
    expect(beforeRefresh.todayRemaining, 0);
    expect(afterRefresh.dailyRequired, 10);
    expect(afterRefresh.todayRemaining, 0);
  });

  test('下午排名刷新清空结算后增量时仍扣除全天日历经验', () {
    final before = SenkaState.forMonth('2026-08').copyWith(
      targetSenka: 1220,
      calculatorCurrentSenka: 1000,
      dailyTargetDateKey: '2026-08-10',
      dailyProjectedSenkaAtStart: 1000,
      days: const {'2026-08-10': SenkaDayRecord(experience: 4)},
      rankingHistory: {
        'player': [
          SenkaRankingSnapshot(
            rank: 500,
            senka: 1000,
            capturedAt: DateTime.utc(2026, 8, 9, 6),
            localSenkaAtCapture: 0,
          ),
        ],
      },
    );
    final after = before.copyWith(
      calculatorCurrentSenka: 1001,
      rankingHistory: {
        'player': [
          SenkaRankingSnapshot(
            rank: 500,
            senka: 1001,
            capturedAt: DateTime.utc(2026, 8, 10, 6),
            localSenkaAtCapture: 4,
          ),
        ],
      },
    );

    final beforeRefresh = SenkaCalculationResult.fromState(
      before,
      now: DateTime.utc(2026, 8, 10, 4, 59),
    );
    final afterRefresh = SenkaCalculationResult.fromState(
      after,
      now: DateTime.utc(2026, 8, 10, 6),
    );

    expect(beforeRefresh.unsettledSenka, 4);
    expect(afterRefresh.unsettledSenka, 0);
    expect(beforeRefresh.dailyRequired, 10);
    expect(afterRefresh.dailyRequired, 10);
    expect(beforeRefresh.todayRemaining, 6);
    expect(afterRefresh.todayRemaining, 6);

    final afterMoreExperience = SenkaCalculationResult.fromState(
      after.copyWith(
        days: const {'2026-08-10': SenkaDayRecord(experience: 5.5)},
      ),
      now: DateTime.utc(2026, 8, 10, 7),
    );
    expect(afterMoreExperience.unsettledSenka, 1.5);
    expect(afterMoreExperience.dailyRequired, 10);
    expect(afterMoreExperience.todayRemaining, 4.5);

    final afterDailyGoal = SenkaCalculationResult.fromState(
      after.copyWith(
        days: const {'2026-08-10': SenkaDayRecord(experience: 12)},
      ),
      now: DateTime.utc(2026, 8, 10, 8),
    );
    expect(afterDailyGoal.todayRemaining, 0);
  });

  test('今日剩余只扣日历经验而不扣当天 EO 与任务奖励', () {
    final state = SenkaState.forMonth('2026-08').copyWith(
      targetSenka: 1440,
      calculatorCurrentSenka: 1000,
      calculatorLocalSenkaAtSet: 0,
      dailyTargetDateKey: '2026-08-10',
      dailyProjectedSenkaAtStart: 1000,
      days: const {
        '2026-08-10': SenkaDayRecord(experience: 4, eo: 75, quest: 80),
      },
    );

    final result = SenkaCalculationResult.fromState(
      state,
      now: DateTime.utc(2026, 8, 10, 3),
    );

    expect(result.projected, 1159);
    expect(result.dailyRequired, 20);
    expect(result.todayRemaining, 16);
  });

  test('当天奖励兑现后首次建立日初目标不会重复算入奖励', () {
    final now = DateTime.utc(2026, 8, 10, 3);
    final before = SenkaState.forMonth('2026-08').copyWith(
      targetSenka: 1595,
      calculatorCurrentSenka: 1000,
      calculatorLocalSenkaAtSet: 0,
      eoStatuses: const {15: SenkaRewardStatus.planned},
      questStatuses: const {284: SenkaRewardStatus.planned},
      days: const {'2026-08-10': SenkaDayRecord(experience: 4)},
    );
    final after = before.copyWith(
      eoStatuses: const {15: SenkaRewardStatus.completed},
      questStatuses: const {284: SenkaRewardStatus.completed},
      days: const {
        '2026-08-10': SenkaDayRecord(experience: 4, eo: 75, quest: 80),
      },
    );

    for (final state in [before, after]) {
      final initialized = ensureSenkaDailyTarget(state, now);
      expect(initialized.dailyTargetDateKey, '2026-08-10');
      expect(initialized.dailyProjectedSenkaAtStart, 1155);
      for (final candidate in [state, initialized]) {
        final result = SenkaCalculationResult.fromState(candidate, now: now);
        expect(result.projected, 1159);
        expect(result.dailyRequired, 20);
        expect(result.todayRemaining, 16);
      }
    }
  });

  test('计划奖励当天兑现不会被今日剩余重复抵扣', () {
    final capturedAt = DateTime.utc(2026, 8, 9, 6);
    SenkaState state({
      required SenkaRewardStatus status,
      required SenkaDayRecord day,
    }) => SenkaState.forMonth('2026-08').copyWith(
      targetSenka: 1300,
      calculatorCurrentSenka: 1000,
      dailyTargetDateKey: '2026-08-10',
      dailyProjectedSenkaAtStart: 1080,
      questStatuses: {284: status},
      days: {'2026-08-10': day},
      rankingHistory: {
        'player': [
          SenkaRankingSnapshot(
            rank: 500,
            senka: 1000,
            capturedAt: capturedAt,
            localSenkaAtCapture: 0,
          ),
        ],
      },
    );

    final before = SenkaCalculationResult.fromState(
      state(status: SenkaRewardStatus.planned, day: const SenkaDayRecord()),
      now: DateTime.utc(2026, 8, 10, 3),
    );
    final after = SenkaCalculationResult.fromState(
      state(
        status: SenkaRewardStatus.completed,
        day: const SenkaDayRecord(quest: 80),
      ),
      now: DateTime.utc(2026, 8, 10, 3),
    );

    expect(before.projected, 1080);
    expect(after.projected, 1080);
    expect(after.dailyRequired, before.dailyRequired);
    expect(after.todayRemaining, before.todayRemaining);
  });

  test('当天修改计划奖励会同步重定日初预计值而不伪造今日进度', () {
    final previous = SenkaState.forMonth('2026-08').copyWith(
      targetSenka: 1300,
      calculatorCurrentSenka: 1000,
      dailyTargetDateKey: '2026-08-10',
      dailyProjectedSenkaAtStart: 1000,
    );
    final changed = previous.copyWith(
      questStatuses: const {284: SenkaRewardStatus.planned},
    );
    final rebased = rebaseSenkaDailyTarget(
      previous,
      changed,
      DateTime.utc(2026, 8, 10, 3),
    );
    final result = SenkaCalculationResult.fromState(
      rebased,
      now: DateTime.utc(2026, 8, 10, 3),
    );

    expect(rebased.dailyProjectedSenkaAtStart, 1080);
    expect(result.dailyRequired, 10);
    expect(result.todayRemaining, 10);
  });

  test('月末二十二点截止后旧月份可用天数为零', () {
    final state = SenkaState.forMonth(
      '2026-08',
    ).copyWith(targetSenka: 1000, calculatorCurrentSenka: 900);

    final beforeCutoff = SenkaCalculationResult.fromState(
      state,
      now: DateTime.utc(2026, 8, 31, 12, 59),
    );
    final atCutoff = SenkaCalculationResult.fromState(
      state,
      now: DateTime.utc(2026, 8, 31, 13),
    );
    final afterMidnight = SenkaCalculationResult.fromState(
      state,
      now: DateTime.utc(2026, 8, 31, 16),
    );

    expect(beforeCutoff.remainingDays, 1);
    expect(atCutoff.remainingDays, 0);
    expect(atCutoff.dailyRequired, 0);
    expect(afterMidnight.remainingDays, 0);
  });

  test('下一次刷新覆盖战果日、任务日与月末结算边界', () {
    expect(
      senkaNextRefreshInstant(DateTime.utc(2026, 8, 9, 16, 59)),
      DateTime.utc(2026, 8, 9, 17),
    );
    expect(
      senkaNextRefreshInstant(DateTime.utc(2026, 8, 9, 17, 1)),
      DateTime.utc(2026, 8, 9, 20),
    );
    expect(
      senkaNextRefreshInstant(DateTime.utc(2026, 8, 9, 20, 1)),
      DateTime.utc(2026, 8, 10, 17),
    );
    expect(
      senkaNextRefreshInstant(DateTime.utc(2026, 8, 31, 11, 59)),
      DateTime.utc(2026, 8, 31, 13),
    );
    expect(
      senkaNextRefreshInstant(DateTime.utc(2026, 8, 31, 13, 1)),
      DateTime.utc(2026, 8, 31, 17),
    );
  });

  test('UTC 17:30 跨过 JST 战果日边界时不偏日', () {
    final state = SenkaState.forMonth('2026-08').copyWith(
      targetSenka: 31,
      days: const {'2026-08-31': SenkaDayRecord(experience: 5)},
    );

    final result = SenkaCalculationResult.fromState(
      state,
      now: DateTime.utc(2026, 8, 30, 17, 30),
    );

    expect(result.remainingDays, 1);
    expect(result.dailyRequired, 31);
    expect(result.todayRemaining, 26);
  });
}
