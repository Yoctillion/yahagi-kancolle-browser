import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/account/account_session.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_controller.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_state.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_store.dart';

String _raw(double target, {double experience = 3.5}) => jsonEncode(
  SenkaState.forMonth('2026-10')
      .copyWith(
        memberId: 1001,
        targetSenka: target,
        days: {'2026-10-20': SenkaDayRecord(experience: experience, eo: 75)},
      )
      .toJson()
    ..['futureUnknownField'] = {'preserved': true},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'queued page-clock refresh cannot overwrite a verified restored archive',
    () async {
      final session = AccountSession(initialMemberId: 1001);
      final store = _RawStore(_raw(3000));
      var instant = DateTime.utc(2026, 10, 20, 3);
      final controller = SenkaController(
        store: store,
        accountSession: session,
        now: () => instant,
      );
      addTearDown(() {
        controller.dispose();
        session.dispose();
      });
      await controller.initialize();
      expect(controller.state.targetSenka, 3000);

      // Freeze semantic mutations before the backup transaction writes data.
      await controller.beginArchiveRestore(1001);
      final imported = _raw(4200, experience: 17);
      await store.restoreArchiveForAccount(1001, imported);
      expect(await store.readArchiveForAccount(1001), imported);

      // A page timer remains alive behind the backup maintenance overlay. Its
      // refresh can queue a write from the old in-memory state while capture is
      // paused, immediately before the transaction calls reloadForAccount.
      instant = DateTime.utc(2026, 10, 21, 3);
      controller.refreshForCurrentTime();
      controller.setTargetSenka(4500);
      await controller.reloadForAccount(1001);

      expect(await store.readArchiveForAccount(1001), imported);
      await controller.endArchiveRestore(1001);
      await controller.idle;
      expect(controller.state.targetSenka, 4500);
      expect(controller.state.monthExperienceSenka, 17);
      expect(controller.state.monthRecorded, 92);
      final saved = SenkaState.fromJson(
        jsonDecode((await store.readArchiveForAccount(1001))!),
      );
      expect(saved.targetSenka, 4500);
      expect(saved.monthExperienceSenka, 17);
      expect(saved.monthRecorded, 92);
    },
  );

  test(
    'a v1 restore barrier replays each reward toggle exactly once',
    () async {
      final session = AccountSession(initialMemberId: 1001);
      final store = _RawStore(_raw(3000));
      final controller = SenkaController(
        store: store,
        accountSession: session,
        now: () => DateTime.utc(2026, 10, 20, 3),
      );
      addTearDown(() {
        controller.dispose();
        session.dispose();
      });
      await controller.initialize();
      await controller.beginArchiveRestore(1001);
      controller.cycleEoReward(15);
      expect(controller.state.eoStatuses[15], SenkaRewardStatus.planned);
      // A v1 logbook restore leaves senka preferences intact and therefore does
      // not call reloadForAccount before leaving maintenance.
      await controller.endArchiveRestore(1001);
      await controller.idle;
      expect(controller.state.eoStatuses[15], SenkaRewardStatus.planned);
      expect(
        (await store.loadForAccount(1001))!.eoStatuses[15],
        SenkaRewardStatus.planned,
      );
    },
  );
}

class _RawStore implements AccountSenkaStore, SenkaBackupStore {
  _RawStore(this.raw);
  String? raw;

  @override
  Future<SenkaState?> load() => loadForAccount(1001);

  @override
  Future<SenkaState?> loadForAccount(int memberId) async =>
      raw == null ? null : SenkaState.fromJson(jsonDecode(raw!));

  @override
  Future<void> save(SenkaState state) async {
    raw = jsonEncode(state.toJson());
  }

  @override
  Stream<int> get archiveChanges => const Stream<int>.empty();

  @override
  Future<void> get idle async {}

  @override
  Future<String?> readArchiveForAccount(int memberId) async => raw;

  @override
  Future<void> restoreArchiveForAccount(int memberId, String? value) async {
    raw = value;
  }
}
