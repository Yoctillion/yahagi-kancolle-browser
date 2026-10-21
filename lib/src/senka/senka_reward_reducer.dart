import '../bridge/captured_api_event.dart';
import '../game_state/game_api_decoder.dart';
import 'senka_catalog.dart';
import 'senka_state.dart';

typedef SenkaRewardRecorder =
    SenkaState Function(
      SenkaState state,
      DateTime at, {
      double eo,
      double quest,
      String? targetMonthKey,
      bool unattributed,
    });

/// Applies actual reward receipts independently of the ordinary EXP cutoff.
///
/// The caller supplies the common ledger writer so all sources share the same
/// archive and ranking-baseline rules. Reward receipts stay separate from the
/// user's planned/completed display choices.
SenkaState reduceSenkaRewards(
  SenkaState state,
  CapturedApiEvent event, {
  required SenkaRewardRecorder recordGain,
}) {
  if (!_rewardPaths.contains(event.path)) return state;
  final decoded = GameApiDecoder.decodeEventData(event);
  if (decoded is! Map) return state;
  final data = decoded.cast<Object?, Object?>();
  if (event.path == _questPath) {
    return _quest(state, event, data, recordGain);
  }
  if (event.path == _mapInfoPath) {
    return _mapInfo(state, event.capturedAt, data, recordGain);
  }
  final amount = _amount(
    data[event.path == _mapNextPath ? 'api_get_eo_rate' : 'api_get_exmap_rate'],
  );
  if (amount == 0) return state;
  return _eoResult(state, event, data, amount, recordGain);
}

SenkaState _quest(
  SenkaState state,
  CapturedApiEvent event,
  Map<Object?, Object?> data,
  SenkaRewardRecorder recordGain,
) {
  final id = _int(event.requestParams['api_quest_id']);
  if (id <= 0) return state;
  final item = senkaQuestById(id);
  final sourceQuestMonth = currentQuestMonthKey(event.capturedAt);
  final cycle = switch (item?.category) {
    SenkaRewardCategory.quarterly =>
      senkaQuarterlyCycleKey(sourceQuestMonth) ?? '',
    SenkaRewardCategory.annual => senkaAnnualCycleKey(sourceQuestMonth) ?? '',
    SenkaRewardCategory.oneTime => 'once',
    _ => 'event:${event.capturedAt.toUtc().toIso8601String()}',
  };
  final category = item?.category.name ?? 'other';
  final key = 'quest:$category:$cycle:$id';
  final currentCycle = switch (item?.category) {
    SenkaRewardCategory.quarterly => state.quarterlyQuestCycleKey,
    SenkaRewardCategory.annual => state.annualQuestCycleKey,
    SenkaRewardCategory.oneTime => 'once',
    _ => '',
  };
  // Version-1 archives recorded IDs without receipt keys. Their cycle metadata
  // establishes ownership, so repeated responses must not replay those gains.
  final recordedBeforeUpgrade =
      item != null &&
      currentCycle == cycle &&
      state.recordedQuestIds.contains(id);
  final duplicate =
      state.recordedRewardKeys.contains(key) || recordedBeforeUpgrade;
  final keys = Set<String>.of(state.recordedRewardKeys)..add(key);
  var next = state.copyWith(recordedRewardKeys: keys);
  if (item != null && currentCycle == cycle) {
    next = next.copyWith(
      questStatuses: Map<int, SenkaRewardStatus>.of(next.questStatuses)
        ..[id] = SenkaRewardStatus.completed,
      recordedQuestIds: Set<int>.of(next.recordedQuestIds)..add(id),
    );
  }
  if (duplicate) return next;

  var amount = 0.0;
  if (data.containsKey('api_bounus') || data.containsKey('api_bounus_count')) {
    final bonuses = data['api_bounus'];
    if (bonuses is List) {
      for (final bonus in bonuses) {
        if (bonus is Map && _int(bonus['api_type']) == 18) {
          final sum = amount + _amount(bonus['api_count']);
          if (sum.isFinite) amount = sum;
        }
      }
    }
  } else if (item != null && item.category != SenkaRewardCategory.oneTime) {
    // Older capture records can omit the reward payload. Fixed catalog rewards
    // remain recoverable; an optional one-time reward cannot be inferred.
    amount = item.senka.toDouble();
  }
  if (amount == 0) return next;

  final targetMonth = _questTargetMonth(event.capturedAt);
  if (item?.category == SenkaRewardCategory.quarterly &&
      cycle != senkaQuarterlyCycleKey(targetMonth)) {
    // The old quarter's points expire at 14:00 on its final calendar day,
    // although non-senka rewards can still be claimed until 04:59 next day.
    return next;
  }
  return recordGain(
    next,
    event.capturedAt,
    quest: amount,
    targetMonthKey: targetMonth,
  );
}

SenkaState _eoResult(
  SenkaState state,
  CapturedApiEvent event,
  Map<Object?, Object?> data,
  double amount,
  SenkaRewardRecorder recordGain,
) {
  final at = event.capturedAt.toUtc();
  final month = _calendarMonth(at);
  // A delayed receipt still identifies its actual award month even after a
  // newer map snapshot has advanced the observed gauge cycle. Route its gain
  // to that archive without moving the current observation cycle backwards.
  final current = _eoCycle(state, month) ?? state;
  final eventKey = 'eo-result:${event.path}:${at.toIso8601String()}:$amount';
  if (current.recordedRewardKeys.contains(eventKey)) return current;
  var next = current.copyWith(
    recordedRewardKeys: Set<String>.of(current.recordedRewardKeys)
      ..add(eventKey),
    latestEoEventAt: _later(current.latestEoEventAt, at),
  );
  final active = current.activeSortie;
  final context = active != null && !active.startedAt.isAfter(at)
      ? active
      : null;
  final area = event.path == _mapNextPath
      ? _int(data['api_maparea_id'], context?.areaId ?? 0)
      : context?.areaId ?? 0;
  final map = event.path == _mapNextPath
      ? _int(data['api_mapinfo_no'], context?.mapNo ?? 0)
      : context?.mapNo ?? 0;
  if (area > 0 && map > 0) {
    return _creditEo(next, area * 10 + map, amount, at, recordGain);
  }
  // A result captured after a reload may lack the active sortie. Keep its
  // actual award time until mapinfo can associate the completed map. Retain
  // invalid-window receipts too: otherwise an unchanged old cleared flag can
  // be mistaken for a reward in the new month after midnight.
  final receipts = _pendingReceipts(next)
    ..add(SenkaEoReceipt(at: at, amount: amount));
  next = _withPendingReceipts(next, receipts);
  return next;
}

SenkaState _mapInfo(
  SenkaState state,
  DateTime capturedAt,
  Map<Object?, Object?> data,
  SenkaRewardRecorder recordGain,
) {
  final values = data['api_map_info'];
  if (values is! List) return state;
  final known = <int>{};
  final cleared = <int>{};
  for (final value in values) {
    if (value is! Map) continue;
    final id = _int(value['api_id']);
    if (senkaEoById(id) == null) continue;
    known.add(id);
    if (_int(value['api_cleared']) > 0) cleared.add(id);
  }
  if (known.isEmpty) return state;
  final at = capturedAt.toUtc();
  if (state.latestEoEventAt != null && at.isBefore(state.latestEoEventAt!)) {
    return state;
  }
  final month = _calendarMonth(at);
  final cycled = _eoCycle(state, month);
  if (cycled == null) return state;
  SenkaState next = cycled;
  final initialized = next.initializedEoMonths.contains(month);
  next = next.copyWith(
    recordedRewardKeys: Set<String>.of(next.recordedRewardKeys)
      ..addAll(
        known.difference(cleared).map((id) => 'eo-reset-seen:$month:$id'),
      ),
  );
  var eligibleCleared = _eligibleCleared(next, month, cleared);
  var newlyCleared = eligibleCleared.difference(next.observedEoIds);
  final remaining = <SenkaEoReceipt>[];
  final assigned = <String>{};
  for (final receiptValue in _pendingReceipts(next)) {
    final pendingAt = receiptValue.at;
    final pending = receiptValue.amount;
    final receiptMonth = _calendarMonth(pendingAt);
    final candidates =
        cleared.where((id) => !assigned.contains('$receiptMonth:$id')).toList()
          ..sort((left, right) {
            // Exact API amounts match the catalogue in ordinary operation. If an
            // unfamiliar amount is captured, preserve it rather than substitute a
            // fixed catalogue reward; mapinfo still supplies the completed IDs.
            final leftDistance = (senkaEoById(left)!.senka - pending).abs();
            final rightDistance = (senkaEoById(right)!.senka - pending).abs();
            final distance = leftDistance.compareTo(rightDistance);
            return distance != 0 ? distance : left.compareTo(right);
          });
    if (receiptMonth == month && candidates.isNotEmpty) {
      final id = candidates.first;
      assigned.add('$receiptMonth:$id');
      next = _creditEo(next, id, pending, pendingAt, recordGain);
    } else if (receiptMonth != month) {
      final matching = cleared
          .where((id) => senkaEoById(id)!.senka == pending)
          .toSet();
      final key = matching.length == 1
          ? 'eo:$receiptMonth:${matching.single}'
          : null;
      if (!_eoInvalidAt(pendingAt) &&
          (key == null || !next.recordedRewardKeys.contains(key))) {
        next = recordGain(
          next,
          pendingAt,
          eo: pending,
          targetMonthKey: receiptMonth,
        );
      }
      next = next.copyWith(
        recordedRewardKeys: Set<String>.of(next.recordedRewardKeys)
          ..addAll([?key, for (final id in matching) 'eo-stale:$month:$id']),
      );
    } else {
      remaining.add(receiptValue);
    }
    eligibleCleared = _eligibleCleared(next, month, cleared);
    newlyCleared = eligibleCleared.difference(next.observedEoIds);
  }
  next = _withPendingReceipts(next, remaining);
  for (final id in newlyCleared) {
    final key = 'eo:$month:$id';
    if (next.recordedRewardKeys.contains(key)) continue;
    next = _creditEo(
      next,
      id,
      senkaEoById(id)!.senka.toDouble(),
      at,
      recordGain,
      unattributed: !initialized,
    );
  }
  final observed = Set<int>.of(next.observedEoIds)..addAll(eligibleCleared);
  final statuses = Map<int, SenkaRewardStatus>.of(next.eoStatuses);
  if (next.monthKey == month) {
    for (final id in eligibleCleared) {
      statuses[id] = SenkaRewardStatus.completed;
    }
  }
  return next.copyWith(
    observedEoIds: observed,
    eoStatuses: statuses,
    initializedEoMonths: Set<String>.of(next.initializedEoMonths)..add(month),
    eoTrackingInitialized: true,
    latestEoEventAt: _later(next.latestEoEventAt, at),
  );
}

List<SenkaEoReceipt> _pendingReceipts(SenkaState state) =>
    state.pendingEoReceipts.isNotEmpty
    ? state.pendingEoReceipts.toList()
    : state.pendingEoReward > 0 && state.pendingEoRewardAt != null
    ? [
        SenkaEoReceipt(
          at: state.pendingEoRewardAt!,
          amount: state.pendingEoReward,
        ),
      ]
    : <SenkaEoReceipt>[];

SenkaState _withPendingReceipts(
  SenkaState state,
  List<SenkaEoReceipt> receipts,
) => receipts.isEmpty
    ? state.copyWith(clearPendingEoReward: true)
    : state.copyWith(
        pendingEoReceipts: receipts,
        pendingEoReward: finiteSenkaSum(
          receipts.map((receipt) => receipt.amount),
        ),
        pendingEoRewardAt: receipts.first.at,
      );

Set<int> _eligibleCleared(SenkaState state, String month, Set<int> cleared) => {
  for (final id in cleared)
    if (!state.recordedRewardKeys.contains('eo-stale:$month:$id') ||
        state.recordedRewardKeys.contains('eo-reset-seen:$month:$id'))
      id,
};

SenkaState _creditEo(
  SenkaState state,
  int id,
  double amount,
  DateTime at,
  SenkaRewardRecorder recordGain, {
  bool unattributed = false,
}) {
  final month = _calendarMonth(at);
  final key = 'eo:$month:$id';
  final observedCycle = state.eoCycleMonthKey.isEmpty
      ? state.monthKey
      : state.eoCycleMonthKey;
  final currentCycle = month == observedCycle;
  final archived = state.monthArchives[month];
  final previouslyObserved = currentCycle
      ? state.initializedEoMonths.contains(month) &&
            state.observedEoIds.contains(id)
      : archived != null &&
            (archived.observedEoIds.contains(id) ||
                (archived.eoTrackingInitialized &&
                    archived.completedEoIds.contains(id)));
  final duplicate =
      state.recordedRewardKeys.contains(key) || previouslyObserved;
  var next = state.copyWith(
    recordedRewardKeys: Set<String>.of(state.recordedRewardKeys)
      ..add(key)
      ..addAll(
        currentCycle
            ? (_eoInvalidAt(at)
                  ? const <String>[]
                  : ['eo-reset-seen:$month:$id'])
            : ['eo-stale:$observedCycle:$id'],
      ),
    observedEoIds: currentCycle
        ? (Set<int>.of(state.observedEoIds)..add(id))
        : state.observedEoIds,
  );
  if (duplicate || _eoInvalidAt(at)) return next;
  next = recordGain(
    next,
    at,
    eo: amount,
    targetMonthKey: month,
    unattributed: unattributed,
  );
  if (next.monthKey == month) {
    next = next.copyWith(
      eoStatuses: Map<int, SenkaRewardStatus>.of(next.eoStatuses)
        ..[id] = SenkaRewardStatus.completed,
    );
  }
  return next;
}

SenkaState? _eoCycle(SenkaState state, String month) {
  final stored = state.eoCycleMonthKey.isNotEmpty
      ? state.eoCycleMonthKey
      : state.monthKey;
  if (month.compareTo(stored) < 0) return null;
  if (stored != month) {
    return state.copyWith(
      eoCycleMonthKey: month,
      observedEoIds: const {},
      eoTrackingInitialized: state.initializedEoMonths.contains(month),
      recordedRewardKeys: Set<String>.of(state.recordedRewardKeys)
        ..addAll([
          for (final id in state.observedEoIds) 'eo-stale:$month:$id',
          if (state.eoCycleMonthKey.isEmpty)
            for (final id in state.completedEoIds) 'eo-stale:$month:$id',
        ]),
    );
  }
  if (state.eoCycleMonthKey.isNotEmpty) return state;
  return state.copyWith(
    eoCycleMonthKey: month,
    observedEoIds: Set<int>.of(state.observedEoIds)
      ..addAll(state.completedEoIds),
    initializedEoMonths: Set<String>.of(state.initializedEoMonths)
      ..addAll(state.eoTrackingInitialized ? {month} : const <String>{}),
  );
}

String _questTargetMonth(DateTime at) {
  final jst = toJst(at);
  final end = DateTime.utc(jst.year, jst.month + 1, 0).day;
  return _monthKey(
    jst.day == end && jst.hour >= 14
        ? DateTime.utc(jst.year, jst.month + 1)
        : jst,
  );
}

String _calendarMonth(DateTime at) => _monthKey(toJst(at));
String _monthKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
bool _eoInvalidAt(DateTime at) {
  final jst = toJst(at);
  return jst.day == DateTime.utc(jst.year, jst.month + 1, 0).day &&
      jst.hour >= 22;
}

DateTime _later(DateTime? previous, DateTime at) =>
    previous != null && previous.isAfter(at) ? previous : at;
int _int(Object? value, [int fallback = 0]) {
  if (value is num && value.isFinite) return value.toInt();
  return int.tryParse('$value') ?? fallback;
}

double _amount(Object? value) {
  final amount = value is num ? value.toDouble() : double.tryParse('$value');
  return amount != null && amount.isFinite && amount > 0 ? amount : 0;
}

const _questPath = '/kcsapi/api_req_quest/clearitemget';
const _mapInfoPath = '/kcsapi/api_get_member/mapinfo';
const _mapNextPath = '/kcsapi/api_req_map/next';
const _rewardPaths = {
  _questPath,
  _mapInfoPath,
  _mapNextPath,
  '/kcsapi/api_req_sortie/battleresult',
  '/kcsapi/api_req_combined_battle/battleresult',
};
