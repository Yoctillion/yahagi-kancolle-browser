import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/battle/prophet_hp_bar.dart';
import 'package:yahagi_kancolle_browser/src/fleet/equipment_display.dart';
import 'package:yahagi_kancolle_browser/src/fleet/fleet_ship_minimal_row.dart';
import 'package:yahagi_kancolle_browser/src/fleet/fleet_summary_card.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_repair_status.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_status_visuals.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_store.dart';
import 'package:yahagi_kancolle_browser/src/layout/panel_style.dart';
import 'package:yahagi_kancolle_browser/src/settings/battle_status_effect_settings.dart';
import 'package:yahagi_kancolle_browser/src/settings/fleet_display_options.dart';

import 'fixtures/fleet_display_sample.dart';

class _Store extends GameStateStore {
  _Store(this.state);
  final GameState state;
  @override
  Future<GameState> load() async => state;
}

/// Ship 1: destroyer with sonar and 100 ASW (opening ASW only).
/// Ship 2: Saratoga Mk.II with a night fighter (night carrier attack only).
GameState _mechanismState() => GameState.empty.copyWith(
  hasPortData: true,
  masterShipTypes: {
    2: const MasterShipType(id: 2, name: '驱逐'),
    11: const MasterShipType(id: 11, name: '正规空母'),
  },
  masterShips: {
    1: const MasterShip(
      id: 1,
      name: '如月改二',
      shipTypeId: 2,
      speed: 10,
      maxFuel: 15,
      maxAmmo: 20,
    ),
    545: const MasterShip(
      id: 545,
      name: 'Saratoga Mk.II',
      shipTypeId: 11,
      speed: 10,
      maxFuel: 80,
      maxAmmo: 90,
      slotCapacities: [27, 19, 15, 6],
    ),
  },
  ships: {
    1: const OwnedShip(
      id: 1,
      masterId: 1,
      level: 76,
      currentHp: 30,
      maxHp: 30,
      condition: 49,
      currentFuel: 15,
      currentAmmo: 20,
      antiSub: 100,
      slotIds: [1],
    ),
    2: const OwnedShip(
      id: 2,
      masterId: 545,
      level: 120,
      currentHp: 80,
      maxHp: 80,
      condition: 49,
      currentFuel: 80,
      currentAmmo: 90,
      slotIds: [2],
    ),
  },
  masterSlotItems: {
    10: const MasterSlotItem(id: 10, name: '三式水中探信仪', type: [0, 0, 14, 18]),
    254: const MasterSlotItem(id: 254, name: 'F6F-3N', type: [0, 0, 6, 45]),
  },
  slotItems: {
    1: const OwnedSlotItem(instanceId: 1, masterSlotItemId: 10),
    2: const OwnedSlotItem(instanceId: 2, masterSlotItemId: 254),
  },
  fleets: const [
    Fleet(id: 1, name: '第一舰队', shipIds: [1, 2]),
  ],
);

Widget _app(Widget child, {Locale locale = const Locale('zh')}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Align(alignment: Alignment.topLeft, child: child),
  ),
);

Widget _row(
  GameState state,
  int shipId, {
  Set<String> visible = defaultFields,
  ShipRepairStatus? repairStatus,
  EquipmentMechanismDisplay? specialAttack,
}) => SizedBox(
  width: 320,
  child: FleetShipMinimalRow(
    state: state,
    ship: state.ships[shipId]!,
    visible: visible,
    shipTypeLabelMode: FleetShipTypeLabelMode.localizedName,
    damagePulseFilter: DamagePulseFilter.all,
    moraleSparkleMode: MoraleSparkleMode.blinking,
    repairStatus: repairStatus,
    specialAttack: specialAttack,
  ),
);

Future<GameStateController> _controller(GameState state) async {
  final controller = GameStateController(gameStateStore: _Store(state));
  await controller.initialize();
  return controller;
}

Widget _flatCard(
  GameStateController controller, {
  double width = 360,
  Locale locale = const Locale('zh'),
  Set<String> visible = defaultFields,
  ValueChanged<int>? onOpenFleet,
}) => _app(
  SizedBox(
    width: width,
    child: PanelStyleScope(
      style: PanelStyle.flat,
      child: FleetSummaryCard(
        controller: controller,
        collapsed: false,
        onToggleCollapse: () {},
        onOpenFleet: onOpenFleet ?? (_) {},
        visible: visible,
      ),
    ),
  ),
  locale: locale,
);

void main() {
  test('morale bands follow the game thresholds', () {
    expect(moraleBandOf(50), MoraleBand.sparkle);
    expect(moraleBandOf(49), MoraleBand.normal);
    expect(moraleBandOf(40), MoraleBand.normal);
    expect(moraleBandOf(39), MoraleBand.mild);
    expect(moraleBandOf(30), MoraleBand.mild);
    expect(moraleBandOf(29), MoraleBand.tired);
    expect(moraleBandOf(20), MoraleBand.tired);
    expect(moraleBandOf(19), MoraleBand.exhausted);
  });

  testWidgets('mechanism tags follow the shared display toggle', (
    tester,
  ) async {
    final state = _mechanismState();
    Future<void> pumpRows(Set<String> visible) async {
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              _row(state, 1, visible: visible),
              _row(state, 2, visible: visible),
            ],
          ),
        ),
      );
      await tester.pump();
    }

    await pumpRows(defaultFields);
    expect(
      find.byKey(const Key('minimal-mechanism-1-openingAsw')),
      findsOneWidget,
    );
    expect(find.text('先反'), findsOneWidget);
    expect(
      find.byKey(const Key('minimal-mechanism-2-nightCarrierAttack')),
      findsOneWidget,
    );

    await pumpRows(defaultFields.difference({'mechanisms'}));
    expect(
      find.byKey(const Key('minimal-mechanism-2-nightCarrierAttack')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('minimal-mechanism-1-openingAsw')),
      findsNothing,
    );
  });

  testWidgets('mechanism tags always use short labels', (tester) async {
    const specialAttack = EquipmentMechanismDisplay(
      label: '大和型特殊攻击',
      shortLabel: '特攻',
      description: '',
      tone: MechanismTone.specialAttack,
      kind: CombatMechanismKind.fleetSpecialAttack,
    );
    final state = _mechanismState();
    await tester.pumpWidget(_app(_row(state, 1, specialAttack: specialAttack)));
    await tester.pump();

    expect(find.text('先反'), findsOneWidget);
    expect(find.text('特攻'), findsOneWidget);
    expect(find.text('先制对潜'), findsNothing);

    await tester.pumpWidget(
      _app(
        _row(
          state,
          1,
          visible: defaultFields.difference({'mechanisms'}),
          specialAttack: specialAttack,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('先反'), findsNothing);
    expect(find.text('特攻'), findsNothing);
  });

  testWidgets('display toggles control supply bars and the speed tag', (
    tester,
  ) async {
    final state = demoState();
    await tester.pumpWidget(
      _app(
        _row(
          state,
          1,
          visible: defaultFields.difference({'fuel', 'shipSpeed'}),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('minimal-supply-fuel-1')), findsNothing);
    expect(find.byKey(const Key('minimal-supply-ammo-1')), findsOneWidget);
    expect(find.text('高速'), findsNothing);

    await tester.pumpWidget(
      _app(_row(state, 1, visible: defaultFields.difference({'fuel'}))),
    );
    await tester.pump();
    expect(find.text('高速'), findsOneWidget);
  });

  testWidgets('status line is dropped when all its fields are hidden', (
    tester,
  ) async {
    final state = demoState();
    await tester.pumpWidget(_app(_row(state, 2)));
    await tester.pump();
    final full = tester.getSize(find.byKey(const Key('minimal-ship-row-2')));

    await tester.pumpWidget(
      _app(
        _row(
          state,
          2,
          visible: defaultFields.difference({'hp', 'fuel', 'ammo', 'morale'}),
        ),
      ),
    );
    await tester.pump();
    final identityOnly = tester.getSize(
      find.byKey(const Key('minimal-ship-row-2')),
    );
    expect(identityOnly.height, lessThan(full.height - 10));
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden morale still flags tired and sparkling ships', (
    tester,
  ) async {
    // demoState 的疲劳：1 号 85、2 号 49、4 号 15。
    final state = demoState();
    final hidden = defaultFields.difference({'morale'});
    Future<void> pumpRows(MoraleSparkleMode sparkle) async {
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              for (final id in [1, 2, 4])
                SizedBox(
                  width: 320,
                  child: FleetShipMinimalRow(
                    state: state,
                    ship: state.ships[id]!,
                    visible: hidden,
                    shipTypeLabelMode: FleetShipTypeLabelMode.localizedName,
                    damagePulseFilter: DamagePulseFilter.all,
                    moraleSparkleMode: sparkle,
                  ),
                ),
            ],
          ),
        ),
      );
      await tester.pump();
    }

    await pumpRows(MoraleSparkleMode.blinking);
    expect(find.byKey(const Key('minimal-morale-1')), findsOneWidget);
    expect(find.byKey(const Key('minimal-morale-2')), findsNothing);
    expect(find.byKey(const Key('minimal-morale-4')), findsOneWidget);
    // 放在第一行，不挤动第二行血条的起点。
    expect(
      tester.getRect(find.byKey(const Key('minimal-morale-4'))).bottom,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const Key('minimal-name-4'))).bottom + 1,
      ),
    );

    await pumpRows(MoraleSparkleMode.off);
    expect(find.byKey(const Key('minimal-morale-1')), findsNothing);
    expect(find.byKey(const Key('minimal-morale-4')), findsOneWidget);
  });

  testWidgets('hiding bars turns the status line into plain values', (
    tester,
  ) async {
    final state = demoState();
    for (final width in [190.0, 320.0]) {
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: width,
            child: FleetShipMinimalRow(
              state: state,
              ship: state.ships[2]!,
              visible: defaultFields.difference({'bars'}),
              shipTypeLabelMode: FleetShipTypeLabelMode.localizedName,
              damagePulseFilter: DamagePulseFilter.all,
              moraleSparkleMode: MoraleSparkleMode.blinking,
            ),
          ),
        ),
      );
      await tester.pump();

      final row = find.byKey(const Key('minimal-ship-row-2'));
      expect(
        find.descendant(of: row, matching: find.byType(ProphetHpBar)),
        findsNothing,
      );
      expect(find.byKey(const Key('minimal-supply-fuel-2')), findsNothing);
      expect(find.byKey(const Key('minimal-supply-ammo-2')), findsNothing);
      final hp = find.byKey(const Key('minimal-hp-value-2'));
      final fuel = find.byKey(const Key('minimal-supply-fuel-value-2'));
      final ammo = find.byKey(const Key('minimal-supply-ammo-value-2'));
      expect(tester.widget<Text>(hp).data, '20/27');
      expect(tester.widget<Text>(fuel).data, '13/25');
      expect(tester.widget<Text>(ammo).data, '15/30');
      // 数值紧跟疲劳块从左排，不留出血条的位置。
      expect(
        tester.getRect(hp).left,
        lessThan(tester.getRect(row).left + width * .3),
      );
      expect(tester.getRect(fuel).left, greaterThan(tester.getRect(hp).right));
      expect(
        tester.getRect(ammo).left,
        greaterThan(tester.getRect(fuel).right),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('original ship type names use two-character short forms', (
    tester,
  ) async {
    const names = {3: '軽巡洋艦', 4: '重雷装巡洋艦', 6: '航空巡洋艦', 11: '正規空母', 16: '水上機母艦'};
    final state = GameState.empty.copyWith(
      hasPortData: true,
      masterShipTypes: {
        for (final e in names.entries)
          e.key: MasterShipType(id: e.key, name: e.value),
      },
      masterShips: {
        for (final id in names.keys)
          id: MasterShip(id: id, name: '艦$id', shipTypeId: id, speed: 10),
      },
      ships: {
        for (final id in names.keys)
          id: OwnedShip(
            id: id,
            masterId: id,
            level: 1,
            currentHp: 10,
            maxHp: 10,
            condition: 49,
          ),
      },
    );
    Future<void> pumpRows(FleetShipTypeLabelMode mode) async {
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              for (final id in names.keys)
                SizedBox(
                  width: 210,
                  child: FleetShipMinimalRow(
                    state: state,
                    ship: state.ships[id]!,
                    visible: defaultFields,
                    shipTypeLabelMode: mode,
                    damagePulseFilter: DamagePulseFilter.all,
                    moraleSparkleMode: MoraleSparkleMode.blinking,
                  ),
                ),
            ],
          ),
        ),
      );
      await tester.pump();
    }

    await pumpRows(FleetShipTypeLabelMode.localizedName);
    for (final short in ['軽巡', '雷巡', '航巡', '空母', '水母']) {
      expect(find.text(short), findsOneWidget);
    }
    expect(find.text('軽巡洋艦'), findsNothing);

    await pumpRows(FleetShipTypeLabelMode.abbreviation);
    for (final abbreviation in ['CL', 'CLT', 'CAV', 'CV', 'AV']) {
      expect(find.text(abbreviation), findsOneWidget);
    }
  });

  testWidgets('retreated ships show zero hp and a desaturated portrait', (
    tester,
  ) async {
    final state = demoState();
    await tester.pumpWidget(
      _app(_row(state, 1, repairStatus: ShipRepairStatus.retreat)),
    );
    await tester.pump();

    final hp = tester.widget<Text>(find.byKey(const Key('minimal-hp-value-1')));
    expect(hp.data, startsWith('0/'));
    expect(
      find.descendant(
        of: find.byKey(const Key('minimal-ship-row-1')),
        matching: find.byType(ColorFiltered),
      ),
      findsOneWidget,
    );
    expect(find.text('退避'), findsOneWidget);
  });

  testWidgets('flat fleet card uses minimal rows without hp frames', (
    tester,
  ) async {
    final controller = await _controller(demoState());
    addTearDown(controller.dispose);
    int? opened;

    await tester.pumpWidget(
      _flatCard(controller, onOpenFleet: (id) => opened = id),
    );
    await tester.pump();

    expect(find.byType(ShipHpFrame), findsNothing);
    expect(find.byType(ShipMoraleMark), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'minimal-ship-row-',
            ),
      ),
      findsNWidgets(6),
    );
    expect(
      find.byKey(const Key('fleet-summary-metric-speed-value')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('minimal-ship-row-1')));
    expect(opened, 1);

    await tester.tap(find.byKey(const Key('fleet-summary-selector-2')));
    await tester.pump();
    expect(find.byKey(const Key('minimal-ship-row-1')), findsNothing);
    expect(find.byKey(const Key('minimal-ship-row-5')), findsOneWidget);
  });

  testWidgets('long names do not overflow at 190dp', (tester) async {
    final base = demoState();
    final state = base.copyWith(
      masterShips: {
        for (final entry in base.masterShips.entries)
          entry.key: MasterShip(
            id: entry.value.id,
            name: 'Very Long Destroyer Name Kai Ni',
            shipTypeId: entry.value.shipTypeId,
            speed: entry.value.speed,
            maxFuel: entry.value.maxFuel,
            maxAmmo: entry.value.maxAmmo,
            slotCount: entry.value.slotCount,
            slotCapacities: entry.value.slotCapacities,
          ),
      },
    );
    final controller = await _controller(state);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _flatCard(
        controller,
        width: 190,
        locale: const Locale('en'),
        visible: {...defaultFields, 'firepower', 'anti-sub'},
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('minimal-ship-row-1')), findsOneWidget);
  });
}
