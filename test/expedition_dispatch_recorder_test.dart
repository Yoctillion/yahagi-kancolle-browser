import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/src/account/account_session.dart';
import 'package:yahagi_kancolle_browser/src/expedition/expedition_dispatch_recorder.dart';
import 'package:yahagi_kancolle_browser/src/expedition/expedition_selection_store.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';

GameState _away(int missionId, DateTime completion) => GameState.empty.copyWith(
  fleets: [
    const Fleet(id: 1, name: '第1舰队'),
    Fleet(
      id: 2,
      name: '第2舰队',
      mission: FleetMission(
        state: 1,
        missionId: missionId,
        completionTime: completion,
      ),
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AccountSession account;
  late SharedPreferencesExpeditionSelectionStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    account = AccountSession(initialMemberId: 1001);
    store = SharedPreferencesExpeditionSelectionStore(accountSession: account);
  });

  Future<void> observe(GameState state) async {
    final controller = GameStateController(initialState: state);
    final recorder = ExpeditionDispatchRecorder(
      controller: controller,
      accountSession: account,
    );
    await pumpEventQueue();
    recorder.dispose();
    controller.dispose();
  }

  test('the mission a fleet is away on becomes its selection', () async {
    var notified = 0;
    void count() => notified++;
    store.changes.addListener(count);
    addTearDown(() => store.changes.removeListener(count));

    await observe(_away(5, DateTime(2030, 1, 1)));
    expect(await store.loadMissionId(2), 5);
    expect(await store.loadMissionId(1), isNull);
    expect(notified, 1);
  });

  test('seeing the same dispatch again keeps a later manual pick', () async {
    final completion = DateTime(2030, 1, 1);
    await observe(_away(5, completion));
    await store.saveMissionId(2, 9);

    await observe(_away(5, completion));
    expect(await store.loadMissionId(2), 9);

    await observe(_away(6, DateTime(2030, 1, 2)));
    expect(await store.loadMissionId(2), 6);
  });

  test(
    'dispatches seen before the account is known are stored later',
    () async {
      account = AccountSession();
      store = SharedPreferencesExpeditionSelectionStore(
        accountSession: account,
      );
      final controller = GameStateController(
        initialState: _away(5, DateTime(2030, 1, 1)),
      );
      final recorder = ExpeditionDispatchRecorder(
        controller: controller,
        accountSession: account,
      );
      addTearDown(controller.dispose);
      addTearDown(recorder.dispose);
      await pumpEventQueue();

      account.selectMember(1001);
      await pumpEventQueue();
      expect(await store.loadMissionId(2), 5);
    },
  );
}
