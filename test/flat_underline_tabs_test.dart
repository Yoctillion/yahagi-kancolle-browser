import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/layout/flat_style.dart';
import 'package:yahagi_kancolle_browser/src/layout/flat_text_toggle.dart';
import 'package:yahagi_kancolle_browser/src/layout/flat_underline_tabs.dart';

void main() {
  testWidgets('选中项金色下划线、等宽平分，按下高亮画在自带的透明 Material 上', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            child: FlatUnderlineTabs(
              key: const Key('tabs'),
              options: [
                FlatTextToggleOption(
                  key: const Key('a'),
                  label: 'A',
                  selected: true,
                  onTap: () {},
                ),
                FlatTextToggleOption(
                  key: const Key('b'),
                  label: 'B',
                  selected: false,
                  onTap: () => taps++,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Border border(String key) =>
        (tester
                        .widget<DecoratedBox>(
                          find.descendant(
                            of: find.byKey(Key(key)),
                            matching: find.byType(DecoratedBox),
                          ),
                        )
                        .decoration
                    as BoxDecoration)
                .border!
            as Border;
    expect(border('a').bottom.color, flatAccentColor);
    expect(border('b').bottom.color, Colors.transparent);
    expect(tester.widget<Text>(find.text('A')).style?.color, flatAccentColor);
    expect(tester.widget<Text>(find.text('B')).style?.color, flatMutedColor);
    expect(
      tester.getSize(find.byKey(const Key('a'))).width,
      tester.getSize(find.byKey(const Key('b'))).width,
    );

    final inkMaterial = tester.widget<Material>(
      find
          .ancestor(
            of: find.byKey(const Key('a')),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(inkMaterial.type, MaterialType.transparency);
    expect(
      find.descendant(
        of: find.byKey(const Key('tabs')),
        matching: find.byWidget(inkMaterial),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('b')));
    expect(taps, 1);
  });
}
