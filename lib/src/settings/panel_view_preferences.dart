import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BattlePanelMode { compact, detailed }

/// View toggles shared by the standalone cards and the smart panel, so a pick
/// made in either place sticks everywhere and across restarts.
final class PanelViewPreferences extends ChangeNotifier {
  /// In-memory only; [load] returns the persisted instance.
  PanelViewPreferences() : _persist = false;

  PanelViewPreferences._persisted() : _persist = true;

  static const greatSuccessTargets = <int>[80, 85, 90, 95, 100];

  static const _expeditionDetailedKey = 'panel_view.expedition_detailed';
  static const _expeditionGreatSuccessKey =
      'panel_view.expedition_great_success';
  static const _expeditionTargetKey = 'panel_view.expedition_target';
  static const _battleModeKey = 'panel_view.battle_mode';
  static const _battleMapExpandedKey = 'panel_view.battle_map_expanded';

  final bool _persist;
  bool _expeditionDetailed = false;
  bool _expeditionGreatSuccess = false;
  int _expeditionTarget = 100;
  BattlePanelMode _battleMode = BattlePanelMode.detailed;
  bool _battleMapExpanded = true;

  bool get expeditionDetailed => _expeditionDetailed;
  bool get expeditionGreatSuccess => _expeditionGreatSuccess;
  int get expeditionTarget => _expeditionTarget;
  BattlePanelMode get battleMode => _battleMode;
  bool get battleMapExpanded => _battleMapExpanded;

  static Future<PanelViewPreferences> load() async {
    final preferences = PanelViewPreferences._persisted();
    try {
      final stored = await SharedPreferences.getInstance();
      preferences._expeditionDetailed =
          stored.getBool(_expeditionDetailedKey) ?? false;
      preferences._expeditionGreatSuccess =
          stored.getBool(_expeditionGreatSuccessKey) ?? false;
      final target = stored.getInt(_expeditionTargetKey);
      if (greatSuccessTargets.contains(target)) {
        preferences._expeditionTarget = target!;
      }
      final mode = stored.getString(_battleModeKey);
      preferences._battleMode = BattlePanelMode.values.firstWhere(
        (value) => value.name == mode,
        orElse: () => BattlePanelMode.detailed,
      );
      preferences._battleMapExpanded =
          stored.getBool(_battleMapExpandedKey) ?? true;
    } catch (_) {
      // Defaults are a usable view; losing the remembered toggles is harmless.
    }
    return preferences;
  }

  set expeditionDetailed(bool value) {
    if (_expeditionDetailed == value) return;
    _expeditionDetailed = value;
    _changed((stored) => stored.setBool(_expeditionDetailedKey, value));
  }

  set expeditionGreatSuccess(bool value) {
    if (_expeditionGreatSuccess == value) return;
    _expeditionGreatSuccess = value;
    _changed((stored) => stored.setBool(_expeditionGreatSuccessKey, value));
  }

  set expeditionTarget(int value) {
    if (_expeditionTarget == value || !greatSuccessTargets.contains(value)) {
      return;
    }
    _expeditionTarget = value;
    _changed((stored) => stored.setInt(_expeditionTargetKey, value));
  }

  set battleMode(BattlePanelMode value) {
    if (_battleMode == value) return;
    _battleMode = value;
    _changed((stored) => stored.setString(_battleModeKey, value.name));
  }

  set battleMapExpanded(bool value) {
    if (_battleMapExpanded == value) return;
    _battleMapExpanded = value;
    _changed((stored) => stored.setBool(_battleMapExpandedKey, value));
  }

  void _changed(Future<bool> Function(SharedPreferences stored) write) {
    notifyListeners();
    if (!_persist) return;
    SharedPreferences.getInstance().then(write).ignore();
  }
}

class PanelViewPreferencesScope
    extends InheritedNotifier<PanelViewPreferences> {
  const PanelViewPreferencesScope({
    super.key,
    required PanelViewPreferences preferences,
    required super.child,
  }) : super(notifier: preferences);

  static PanelViewPreferences? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PanelViewPreferencesScope>()
      ?.notifier;
}

/// Falls back to per-widget in-memory toggles where no scope is installed
/// (isolated cards in tests and previews).
mixin PanelViewPreferencesHost<T extends StatefulWidget> on State<T> {
  PanelViewPreferences? _fallback;

  PanelViewPreferences get panelViewPreferences =>
      PanelViewPreferencesScope.maybeOf(context) ??
      (_fallback ??= PanelViewPreferences()..addListener(_rebuild));

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _fallback?.dispose();
    super.dispose();
  }
}
