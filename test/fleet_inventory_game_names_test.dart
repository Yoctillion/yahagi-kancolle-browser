import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/fleet/fleet_ship_status_capsule.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_remodel_capsule.dart';
import 'package:yahagi_kancolle_browser/src/fleet/fleet_ui_strings.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/inventory/owned_inventory_page.dart';
import 'package:yahagi_kancolle_browser/src/inventory/equipment_compatibility_drawer.dart';
import 'package:yahagi_kancolle_browser/src/inventory/ship_equipment_compatibility_drawer.dart';
import 'package:yahagi_kancolle_browser/src/localization/game_name_localizations.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_kc3_bundle.dart';

void main() {
  late ShipSubtitleKc3Bundle bundle;
  setUpAll(() {
    bundle = ShipSubtitleKc3Bundle.fromJsonString(
      File(ShipSubtitleKc3Bundle.bundledAsset).readAsStringSync(),
    );
  });

  const state = GameState(
    hasPortData: true,
    hasEquipmentCompatibilityData: true,
    masterShips: {
      139: MasterShip(
        id: 139,
        name: '矢矧',
        shipTypeId: 3,
        afterShipId: 306,
        afterLv: 35,
        equipTypeIds: {1},
      ),
      306: MasterShip(id: 306, name: '矢矧改', shipTypeId: 3),
    },
    masterShipTypes: {
      3: MasterShipType(id: 3, name: '軽巡洋艦', equipTypeIds: {1}),
    },
    masterSlotItemTypes: {1: '小口径主砲'},
    masterSlotItems: {
      1: MasterSlotItem(id: 1, name: '12cm単装砲', sortNo: 1, type: [1, 0, 1, 1]),
    },
    slotItems: {10: OwnedSlotItem(id: 10, masterId: 1)},
    ships: {1: OwnedShip(id: 1, masterId: 139, level: 20)},
  );

  Widget app(Locale locale, Widget child) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: GameNameLocalizationScope(
      bundle: bundle,
      child: Scaffold(body: child),
    ),
  );

  for (final entry in const {'en': 'Yahagi', 'ko': '야하기'}.entries) {
    testWidgets('${entry.key} fleet capsule translates ship and type names', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          Locale(entry.key),
          FleetShipStatusCapsule(state: state, ship: state.ships[1]!),
        ),
      );
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text('矢矧'), findsNothing);
      expect(find.text('軽巡洋艦'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${entry.key} inventory renders translated ship names', (
      tester,
    ) async {
      GameStateController.disableTimerForTest = true;
      final controller = GameStateController(initialState: state);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        app(Locale(entry.key), OwnedInventoryPage(controller: controller)),
      );
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text('矢矧'), findsNothing);
      expect(find.text('軽巡洋艦'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${entry.key} unowned cards translate names and types', (
      tester,
    ) async {
      final unowned = state.copyWith(ships: {}, slotItems: {});
      await tester.pumpWidget(
        app(
          Locale(entry.key),
          UnownedInventoryView(state: unowned, showShips: true),
        ),
      );
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text('軽巡洋艦'), findsNothing);
      await tester.pumpWidget(
        app(
          Locale(entry.key),
          UnownedInventoryView(state: unowned, showShips: false),
        ),
      );
      expect(find.text('12cm単装砲'), findsNothing);
      expect(find.text('小口径主砲'), findsNothing);
      expect(find.textContaining('12cm'), findsOneWidget);
    });

    testWidgets(
      '${entry.key} compatibility drawers translate both directions',
      (tester) async {
        await tester.pumpWidget(
          app(
            Locale(entry.key),
            EquipmentCompatibilityDrawer(
              state: state,
              equipment: state.masterSlotItems[1]!,
              onClose: () {},
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text(entry.value), findsOneWidget);
        expect(find.text('12cm単装砲'), findsNothing);
        expect(find.text('軽巡洋艦'), findsNothing);
        expect(tester.takeException(), isNull, reason: 'equipment to ships');
        await tester.pumpWidget(
          app(
            Locale(entry.key),
            ShipEquipmentCompatibilityDrawer(
              state: state,
              ship: state.masterShips[139]!,
              ownedShip: state.ships[1],
              onClose: () {},
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text(entry.value), findsOneWidget);
        expect(find.text('12cm単装砲'), findsNothing);
        expect(find.text('小口径主砲'), findsNothing);
        expect(find.textContaining('軽巡洋艦'), findsNothing);
        expect(tester.takeException(), isNull, reason: 'ship to equipment');
      },
    );

    testWidgets('${entry.key} remodel target includes translated affix', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          Locale(entry.key),
          ShipRemodelCapsule(state: state, ship: state.ships[1]!),
        ),
      );
      expect(find.textContaining(entry.value), findsOneWidget);
      expect(find.textContaining('矢矧改'), findsNothing);
    });

    testWidgets(
      '${entry.key} mechanism descriptions translate embedded names',
      (tester) async {
        await tester.pumpWidget(
          app(
            Locale(entry.key),
            Builder(
              builder: (context) => Column(
                children: [
                  Text(fleetMechanismDescription(context, '长门改二旗舰的特殊攻击编成。')),
                  Text(
                    fleetMechanismDescription(
                      context,
                      '金刚级改二丙／榛名改二乙系旗舰的夜战特殊攻击编成。',
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        expect(find.textContaining('長門'), findsNothing);
        expect(find.textContaining('改二'), findsNothing);
        expect(find.textContaining('丙'), findsNothing);
      },
    );
  }

  for (final locale in const [
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    Locale('ja'),
  ]) {
    testWidgets('${locale.toLanguageTag()} keeps original fleet names', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          locale,
          FleetShipStatusCapsule(state: state, ship: state.ships[1]!),
        ),
      );
      expect(find.text('矢矧'), findsOneWidget);
      expect(find.text('軽巡洋艦'), findsOneWidget);
    });
  }
}
