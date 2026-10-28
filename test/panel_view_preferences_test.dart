import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/src/settings/panel_view_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults without stored values', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await PanelViewPreferences.load();
    expect(preferences.expeditionDetailed, isFalse);
    expect(preferences.expeditionGreatSuccess, isFalse);
    expect(preferences.expeditionTarget, 100);
    expect(preferences.battleMode, BattlePanelMode.detailed);
    expect(preferences.battleMapExpanded, isTrue);
  });

  test('changes survive a reload', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final first = await PanelViewPreferences.load();
    first
      ..expeditionDetailed = true
      ..expeditionGreatSuccess = true
      ..expeditionTarget = 90
      ..battleMode = BattlePanelMode.compact
      ..battleMapExpanded = false;
    await pumpEventQueue();

    final reloaded = await PanelViewPreferences.load();
    expect(reloaded.expeditionDetailed, isTrue);
    expect(reloaded.expeditionGreatSuccess, isTrue);
    expect(reloaded.expeditionTarget, 90);
    expect(reloaded.battleMode, BattlePanelMode.compact);
    expect(reloaded.battleMapExpanded, isFalse);
  });

  test('an unknown stored target falls back to the default', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'panel_view.expedition_target': 42,
    });
    expect((await PanelViewPreferences.load()).expeditionTarget, 100);
  });

  test('the in-memory instance notifies without touching storage', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = PanelViewPreferences();
    var notified = 0;
    preferences.addListener(() => notified++);
    preferences.battleMapExpanded = false;
    preferences.battleMapExpanded = false;
    expect(notified, 1);
    await pumpEventQueue();
    expect((await PanelViewPreferences.load()).battleMapExpanded, isTrue);
  });
}
