import 'dart:async';

import 'package:flutter/foundation.dart';

import '../account/account_session.dart';
import '../bridge/captured_api_event.dart';
import '../game_state/game_api_event_pipeline.dart';
import '../performance/frame_notification_coalescer.dart';
import 'senka_calculation.dart';
import 'senka_catalog.dart';
import 'senka_ledger.dart';
import 'senka_reducer.dart';
import 'senka_state.dart';
import 'senka_store.dart';

class SenkaController extends ChangeNotifier implements GameApiEventConsumer {
  SenkaController({
    required this.store,
    this._reducer = const SenkaReducer(),
    DateTime Function()? now,
    FrameNotificationCoalescer? captureNotifications,
    AccountSession? accountSession,
  }) : _now = now ?? DateTime.now,
       _accountSession =
           accountSession ??
           (store is AccountSenkaStore ? AccountSession.shared : null),
       _captureNotifications =
           captureNotifications ?? FrameNotificationCoalescer(),
       _state = SenkaState.forMonth(
         currentSenkaMonthKey((now ?? DateTime.now)()),
       ) {
    _accountSession?.addListener(_onAccountChanged);
  }

  final SenkaStore store;
  final SenkaReducer _reducer;
  final FrameNotificationCoalescer _captureNotifications;
  final DateTime Function() _now;
  final AccountSession? _accountSession;
  AccountScope? _accountScope;
  SenkaState _state;
  Future<void> _queue = Future<void>.value();
  int _revision = 0;
  final Map<int, ({int revision, SenkaState state})> _pendingAccountSaves = {};
  final Map<int, _SenkaRestoration> _accountRestorations = {};
  final Map<int, _SenkaRestoration> _archiveMaintenances = {};
  _SenkaRestoration? _standaloneRestoration;
  bool _disposed = false;
  Object? _persistenceError;

  SenkaState get state => _state;
  double get monthBaseSenka => _state.monthExperienceSenka;
  bool get hasPersistenceError => _persistenceError != null;
  @override
  Future<void> get idle async {
    // A queued operation may schedule a retry after a failed load. Drain that
    // work too, so callers observe the restored and persisted final state.
    while (true) {
      final current = _queue;
      await current;
      if (identical(current, _queue)) return;
    }
  }

  @override
  bool supportsPath(String path) => _reducer.supportsPath(path);

  Future<void> initialize() async {
    if (_disposed) return;
    if (_accountSession != null) {
      _onAccountChanged();
      final restoration = _activeRestoration;
      if (restoration != null) _scheduleRestoration(restoration);
      await idle;
      return;
    }
    final restoration = _standaloneRestoration ??= _SenkaRestoration(
      memberId: null,
      preview: _state,
    );
    _scheduleRestoration(restoration);
    await idle;
  }

  /// Called after a backup transaction commits or rolls back while capture is
  /// paused. Discard pre-restore memory so it cannot overwrite the restored raw.
  Future<void> reloadForAccount(int memberId) async {
    await idle;
    if (_disposed ||
        (_accountSession != null &&
            _accountSession.current.memberId != memberId)) {
      return;
    }
    _pendingAccountSaves.remove(memberId);
    _accountRestorations.remove(memberId)?.completeSettings(false);
    if (_accountSession != null) {
      _accountScope = null;
      _onAccountChanged();
      await idle;
    } else {
      _standaloneRestoration = null;
      await initialize();
    }
    if (hasPersistenceError) {
      throw StateError('Could not reload restored senka archive');
    }
  }

  bool isArchiveRestoreActive(int memberId) =>
      _archiveMaintenances.containsKey(memberId);

  /// Freeze intentions before draining accepted writes. Timer refreshes and
  /// user edits stay as patches until the imported archive has been reloaded.
  Future<void> beginArchiveRestore(int memberId) async {
    if (_disposed || memberId <= 0) return;
    if (isArchiveRestoreActive(memberId)) {
      throw StateError('Senka archive restore is already active');
    }
    _archiveMaintenances[memberId] = _SenkaRestoration(
      memberId: memberId,
      preview: _state,
    );
    await idle;
  }

  Future<void> endArchiveRestore(int memberId) async {
    final maintenance = _archiveMaintenances[memberId];
    if (maintenance == null) return;
    await idle;
    if (_disposed || maintenance.patches.isEmpty) {
      _archiveMaintenances.remove(memberId);
      maintenance.completeSettings(!_disposed);
      return;
    }
    // Always reload the durable base: the visible preview already includes
    // these intentions, including when an old v1 restore leaves senka alone.
    final archive = store is AccountSenkaStore
        ? await (store as AccountSenkaStore).loadForAccount(memberId)
        : await store.load();
    if (_disposed) {
      _archiveMaintenances.remove(memberId);
      maintenance.completeSettings(false);
      return;
    }
    final instant = _now();
    final fallback = maintenance.initial.memberId == memberId
        ? maintenance.initial
        : SenkaState.forMonth(
            currentSenkaMonthKey(instant),
          ).copyWith(memberId: memberId);
    final current = migrateSenkaExperienceTracking(
      migrateSenkaStateToMonth(
        archive ?? fallback,
        currentSenkaMonthKey(instant),
      ),
    );
    final rewards = migrateSenkaRewardCycles(current, instant);
    var merged = identical(rewards, current)
        ? ensureSenkaDailyTarget(current, instant)
        : rebaseSenkaDailyTarget(current, rewards, instant);
    for (final patch in maintenance.patches) {
      merged = patch(merged);
    }
    _archiveMaintenances.remove(memberId);
    final snapshot = merged;
    final revision = ++_revision;
    _rememberAccountSave(snapshot, revision);
    final visible =
        _accountSession == null || _accountSession.current.memberId == memberId;
    if (visible) {
      _state = snapshot;
      notifyListeners();
    }
    _enqueue(() async {
      try {
        maintenance.completeSettings(await _saveIfCurrent(snapshot, revision));
      } catch (_) {
        maintenance.completeSettings(false);
      }
    });
    await idle;
  }

  _SenkaRestoration? get _activeMaintenance =>
      _archiveMaintenances[_accountSession?.current.memberId ??
          _state.memberId];

  @override
  void accept(CapturedApiEvent event) {
    if (_disposed) return;
    final scope = _accountSession?.current;
    if (scope != null && !scope.isKnown) return;
    _enqueue(() async {
      if (_disposed || (scope != null && !_accountSession!.isCurrent(scope))) {
        return;
      }
      SenkaState patch(SenkaState state) => _reducer.reduce(state, event);
      final next = patch(_state);
      if (identical(next, _state)) return;
      final maintenance = _activeMaintenance;
      if (maintenance != null) {
        maintenance.patches.add(patch);
        _state = next;
        _revision++;
        _captureNotifications.schedule(notifyListeners);
        return;
      }
      final restoration = _activeRestoration;
      if (restoration != null) {
        restoration.patches.add(patch);
        restoration.preview = next;
        _state = next;
        _revision++;
        _captureNotifications.schedule(notifyListeners);
        _scheduleRestoration(restoration);
        return;
      }
      _state = next;
      final revision = ++_revision;
      _rememberAccountSave(next, revision);
      _captureNotifications.schedule(notifyListeners);
      await _saveIfCurrent(next, revision);
    });
  }

  void _onAccountChanged() {
    if (_disposed) return;
    final scope = _accountSession!.current;
    if (identical(scope, _accountScope)) return;
    _accountScope = scope;
    final empty = SenkaState.forMonth(
      currentSenkaMonthKey(_now()),
    ).copyWith(memberId: scope.memberId);
    final restoration = scope.isKnown
        ? _accountRestorations.putIfAbsent(
            scope.memberId,
            () => _SenkaRestoration(memberId: scope.memberId, preview: empty),
          )
        : null;
    _state = restoration?.preview ?? empty;
    _revision++;
    _persistenceError = null;
    notifyListeners();
    if (restoration != null) _scheduleRestoration(restoration);
  }

  _SenkaRestoration? get _activeRestoration => _accountSession == null
      ? _standaloneRestoration
      : _accountRestorations[_accountSession.current.memberId];

  void _scheduleRestoration(_SenkaRestoration restoration) {
    if (_disposed || restoration.scheduled) return;
    restoration.scheduled = true;
    _enqueue(() => _restore(restoration));
  }

  Future<void> _restore(_SenkaRestoration restoration) async {
    if (_disposed) return;
    final owner = restoration.memberId;
    try {
      final pending = _pendingAccountSaves[owner]?.state;
      final archive =
          pending ??
          (owner != null && store is AccountSenkaStore
              ? await (store as AccountSenkaStore).loadForAccount(owner)
              : await store.load());
      if (_disposed) return;
      final loaded = owner == null || archive?.memberId == owner
          ? archive
          : null;
      final instant = _now();
      final current = migrateSenkaExperienceTracking(
        migrateSenkaStateToMonth(
          loaded ?? restoration.initial,
          currentSenkaMonthKey(instant),
        ),
      );
      final rewards = migrateSenkaRewardCycles(current, instant);
      var merged = identical(rewards, current)
          ? ensureSenkaDailyTarget(current, instant)
          : rebaseSenkaDailyTarget(current, rewards, instant);
      // Apply intentions to the loaded archive, never a snapshot of the empty
      // account shell shown while its asynchronous load was in progress.
      for (final patch in restoration.patches) {
        merged = patch(merged);
      }
      final visible = identical(_activeRestoration, restoration);
      if (owner == null) {
        _standaloneRestoration = null;
      } else {
        _accountRestorations.remove(owner);
      }
      final revision = ++_revision;
      final needsSave =
          restoration.patches.isNotEmpty ||
          pending != null ||
          (owner == null && loaded != null && !identical(merged, loaded));
      if (needsSave) _rememberAccountSave(merged, revision);
      if (visible) {
        _state = merged;
        _persistenceError = null;
        notifyListeners();
      }
      final saved = !needsSave || await _saveIfCurrent(merged, revision);
      restoration.completeSettings(saved);
    } catch (error) {
      if (!_disposed && identical(_activeRestoration, restoration)) {
        _persistenceError = error;
        notifyListeners();
      }
      restoration.completeSettings(false);
      debugPrint('Senka persistence restore failed: $error');
    } finally {
      restoration.scheduled = false;
    }
  }

  void cycleEoReward(int id) {
    if (senkaEoById(id) == null || _disposed) return;
    final instant = _now();
    _replace((state) {
      final values = Map<int, SenkaRewardStatus>.of(state.eoStatuses);
      values[id] = (values[id] ?? SenkaRewardStatus.deferred).next;
      final next = state.copyWith(eoStatuses: values);
      return rebaseSenkaDailyTarget(state, next, instant);
    });
  }

  void cycleQuestReward(int id) {
    if (senkaQuestById(id) == null || _disposed) return;
    final instant = _now();
    _replace((state) {
      final values = Map<int, SenkaRewardStatus>.of(state.questStatuses);
      values[id] = (values[id] ?? SenkaRewardStatus.deferred).next;
      final next = state.copyWith(questStatuses: values);
      return rebaseSenkaDailyTarget(state, next, instant);
    });
  }

  void toggleEo(int id) => cycleEoReward(id);

  void toggleQuest(int id) => cycleQuestReward(id);

  void setCurrentSenka(double value) {
    if (!value.isFinite || _disposed) return;
    final normalized = value < 0 ? 0.0 : value;
    if (_activeMaintenance == null &&
        _activeRestoration == null &&
        _state.calculatorCurrentSenka == normalized) {
      return;
    }
    final instant = _now();
    _replace((state) {
      final next = state.copyWith(
        calculatorCurrentSenka: normalized,
        calculatorLocalSenkaAtSet: state.monthRecorded,
      );
      return rebaseSenkaDailyTarget(state, next, instant);
    });
  }

  void setTargetSenka(double value) {
    if (!value.isFinite || _disposed) return;
    final normalized = value < 0 ? 0.0 : value;
    if (_activeMaintenance == null &&
        _activeRestoration == null &&
        _state.targetSenka == normalized) {
      return;
    }
    _replace((state) => state.copyWith(targetSenka: normalized));
  }

  Future<bool> resetBaseSenka() => setBaseSenka(0);

  Future<bool> setBaseSenka(double value) async {
    if (!value.isFinite || value < 0 || _disposed) return false;
    final scaled = value * 100;
    if (!scaled.isFinite) return false;
    final normalized = scaled.roundToDouble() / 100;
    if (!normalized.isFinite) return false;
    final instant = _now();
    return _replaceForSettings((state) {
      final current = migrateSenkaStateToMonth(
        state,
        currentSenkaMonthKey(instant),
      );
      final updated = replaceSenkaBaseExperience(current, normalized, instant);
      final rebased = _rebaseLatestPlayerRanking(updated);
      return rebaseSenkaDailyTarget(state, rebased, instant);
    });
  }

  void refreshForCurrentTime() {
    if (_disposed) return;
    final now = _now();
    SenkaState refresh(SenkaState state) {
      final monthMigrated = migrateSenkaStateToMonth(
        state,
        currentSenkaMonthKey(now),
      );
      final rewardMigrated = migrateSenkaRewardCycles(monthMigrated, now);
      return identical(rewardMigrated, monthMigrated)
          ? ensureSenkaDailyTarget(monthMigrated, now)
          : rebaseSenkaDailyTarget(monthMigrated, rewardMigrated, now);
    }

    if (_activeMaintenance == null &&
        _activeRestoration == null &&
        identical(refresh(_state), _state)) {
      notifyListeners();
      return;
    }
    _replace(refresh);
  }

  void toggleSortieFavorite(String mapKey) {
    if (!_canToggleSortieMap(mapKey)) return;
    _replace((state) {
      if (!state.sortieStats.containsKey(mapKey)) return state;
      final values = Set<String>.of(state.favoriteSortieMapKeys);
      values.contains(mapKey) ? values.remove(mapKey) : values.add(mapKey);
      return state.copyWith(favoriteSortieMapKeys: values);
    });
  }

  void toggleSortieHidden(String mapKey) {
    if (!_canToggleSortieMap(mapKey)) return;
    _replace((state) {
      if (!state.sortieStats.containsKey(mapKey)) return state;
      final values = Set<String>.of(state.hiddenSortieMapKeys);
      values.contains(mapKey) ? values.remove(mapKey) : values.add(mapKey);
      return state.copyWith(hiddenSortieMapKeys: values);
    });
  }

  bool _canToggleSortieMap(String mapKey) =>
      !_disposed &&
      RegExp(r'^[1-9]\d*-[1-9]\d*$').hasMatch(mapKey) &&
      (_activeMaintenance != null ||
          _activeRestoration != null ||
          _state.sortieStats.containsKey(mapKey));

  void _replace(SenkaState Function(SenkaState) patch) {
    if (_disposed ||
        (_accountSession != null && !_accountSession.current.isKnown)) {
      return;
    }
    final next = patch(_state);
    final maintenance = _activeMaintenance;
    if (maintenance != null) {
      maintenance.patches.add(patch);
      _state = next;
      _revision++;
      notifyListeners();
      return;
    }
    final restoration = _activeRestoration;
    if (restoration != null) {
      restoration.patches.add(patch);
      restoration.preview = next;
      _state = next;
      _revision++;
      notifyListeners();
      _scheduleRestoration(restoration);
      return;
    }
    _state = next;
    final revision = ++_revision;
    _rememberAccountSave(next, revision);
    notifyListeners();
    _enqueue(() async {
      await _saveIfCurrent(next, revision);
    });
  }

  Future<bool> _replaceForSettings(SenkaState Function(SenkaState) patch) {
    if (_disposed ||
        (_accountSession != null && !_accountSession.current.isKnown)) {
      return Future<bool>.value(false);
    }
    final restoration = _activeMaintenance ?? _activeRestoration;
    if (restoration != null) {
      final result = Completer<bool>();
      restoration.settings.add(result);
      _replace(patch);
      return result.future;
    }
    final next = patch(_state);
    _state = next;
    final revision = ++_revision;
    _rememberAccountSave(next, revision);
    notifyListeners();
    final result = Completer<bool>();
    _enqueue(() async {
      if (_disposed) {
        if (!result.isCompleted) result.complete(false);
        return;
      }
      try {
        final saved = await _saveIfCurrent(next, revision);
        if (!result.isCompleted) result.complete(saved);
      } catch (_) {
        if (!result.isCompleted) result.complete(false);
      }
    });
    return result.future;
  }

  void _enqueue(Future<void> Function() operation) {
    final scheduled = _queue.then<void>(
      (_) => operation(),
      onError: (Object _, StackTrace _) => operation(),
    );
    _queue = scheduled.then<void>(
      (_) {},
      onError: (Object error, StackTrace _) {
        debugPrint('Senka persistence failed: $error');
      },
    );
  }

  void _rememberAccountSave(SenkaState snapshot, int revision) {
    if (_accountSession == null || snapshot.memberId <= 0) return;
    _pendingAccountSaves[snapshot.memberId] = (
      revision: revision,
      state: snapshot,
    );
  }

  Future<bool> _saveIfCurrent(SenkaState snapshot, int revision) async {
    // A switch changes the UI revision, but cannot revoke a save already
    // accepted for another owner. Only a newer save for that owner supersedes it.
    final latest = _accountSession == null
        ? _revision
        : _pendingAccountSaves[snapshot.memberId]?.revision;
    if (revision != latest) return false;
    try {
      await store.save(snapshot);
      if (_pendingAccountSaves[snapshot.memberId]?.revision == revision) {
        _pendingAccountSaves.remove(snapshot.memberId);
      }
      if (_isVisibleSave(snapshot, revision) && _persistenceError != null) {
        _persistenceError = null;
        if (!_disposed) notifyListeners();
      }
      return true;
    } catch (error, stackTrace) {
      if (_isVisibleSave(snapshot, revision)) {
        _persistenceError = error;
        if (!_disposed) notifyListeners();
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  bool _isVisibleSave(SenkaState snapshot, int revision) =>
      revision == _revision &&
      (_accountSession == null ||
          _accountSession.current.memberId == snapshot.memberId);

  @override
  void dispose() {
    _disposed = true;
    _standaloneRestoration?.completeSettings(false);
    for (final restoration in _accountRestorations.values) {
      restoration.completeSettings(false);
    }
    for (final maintenance in _archiveMaintenances.values) {
      maintenance.completeSettings(false);
    }
    _accountSession?.removeListener(_onAccountChanged);
    _captureNotifications.dispose();
    super.dispose();
  }
}

class _SenkaRestoration {
  _SenkaRestoration({required this.memberId, required this.preview})
    : initial = preview;

  final int? memberId;
  final SenkaState initial;
  SenkaState preview;
  bool scheduled = false;
  final patches = <SenkaState Function(SenkaState)>[];
  final settings = <Completer<bool>>[];

  void completeSettings(bool success) {
    for (final result in settings) {
      if (!result.isCompleted) result.complete(success);
    }
    settings.clear();
  }
}

SenkaState _rebaseLatestPlayerRanking(SenkaState state) {
  final playerHistory = state.rankingHistory['player'];
  if (playerHistory == null || playerHistory.isEmpty) {
    return state.copyWith(calculatorLocalSenkaAtSet: state.monthRecorded);
  }
  final latest = playerHistory.last;
  final rankingHistory = <String, List<SenkaRankingSnapshot>>{
    for (final entry in state.rankingHistory.entries)
      entry.key: List<SenkaRankingSnapshot>.of(entry.value),
  };
  rankingHistory['player'] = <SenkaRankingSnapshot>[
    ...playerHistory.take(playerHistory.length - 1),
    SenkaRankingSnapshot(
      rank: latest.rank,
      senka: latest.senka,
      capturedAt: latest.capturedAt,
      localSenkaAtCapture: state.monthRecorded,
      settlementCutoff: latest.settlementCutoff,
    ),
  ];
  return state.copyWith(
    rankingHistory: rankingHistory,
    calculatorLocalSenkaAtSet: state.monthRecorded,
  );
}
