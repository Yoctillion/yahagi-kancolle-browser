import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_tap_tip.dart';

Future<void> _pump(WidgetTester tester, Widget tip) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(body: Center(child: tip)),
  ),
);

RenderParagraph _paragraphContaining(WidgetTester tester, String text) => tester
    .renderObjectList<RenderParagraph>(find.byType(RichText))
    .firstWhere((p) => p.text.toPlainText().contains(text));

void main() {
  testWidgets('tap shows the tip in a small font', (tester) async {
    await _pump(tester, const BattleTapTip(message: '彩雲', child: Text('x')));
    expect(find.text('彩雲'), findsNothing);

    await tester.tap(find.text('x'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('彩雲'), findsOneWidget);
    final paragraph = _paragraphContaining(tester, '彩雲');
    final span = paragraph.text as TextSpan;
    final fontSize =
        span.style?.fontSize ??
        (span.children?.first as TextSpan).style?.fontSize;
    expect(fontSize, BattleTapTip.fontSize);
    expect(BattleTapTip.fontSize, 10);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('richMessage is rendered', (tester) async {
    await _pump(
      tester,
      const BattleTapTip(
        richMessage: TextSpan(
          text: 'a',
          children: [TextSpan(text: 'b')],
        ),
        child: Text('x'),
      ),
    );

    await tester.tap(find.text('x'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('ab', findRichText: true), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
