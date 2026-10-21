import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/fleet/dashboard_card.dart';
import 'package:yahagi_kancolle_browser/src/layout/flat_text_toggle.dart';
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

  Widget tallChildren({required bool collapsed, required double width}) =>
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: PanelStyleScope(
                style: PanelStyle.flat,
                child: DashboardCard(
                  title: '舰队',
                  icon: const Icon(Icons.sailing),
                  collapsed: collapsed,
                  onToggleCollapse: () {},
                  titleBadge: const Chip(label: Text('待机')),
                  trailing: const SizedBox(width: 60, height: 30),
                  headerAction: const IconButton(
                    onPressed: null,
                    icon: Icon(Icons.settings),
                  ),
                  child: const SizedBox(height: 20),
                ),
              ),
            ),
          ),
        ),
      );

  for (final width in [190.0, 260.0]) {
    testWidgets('flat 标题行遇到偏高子项不整体缩放 ($width)', (tester) async {
      await tester.pumpWidget(tallChildren(collapsed: false, width: width));
      expect(tester.takeException(), isNull);
      final header = find.byKey(const Key('dashboard-card-header'));
      expect(tester.getSize(header).height, 24);
      final title = find.text('舰队');
      expect(tester.widget<Text>(title).style?.fontSize, 11);
      expect(tester.getSize(title).height, greaterThanOrEqualTo(13));
      for (final box in tester.widgetList<FittedBox>(
        find.descendant(of: header, matching: find.byType(FittedBox)),
      )) {
        expect(
          find.descendant(of: find.byWidget(box), matching: title),
          findsNothing,
        );
      }
      final card = tester.getRect(find.byType(DashboardCard));
      final chevron = tester.getRect(find.byType(IconButton).last);
      expect(card.right - chevron.right, lessThanOrEqualTo(8));
    });
  }

  testWidgets('flat 折叠态折叠按钮贴右边缘', (tester) async {
    await tester.pumpWidget(tallChildren(collapsed: true, width: 190));
    expect(tester.takeException(), isNull);
    final card = tester.getRect(find.byType(DashboardCard));
    final chevron = tester.getRect(find.byType(IconButton).last);
    expect(card.right - chevron.right, lessThanOrEqualTo(8));
  });

  testWidgets('flat 展开时没有摘要且 trailing 照常显示', (tester) async {
    await tester.pumpWidget(
      _host(style: PanelStyle.flat, collapsed: false, summary: '3 队 · 满血'),
    );
    expect(find.byKey(const Key('dashboard-card-summary')), findsNothing);
    expect(find.byKey(const Key('card-trailing')), findsOneWidget);
  });

  group('flat 标题徽标', () {
    const appFont = 'HarmonyOS_Sans_SC';
    setUpAll(() async {
      await (FontLoader(
        appFont,
      )..addFont(rootBundle.load('assets/fonts/HarmonyOS_Sans_SC.ttf'))).load();
    });

    Widget badgeHost({required double width, required String badge}) =>
        MaterialApp(
          locale: const Locale('zh'),
          theme: ThemeData(fontFamily: appFont),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: PanelStyleScope(
                  style: PanelStyle.flat,
                  child: DashboardCard(
                    title: 'Battle prediction results',
                    icon: const Icon(Icons.sailing),
                    collapsed: false,
                    onToggleCollapse: () {},
                    titleBadge: Text(
                      badge,
                      key: const Key('card-badge'),
                      style: const TextStyle(fontSize: 10.5),
                    ),
                    trailing: const Text('切换器'),
                    child: const SizedBox(height: 20),
                  ),
                ),
              ),
            ),
          ),
        );

    RenderParagraph titleParagraph(WidgetTester tester) =>
        tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.text('Battle prediction results'),
            matching: find.byType(RichText),
          ),
        );

    testWidgets('放得下时标题不因徽标被截断', (tester) async {
      await tester.pumpWidget(badgeHost(width: 320, badge: 'Confirmed'));

      expect(tester.takeException(), isNull);
      expect(titleParagraph(tester).didExceedMaxLines, isFalse);
      final badge = find.byKey(const Key('card-badge'));
      expect(
        tester.getRect(badge).width,
        moreOrLessEquals(
          tester.renderObject<RenderParagraph>(badge).getMaxIntrinsicWidth(24),
        ),
      );
    });

    testWidgets('放不下时徽标缩放而不溢出', (tester) async {
      await tester.pumpWidget(
        badgeHost(width: 170, badge: 'A very long confirmed badge'),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('flat 英文标题行', () {
    Widget englishHost({required double width, required double scale}) =>
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: PanelStyleScope(
                    style: PanelStyle.flat,
                    child: DashboardCard(
                      title: 'Pre-sortie check',
                      icon: const Icon(Icons.sailing),
                      collapsed: false,
                      onToggleCollapse: () {},
                      collapseButtonKey: const Key('card-collapse'),
                      titleBadge: const Text('Ready'),
                      trailing: FlatTextToggle(
                        options: [
                          FlatTextToggleOption(
                            key: const Key('toggle-summary'),
                            label: 'Summary',
                            selected: true,
                            onTap: () {},
                          ),
                          FlatTextToggleOption(
                            key: const Key('toggle-check'),
                            label: 'Check',
                            selected: false,
                            onTap: () {},
                          ),
                        ],
                      ),
                      headerAction: const IconButton(
                        onPressed: null,
                        icon: Icon(Icons.settings),
                      ),
                      child: const SizedBox(height: 20),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

    for (final (width, scale) in [(180.0, 1.3), (180.0, 1.0), (300.0, 1.3)]) {
      testWidgets('折叠按钮始终完整可见 ($width, x$scale)', (tester) async {
        await tester.pumpWidget(englishHost(width: width, scale: scale));
        expect(tester.takeException(), isNull);
        final header = find.byKey(const Key('dashboard-card-header'));
        expect(tester.getSize(header).height, 24);
        expect(
          find.descendant(
            of: header,
            matching: find.byType(SingleChildScrollView),
          ),
          findsNothing,
        );
        final card = tester.getRect(find.byType(DashboardCard));
        final chevron = tester.getRect(find.byKey(const Key('card-collapse')));
        expect(chevron.left, greaterThanOrEqualTo(card.left));
        expect(chevron.right, lessThanOrEqualTo(card.right));
        expect(card.right - chevron.right, lessThanOrEqualTo(8));
      });
    }
  });
}
