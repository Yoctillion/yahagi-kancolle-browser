import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/localization/game_name_localizations.dart';
import 'package:yahagi_kancolle_browser/src/improvement/improvement_dataset.dart';
import 'package:yahagi_kancolle_browser/src/improvement/improvement_planner_controller.dart';
import 'package:yahagi_kancolle_browser/src/improvement/improvement_planner_view.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_kc3_bundle.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/composition_image_card.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/exp_calc/exp_calc_ship_picker.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/sortie_map_query/enemy_catalog.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/sortie_map_query/sortie_enemy_details.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/sortie_map_query/sortie_map_models.dart';

import 'fixtures/composition_image_fixture.dart';

void main() {
  late ShipSubtitleKc3Bundle bundle;
  setUpAll(() {
    bundle = ShipSubtitleKc3Bundle.fromJsonString(
      File(ShipSubtitleKc3Bundle.bundledAsset).readAsStringSync(),
    );
  });

  for (final language in ['en', 'ko']) {
    for (final width in [360.0, 430.0]) {
      testWidgets(
        '$language composition preview and saved table fit width $width with long equipment names',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final fixture = compositionImageFixture();
          final state = fixture.copyWith(
            masterSlotItems: {
              ...fixture.masterSlotItems,
              203: const MasterSlotItem(
                id: 203,
                name: _longEquipmentName,
                type: [1, 1, 2, 2],
              ),
            },
          );
          late String translated;
          for (final recordMode in [false, true]) {
            await tester.pumpWidget(
              _app(
                bundle,
                Locale(language),
                Builder(
                  builder: (context) {
                    translated = gameNames(
                      context,
                    ).equipmentName(_longEquipmentName);
                    return SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: FittedBox(
                          key: const Key('narrow-composition-preview'),
                          fit: BoxFit.fitWidth,
                          alignment: Alignment.topLeft,
                          child: CompositionImageCard(
                            state: state,
                            fleetIds: const {1},
                            landBaseAreaId: null,
                            landBaseIds: const {},
                            planeCountMode: CompositionPlaneCountMode.maximum,
                            generatedAt: DateTime.utc(2026, 10, 19),
                            recordMode: recordMode,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(translated, isNot(_longEquipmentName));
            expect(find.text(translated), findsWidgets);
            expect(
              tester
                  .getSize(find.byKey(const Key('narrow-composition-preview')))
                  .width,
              lessThanOrEqualTo(width - 24),
            );
            expect(
              tester.takeException(),
              isNull,
              reason:
                  'recordMode=$recordMode, language=$language, width=$width',
            );
          }
        },
      );

      testWidgets(
        '$language enemy details fit width $width with long equipment names',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final catalog = EnemyCatalogData.fromJsonString(
            jsonEncode({
              'schemaVersion': 1,
              'dataVersion': 'test',
              'revision': 1,
              'publishedAt': '2026-10-19T00:00:00Z',
              'source': 'test',
              'quality': {},
              'aliases': {'1501|駆逐イ級': 'enemy'},
              'ships': [
                {
                  'key': 'enemy',
                  'id': 1501,
                  'name': '駆逐イ級',
                  'shipType': '駆逐艦',
                  'equipment': [
                    {'slot': 1, 'name': _longEquipmentName, 'matched': true},
                  ],
                },
              ],
            }),
          );
          late String translated;
          await tester.pumpWidget(
            _app(
              bundle,
              Locale(language),
              Builder(
                builder: (context) {
                  translated = gameNames(
                    context,
                  ).equipmentName(_longEquipmentName);
                  return TextButton(
                    onPressed: () => showSortieEnemyDetails(
                      context,
                      entry: const EnemyShipEntry(
                        id: 1501,
                        nameJa: '駆逐イ級',
                        nameZh: '驱逐イ级',
                      ),
                      state: GameState.empty,
                      catalog: catalog,
                    ),
                    child: const Text('open'),
                  );
                },
              ),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          expect(translated, isNot(_longEquipmentName));
          final label = tester.widget<Text>(find.text(translated));
          expect(label.maxLines, 1);
          expect(label.overflow, TextOverflow.ellipsis);
          expect(
            tester
                .getSize(find.byKey(const Key('sortie-enemy-details-card')))
                .width,
            lessThanOrEqualTo(width - 32),
          );
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const Key('sortie-enemy-details-close')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('sortie-enemy-details-card')),
            findsNothing,
          );
        },
      );
    }

    testWidgets(
      'enemy details use $language names without altering lookup keys',
      (tester) async {
        final catalog = EnemyCatalogData.fromJsonString(
          jsonEncode({
            'schemaVersion': 1,
            'dataVersion': 'test',
            'revision': 1,
            'publishedAt': '2026-10-19T00:00:00Z',
            'source': 'test',
            'quality': {},
            'aliases': {'1501|駆逐イ級': 'enemy'},
            'ships': [
              {
                'key': 'enemy',
                'id': 1501,
                'name': '駆逐イ級',
                'shipType': '駆逐艦',
                'equipment': [
                  {'slot': 1, 'name': '12.7cm連装砲', 'matched': true},
                ],
              },
            ],
          }),
        );
        const entry = EnemyShipEntry(id: 1501, nameJa: '駆逐イ級', nameZh: '驱逐イ级');
        late String ship;
        late String equipment;
        late String type;
        await tester.pumpWidget(
          _app(
            bundle,
            Locale(language),
            Builder(
              builder: (context) {
                final names = gameNames(context);
                ship = names.shipName(entry.nameJa, shipId: entry.id);
                equipment = names.equipmentName('12.7cm連装砲');
                type = names.shipTypeName('駆逐艦');
                return TextButton(
                  onPressed: () => showSortieEnemyDetails(
                    context,
                    entry: entry,
                    state: GameState.empty,
                    catalog: catalog,
                  ),
                  child: const Text('open'),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text(ship), findsOneWidget);
        expect(find.text(equipment), findsOneWidget);
        expect(find.text(type), findsOneWidget);
        expect(catalog.resolve(entry)?.name, '駆逐イ級');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'improvement translates equipment, consumed items and secretaries in $language',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1800, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final controller = ImprovementPlannerController(
          dataset: _improvementDataset,
        );
        addTearDown(controller.dispose);
        controller.selectWeekday(1);
        late String ship;
        late String equipment;
        late String consumed;
        await tester.pumpWidget(
          _app(
            bundle,
            Locale(language),
            Builder(
              builder: (context) {
                final names = gameNames(context);
                ship = names.shipName('明石');
                equipment = names.equipmentName('12.7cm連装砲');
                consumed = names.equipmentName('61cm四連装魚雷');
                return ImprovementPlannerView(
                  controller: controller,
                  state: _improvementState,
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(equipment, isNot('12.7cm連装砲'));
        expect(consumed, isNot('61cm四連装魚雷'));
        expect(find.text(equipment), findsWidgets);
        expect(find.text(consumed), findsWidgets);
        expect(find.text(ship), findsWidgets);
        expect(
          find.text(language == 'en' ? 'Action Report' : '전투상보'),
          findsOneWidget,
        );
        expect(find.text('明石'), findsNothing);
        expect(_improvementState.masterSlotItems[1]!.name, '12.7cm連装砲');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'composition image displays $language ships, types and equipment',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1300, 1800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final state = compositionImageFixture();
        late String shipName;
        late String shipType;
        late String equipmentName;
        await tester.pumpWidget(
          _app(
            bundle,
            Locale(language),
            Builder(
              builder: (context) {
                final names = gameNames(context);
                shipName = names.shipName('矢矧改二乙', shipId: 100);
                shipType = names.shipTypeName('軽巡洋艦', typeId: 3);
                equipmentName = names.equipmentName('熟練見張員');
                return SingleChildScrollView(
                  child: CompositionImageCard(
                    state: state,
                    fleetIds: const {1},
                    landBaseAreaId: null,
                    landBaseIds: const {},
                    planeCountMode: CompositionPlaneCountMode.maximum,
                    generatedAt: DateTime.utc(2026, 10, 19),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(shipName, isNot('矢矧改二乙'));
        expect(shipType, isNot('軽巡洋艦'));
        expect(equipmentName, isNot('熟練見張員'));
        expect(find.text(shipName), findsOneWidget);
        expect(find.text(shipType), findsWidgets);
        expect(find.text(equipmentName), findsWidgets);
        expect(find.text('矢矧改二乙'), findsNothing);
        expect(state.masterShips[100]!.name, '矢矧改二乙');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('experience ship selector and its dialog use $language names', (
      tester,
    ) async {
      final state = compositionImageFixture();
      late String translated;
      await tester.pumpWidget(
        _app(
          bundle,
          Locale(language),
          Builder(
            builder: (context) {
              translated = gameNames(context).shipName('矢矧改二乙', shipId: 100);
              return ExpCalcShipPicker(
                state: state,
                ships: [state.ships[1]!],
                selectedId: 1,
                onSelected: (_) {},
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining(translated), findsOneWidget);
      await tester.tap(find.byKey(const Key('exp-calc-ship-selector')));
      await tester.pumpAndSettle();
      expect(find.text(translated), findsOneWidget);
      expect(find.text('矢矧改二乙'), findsNothing);
    });
  }

  for (final locale in [
    const Locale('zh'),
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    const Locale('ja'),
  ]) {
    testWidgets('experience selector preserves existing name for $locale', (
      tester,
    ) async {
      final state = compositionImageFixture();
      await tester.pumpWidget(
        _app(
          bundle,
          locale,
          ExpCalcShipPicker(
            state: state,
            ships: [state.ships[1]!],
            selectedId: 1,
            onSelected: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('矢矧改二乙 · Lv.99'), findsOneWidget);
    });
  }
}

Widget _app(ShipSubtitleKc3Bundle bundle, Locale locale, Widget child) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) =>
          GameNameLocalizationScope(bundle: bundle, child: child!),
      home: Scaffold(body: child),
    );

const _improvementState = GameState(
  masterSlotItems: {
    1: MasterSlotItem(id: 1, name: '12.7cm連装砲', type: [1, 0, 1, 1]),
    15: MasterSlotItem(id: 15, name: '61cm四連装魚雷', type: [2, 0, 5, 5]),
  },
);

const _longEquipmentName = 'Bofors 15cm連装速射砲 Mk.9改+単装速射砲 Mk.10改 Model 1938';
final _improvementDataset = ImprovementDataset(
  version: const ImprovementDatasetVersion(dataVersion: 'test', commitSha: ''),
  entries: [
    ImprovementEntry(
      equipmentId: 1,
      baseCost: const ImprovementResourceCost(
        fuel: 0,
        ammo: 0,
        steel: 0,
        bauxite: 0,
      ),
      arrangements: [
        ImprovementArrangement(
          secretaryId: 1,
          secretaryLabel: '明石',
          weekdays: {1},
        ),
      ],
      stage0: const ImprovementStageCost(
        developmentMin: 1,
        developmentMax: 1,
        improvementMin: 1,
        improvementMax: 1,
        items: [
          ImprovementConsumeItem(equipmentId: 15, count: 1),
          ImprovementConsumeItem(materialKey: 'ActionReport', count: 1),
        ],
      ),
      stage1: const ImprovementStageCost(
        developmentMin: 1,
        developmentMax: 1,
        improvementMin: 1,
        improvementMax: 1,
        items: [],
      ),
      upgrades: const [],
    ),
  ],
);
