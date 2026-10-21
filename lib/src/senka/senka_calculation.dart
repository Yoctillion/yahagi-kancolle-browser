import 'dart:math' as math;

import 'senka_catalog.dart';
import 'senka_ledger.dart';
import 'senka_state.dart';

class SenkaCalculationResult {
  const SenkaCalculationResult({
    required this.plannedEo,
    required this.plannedQuest,
    required this.projected,
    required this.gap,
    required this.over,
    required this.percentage,
    required this.remainingDays,
    required this.unsettledSenka,
    required this.dailyRequired,
    required this.todayRemaining,
  });

  factory SenkaCalculationResult.fromState(SenkaState state, {DateTime? now}) {
    final instant = now ?? DateTime.now().toUtc();
    final currentDate = senkaCurrentDate(instant);
    final plannedEo = _plannedSenka(state.eoStatuses, senkaEoCatalog);
    final plannedQuest = _plannedSenka(state.questStatuses, senkaQuestCatalog);
    final baseSenka = state.unsettledSenka;
    final projected = senkaProjected(state);
    final difference = state.targetSenka - projected;
    final gap = math.max(difference, 0).toDouble();
    final over = math.max(-difference, 0).toDouble();
    final remainingDays = state.monthKey == currentSenkaMonthKey(instant)
        ? senkaAvailableDays(instant)
        : 0;
    final today = state.day(currentDate);
    final currentDateKey = dateKey(currentDate);
    final projectedAtDayStart = state.dailyTargetDateKey == currentDateKey
        ? state.dailyProjectedSenkaAtStart
        : math.max(projected - today.experience, 0).toDouble();
    final gapAtDayStart = math
        .max(state.targetSenka - projectedAtDayStart, 0)
        .toDouble();
    final dailyRequired = remainingDays > 0 && gap > 0
        ? gapAtDayStart / remainingDays
        : 0.0;
    // Calendar experience spans the whole senka day, survives ranking refreshes,
    // and excludes EO/quest rewards already accounted for in the projection.
    final todayProgress = today.experience;

    return SenkaCalculationResult(
      plannedEo: plannedEo,
      plannedQuest: plannedQuest,
      projected: projected,
      gap: gap,
      over: over,
      percentage: state.targetSenka > 0
          ? boundedSenkaValue(projected / state.targetSenka * 100)
          : 0,
      remainingDays: remainingDays,
      unsettledSenka: baseSenka,
      dailyRequired: dailyRequired,
      todayRemaining: math.max(dailyRequired - todayProgress, 0).toDouble(),
    );
  }

  final double plannedEo;
  final double plannedQuest;
  final double projected;
  final double gap;
  final double over;
  final double percentage;
  final int remainingDays;
  final double unsettledSenka;
  @Deprecated('Use unsettledSenka')
  double get baseSenka => unsettledSenka;
  final double dailyRequired;
  final double todayRemaining;
}

double senkaProjected(SenkaState state) => finiteSenkaSum([
  state.calculatorCurrentSenka,
  state.unsettledSenka,
  _plannedSenka(state.eoStatuses, senkaEoCatalog),
  _plannedSenka(state.questStatuses, senkaQuestCatalog),
]);

SenkaState ensureSenkaDailyTarget(SenkaState state, DateTime instant) {
  final businessDate = senkaCurrentDate(instant);
  final key = dateKey(businessDate);
  if (state.monthKey != currentSenkaMonthKey(instant) ||
      state.dailyTargetDateKey.compareTo(key) >= 0) {
    return state;
  }
  final projected = senkaProjected(state);
  final inferredStart = math
      .max(projected - state.day(businessDate).experience, 0)
      .toDouble();
  return state.copyWith(
    dailyTargetDateKey: key,
    dailyProjectedSenkaAtStart: inferredStart,
  );
}

SenkaState rebaseSenkaDailyTarget(
  SenkaState previous,
  SenkaState next,
  DateTime instant,
) {
  final initialized = ensureSenkaDailyTarget(previous, instant);
  if (initialized.monthKey != next.monthKey) {
    return ensureSenkaDailyTarget(next, instant);
  }
  final projectionChange = senkaProjected(next) - senkaProjected(previous);
  return next.copyWith(
    dailyTargetDateKey: initialized.dailyTargetDateKey,
    dailyProjectedSenkaAtStart: boundedSenkaValue(
      initialized.dailyProjectedSenkaAtStart + projectionChange,
    ),
  );
}

int senkaRemainingDaysInMonth(int year, int month, int day) =>
    DateTime.utc(year, month + 1, 0).day - day + 1;

DateTime senkaCurrentDate(DateTime instant) => DateTime.parse(
  '${senkaRecordDateKey(instant, currentSenkaMonthKey(instant))}T00:00:00Z',
);

int senkaAvailableDays(DateTime instant) {
  final businessDate = senkaCurrentDate(instant);
  return senkaRemainingDaysInMonth(
    businessDate.year,
    businessDate.month,
    businessDate.day,
  );
}

DateTime senkaNextRefreshInstant(DateTime instant) {
  final now = instant.toUtc();
  final jst = toJst(now);
  final today = DateTime.utc(jst.year, jst.month, jst.day);
  final tomorrow = today.add(const Duration(days: 1));
  final candidates = <DateTime>[
    for (final date in [today, tomorrow]) ...[
      for (final hour in [0, 2, 3, 5, 14, 15]) _jstBoundary(date, hour),
      if (date.day == DateTime.utc(date.year, date.month + 1, 0).day)
        _jstBoundary(date, 22),
    ],
  ]..removeWhere((candidate) => !candidate.isAfter(now));
  candidates.sort();
  return candidates.first;
}

DateTime _jstBoundary(DateTime jstDate, int hour) => DateTime.utc(
  jstDate.year,
  jstDate.month,
  jstDate.day,
  hour,
).subtract(const Duration(hours: 9));

double _plannedSenka(
  Map<int, SenkaRewardStatus> statuses,
  List<SenkaCatalogItem> catalog,
) => catalog.fold(
  0,
  (sum, item) =>
      statuses[item.id] == SenkaRewardStatus.planned ? sum + item.senka : sum,
);
