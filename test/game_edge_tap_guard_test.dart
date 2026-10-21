import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/fleet/fleet_ship_minimal_row.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/layout/flat_list_row.dart';
import 'package:yahagi_kancolle_browser/src/layout/game_edge_tap_guard.dart';
import 'package:yahagi_kancolle_browser/src/layout/panel_style.dart';
import 'package:yahagi_kancolle_browser/src/settings/battle_status_effect_settings.dart';
import 'package:yahagi_kancolle_browser/src/settings/fleet_display_options.dart';
import 'package:yahagi_kancolle_browser/src/settings/module_display_settings.dart';

/// 宽 200 的信息栏；有 edge 时 scope 就是信息栏根节点。
Widget _app(PanelGameEdge? edge, Widget child) {
  Widget panel = SizedBox(width: 200, child: child);
  if (edge != null) panel = PanelGameEdgeScope(edge: edge, child: panel);
  return MaterialApp(
    home: Scaffold(
      body: Align(alignment: Alignment.topLeft, child: panel),
    ),
  );
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
  test('游戏所在侧按横竖屏与信息栏位置推出', () {
    for (final infoOnLeft in [true, false]) {
      expect(
        panelGameEdgeFor(isLandscape: false, infoOnLeft: infoOnLeft),
        PanelGameEdge.none,
      );
    }
    expect(
      panelGameEdgeFor(isLandscape: true, infoOnLeft: true),
      PanelGameEdge.right,
    );
    expect(
      panelGameEdgeFor(isLandscape: true, infoOnLeft: false),
      PanelGameEdge.left,
    );
  });

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

  for (final edge in [PanelGameEdge.left, PanelGameEdge.right]) {
    testWidgets('两列格子按信息栏边缘判定（游戏在 ${edge.name}）', (tester) async {
      var leftTaps = 0;
      var rightTaps = 0;
      await tester.pumpWidget(
        _app(
          edge,
          PanelStyleScope(
            style: PanelStyle.flat,
            child: ModuleSlotGrid(
              emptyLabel: '',
              children: [
                FlatListRow(
                  key: const Key('left-cell'),
                  onTap: () => leftTaps++,
                  name: const Text('a'),
                ),
                FlatListRow(
                  key: const Key('right-cell'),
                  onTap: () => rightTaps++,
                  name: const Text('b'),
                ),
              ],
            ),
          ),
        ),
      );
      final leftCell = find.byKey(const Key('left-cell'));
      final rightCell = find.byKey(const Key('right-cell'));
      final leftWidth = tester.getSize(leftCell).width;
      expect(leftWidth, lessThan(100));
      expect(tester.getTopLeft(rightCell).dx, greaterThan(100));

      // 靠中缝的内侧边缘点按照常触发。
      await _tapAt(tester, leftCell, leftWidth - 4);
      await _tapAt(tester, rightCell, 4);
      expect(leftTaps, 1);
      expect(rightTaps, 1);

      // 离信息栏靠游戏一侧 15dp：已超出单元格自身的 12dp，但仍在防误触边内。
      final outerCell = edge == PanelGameEdge.left ? leftCell : rightCell;
      final outerOrigin = tester.getTopLeft(outerCell).dx;
      final stripX = edge == PanelGameEdge.left ? 15.0 : 200 - 15.0;
      final clearX = edge == PanelGameEdge.left ? 25.0 : 200 - 25.0;
      await _tapAt(tester, outerCell, stripX - outerOrigin);
      expect(leftTaps + rightTaps, 2);
      await _tapAt(tester, outerCell, clearX - outerOrigin);
      expect(leftTaps + rightTaps, 3);
    });
  }

  testWidgets('scope 为 none 时边缘点按照常触发', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(PanelGameEdge.none, _guardedRow(() => taps++)),
    );
    await _tapAt(tester, find.byType(InkWell), 5);
    await _tapAt(tester, find.byType(InkWell), 195);
    expect(taps, 2);
  });

  testWidgets('切换游戏所在侧不重建行内状态', (tester) async {
    Widget build(PanelGameEdge edge) =>
        _app(edge, const GameEdgeTapGuard(child: TextField()));
    await tester.pumpWidget(build(PanelGameEdge.none));
    final before = tester.state(find.byType(EditableText));
    await tester.pumpWidget(build(PanelGameEdge.left));
    expect(tester.state(find.byType(EditableText)), same(before));
    await tester.pumpWidget(build(PanelGameEdge.right));
    expect(tester.state(find.byType(EditableText)), same(before));
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
