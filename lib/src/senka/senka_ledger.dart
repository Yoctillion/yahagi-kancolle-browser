import 'senka_catalog.dart';
import 'senka_state.dart';

// All source reducers route through this ledger. Changing the operation month
// must never discard the preceding month's records or a future quest reward.
SenkaState recordSenkaReward(
  SenkaState state,
  DateTime at, {
  double eo = 0,
  double quest = 0,
  String? targetMonthKey,
  bool unattributed = false,
}) => _inMonth(state, targetMonthKey ?? currentSenkaMonthKey(at), (month) {
  if (unattributed) {
    return rebaseSenkaLocalBaseline(
      month.copyWith(
        unattributedEoSenka: boundedSenkaValue(month.unattributedEoSenka + eo),
      ),
      eo,
    );
  }
  return _changeRecorded(month, at, eo: eo, quest: quest);
});

SenkaState observeSenkaExperience(
  SenkaState state,
  int experience,
  DateTime instant, {
  required bool sortieResult,
  required bool returnedToPort,
}) {
  if (experience < 0 || experience > 554400000) return state;
  final at = instant.toUtc();
  final samples = List<SenkaExperienceSample>.of(state.experienceSamples);
  if (samples.isEmpty && state.latestExperience != null) {
    // Historical version-1 days are already recorded. Never reconstruct them
    // from the cumulative total: it is an anchor for future observations only.
    samples.add(
      SenkaExperienceSample(
        at: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        experience: state.latestExperience! - state.pendingSortieExperience,
      ),
    );
    if (state.pendingSortieExperience > 0) {
      samples.add(
        SenkaExperienceSample(
          at:
              state.latestSortieEventAt ??
              at.subtract(const Duration(microseconds: 1)),
          experience: state.latestExperience!,
          sortieResult: true,
        ),
      );
    }
  }
  if (samples.isEmpty) {
    return state.copyWith(
      latestExperience: experience,
      experienceSamples: [
        SenkaExperienceSample(
          at: at,
          experience: experience,
          sortieResult: sortieResult,
          returnedToPort: returnedToPort,
        ),
      ],
    );
  }
  var index = samples.indexWhere(
    (sample) =>
        sample.at == at &&
        sample.sortieResult == sortieResult &&
        sample.returnedToPort == returnedToPort,
  );
  var replace = index >= 0;
  if (replace && experience <= samples[index].experience) return state;
  if (replace && index == 0) {
    samples[0] = SenkaExperienceSample(
      at: at.subtract(const Duration(microseconds: 1)),
      experience: samples[0].experience,
      heldAtAnchor: samples[0].heldAtAnchor,
    );
    replace = false;
  }
  var sequence = 0;
  if (replace) {
    sequence = samples[index].sequence;
  } else {
    index = samples.indexWhere((sample) => sample.at.isAfter(at));
    if (index < 0) index = samples.length;
    if (index > 0 && samples[index - 1].at == at) {
      sequence = samples[index - 1].sequence + 1;
    }
  }
  final previous = index > 0 ? samples[index - 1] : null;
  final nextIndex = index + (replace ? 1 : 0);
  final following = nextIndex < samples.length ? samples[nextIndex] : null;
  // Reject contradictory snapshots before advancing the high water or
  // releasing a pending sortie. Insertion of an older valid snapshot is safe.
  if (previous == null ||
      experience < previous.experience ||
      (following != null && experience > following.experience)) {
    return state;
  }
  final sample = SenkaExperienceSample(
    at: at,
    experience: experience,
    sortieResult: sortieResult,
    returnedToPort: returnedToPort,
    sequence: sequence,
  );
  if (replace) {
    samples[index] = sample;
  } else {
    samples.insert(index, sample);
  }

  var current = state;
  var held = samples.first.heldAtAnchor;
  final heldAfter = <int>[held];
  for (var i = 1; i < samples.length; i++) {
    final observation = samples[i];
    final gained = observation.experience - samples[i - 1].experience;
    var credited = 0;
    if (observation.sortieResult) {
      held += gained;
    } else {
      credited = gained;
      if (observation.returnedToPort) {
        credited += held;
        held = 0;
      }
    }
    heldAfter.add(held);
    final amount = credited * experienceToSenkaRate;
    final old = current.contributions[_sampleKey(observation)];
    if ((old?.experience ?? 0) != amount) {
      current = _replaceExperienceContribution(current, observation, amount);
    }
  }
  // Compact only observation metadata. Daily records and archived months stay
  // intact; the retained anchor also carries any sortie still awaiting port.
  if (samples.length > 2048) {
    final removeCount = samples.length - 2048;
    final contributions = Map<String, SenkaContribution>.of(
      current.contributions,
    );
    for (final observation in samples.take(removeCount + 1)) {
      contributions.remove(_sampleKey(observation));
    }
    samples[removeCount] = samples[removeCount].asAnchor(
      heldAfter[removeCount],
    );
    samples.removeRange(0, removeCount);
    current = current.copyWith(contributions: contributions);
  }
  current = current.copyWith(
    experienceSamples: samples,
    latestExperience: samples.last.experience,
    pendingSortieExperience: held,
  );
  if (state.dailyTargetDateKey.isNotEmpty &&
      state.monthKey == current.monthKey) {
    final date = DateTime.tryParse(state.dailyTargetDateKey);
    if (date != null) {
      final todayChange =
          current.day(date).experience - state.day(date).experience;
      final startingChange =
          current.unsettledSenka - state.unsettledSenka - todayChange;
      if (startingChange.abs() > 1e-9) {
        current = current.copyWith(
          dailyProjectedSenkaAtStart:
              (state.dailyProjectedSenkaAtStart + startingChange).clamp(
                0.0,
                double.maxFinite,
              ),
        );
      }
    }
  }
  return current;
}

String _sampleKey(SenkaExperienceSample sample) =>
    'xp:${sample.at.microsecondsSinceEpoch}:${sample.sequence}';

SenkaState _replaceExperienceContribution(
  SenkaState state,
  SenkaExperienceSample sample,
  double amount,
) {
  final key = _sampleKey(sample);
  final old = state.contributions[key];
  final monthKey = currentSenkaMonthKey(sample.at);
  var current = state;
  if (old != null) {
    current = _inMonth(
      current,
      old.monthKey,
      (month) => _changeRecorded(month, old.at, experience: -old.experience),
    );
  }
  if (amount > 0) {
    current = _inMonth(
      current,
      monthKey,
      (month) => _changeRecorded(month, sample.at, experience: amount),
    );
  }
  final contributions = Map<String, SenkaContribution>.of(
    current.contributions,
  );
  if (amount > 0) {
    contributions[key] = SenkaContribution(
      at: sample.at,
      monthKey: monthKey,
      experience: amount,
    );
  } else {
    contributions.remove(key);
  }
  return current.copyWith(contributions: contributions);
}

SenkaState _inMonth(
  SenkaState state,
  String monthKey,
  SenkaState Function(SenkaState) change,
) {
  if (monthKey == state.monthKey) return change(state);
  final month = state.monthArchives[monthKey] ?? SenkaState.forMonth(monthKey);
  final archives = Map<String, SenkaState>.of(state.monthArchives)
    ..[monthKey] = detachedSenkaMonth(change(month));
  return state.copyWith(monthArchives: archives);
}

String senkaRecordDateKey(DateTime at, String monthKey) {
  final businessKey = dateKey(senkaBusinessDate(at));
  if (businessKey.startsWith('$monthKey-')) return businessKey;
  // Early carryover belongs to day 1 of its operation, not an invalid date in
  // the previous calendar month. The exact instant remains in period records.
  return '$monthKey-01';
}

SenkaState _changeRecorded(
  SenkaState state,
  DateTime at, {
  double experience = 0,
  double eo = 0,
  double quest = 0,
}) {
  final dayKey = senkaRecordDateKey(at, state.monthKey);
  final days = Map<String, SenkaDayRecord>.of(state.days);
  final periodKey = senkaSettlementPeriodStart(at).toIso8601String();
  final periods = Map<String, SenkaDayRecord>.of(state.settlementPeriods);
  SenkaDayRecord change(SenkaDayRecord old) => SenkaDayRecord(
    experience: (old.experience + experience).clamp(0.0, double.maxFinite),
    eo: (old.eo + eo).clamp(0.0, double.maxFinite),
    quest: (old.quest + quest).clamp(0.0, double.maxFinite),
  );
  days[dayKey] = change(days[dayKey] ?? const SenkaDayRecord());
  periods[periodKey] = change(periods[periodKey] ?? const SenkaDayRecord());
  final next = state.copyWith(days: days, settlementPeriods: periods);
  final latest = state.rankingHistory['player']?.lastOrNull;
  final cutoff = latest == null
      ? null
      : latest.settlementCutoff ?? senkaRankingCutoff(latest.capturedAt);
  if (cutoff != null && senkaSettlementPeriodStart(at).isBefore(cutoff)) {
    return rebaseSenkaLocalBaseline(next, experience + eo + quest);
  }
  return next;
}

SenkaState rebaseSenkaLocalBaseline(SenkaState state, double change) {
  final playerHistory = state.rankingHistory['player'];
  if (playerHistory == null || playerHistory.isEmpty) {
    return state.copyWith(
      calculatorLocalSenkaAtSet: state.calculatorLocalSenkaAtSet == null
          ? (state.calculatorCurrentSenka > 0 ? state.monthRecorded : null)
          : (state.calculatorLocalSenkaAtSet! + change).clamp(
              0.0,
              double.maxFinite,
            ),
    );
  }
  final history = Map<String, List<SenkaRankingSnapshot>>.of(
    state.rankingHistory,
  );
  final latest = playerHistory.last;
  history['player'] = [
    ...playerHistory.take(playerHistory.length - 1),
    SenkaRankingSnapshot(
      rank: latest.rank,
      senka: latest.senka,
      capturedAt: latest.capturedAt,
      localSenkaAtCapture: (latest.localSenkaAtCapture + change).clamp(
        0.0,
        double.maxFinite,
      ),
      settlementCutoff: latest.settlementCutoff,
    ),
  ];
  return state.copyWith(
    rankingHistory: history,
    calculatorLocalSenkaAtSet:
        ((state.calculatorLocalSenkaAtSet ?? latest.localSenkaAtCapture) +
                change)
            .clamp(0.0, double.maxFinite),
  );
}

SenkaState replaceSenkaBaseExperience(
  SenkaState state,
  double amount,
  DateTime at,
) {
  final contributions = Map<String, SenkaContribution>.of(state.contributions)
    ..removeWhere((_, contribution) => contribution.monthKey == state.monthKey);
  return state.copyWith(
    unattributedExperienceSenka: amount,
    days: {
      for (final entry in state.days.entries)
        entry.key: SenkaDayRecord(eo: entry.value.eo, quest: entry.value.quest),
    },
    settlementPeriods: {
      for (final entry in state.settlementPeriods.entries)
        entry.key: SenkaDayRecord(eo: entry.value.eo, quest: entry.value.quest),
    },
    experienceSamples: state.latestExperience == null
        ? const []
        : [
            SenkaExperienceSample(
              at: at,
              experience: state.latestExperience!,
              heldAtAnchor: state.pendingSortieExperience,
            ),
          ],
    contributions: contributions,
    pendingSortieExperience: state.pendingSortieExperience,
  );
}
