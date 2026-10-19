import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/fleet/anchorage_repair_view.dart';
import 'package:yahagi_kancolle_browser/src/fleet/construction_summary_card.dart';
import 'package:yahagi_kancolle_browser/src/fleet/fleet_information_center.dart';
import 'package:yahagi_kancolle_browser/src/fleet/nosaki_sparkle_view.dart';
import 'package:yahagi_kancolle_browser/src/fleet/operation_status_views.dart';
import 'package:yahagi_kancolle_browser/src/fleet/pre_sortie_check_summary.dart';
import 'package:yahagi_kancolle_browser/src/fleet/repair_summary_card.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
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

  for (final entry in const {'en': 'Yahagi', 'ko': '야하기'}.entries) {
    testWidgets('${entry.key} ship names cover secondary fleet surfaces', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final state = GameState(
        hasMasterData: true,
        hasPortData: true,
        masterShips: const {
          139: MasterShip(id: 139, name: '矢矧', shipTypeId: 3, slotCount: 2),
        },
        masterShipTypes: const {3: MasterShipType(id: 3, name: '軽巡洋艦')},
        masterSlotItems: const {
          1: MasterSlotItem(id: 1, name: '12cm単装砲', type: [1, 0, 1, 1]),
        },
        ships: const {
          1: OwnedShip(
            id: 1,
            masterId: 139,
            level: 20,
            currentHp: 8,
            maxHp: 10,
            slotIds: [10],
          ),
        },
        slotItems: const {10: OwnedSlotItem(id: 10, masterId: 1)},
        fleets: const [
          Fleet(id: 1, name: 'Custom Fleet', shipIds: [1]),
        ],
        repairDocks: [
          RepairDock(
            id: 1,
            state: 1,
            shipId: 1,
            completionTime: DateTime.now().add(const Duration(days: 1)),
          ),
        ],
        constructionDocks: [
          ConstructionDock(
            id: 1,
            state: 2,
            createdShipMasterId: 139,
            completionTime: DateTime.now().add(const Duration(days: 1)),
          ),
        ],
      );
      final controller = GameStateController(initialState: state);
      addTearDown(controller.dispose);
      Widget app(Widget child) => MaterialApp(
        locale: Locale(entry.key),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            GameNameLocalizationScope(bundle: bundle, child: child!),
        home: Scaffold(body: child),
      );
      final surfaces = <String, Widget>{
        'fleet details': FleetInformationCenter(controller: controller),
        'repair dock': RepairDockStatusView(state: state),
        'construction dock': ConstructionDockStatusView(state: state),
        'construction summary': ConstructionSummaryCard(
          controller: controller,
          collapsed: false,
          onToggleCollapse: () {},
          onOpenConstruction: () {},
        ),
        'repair summary': RepairSummaryCard(
          controller: controller,
          collapsed: false,
          onToggleCollapse: () {},
          onOpenRepair: (_) {},
        ),
        'anchorage repair': AnchorageRepairView(controller: controller),
        'Nosaki sparkle': NosakiSparkleView(controller: controller),
        'pre-sortie warnings': PreSortieCheckSummary(
          controller: controller,
          collapsed: false,
          onToggleCollapse: () {},
          onOpenFleet: (_) {},
        ),
      };
      for (final surface in surfaces.entries) {
        await tester.pumpWidget(
          app(KeyedSubtree(key: ValueKey(surface.key), child: surface.value)),
        );
        await tester.pump();
        if (surface.key == 'pre-sortie warnings') {
          // Two master slots but only one assigned item: exercise the actual
          // missing-main-equipment warning, whose message includes the ship.
          expect(
            find.byKey(const Key('pre-sortie-warning-1-main-equipment')),
            findsOneWidget,
          );
        }
        expect(
          find.textContaining(entry.value),
          findsWidgets,
          reason: surface.key,
        );
        expect(find.textContaining('矢矧'), findsNothing, reason: surface.key);
        expect(find.text('軽巡洋艦'), findsNothing, reason: surface.key);
        expect(tester.takeException(), isNull, reason: surface.key);
      }
    });
  }
}
