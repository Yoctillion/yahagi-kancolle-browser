import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/battle/flat_battle_header.dart';
import 'package:yahagi_kancolle_browser/src/layout/panel_style.dart';

const _mapBody = Key('test-map-body');
const _node = Key('flat-battle-header-node');

Future<void> _pump(
  WidgetTester tester, {
  required bool expanded,
  double textScale = 1,
}) => tester.pumpWidget(
  MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 210,
          child: PanelStyleScope(
            style: PanelStyle.flat,
            child: FlatBattleHeader(
              nodeIcon: const SizedBox.square(
                key: Key('test-node-icon'),
                dimension: 16,
              ),
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

    expect(find.byKey(_mapBody), findsNothing);
    final header = tester.getTopLeft(find.byType(FlatBattleHeader)).dy;
    // The letter may sit up to a pixel lower to meet the icon's center.
    expect(tester.getTopLeft(find.byKey(_node)).dy - header, lessThan(2));
    expect(
      tester.getBottomLeft(find.byKey(_node)).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.text('制空：确保')).dy),
    );
  });

  for (final scale in <double>[1, 1.5]) {
    testWidgets('node icon centers on the node letter caps ($scale)', (
      tester,
    ) async {
      await _pump(tester, expanded: false, textScale: scale);

      final rich = find.descendant(
        of: find.byKey(_node),
        matching: find.byType(RichText),
      );
      final widget = tester.widget<RichText>(rich);
      final painter = TextPainter(
        text: widget.text,
        textDirection: TextDirection.ltr,
        textScaler: widget.textScaler,
      )..layout();
      final baseline =
          tester.getTopLeft(rich).dy +
          painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      painter.dispose();
      final capCenter =
          baseline -
          FlatBattleHeader.capHeightEm *
              TextScaler.linear(scale).scale(FlatBattleHeader.nodeFontSize) /
              2;
      expect(
        tester.getCenter(find.byKey(const Key('test-node-icon'))).dy,
        moreOrLessEquals(capCenter, epsilon: 0.5),
      );
    });
  }
}
