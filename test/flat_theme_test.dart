import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/layout/flat_list_row.dart';
import 'package:yahagi_kancolle_browser/src/layout/flat_portrait_backdrop.dart';
import 'package:yahagi_kancolle_browser/src/layout/flat_style.dart';
import 'package:yahagi_kancolle_browser/src/layout/flat_text_toggle.dart';
import 'package:yahagi_kancolle_browser/src/theme/app_palette.dart';
import 'package:yahagi_kancolle_browser/src/theme/app_theme.dart';

Future<BuildContext> _pumpTheme(WidgetTester tester, AppThemeMode mode) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: createAppTheme(mode: mode),
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox();
        },
      ),
    ),
  );
  // 切换主题有过渡动画，结束后取到的才是目标主题。
  await tester.pumpAndSettle();
  return captured;
}

void main() {
  testWidgets('扁平行文字在浅色主题下映射为前景色，深色主题保持原色', (tester) async {
    for (final mode in AppThemeMode.values) {
      final context = await _pumpTheme(tester, mode);
      final palette = AppPalette.of(context);
      final text = flatRowText(context, 'A') as Text;
      expect(
        text.style?.color,
        palette.isDark ? Colors.white : palette.foreground,
        reason: mode.name,
      );
    }
  });

  testWidgets('立绘上的描边在浅色主题下改用面板底色', (tester) async {
    for (final mode in AppThemeMode.values) {
      final context = await _pumpTheme(tester, mode);
      final palette = AppPalette.of(context);
      expect(
        flatOnImageShadows(context).single.color,
        palette.isDark ? Colors.black : palette.surface,
        reason: mode.name,
      );
    }
  });

  testWidgets('富文本的每个子片段都跟随主题', (tester) async {
    final context = await _pumpTheme(tester, AppThemeMode.seaSalt);
    final palette = AppPalette.of(context);
    final span =
        appTextSpan(
              context,
              const TextSpan(
                style: TextStyle(color: Colors.white),
                children: [
                  TextSpan(
                    text: 'a',
                    style: TextStyle(color: flatMutedColor),
                  ),
                ],
              ),
            )
            as TextSpan;
    expect(span.style?.color, palette.foreground);
    expect((span.children!.single as TextSpan).style?.color, palette.muted);

    final dark = await _pumpTheme(tester, AppThemeMode.dark);
    const original = TextSpan(style: TextStyle(color: Colors.white));
    expect(appTextSpan(dark, original), same(original));
  });

  testWidgets('文字切换的选中色在浅色主题下用主题强调色', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: createAppTheme(mode: AppThemeMode.skyBlue),
        home: Scaffold(
          body: FlatTextToggle(
            options: [
              FlatTextToggleOption(
                key: const Key('a'),
                label: 'A',
                selected: true,
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
    final palette = AppPalette.forMode(AppThemeMode.skyBlue);
    expect(tester.widget<Text>(find.text('A')).style?.color, palette.accent);
  });
}
