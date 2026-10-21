import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/fleet/fleet_ship_minimal_row.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/layout/flat_list_row.dart';
import 'package:yahagi_kancolle_browser/src/layout/game_edge_tap_guard.dart';
import 'package:yahagi_kancolle_browser/src/layout/panel_style.dart';
import 'package:yahagi_kancolle_browser/src/settings/battle_status_effect_settings.dart';
import 'package:yahagi_kancolle_browser/src/settings/fleet_display_options.dart';

Widget _app(PanelGameEdge? edge, Widget child) {
  Widget body = Align(
    alignment: Alignment.topLeft,
    child: SizedBox(width: 200, child: child),
  );
  if (edge != null) body = PanelGameEdgeScope(edge: edge, child: body);
  return MaterialApp(home: Scaffold(body: body));
}

Widget _guardedRow(VoidCallback onTap) => GameEdgeTapGuard(
  child: InkWell(
    onTap: onTap,
    child: const SizedBox(height: 40, width: double.infinity),
  ),
);

Future<void> _tapAt(WidgetTester tester, Finder finder, double dx) async {
  final origin = tester.getTopLeft(finder);
  await tester.tapAt(origin + Offset(dx, 10));
  await tester.pump();
}

void main() {
  testWidgets('左边缘条带内点按不触发，条带外触发', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(PanelGameEdge.left, _guardedRow(() => taps++)),
    );
    final row = find.byType(InkWell);
    await _tapAt(tester, row, 5);
    expect(taps, 0);
    await _tapAt(tester, row, 30);
    expect(taps, 1);
  });

  testWidgets('右边缘镜像成立', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(PanelGameEdge.right, _guardedRow(() => taps++)),
    );
    final row = find.byType(InkWell);
    await _tapAt(tester, row, 195);
    expect(taps, 0);
    await _tapAt(tester, row, 170);
    expect(taps, 1);
  });

  testWidgets('没有 scope 时边缘点按照常触发', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(null, _guardedRow(() => taps++)));
    await _tapAt(tester, find.byType(InkWell), 5);
    expect(taps, 1);
  });

  testWidgets('从条带内开始拖动仍能滚动', (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: PanelGameEdgeScope(
          edge: PanelGameEdge.left,
          child: Scaffold(
            body: SingleChildScrollView(
              controller: controller,
              child: Column(
                children: [for (var i = 0; i < 20; i++) _guardedRow(() {})],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.dragFrom(const Offset(5, 300), const Offset(0, -150));
    await tester.pump();
    expect(controller.offset, greaterThan(0));
  });

  testWidgets('FlatListRow 条带内点按不触发，无 onTap 时不包守卫', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(
        PanelGameEdge.left,
        FlatListRow(onTap: () => taps++, name: const Text('x')),
      ),
    );
    await _tapAt(tester, find.byType(FlatListRow), 5);
    expect(taps, 0);
    await _tapAt(tester, find.byType(FlatListRow), 30);
    expect(taps, 1);

    await tester.pumpWidget(
      _app(PanelGameEdge.left, const FlatListRow(name: Text('x'))),
    );
    expect(find.byType(GameEdgeTapGuard), findsNothing);
  });

  testWidgets('FleetShipMinimalRow 条带内点按不触发', (tester) async {
    var taps = 0;
    final state = GameState.empty.copyWith(
      ships: {
        1: const OwnedShip(
          id: 1,
          masterId: 1,
          level: 1,
          currentHp: 10,
          maxHp: 10,
        ),
      },
    );
    await tester.pumpWidget(
      _app(
        PanelGameEdge.right,
        FleetShipMinimalRow(
          state: state,
          ship: state.ships[1]!,
          visible: defaultFields,
          shipTypeLabelMode: FleetShipTypeLabelMode.localizedName,
          damagePulseFilter: DamagePulseFilter.all,
          moraleSparkleMode: MoraleSparkleMode.blinking,
          onTap: () => taps++,
        ),
      ),
    );
    final row = find.byType(FleetShipMinimalRow);
    await _tapAt(tester, row, 195);
    expect(taps, 0);
    await _tapAt(tester, row, 100);
    expect(taps, 1);
  });
}
