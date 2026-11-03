import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/fleet/fleet_information_center.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_attack/attack_profile.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_attack/ship_attack_profile.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_attack_details_dialog.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';

import '../../fixtures/kcsapi_fixtures.dart';
import '_fixtures.dart';

Widget _app(Widget home, {Locale locale = const Locale('zh')}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: home),
);

ShipAttackProfile _battleshipProfile() {
  final bigGun = gear(8, t2: 3, firepower: 20);
  final state = buildState(
    <ShipSpec>[
      ShipSpec(
        id: 1,
        shipTypeId: 9,
        firepower: 150,
        luck: 20,
        lineOfSight: 40,
        gears: <GearSpec?>[
          GearSpec(bigGun),
          GearSpec(bigGun),
          GearSpec(gear(116, t2: 19, firepower: 9)),
          GearSpec(gear(59, t2: 10, lineOfSight: 6)),
        ],
        slotCapacities: const <int>[4, 4, 4, 3],
      ),
    ],
    fleets: const <List<int>>[
      <int>[1],
    ],
  );
  return computeShipAttackProfile(state, state.ships[1]!)!;
}

Future<void> _openDialog(
  WidgetTester tester, {
  required ShipAttackProfile profile,
  bool night = false,
  Locale locale = const Locale('zh'),
}) async {
  await tester.pumpWidget(
    _app(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showShipAttackDetailsDialog(
            context,
            title: night ? '夜战期望' : '昼战期望',
            phase: night ? profile.night : profile.day,
            omitsBombingBonus: profile.omitsBombingBonus,
          ),
          child: const Text('open'),
        ),
      ),
      locale: locale,
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows day and night expectation cells', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = GameStateController();
    addTearDown(controller.dispose);
    controller
      ..accept(start2Event)
      ..accept(portEvent)
      ..accept(slotItemEvent);
    await controller.idle;

    await tester.pumpWidget(
      _app(FleetInformationCenter(controller: controller)),
    );
    await tester.pump();

    final state = controller.state;
    final ship = state.ships[state.fleets.first.shipIds.first]!;
    final profile = computeShipAttackProfile(state, ship)!;
    final dayCell = find.byKey(Key('ship-attack-day-${ship.id}'));
    final nightCell = find.byKey(Key('ship-attack-night-${ship.id}'));
    expect(dayCell, findsOneWidget);
    expect(nightCell, findsOneWidget);

    String expectation(AttackPhaseProfile? phase) =>
        phase == null ? '不参加' : '${phase.expectedPower.round()}';
    expect(
      find.descendant(
        of: dayCell,
        matching: find.text(expectation(profile.day)),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: nightCell,
        matching: find.text(expectation(profile.night)),
      ),
      findsOneWidget,
    );
  });

  testWidgets('dialog lists rows and conditions', (tester) async {
    await _openDialog(tester, profile: _battleshipProfile());
    expect(find.text('主主徹'), findsOneWidget);
    expect(find.text('35%'), findsOneWidget);
    expect(find.text('232'), findsOneWidget);
    expect(find.text('×1.2×2'), findsOneWidget);
    expect(find.text('期望 238'), findsOneWidget);
    expect(find.textContaining('制空确保'), findsOneWidget);
    expect(find.textContaining('未计爆装加成'), findsNothing);
  });

  testWidgets('non-participating phase shows 不参加', (tester) async {
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showShipAttackDetailsDialog(
              context,
              title: '昼战期望',
              phase: null,
              omitsBombingBonus: false,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('不参加'), findsOneWidget);
  });

  testWidgets('narrow layout does not overflow', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await _openDialog(
      tester,
      profile: _battleshipProfile(),
      locale: const Locale('en'),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Normal attack'), findsOneWidget);
  });
}
