import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/fleet/fleet_ship_status_capsule.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/inventory/equipment_compatibility_drawer.dart';
import 'package:yahagi_kancolle_browser/src/inventory/owned_inventory_page.dart';
import 'package:yahagi_kancolle_browser/src/inventory/ship_equipment_compatibility_drawer.dart';
import 'package:yahagi_kancolle_browser/src/localization/game_name_catalog.dart';
import 'package:yahagi_kancolle_browser/src/localization/game_name_localizations.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_kc3_bundle.dart';

void main() {
  late ShipSubtitleKc3Bundle bundle;
  setUpAll(() {
    bundle = ShipSubtitleKc3Bundle.fromJsonString(
      File(ShipSubtitleKc3Bundle.bundledAsset).readAsStringSync(),
    );
  });
  setUp(() => GameStateController.disableTimerForTest = true);

  // Both source names occur verbatim in the bundled KC3 dictionaries.
  const shipName = 'Октябрьская революция';
  const equipmentName = 'Bofors 15cm連装速射砲 Mk.9改+単装速射砲 Mk.10改 Model 1938';
  const state = GameState(
    hasPortData: true,
    hasEquipmentCompatibilityData: true,
    masterShips: {
      730: MasterShip(
        id: 730,
        name: shipName,
        shipTypeId: 9,
        equipTypeIds: {2},
      ),
    },
    masterShipTypes: {
      9: MasterShipType(id: 9, name: '戦艦', equipTypeIds: {2}),
    },
    masterSlotItemTypes: {2: '中口径主砲'},
    masterSlotItems: {
      1: MasterSlotItem(
        id: 1,
        name: equipmentName,
        sortNo: 1,
        type: [1, 0, 2, 2],
      ),
    },
    ships: {
      1: OwnedShip(id: 1, masterId: 730, level: 99, slotIds: [10]),
    },
    slotItems: {10: OwnedSlotItem(id: 10, masterId: 1)},
  );

  for (final language in ['en', 'ko']) {
    for (final width in [360.0, 430.0]) {
      testWidgets('$language real long names fit ${width.toInt()}px surfaces', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final controller = GameStateController(initialState: state);
        addTearDown(controller.dispose);
        final names = GameNameCatalog(locale: Locale(language), bundle: bundle);
        final translatedShip = names.shipName(shipName, shipId: 730);
        final translatedEquipment = names.equipmentName(equipmentName);
        expect(translatedShip, isNot(shipName));
        expect(translatedShip.length, greaterThan(language == 'en' ? 20 : 10));
        expect(translatedEquipment, isNot(equipmentName));
        expect(
          translatedEquipment.length,
          greaterThan(language == 'en' ? 90 : 40),
        );
        final unowned = state.copyWith(ships: {}, slotItems: {});
        final surfaces = <({String label, Widget child, List<String> names})>[
          (
            label: 'fleet capsule',
            child: SizedBox(
              height: 220,
              child: FleetShipStatusCapsule(
                state: state,
                ship: state.ships[1]!,
              ),
            ),
            names: [translatedShip],
          ),
          (
            label: 'owned ships',
            child: OwnedInventoryPage(controller: controller, showShips: true),
            names: [translatedShip],
          ),
          (
            label: 'owned equipment',
            child: OwnedInventoryPage(controller: controller, showShips: false),
            names: [translatedEquipment],
          ),
          (
            label: 'unowned ships',
            child: UnownedInventoryView(state: unowned, showShips: true),
            names: [translatedShip],
          ),
          (
            label: 'unowned equipment',
            child: UnownedInventoryView(state: unowned, showShips: false),
            names: [translatedEquipment],
          ),
          (
            label: 'equipment compatibility',
            child: EquipmentCompatibilityDrawer(
              state: state,
              equipment: state.masterSlotItems[1]!,
              onClose: () {},
            ),
            names: [translatedShip, translatedEquipment],
          ),
          (
            label: 'ship compatibility',
            child: ShipEquipmentCompatibilityDrawer(
              state: state,
              ship: state.masterShips[730]!,
              ownedShip: state.ships[1],
              onClose: () {},
            ),
            names: [translatedShip, translatedEquipment],
          ),
        ];
        for (final surface in surfaces) {
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(language),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) =>
                  GameNameLocalizationScope(bundle: bundle, child: child!),
              home: Scaffold(
                body: KeyedSubtree(
                  key: ValueKey(surface.label),
                  child: surface.child,
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 200));
          for (final name in surface.names) {
            expect(find.text(name), findsWidgets, reason: surface.label);
          }
          expect(find.text(shipName), findsNothing, reason: surface.label);
          expect(find.text(equipmentName), findsNothing, reason: surface.label);
          expect(tester.takeException(), isNull, reason: surface.label);
        }
      });
    }
  }
}
