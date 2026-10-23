import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/fleet/expedition_summary_card.dart';
import 'package:yahagi_kancolle_browser/src/fleet/pre_sortie_check_summary.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/layout/flat_text_toggle.dart';
import 'package:yahagi_kancolle_browser/src/layout/panel_style.dart';
import 'package:yahagi_kancolle_browser/src/theme/app_palette.dart';
import 'package:yahagi_kancolle_browser/src/theme/app_theme.dart';

const _gold = Color(0xffd4a85f);
const _grey = Color(0xff8197a5);

Widget _host(Widget child, {PanelStyle style = PanelStyle.flat}) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: PanelStyleScope(
      style: style,
      child: Center(child: child),
    ),
  ),
);

Color? _textColor(WidgetTester tester, Finder within, String text) => tester
    .widget<Text>(find.descendant(of: within, matching: find.text(text)))
    .style
    ?.color;

Border _underline(WidgetTester tester, Key option) =>
    (tester
                    .widget<DecoratedBox>(
                      find.descendant(
                        of: find.byKey(option),
                        matching: find.byType(DecoratedBox),
                      ),
                    )
                    .decoration
                as BoxDecoration)
            .border!
        as Border;

void _expectOnlyUnderline(WidgetTester tester, Finder within) {
  for (final box in tester.widgetList<DecoratedBox>(
    find.descendant(of: within, matching: find.byType(DecoratedBox)),
  )) {
    final d = box.decoration as BoxDecoration;
    expect(d.color, isNull);
    expect(d.borderRadius, isNull);
    final border = d.border! as Border;
    expect(border.top, BorderSide.none);
    expect(border.left, BorderSide.none);
    expect(border.right, BorderSide.none);
    expect(border.bottom.width, 2);
  }
  for (final m in tester.widgetList<Material>(
    find.descendant(of: within, matching: find.byType(Material)),
  )) {
    expect(m.color == null || m.color == Colors.transparent, isTrue);
  }
}

void main() {
  testWidgets('FlatTextToggle 选中金色底线、无底色，保留行高与点击回调', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        FlatTextToggle(
          key: const Key('t'),
          options: [
            FlatTextToggleOption(
              key: const Key('a'),
              label: 'A',
              selected: true,
              onTap: () => taps++,
            ),
            FlatTextToggleOption(
              key: const Key('b'),
              label: 'B',
              selected: false,
              onTap: () {},
            ),
          ],
        ),
      ),
    );
    final t = find.byKey(const Key('t'));
    expect(_textColor(tester, t, 'A'), _gold);
    expect(_textColor(tester, t, 'B'), _grey);
    expect(tester.widget<Text>(find.text('A')).style?.fontSize, 10.5);
    expect(_underline(tester, const Key('a')).bottom.color, _gold);
    expect(_underline(tester, const Key('b')).bottom.color, Colors.transparent);
    expect(
      tester.getSize(find.byKey(const Key('a'))).height,
      tester.getSize(find.text('A')).height + 6,
    );
    _expectOnlyUnderline(tester, t);
    await tester.tap(find.byKey(const Key('a')));
    expect(taps, 1);
  });

  testWidgets('FlatTextToggle 窄宽换行保持选中底线且不溢出', (tester) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          key: const Key('narrow-toggle-host'),
          width: 72,
          child: FlatTextToggle(
            options: [
              for (final label in ['Summary', 'Check', 'Expedition plans'])
                FlatTextToggleOption(
                  key: Key(label),
                  label: label,
                  selected: label == 'Check',
                  onTap: () {},
                ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final host = tester.getRect(find.byKey(const Key('narrow-toggle-host')));
    for (final label in ['Summary', 'Check', 'Expedition plans']) {
      final rect = tester.getRect(find.byKey(Key(label)));
      expect(rect.left, greaterThanOrEqualTo(host.left));
      expect(rect.right, lessThanOrEqualTo(host.right));
    }
    expect(
      tester.getTopLeft(find.byKey(const Key('Check'))).dy,
      greaterThan(tester.getTopLeft(find.byKey(const Key('Summary'))).dy),
    );
    expect(_underline(tester, const Key('Check')).bottom.color, _gold);
  });

  testWidgets('FlatTextToggle 浅色主题的底线与文字使用同一强调色', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: createAppTheme(mode: AppThemeMode.skyBlue),
        home: Scaffold(
          body: FlatTextToggle(
            options: [
              FlatTextToggleOption(
                key: const Key('themed-option'),
                label: '进度',
                selected: true,
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      _underline(tester, const Key('themed-option')).bottom.color,
      AppPalette.forMode(AppThemeMode.skyBlue).accent,
    );
  });

  testWidgets('ExpeditionModeSelector 扁平下为文字切换', (tester) async {
    var mode = ExpeditionSummaryMode.summary;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => ExpeditionModeSelector(
            mode: mode,
            compact: true,
            summaryLabel: '进度',
            checkLabel: '检查',
            onChanged: (m) => setState(() => mode = m),
          ),
        ),
      ),
    );
    final s = find.byKey(const Key('expedition-summary-mode-selector'));
    expect(s, findsOneWidget);
    expect(_textColor(tester, s, '进度'), _gold);
    expect(
      _underline(tester, const Key('expedition-mode-summary')).bottom.color,
      _gold,
    );
    expect(
      _underline(tester, const Key('expedition-mode-check')).bottom.color,
      Colors.transparent,
    );
    _expectOnlyUnderline(tester, s);
    await tester.tap(find.byKey(const Key('expedition-mode-check')));
    await tester.pump();
    expect(mode, ExpeditionSummaryMode.check);
    expect(_textColor(tester, s, '检查'), _gold);
    expect(_textColor(tester, s, '进度'), _grey);
    expect(
      _underline(tester, const Key('expedition-mode-summary')).bottom.color,
      Colors.transparent,
    );
    expect(
      _underline(tester, const Key('expedition-mode-check')).bottom.color,
      _gold,
    );
  });

  for (final compact in [false, true]) {
    testWidgets('ExpeditionModeSelector 卡片档保持带底色与原行高 (compact=$compact)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          ExpeditionModeSelector(
            mode: ExpeditionSummaryMode.summary,
            compact: compact,
            summaryLabel: '进度',
            checkLabel: '检查',
            onChanged: (_) {},
          ),
          style: PanelStyle.card,
        ),
      );
      final selector = find.byKey(
        const Key('expedition-summary-mode-selector'),
      );
      final box = tester.widget<Container>(selector);
      expect((box.decoration as BoxDecoration).color, isNotNull);
      expect(tester.getSize(selector).height, compact ? 26 : 38);
      expect(find.byType(FlatTextToggle), findsNothing);
    });
  }

  testWidgets('出击检查模式选择器扁平下为文字切换', (tester) async {
    final controller = GameStateController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 400,
          child: PreSortieCheckSummary(
            controller: controller,
            collapsed: false,
            onToggleCollapse: () {},
            onOpenFleet: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final s = find.byKey(const Key('sortie-check-mode-selector'));
    expect(s, findsOneWidget);
    _expectOnlyUnderline(tester, s);
    final maps = find.byKey(const Key('sortie-check-mode-maps'));
    await tester.tap(maps);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.descendant(of: maps, matching: find.byType(Text)))
          .style
          ?.color,
      _gold,
    );
    expect(
      _underline(tester, const Key('sortie-check-mode-maps')).bottom.color,
      _gold,
    );
  });
}
