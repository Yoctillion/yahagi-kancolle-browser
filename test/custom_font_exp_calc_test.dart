import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/exp_calc/exp_calc_models.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/exp_calc/exp_calc_page.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/exp_calc/exp_calc_ship_picker.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/exp_calc/exp_tracker_store.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/sortie_map_query/sortie_map_models.dart';

const _customFamily = 'UserFont_test';
const _fallback = ['HarmonyOS_Sans_TC', 'HarmonyOS_Sans', 'sans-serif'];
const _state = GameState(
  masterShips: {1: MasterShip(id: 1, name: '测试舰娘', shipTypeId: 2)},
  ships: {1: OwnedShip(id: 1, masterId: 1, level: 12)},
);
const _catalog = SortieMapCatalogData(version: 1, source: 'test', maps: []);

void main() {
  testWidgets('experience page follows the app font and preserves fallback', (
    tester,
  ) async {
    final store = _MemoryTrackerStore();
    Widget app(String family) => _app(
      ExpCalcPage(
        state: _state,
        store: store,
        catalogLoader: () async => _catalog,
      ),
      family: family,
    );

    for (final family in [_customFamily, 'HarmonyOS_Sans_TC']) {
      await tester.pumpWidget(app(family));
      await tester.pumpAndSettle();
      final title = find.text('舰娘与目标');
      final style = _renderedStyle(tester, title);
      expect(style.fontFamily, family);
      expect(style.fontFamilyFallback, _fallback);
      final dropdown = tester.widget<DropdownButton<String>>(
        find.byKey(const Key('exp-calc-map-selector')),
      );
      expect(dropdown.style?.fontFamily, family);
      expect(dropdown.style?.fontFamilyFallback, _fallback);
      final theme = Theme.of(tester.element(title));
      expect(theme.primaryTextTheme.titleLarge?.fontFamily, family);
      expect(theme.primaryTextTheme.titleLarge?.fontFamilyFallback, _fallback);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('experience ship dialog inherits the app font and fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        ExpCalcShipPicker(
          state: _state,
          ships: _state.ships.values.toList(),
          selectedId: 1,
          onSelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exp-calc-ship-selector')));
    await tester.pumpAndSettle();

    for (final text in ['全部', '测试舰娘', 'Lv.12']) {
      final style = _renderedStyle(tester, find.text(text));
      expect(style.fontFamily, _customFamily, reason: text);
      expect(style.fontFamilyFallback, _fallback, reason: text);
    }
    expect(tester.takeException(), isNull);
  });
}

Widget _app(Widget child, {String family = _customFamily}) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(fontFamily: family, fontFamilyFallback: _fallback),
  home: Scaffold(body: child),
);

TextStyle _renderedStyle(WidgetTester tester, Finder text) {
  final rich = tester.widget<RichText>(
    find.descendant(of: text, matching: find.byType(RichText)),
  );
  return (rich.text as TextSpan).style!;
}

final class _MemoryTrackerStore implements ExpTrackerStore {
  @override
  Future<List<ExpCalcTrackItem>> loadTrackItems(int memberId) async => [];

  @override
  Future<bool> saveTrackItems(
    int memberId,
    List<ExpCalcTrackItem> items,
  ) async => true;
}
