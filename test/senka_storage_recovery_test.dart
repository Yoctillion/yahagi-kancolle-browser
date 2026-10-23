import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:yahagi_kancolle_browser/src/account/account_session.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_controller.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_state.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_store.dart';

import 'fixtures/kcsapi_fixtures.dart';

final _now = DateTime.utc(2026, 8, 10);

SenkaState _archive([int owner = 1001]) =>
    SenkaState.forMonth('2026-08').copyWith(
      memberId: owner,
      nickname: 'archived owner',
      targetSenka: 3000,
      days: const {'2026-08-09': SenkaDayRecord(experience: 70, eo: 75)},
      questStatuses: const {949: SenkaRewardStatus.completed},
      rankingHistory: {
        'player': [
          SenkaRankingSnapshot(
            rank: 500,
            senka: 1000,
            capturedAt: _now,
            localSenkaAtCapture: 145,
          ),
        ],
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test(
    'generic delayed restore replays edits onto the complete archive',
    () async {
      final store = _DelayedStore(_archive());
      final controller = SenkaController(store: store, now: () => _now);
      addTearDown(controller.dispose);
      final initialization = controller.initialize();
      await store.started.future;
      controller.setTargetSenka(3200);
      controller.cycleQuestReward(949);
      store.release.complete();
      await initialization;
      await controller.idle;
      expect(controller.state.targetSenka, 3200);
      expect(controller.state.nickname, 'archived owner');
      expect(controller.state.day(DateTime.utc(2026, 8, 9)).experience, 70);
      expect(controller.state.rankingHistory['player'], hasLength(1));
      expect(controller.state.questStatuses[949], SenkaRewardStatus.deferred);
      expect(store.archive!.toJson(), controller.state.toJson());
    },
  );

  test(
    'edit during restore survives switching away before it finishes',
    () async {
      final session = AccountSession(initialMemberId: 1001);
      final store = _DelayedAccountStore(_archive());
      final controller = SenkaController(
        store: store,
        accountSession: session,
        now: () => _now,
      );
      addTearDown(() {
        controller.dispose();
        session.dispose();
      });
      final initialization = controller.initialize();
      await store.started.future;
      controller.setTargetSenka(3200);
      session.selectMember(2002);
      store.release.complete();
      await initialization;
      await controller.idle;
      expect(controller.state.memberId, 2002);
      expect(store.archive!.targetSenka, 3200);
      expect(store.archive!.day(DateTime.utc(2026, 8, 9)).experience, 70);
      expect(store.archive!.rankingHistory['player'], hasLength(1));
      session.selectMember(1001);
      await controller.idle;
      expect(controller.state.targetSenka, 3200);
      expect(controller.state.questStatuses[949], SenkaRewardStatus.completed);
    },
  );

  test('load failure retries the archive before saving an edit', () async {
    final store = _FailingLoadStore(_archive());
    final controller = SenkaController(store: store, now: () => _now);
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.hasPersistenceError, isTrue);
    controller.setTargetSenka(3200);
    await controller.idle;
    expect(controller.hasPersistenceError, isFalse);
    expect(store.archive!.targetSenka, 3200);
    expect(store.archive!.day(DateTime.utc(2026, 8, 9)).experience, 70);
    expect(store.archive!.rankingHistory['player'], hasLength(1));
  });

  test('idle includes restoration retried by a queued API event', () async {
    final store = _FailingLoadStore(_archive());
    final controller = SenkaController(store: store, now: () => _now);
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.accept(
      kcsapiEvent('/kcsapi/api_get_member/basic', {
        'api_member_id': 1001,
        'api_nickname': 'current owner',
        'api_experience': 100000,
      }, capturedAt: _now),
    );
    await controller.idle;
    expect(controller.hasPersistenceError, isFalse);
    expect(controller.state.nickname, 'current owner');
    expect(store.archive!.nickname, 'current owner');
    expect(controller.state.day(DateTime.utc(2026, 8, 9)).experience, 70);
    expect(store.archive!.rankingHistory['player'], hasLength(1));
  });

  test(
    'overflowing finite base is rejected without any state mutation',
    () async {
      final store = _MemoryStore(_archive());
      final controller = SenkaController(store: store, now: () => _now);
      addTearDown(controller.dispose);
      await controller.initialize();
      final before = controller.state.toJson();
      expect(await controller.setBaseSenka(double.maxFinite), isFalse);
      expect(controller.state.toJson(), before);
      expect(() => jsonEncode(controller.state.toJson()), returnsNormally);
    },
  );

  test('rejected native write reports failure and a retry recovers', () async {
    final previous = SharedPreferencesStorePlatform.instance;
    final platform = _RejectOncePlatform();
    SharedPreferencesStorePlatform.instance = platform;
    addTearDown(() {
      SharedPreferencesStorePlatform.instance = previous;
      SharedPreferences.resetStatic();
    });
    final session = AccountSession(initialMemberId: 1001);
    final prefs = await SharedPreferences.getInstance();
    final controller = SenkaController(
      store: SharedPreferencesSenkaStore(prefs, accountSession: session),
      accountSession: session,
      now: () => _now,
    );
    addTearDown(() {
      controller.dispose();
      session.dispose();
    });
    await controller.initialize();
    expect(await controller.setBaseSenka(12.34), isFalse);
    expect(controller.hasPersistenceError, isTrue);
    expect(prefs.getString('account.1001.senka.archive.v1'), isNull);
    expect(await controller.setBaseSenka(12.34), isTrue);
    expect(controller.hasPersistenceError, isFalse);
    await prefs.reload();
    expect(
      SenkaState.fromJson(
        jsonDecode(prefs.getString('account.1001.senka.archive.v1')!),
      ).monthExperienceSenka,
      12.34,
    );
  });

  test(
    'first account raw is backed up once before later saves overwrite it',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_archive().toJson());
      await prefs.setString('account.1001.senka.archive.v1', raw);
      final store = SharedPreferencesSenkaStore(prefs);
      await store.loadForAccount(1001);
      await store.save(_archive().copyWith(targetSenka: 3200));
      await store.save(_archive().copyWith(targetSenka: 3300));
      expect(prefs.getString('account.1001.senka.archive.v1.raw-backup'), raw);
      expect((await store.loadForAccount(1001))!.targetSenka, 3300);
    },
  );
  test(
    'a native exception also rolls back the failed preferences cache',
    () async {
      final previous = SharedPreferencesStorePlatform.instance;
      SharedPreferencesStorePlatform.instance = _ThrowOncePlatform();
      addTearDown(() {
        SharedPreferencesStorePlatform.instance = previous;
        SharedPreferences.resetStatic();
      });
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPreferencesSenkaStore(prefs);
      await expectLater(store.save(_archive()), throwsStateError);
      expect(prefs.getString('account.1001.senka.archive.v1'), isNull);
      await store.save(_archive());
      await prefs.reload();
      expect((await store.loadForAccount(1001))!.targetSenka, 3000);
    },
  );
}

class _MemoryStore implements SenkaStore {
  _MemoryStore(this.archive);
  SenkaState? archive;
  @override
  Future<SenkaState?> load() async => archive;
  @override
  Future<void> save(SenkaState value) async => archive = value;
}

class _DelayedStore extends _MemoryStore {
  _DelayedStore(super.archive);
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<SenkaState?> load() async {
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
    return super.load();
  }
}

class _DelayedAccountStore extends _DelayedStore implements AccountSenkaStore {
  _DelayedAccountStore(super.archive);
  @override
  Future<SenkaState?> loadForAccount(int memberId) async =>
      memberId == 1001 ? load() : null;
}

class _FailingLoadStore extends _MemoryStore {
  _FailingLoadStore(super.archive);
  bool fail = true;
  @override
  Future<SenkaState?> load() async {
    if (fail) {
      fail = false;
      throw StateError('first load unavailable');
    }
    return super.load();
  }
}

class _RejectOncePlatform extends InMemorySharedPreferencesStore {
  _RejectOncePlatform() : super.empty();
  bool fail = true;
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (fail) {
      fail = false;
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}

class _ThrowOncePlatform extends InMemorySharedPreferencesStore {
  _ThrowOncePlatform() : super.empty();
  bool fail = true;
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (fail) {
      fail = false;
      throw StateError('native write unavailable');
    }
    return super.setValue(valueType, key, value);
  }
}
