import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/fleet/expedition_summary_card.dart';
import 'package:yahagi_kancolle_browser/src/fleet/land_base_summary_card.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/inventory/owned_inventory_page.dart';
import 'package:yahagi_kancolle_browser/src/theme/app_palette.dart';
import 'package:yahagi_kancolle_browser/src/theme/app_theme.dart';
import 'package:yahagi_kancolle_browser/src/widgets/app_segmented_style.dart';
import 'package:yahagi_kancolle_browser/src/widgets/filter_controls.dart';

void main() {
  testWidgets(
    'headers, page tabs, filters and Material selectors share theme roles',
    (tester) async {
      final game = GameStateController(
        initialState: GameState(
          landBases: const [
            LandBaseState(areaId: 6, baseId: 1, name: 'Base 6'),
            LandBaseState(areaId: 7, baseId: 1, name: 'Base 7'),
          ],
        ),
      );
      addTearDown(game.dispose);
      await game.initialize();
      bool? ownership;
      int? nativeSelection;
      Size? originalHeaderSize;
      Color? previousSelectedColor;
      Material button(String key) {
        final finder = find.byKey(Key(key));
        final widget = tester.widget(finder);
        if (widget is Material) return widget;
        return tester.widget<Material>(
          find.descendant(of: finder, matching: find.byType(Material)).first,
        );
      }

      Text label(String key) => tester.widget<Text>(
        find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)),
      );

      for (final theme in AppThemeMode.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: createAppTheme(mode: theme),
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExpeditionModeSelector(
                    mode: ExpeditionSummaryMode.summary,
                    compact: true,
                    summaryLabel: 'Progress',
                    checkLabel: 'Check',
                    onChanged: (_) {},
                  ),
                  OwnedInventoryOwnershipSegmented(
                    showOwned: true,
                    onChanged: (value) => ownership = value,
                  ),
                  LandBaseSummaryCard(
                    controller: game,
                    collapsed: false,
                    showLogo: false,
                    showTitle: false,
                    onToggleCollapse: () {},
                  ),
                  Row(
                    children: [
                      HeaderFilterIconButton(
                        key: const Key('inactive-button'),
                        icon: Icons.search,
                        active: false,
                        tooltip: 'inactive',
                        onPressed: () {},
                      ),
                      HeaderFilterIconButton(
                        key: const Key('active-button'),
                        icon: Icons.filter_alt_outlined,
                        active: true,
                        tooltip: 'active',
                        onPressed: () {},
                      ),
                      CompactFilterChip(
                        key: const Key('selected-chip'),
                        label: 'selected',
                        selected: true,
                        onTap: () {},
                      ),
                    ],
                  ),
                  Builder(
                    builder: (context) => SegmentedButton<int>(
                      key: const Key('native-selector'),
                      style: AppSegmentedStyle.materialStyle(context),
                      selected: const {0},
                      segments: const [
                        ButtonSegment(value: 0, label: Text('First')),
                        ButtonSegment(value: 1, label: Text('Second')),
                      ],
                      onSelectionChanged: (values) =>
                          nativeSelection = values.single,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final referenceColor = button('expedition-mode-summary').color;
        final referenceText = label('expedition-mode-summary').style?.color;
        final rail =
            tester
                    .widget<Container>(
                      find.byKey(const Key('expedition-summary-mode-selector')),
                    )
                    .decoration
                as BoxDecoration;
        expect(button('owned-inventory-tab-owned').color, referenceColor);
        expect(button('land-base-area-selector-6').color, referenceColor);
        expect(label('owned-inventory-tab-owned').style?.color, referenceText);
        expect(label('land-base-area-selector-6').style?.color, referenceText);
        final active = tester.widget<IconButton>(
          find.descendant(
            of: find.byKey(const Key('active-button')),
            matching: find.byType(IconButton),
          ),
        );
        final inactive = tester.widget<IconButton>(
          find.descendant(
            of: find.byKey(const Key('inactive-button')),
            matching: find.byType(IconButton),
          ),
        );
        expect(active.style?.backgroundColor?.resolve({}), referenceColor);
        expect(inactive.style?.backgroundColor?.resolve({}), rail.color);
        expect(
          active.style?.side?.resolve({})?.color,
          (rail.border! as Border).top.color,
        );
        expect(
          tester.getSize(find.byKey(const Key('inactive-button'))),
          const Size(34, 34),
        );
        final chip = tester.widget<Container>(
          find.descendant(
            of: find.byKey(const Key('selected-chip')),
            matching: find.byType(Container),
          ),
        );
        expect((chip.decoration as BoxDecoration).color, referenceColor);
        expect(label('selected-chip').style?.color, referenceText);
        final native = tester.widget<SegmentedButton<int>>(
          find.byKey(const Key('native-selector')),
        );
        expect(
          native.style?.backgroundColor?.resolve({WidgetState.selected}),
          referenceColor,
        );
        expect(
          native.style?.foregroundColor?.resolve({WidgetState.selected}),
          referenceText,
        );
        expect(
          native.style?.backgroundColor?.resolve({
            WidgetState.disabled,
            WidgetState.selected,
          }),
          isNot(native.style?.backgroundColor?.resolve({WidgetState.disabled})),
        );
        final headerSize = tester.getSize(
          find.byKey(const Key('expedition-summary-mode-selector')),
        );
        if (originalHeaderSize != null) expect(headerSize, originalHeaderSize);
        if (previousSelectedColor != null) {
          expect(referenceColor, isNot(previousSelectedColor));
        }
        originalHeaderSize = headerSize;
        previousSelectedColor = referenceColor;
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byKey(const Key('land-base-area-selector-7')));
      await tester.pumpAndSettle();
      expect(
        button('land-base-area-selector-7').color,
        button('expedition-mode-summary').color,
      );
      await tester.tap(find.byKey(const Key('owned-inventory-tab-unowned')));
      expect(ownership, false);
      await tester.tap(find.text('Second'));
      expect(nativeSelection, 1);
    },
  );
}
