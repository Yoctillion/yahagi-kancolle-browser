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

Widget _app(
  Widget child, {
  Locale locale = const Locale('zh'),
  TextScaler textScaler = TextScaler.noScaling,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: textScaler),
    child: child!,
  ),
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
  double width = 320,
}) => SizedBox(
  width: width,
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

GameState _largeStatusState({bool hasMaster = true}) =>
    GameState.empty.copyWith(
      masterShips: {
        if (hasMaster)
          1: const MasterShip(
            id: 1,
            name: '艦娘',
            shipTypeId: 2,
            maxFuel: 9999,
            maxAmmo: 8888,
          ),
      },
      ships: {
        1: const OwnedShip(
          id: 1,
          masterId: 1,
          level: 1,
          currentHp: 123,
          maxHp: 999,
          currentFuel: 4567,
          currentAmmo: 2345,
          condition: 49,
        ),
      },
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
  testWidgets('morale chip stays content sized beside status tags', (
    tester,
  ) async {
    final state = _mechanismState();
    for (final width in [320.0, 640.0]) {
      await tester.pumpWidget(_app(_row(state, 1, width: width)));
      await tester.pump();

      final info = tester.getRect(
        find.byKey(const Key('minimal-status-info-1')),
      );
      final morale = tester.getRect(find.byKey(const Key('minimal-morale-1')));
      expect(morale.width, inInclusiveRange(28, 50));
      expect(morale.width, lessThan(info.width / 2));
      for (final tag in [
        find.text('高速'),
        find.byKey(const Key('minimal-mechanism-1-openingAsw')),
      ]) {
        final rect = tester.getRect(tag);
        expect(rect.left, greaterThanOrEqualTo(morale.right));
        expect(rect.center.dy, closeTo(morale.center.dy, .01));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('status info remains one line in narrow cells', (tester) async {
    final state = _mechanismState();
    for (final width in [160.0, 190.0]) {
      await tester.pumpWidget(
        _app(_row(state, 1, width: width, repairStatus: ShipRepairStatus.dock)),
      );
      await tester.pump();

      final info = tester.getRect(
        find.byKey(const Key('minimal-status-info-1')),
      );
      final morale = tester.getRect(find.byKey(const Key('minimal-morale-1')));
      for (final tag in [
        find.text('高速'),
        find.byKey(const Key('minimal-mechanism-1-openingAsw')),
        find.byKey(const Key('minimal-repair-1')),
      ]) {
        expect(tag, findsOneWidget);
        final rect = tester.getRect(tag);
        expect(rect.center.dy, closeTo(morale.center.dy, .01));
        expect(rect.left, greaterThanOrEqualTo(morale.right));
        expect(rect.right, lessThanOrEqualTo(info.right + .01));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('fixed status grid keeps info above hp below identity', (
    tester,
  ) async {
    final state = _mechanismState();
    for (final width in [320.0, 640.0]) {
      await tester.pumpWidget(
        _app(_row(state, 1, width: width, repairStatus: ShipRepairStatus.dock)),
      );
      await tester.pump();

      final name = tester.getRect(find.byKey(const Key('minimal-name-1')));
      final hp = tester.getRect(find.byKey(const Key('minimal-hp-value-1')));
      final level = tester.getRect(find.text('Lv76'));
      expect(level.center.dy, closeTo(name.center.dy, .01));
      for (final info in [
        find.byKey(const Key('minimal-morale-1')),
        find.text('高速'),
        find.byKey(const Key('minimal-mechanism-1-openingAsw')),
        find.byKey(const Key('minimal-repair-1')),
      ]) {
        expect(info, findsOneWidget);
        final rect = tester.getRect(info);
        expect(rect.top, greaterThanOrEqualTo(name.bottom));
        expect(rect.bottom, lessThanOrEqualTo(hp.top));
        expect(
          rect.right,
          lessThanOrEqualTo(
            tester
                .getRect(find.byKey(const Key('minimal-status-info-1')))
                .right,
          ),
        );
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('fixed status grid keeps supply stacked beside info and hp', (
    tester,
  ) async {
    final state = demoState();
    for (final width in [320.0, 640.0]) {
      await tester.pumpWidget(_app(_row(state, 2, width: width)));
      await tester.pump();

      final fuel = tester.getRect(
        find.byKey(const Key('minimal-supply-fuel-value-2')),
      );
      final ammo = tester.getRect(
        find.byKey(const Key('minimal-supply-ammo-value-2')),
      );
      final hp = tester.getRect(find.byKey(const Key('minimal-hp-value-2')));
      expect(fuel.left, closeTo(ammo.left, .01));
      expect(fuel.bottom, lessThanOrEqualTo(ammo.top));
      expect(hp.right, lessThan(fuel.left));
      final infoCell = tester.getRect(
        find.byKey(const Key('minimal-status-info-2')),
      );
      final hpCell = tester.getRect(
        find.byKey(const Key('minimal-status-hp-2')),
      );
      final fuelCell = tester.getRect(
        find.byKey(const Key('minimal-status-fuel-2')),
      );
      final ammoCell = tester.getRect(
        find.byKey(const Key('minimal-status-ammo-2')),
      );
      expect(infoCell.top, closeTo(fuelCell.top, .01));
      expect(hpCell.top, closeTo(ammoCell.top, .01));
      expect(infoCell.bottom, lessThanOrEqualTo(hpCell.top));
      expect(fuelCell.left, closeTo(ammoCell.left, .01));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'metadata stays visible when all numeric status fields are hidden',
    (tester) async {
      await tester.pumpWidget(
        _app(_row(_mechanismState(), 1, visible: {'shipSpeed', 'mechanisms'})),
      );
      await tester.pump();

      final info = find.byKey(const Key('minimal-status-info-1'));
      expect(info, findsOneWidget);
      expect(
        find.descendant(of: info, matching: find.text('高速')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: info,
          matching: find.byKey(const Key('minimal-mechanism-1-openingAsw')),
        ),
        findsOneWidget,
      );
      for (final field in ['hp', 'fuel', 'ammo']) {
        expect(find.byKey(Key('minimal-status-$field-1')), findsNothing);
      }
      expect(find.byKey(const Key('minimal-morale-1')), findsNothing);
      final row = tester.getRect(find.byKey(const Key('minimal-ship-row-1')));
      expect(tester.getRect(info).left, closeTo(row.left + 2, .01));
      expect(tester.getRect(info).right, closeTo(row.right - 2, .01));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('status meters fill available cells after icons and values', (
    tester,
  ) async {
    final state = demoState();
    var previousWidths = <double>[];
    for (final width in [320.0, 640.0]) {
      await tester.pumpWidget(
        _app(
          _row(
            state,
            2,
            width: width,
            visible: {'hp', 'fuel', 'ammo', 'morale', 'bars'},
          ),
        ),
      );
      await tester.pump();

      final rowRect = tester.getRect(
        find.byKey(const Key('minimal-ship-row-2')),
      );
      final tracks = [
        find.byKey(const Key('minimal-hp-track-2')),
        find.byKey(const Key('minimal-supply-fuel-2')),
        find.byKey(const Key('minimal-supply-ammo-2')),
      ];
      final values = [
        find.byKey(const Key('minimal-hp-value-2')),
        find.byKey(const Key('minimal-supply-fuel-value-2')),
        find.byKey(const Key('minimal-supply-ammo-value-2')),
      ];
      final icons = [
        find.byKey(const Key('minimal-hp-icon-2')),
        find.byKey(const Key('minimal-supply-fuel-icon-2')),
        find.byKey(const Key('minimal-supply-ammo-icon-2')),
      ];
      final fields = ['hp', 'fuel', 'ammo'];
      final widths = <double>[];
      for (var i = 0; i < tracks.length; i++) {
        expect(icons[i], findsOneWidget);
        expect(values[i], findsOneWidget);
        expect(tracks[i], findsOneWidget);
        final icon = tester.getRect(icons[i]);
        final value = tester.getRect(values[i]);
        final track = tester.getRect(tracks[i]);
        expect(icon.right, lessThanOrEqualTo(value.left));
        expect(value.right, lessThanOrEqualTo(track.left));
        expect(track.left, greaterThanOrEqualTo(rowRect.left));
        expect(track.right, lessThanOrEqualTo(rowRect.right));
        final cell = tester.getRect(
          find.byKey(Key('minimal-status-${fields[i]}-2')),
        );
        expect(track.right, closeTo(cell.right, .01));
        widths.add(track.width);
        if (previousWidths.isNotEmpty) {
          expect(track.width, greaterThan(previousWidths[i]));
        }
      }
      previousWidths = widths;
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('narrow status rows keep large numbers readable at text scales', (
    tester,
  ) async {
    final state = _largeStatusState();
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final width in [160.0, 190.0, 240.0, 300.0, 400.0]) {
        await tester.pumpWidget(
          _app(
            _row(
              state,
              1,
              width: width,
              visible: {'hp', 'fuel', 'ammo', 'morale', 'bars'},
            ),
            textScaler: TextScaler.linear(scale),
          ),
        );
        await tester.pump();

        final rowRect = tester.getRect(
          find.byKey(const Key('minimal-ship-row-1')),
        );
        for (final key in [
          'minimal-hp-value-1',
          'minimal-supply-fuel-value-1',
          'minimal-supply-ammo-value-1',
        ]) {
          final value = find.byKey(Key(key));
          expect(value, findsOneWidget);
          final text = tester.widget<Text>(value);
          final actual = tester.getRect(value);
          final measured = TextPainter(
            text: TextSpan(
              text: text.data,
              style: DefaultTextStyle.of(
                tester.element(value),
              ).style.merge(text.style),
            ),
            textDirection: TextDirection.ltr,
            textScaler: TextScaler.linear(scale),
            maxLines: text.maxLines,
          )..layout(maxWidth: actual.width);
          expect(actual.width, closeTo(measured.width, .05));
          expect(actual.height, closeTo(measured.height, .05));
          expect(actual.left, greaterThanOrEqualTo(rowRect.left));
          expect(actual.right, lessThanOrEqualTo(rowRect.right));
          expect(actual.bottom, lessThanOrEqualTo(rowRect.bottom));
          expect(
            find.ancestor(of: value, matching: find.byType(FittedBox)),
            findsNothing,
          );
        }
        // A track also fills its cell when a narrow value puts it below the label.
        for (final field in ['hp', 'fuel', 'ammo']) {
          final track = tester.getRect(
            find.byKey(
              Key(
                field == 'hp'
                    ? 'minimal-hp-track-1'
                    : 'minimal-supply-$field-1',
              ),
            ),
          );
          final cell = tester.getRect(
            find.byKey(Key('minimal-status-$field-1')),
          );
          expect(track.right, closeTo(cell.right, .01));
        }
        if (width <= 190) {
          final hp = tester.getRect(
            find.byKey(const Key('minimal-hp-value-1')),
          );
          final fuel = tester.getRect(
            find.byKey(const Key('minimal-supply-fuel-value-1')),
          );
          expect(fuel.left, greaterThanOrEqualTo(hp.right));
          expect(fuel.top, lessThan(hp.top));
        }
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('missing masters and hidden status fields keep their contract', (
    tester,
  ) async {
    final state = _largeStatusState(hasMaster: false);
    await tester.pumpWidget(
      _app(_row(state, 1, width: 190, visible: {'fuel', 'ammo', 'bars'})),
    );
    await tester.pump();
    expect(find.text('4567/0'), findsOneWidget);
    expect(find.text('2345/0'), findsOneWidget);
    expect(find.byKey(const Key('minimal-hp-value-1')), findsNothing);
    expect(find.byKey(const Key('minimal-hp-icon-1')), findsNothing);
    expect(find.byKey(const Key('minimal-hp-track-1')), findsNothing);
    expect(find.byKey(const Key('minimal-morale-1')), findsNothing);
    expect(find.byKey(const Key('minimal-status-info-1')), findsNothing);
    final supplyOnlyRow = tester.getRect(
      find.byKey(const Key('minimal-ship-row-1')),
    );
    for (final field in ['fuel', 'ammo']) {
      final cell = tester.getRect(find.byKey(Key('minimal-status-$field-1')));
      expect(cell.left, closeTo(supplyOnlyRow.left + 2, .01));
      expect(cell.right, closeTo(supplyOnlyRow.right - 2, .01));
    }
    expect(find.byType(DamagePulseGlow), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      _app(_row(state, 1, width: 190, visible: {'hp', 'bars'})),
    );
    await tester.pump();
    for (final field in ['fuel', 'ammo']) {
      expect(find.byKey(Key('minimal-supply-$field-value-1')), findsNothing);
      expect(find.byKey(Key('minimal-supply-$field-icon-1')), findsNothing);
      expect(find.byKey(Key('minimal-supply-$field-1')), findsNothing);
      expect(find.byKey(Key('minimal-status-$field-1')), findsNothing);
    }
    expect(find.byKey(const Key('minimal-morale-1')), findsNothing);
    expect(find.byKey(const Key('minimal-hp-value-1')), findsOneWidget);
    final hpOnlyRow = tester.getRect(
      find.byKey(const Key('minimal-ship-row-1')),
    );
    final hpOnlyCell = tester.getRect(
      find.byKey(const Key('minimal-status-hp-1')),
    );
    expect(hpOnlyCell.left, closeTo(hpOnlyRow.left + 2, .01));
    expect(hpOnlyCell.right, closeTo(hpOnlyRow.right - 2, .01));
    expect(find.byType(DamagePulseGlow), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
          visible: defaultFields.difference({
            'hp',
            'fuel',
            'ammo',
            'morale',
            'shipSpeed',
            'mechanisms',
          }),
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
    // 隐藏数值后的警告仍在左上信息格，位于舰名下方、HP 上方。
    final morale = tester.getRect(find.byKey(const Key('minimal-morale-4')));
    expect(
      morale.top,
      greaterThanOrEqualTo(
        tester.getRect(find.byKey(const Key('minimal-name-4'))).bottom,
      ),
    );
    expect(
      morale.bottom,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const Key('minimal-status-hp-4'))).top,
      ),
    );
    expect(
      morale.right,
      lessThan(
        tester.getRect(find.byKey(const Key('minimal-status-fuel-4'))).left,
      ),
    );

    await pumpRows(MoraleSparkleMode.off);
    expect(find.byKey(const Key('minimal-morale-1')), findsNothing);
    expect(find.byKey(const Key('minimal-morale-4')), findsOneWidget);
  });

  testWidgets('fixed status grid keeps plain values when bars are hidden', (
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
      // 关条只隐藏条形，数值仍留在各自的格子中。
      expect(
        tester.getRect(hp).left,
        lessThan(tester.getRect(row).left + width * .3),
      );
      expect(tester.getRect(fuel).left, greaterThan(tester.getRect(hp).right));
      expect(
        tester.getRect(ammo).left,
        closeTo(tester.getRect(fuel).left, .01),
      );
      expect(
        tester.getRect(fuel).bottom,
        lessThanOrEqualTo(tester.getRect(ammo).top),
      );
      expect(
        tester.getRect(find.byKey(const Key('minimal-status-hp-2'))).top,
        closeTo(
          tester.getRect(find.byKey(const Key('minimal-status-ammo-2'))).top,
          .01,
        ),
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
