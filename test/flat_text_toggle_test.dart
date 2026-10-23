import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/fleet/expedition_summary_card.dart';
import 'package:yahagi_kancolle_browser/src/fleet/pre_sortie_check_summary.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/layout/flat_text_toggle.dart';
import 'package:yahagi_kancolle_browser/src/layout/panel_style.dart';

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

void _expectNoSurface(WidgetTester tester, Finder within) {
  for (final box in tester.widgetList<DecoratedBox>(
    find.descendant(of: within, matching: find.byType(DecoratedBox)),
  )) {
    final d = box.decoration;
    expect(
      d is BoxDecoration &&
          (d.color != null || d.border != null || d.borderRadius != null),
      isFalse,
    );
  }
  for (final m in tester.widgetList<Material>(
    find.descendant(of: within, matching: find.byType(Material)),
  )) {
    expect(m.color == null || m.color == Colors.transparent, isTrue);
  }
}

void main() {
  testWidgets('FlatTextToggle 选中金色、无装饰、点击回调', (tester) async {
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
    _expectNoSurface(tester, t);
    await tester.tap(find.byKey(const Key('a')));
    expect(taps, 1);
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
    _expectNoSurface(tester, s);
    await tester.tap(find.byKey(const Key('expedition-mode-check')));
    await tester.pump();
    expect(mode, ExpeditionSummaryMode.check);
    expect(_textColor(tester, s, '检查'), _gold);
    expect(_textColor(tester, s, '进度'), _grey);
  });

  testWidgets('ExpeditionModeSelector 卡片档保持带底色', (tester) async {
    await tester.pumpWidget(
      _host(
        ExpeditionModeSelector(
          mode: ExpeditionSummaryMode.summary,
          compact: true,
          summaryLabel: '进度',
          checkLabel: '检查',
          onChanged: (_) {},
        ),
        style: PanelStyle.card,
      ),
    );
    final box = tester.widget<Container>(
      find.byKey(const Key('expedition-summary-mode-selector')),
    );
    expect((box.decoration as BoxDecoration).color, isNotNull);
  });

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
    _expectNoSurface(tester, s);
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
  });
}
