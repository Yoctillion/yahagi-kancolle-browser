import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/fleet/dashboard_card.dart';
import 'package:yahagi_kancolle_browser/src/layout/panel_style.dart';

Widget _host({
  required PanelStyle? style,
  required bool collapsed,
  String? summary,
}) {
  Widget card = DashboardCard(
    title: '舰队',
    icon: const Icon(Icons.sailing),
    collapsed: collapsed,
    onToggleCollapse: () {},
    collapsedSummary: summary,
    trailing: const Text('切换器', key: Key('card-trailing')),
    child: const SizedBox(height: 20),
  );
  if (style != null) card = PanelStyleScope(style: style, child: card);
  return MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 300, child: card),
      ),
    ),
  );
}

void main() {
  testWidgets('flat 样式没有卡片底色且标题行不超过 26', (tester) async {
    await tester.pumpWidget(_host(style: PanelStyle.flat, collapsed: false));
    final colored = tester.widgetList<Container>(find.byType(Container)).where((
      c,
    ) {
      final d = c.decoration;
      return d is BoxDecoration && d.color == const Color(0xff142735);
    });
    expect(colored, isEmpty);
    final boxes = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .where(
          (b) =>
              b.decoration is BoxDecoration &&
              (b.decoration as BoxDecoration).color == const Color(0xff142735),
        );
    expect(boxes, isEmpty);
    final header = tester.getSize(
      find.byKey(const Key('dashboard-card-header')),
    );
    expect(header.height, lessThanOrEqualTo(26));
  });

  testWidgets('flat 折叠时显示摘要', (tester) async {
    await tester.pumpWidget(
      _host(style: PanelStyle.flat, collapsed: true, summary: '3 队 · 满血'),
    );
    final text = tester.widget<Text>(
      find.byKey(const Key('dashboard-card-summary')),
    );
    expect(text.data, '3 队 · 满血');
  });

  testWidgets('card 样式折叠时不显示摘要', (tester) async {
    await tester.pumpWidget(
      _host(style: null, collapsed: true, summary: '3 队 · 满血'),
    );
    expect(find.byKey(const Key('dashboard-card-summary')), findsNothing);
  });

  testWidgets('flat 展开时没有摘要且 trailing 照常显示', (tester) async {
    await tester.pumpWidget(
      _host(style: PanelStyle.flat, collapsed: false, summary: '3 队 · 满血'),
    );
    expect(find.byKey(const Key('dashboard-card-summary')), findsNothing);
    expect(find.byKey(const Key('card-trailing')), findsOneWidget);
  });
}
