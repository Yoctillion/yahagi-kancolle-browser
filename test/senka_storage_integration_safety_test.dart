import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_controller.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_ledger.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_reducer.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_state.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_store.dart';
import 'package:yahagi_kancolle_browser/src/account/account_session.dart';

import 'fixtures/kcsapi_fixtures.dart';

DateTime _jst(int month, int day, int hour, [int minute = 0]) => DateTime.utc(
  2026,
  month,
  day,
  hour,
  minute,
).subtract(const Duration(hours: 9));

SenkaState _roundTrip(SenkaState state) =>
    SenkaState.fromJson(jsonDecode(jsonEncode(state.toJson())));

SenkaState _port(SenkaState state, int experience, DateTime at) =>
    const SenkaReducer().reduce(
      state,
      kcsapiEvent('/kcsapi/api_port/port', {
        'api_basic': {
          'api_member_id': 1001,
          'api_nickname': 'owner',
          'api_experience': experience,
        },
      }, capturedAt: at),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'finishing an old owner restore cannot replace a newly selected owner',
    () async {
      final session = AccountSession(initialMemberId: 1001);
      final store = _OwnerSwitchStore();
      final controller = SenkaController(
        store: store,
        accountSession: session,
        now: () => _jst(8, 10, 12),
      );
      addTearDown(() {
        controller.dispose();
        session.dispose();
      });
      await controller.initialize();
      await controller.beginArchiveRestore(1001);
      controller.setTargetSenka(3200);
      store.gate = true;
      final ending = controller.endArchiveRestore(1001);
      await store.started.future;
      session.selectMember(2002);
      await controller.idle;
      expect(controller.state.targetSenka, 5000);
      store.release.complete();
      await ending;
      expect(controller.state.memberId, 2002);
      expect(controller.state.targetSenka, 5000);
      expect(store.archives[1001]!.targetSenka, 3200);
    },
  );

  test(
    'version-1 data stays intact in an archived month and future rewards survive reset',
    () {
      final legacy = SenkaState.fromJson({
        'monthKey': '2026-08',
        'memberId': 1001,
        'experienceTrackingVersion': 1,
        'latestExperience': 100000,
        'days': {
          '2026-08-10': {'experience': 70, 'eo': 75},
        },
        'targetSenka': 3000,
        'rankingHistory': {
          'player': [
            {
              'rank': 500,
              'senka': 1000,
              'capturedAt': _jst(8, 10, 15).toIso8601String(),
              'localSenkaAtCapture': 145,
            },
          ],
        },
      });
      var state = recordSenkaReward(
        legacy,
        _jst(8, 31, 14),
        quest: 480,
        targetMonthKey: '2026-09',
      );
      state = replaceSenkaBaseExperience(state, 12.34, _jst(8, 31, 16));
      state = _roundTrip(migrateSenkaStateToMonth(state, '2026-09'));
      expect(state.monthRecorded, 480);
      final august = state.monthArchives['2026-08']!;
      expect(august.monthExperienceSenka, 12.34);
      expect(august.day(DateTime.utc(2026, 8, 10)).eo, 75);
      expect(august.rankingHistory['player'], hasLength(1));
      expect(august.targetSenka, 3000);
    },
  );

  test('an ongoing sortie survives a month migration and JSON reload', () {
    var state = _port(SenkaState.forMonth('2026-08'), 100000, _jst(8, 31, 21));
    state = const SenkaReducer().reduce(
      state,
      kcsapiEvent('/kcsapi/api_req_map/start', {
        'api_maparea_id': 1,
        'api_mapinfo_no': 5,
        'api_no': 1,
        'api_bosscell_no': 4,
      }, capturedAt: _jst(8, 31, 21, 59)),
    );
    expect(state.activeSortie, isNotNull);
    state = migrateSenkaStateToMonth(state, '2026-09');
    expect(state.activeSortie, isNotNull);
    final restored = _roundTrip(state);
    expect(restored.activeSortie, isNotNull);
    expect(restored.activeSortie!.mapKey, '1-5');
  });

  test(
    'a late port snapshot corrects XP periods without rewinding sortie state',
    () {
      var state = _port(
        SenkaState.forMonth('2026-08'),
        100000,
        _jst(8, 10, 12),
      );
      state = _port(state, 110000, _jst(8, 10, 16));
      state = _port(_roundTrip(state), 105000, _jst(8, 10, 13));
      final before = senkaSettlementPeriodStart(
        _jst(8, 10, 13),
      ).toIso8601String();
      final after = senkaSettlementPeriodStart(
        _jst(8, 10, 16),
      ).toIso8601String();
      expect(state.monthExperienceSenka, 7);
      expect(state.settlementPeriods[before]?.experience, closeTo(3.5, 1e-9));
      expect(state.settlementPeriods[after]?.experience, closeTo(3.5, 1e-9));
      expect(state.latestSortieEventAt, _jst(8, 10, 16));
    },
  );

  test('late pre-sortie XP is not reduced by a later pending sortie gain', () {
    var state = _port(SenkaState.forMonth('2026-08'), 100000, _jst(8, 10, 12));
    state = const SenkaReducer().reduce(
      state,
      kcsapiEvent('/kcsapi/api_req_sortie/battleresult', {
        'api_member_exp': 110000,
      }, capturedAt: _jst(8, 10, 13, 59)),
    );
    state = const SenkaReducer().reduce(
      _roundTrip(state),
      kcsapiEvent('/kcsapi/api_get_member/basic', {
        'api_member_id': 1001,
        'api_experience': 105000,
      }, capturedAt: _jst(8, 10, 13)),
    );
    state = _port(state, 110000, _jst(8, 10, 14, 1));
    final before = senkaSettlementPeriodStart(
      _jst(8, 10, 13),
    ).toIso8601String();
    final after = senkaSettlementPeriodStart(
      _jst(8, 10, 14, 1),
    ).toIso8601String();
    expect(state.monthExperienceSenka, 7);
    expect(state.settlementPeriods[before]?.experience, closeTo(3.5, 1e-9));
    expect(state.settlementPeriods[after]?.experience, closeTo(3.5, 1e-9));
  });

  test(
    'a rejected backup and failed cache reload cannot skip the real backup on retry',
    () async {
      final original = jsonEncode(
        SenkaState.forMonth(
          '2026-08',
        ).copyWith(memberId: 1001, targetSenka: 3000).toJson(),
      );
      final previous = SharedPreferencesStorePlatform.instance;
      final platform = _BackupAndReloadFailurePlatform({
        'flutter.account.1001.senka.archive.v1': original,
      });
      SharedPreferencesStorePlatform.instance = platform;
      SharedPreferences.resetStatic();
      addTearDown(() {
        SharedPreferencesStorePlatform.instance = previous;
        SharedPreferences.resetStatic();
      });
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPreferencesSenkaStore(prefs);
      final next = SenkaState.forMonth(
        '2026-08',
      ).copyWith(memberId: 1001, targetSenka: 3200);
      await expectLater(store.save(next), throwsStateError);
      await store.save(next.copyWith(targetSenka: 3300));
      await prefs.reload();
      expect(
        prefs.getString('account.1001.senka.archive.v1.raw-backup'),
        original,
      );
      expect((await store.loadForAccount(1001))!.targetSenka, 3300);
    },
  );

  test(
    'superseded base requests cannot report a successful save when every write fails',
    () async {
      final controller = SenkaController(
        store: _RejectingStore(),
        now: () => _jst(8, 10, 12),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final results = await Future.wait([
        controller.setBaseSenka(12.34),
        controller.setBaseSenka(56.78),
      ]);
      expect(results, [false, false]);
      expect(controller.hasPersistenceError, isTrue);
    },
  );
}

class _BackupAndReloadFailurePlatform extends InMemorySharedPreferencesStore {
  _BackupAndReloadFailurePlatform(super.data) : super.withData();
  bool rejectBackup = true;
  bool rejectRead = false;
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (rejectBackup) {
      rejectBackup = false;
      rejectRead = true;
      return false;
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<Map<String, Object>> getAll() async {
    if (rejectRead) {
      rejectRead = false;
      throw StateError('cache reload unavailable');
    }
    return super.getAll();
  }
}

class _RejectingStore implements SenkaStore {
  @override
  Future<SenkaState?> load() async => null;
  @override
  Future<void> save(SenkaState state) async =>
      throw StateError('disk unavailable');
}

class _OwnerSwitchStore implements AccountSenkaStore {
  final archives = <int, SenkaState>{
    1001: SenkaState.forMonth(
      '2026-08',
    ).copyWith(memberId: 1001, targetSenka: 3000),
    2002: SenkaState.forMonth(
      '2026-08',
    ).copyWith(memberId: 2002, targetSenka: 5000),
  };
  bool gate = false;
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<SenkaState?> load() => loadForAccount(1001);
  @override
  Future<SenkaState?> loadForAccount(int memberId) async {
    if (gate && memberId == 1001) {
      if (!started.isCompleted) started.complete();
      await release.future;
    }
    return archives[memberId];
  }

  @override
  Future<void> save(SenkaState state) async {
    archives[state.memberId] = state;
  }
}
