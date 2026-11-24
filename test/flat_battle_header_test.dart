import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/battle/flat_battle_header.dart';
import 'package:yahagi_kancolle_browser/src/layout/panel_style.dart';

const _mapBody = Key('test-map-body');
const _node = Key('flat-battle-header-node');

Future<void> _pump(WidgetTester tester, {required bool expanded}) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 210,
              child: PanelStyleScope(
                style: PanelStyle.flat,
                child: FlatBattleHeader(
                  nodeIcon: const SizedBox.square(dimension: 16),
                  nodeLabel: 'K',
                  enemyName: '深海潜水艦隊集団 旗艦戦隊',
                  mapBody: expanded
                      ? const SizedBox(key: _mapBody, height: 80)
                      : null,
                  details: const <Widget>[Text('制空：确保')],
                ),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('expanded map sits above the title row', (tester) async {
    await _pump(tester, expanded: true);

    expect(
      tester.getBottomLeft(find.byKey(_mapBody)).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byKey(_node)).dy),
    );
    expect(
      tester.getTopLeft(find.byKey(_node)).dy,
      lessThan(tester.getTopLeft(find.text('制空：确保')).dy),
    );
  });

  testWidgets('collapsed header keeps the title row on top', (tester) async {
    await _pump(tester, expanded: false);
    final collapsedTop = tester.getTopLeft(find.byKey(_node)).dy;

    expect(collapsedTop, tester.getTopLeft(find.byType(FlatBattleHeader)).dy);
  });
}
