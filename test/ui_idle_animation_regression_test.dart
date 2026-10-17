import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/fleet/fleet_information_center.dart';
import 'package:yahagi_kancolle_browser/src/fleet/fleet_ship_status_capsule.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/battle_status_effect_settings.dart';

void main() {
  testWidgets(
    'sparkle follows settings threshold ticker visibility and roster viewport',
    (tester) async {
      GameStateController.disableTimerForTest = true;
      addTearDown(() => GameStateController.disableTimerForTest = false);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 400);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      Future<void> render({
        int condition = 50,
        MoraleSparkleMode mode = MoraleSparkleMode.blinking,
        bool visible = true,
        int shipCount = 1,
        bool lastOnly = false,
      }) async {
        final controller = GameStateController(
          initialState: GameState(
            hasPortData: true,
            fleets: [
              Fleet(
                id: 1,
                name: 'fixture',
                shipIds: List.generate(shipCount, (i) => i + 1),
              ),
            ],
            ships: {
              for (var i = 1; i <= shipCount; i++)
                i: OwnedShip(
                  id: i,
                  masterId: 1,
                  level: 1,
                  condition: lastOnly && i < shipCount ? 49 : condition,
                  currentHp: 10,
                  maxHp: 10,
                ),
            },
            masterShips: const {
              1: MasterShip(id: 1, name: 'fixture', shipTypeId: 2),
            },
          ),
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TickerMode(
                enabled: visible,
                child: FleetInformationCenter(
                  controller: controller,
                  damagePulseMode: DamagePulseFilter.off,
                  moraleSparkleMode: mode,
                  clock: () => DateTime(2026, 9, 30),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 250));
      }

      await render(condition: 49);
      expect(tester.binding.transientCallbackCount, 0);
      await render();
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await render(mode: MoraleSparkleMode.off);
      expect(tester.binding.transientCallbackCount, 0);
      expect(find.byKey(const Key('fleet-morale-stars-1')), findsNothing);
      await render(mode: MoraleSparkleMode.steady);
      expect(tester.binding.transientCallbackCount, 0);
      expect(find.byKey(const Key('fleet-morale-stars-1')), findsOneWidget);
      await render();
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await render(visible: false);
      expect(tester.binding.transientCallbackCount, 0);
      await render();
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await render(condition: 49);
      expect(tester.binding.transientCallbackCount, 0);
      await render(shipCount: 7, lastOnly: true);
      expect(tester.binding.transientCallbackCount, 0);
      final list = find
          .ancestor(
            of: find.byKey(const Key('fleet-roster-ship-1')),
            matching: find.byType(ListView),
          )
          .first;
      final scroll = tester.widget<ListView>(list).controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      scroll.jumpTo(0);
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.binding.transientCallbackCount, 0);
      await render(shipCount: 0);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
      expect(tester.binding.transientCallbackCount, 0);
    },
  );
  testWidgets('summary sparkle mode changes stop and restart its controller', (
    tester,
  ) async {
    Future<void> render(MoraleSparkleMode mode, {int condition = 50}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 600,
                child: FleetShipStatusCapsule(
                  state: const GameState(
                    masterShips: {
                      1: MasterShip(id: 1, name: 'fixture', shipTypeId: 2),
                    },
                  ),
                  ship: OwnedShip(
                    id: 1,
                    masterId: 1,
                    level: 1,
                    condition: condition,
                    currentHp: 10,
                    maxHp: 10,
                  ),
                  damagePulseFilter: DamagePulseFilter.off,
                  moraleSparkleMode: mode,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
    }

    await render(MoraleSparkleMode.blinking);
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await render(MoraleSparkleMode.steady);
    expect(tester.binding.transientCallbackCount, 0);
    expect(find.byKey(const Key('fleet-morale-stars-1')), findsOneWidget);
    await render(MoraleSparkleMode.off);
    expect(tester.binding.transientCallbackCount, 0);
    expect(find.byKey(const Key('fleet-morale-stars-1')), findsNothing);
    await render(MoraleSparkleMode.blinking);
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await render(MoraleSparkleMode.steady, condition: 49);
    expect(tester.binding.transientCallbackCount, 0);
    expect(find.byKey(const Key('fleet-morale-stars-1')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('roster schedules no frames when all effects disabled', (
    tester,
  ) async {
    GameStateController.disableTimerForTest = true;
    addTearDown(() => GameStateController.disableTimerForTest = false);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = GameStateController(
      initialState: const GameState(
        hasPortData: true,
        fleets: [
          Fleet(id: 1, name: 'offline', shipIds: [1]),
        ],
        ships: {
          1: OwnedShip(
            id: 1,
            masterId: 1,
            level: 1,
            condition: 49,
            currentHp: 10,
            maxHp: 10,
          ),
        },
        masterShips: {
          1: MasterShip(id: 1, name: 'offline ship', shipTypeId: 2),
        },
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FleetInformationCenter(
            controller: controller,
            damagePulseMode: DamagePulseFilter.off,
            moraleSparkleMode: MoraleSparkleMode.off,
            clock: () => DateTime(2026, 9, 30),
          ),
        ),
      ),
    );
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final scheduled = tester.binding.transientCallbackCount;

    expect(scheduled, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(tester.binding.transientCallbackCount, 0);
  });
}
