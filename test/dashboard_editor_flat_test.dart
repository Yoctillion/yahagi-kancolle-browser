import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/fleet/dashboard_card.dart';
import 'package:yahagi_kancolle_browser/src/layout/flat_collapse_chevron.dart';
import 'package:yahagi_kancolle_browser/src/layout/flat_style.dart';
import 'package:yahagi_kancolle_browser/src/layout/hd_home_editor.dart';
import 'package:yahagi_kancolle_browser/src/layout/panel_style.dart';
import 'package:yahagi_kancolle_browser/src/settings/module_display_settings.dart';

class _Calls {
  final toggled = <String>[];
  var resets = 0;
  var dones = 0;
  final moves = <String>[];
}

Widget _host({
  required PanelStyle style,
  required _Calls calls,
  Set<String> hidden = const {},
  double width = 300,
  String locale = 'zh',
  double textScale = 1,
}) => MaterialApp(
  locale: Locale(locale),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: MediaQuery.withClampedTextScaling(
      minScaleFactor: textScale,
      maxScaleFactor: textScale,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: 400,
          child: PanelStyleScope(
            style: style,
            child: DashboardEditor(
              modules: const ['fleet', 'repair'],
              hidden: hidden,
              cardBuilder: (id) => Builder(
                builder: (context) => DashboardCard(
                  key: Key('card-$id'),
                  title: id,
                  icon: const Icon(Icons.sailing),
                  collapsed: true,
                  collapsedSummary: id == 'fleet' ? '最低疲劳 49' : '进行中 2',
                  onToggleCollapse: () {},
                  headerAction: moduleDisplayGear(context, id, () {}),
                  child: const SizedBox(height: 20),
                ),
              ),
              onToggle: calls.toggled.add,
              onMove: (id, target, after) => calls.moves.add('$id>$target'),
              onReset: () => calls.resets++,
              onDone: () => calls.dones++,
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('flat 编辑行加高到 32，勾选框和齿轮垂直居中', (tester) async {
    final calls = _Calls();
    await tester.pumpWidget(
      _host(style: PanelStyle.flat, calls: calls, hidden: {'repair'}),
    );
    expect(find.byType(Checkbox), findsNothing);
    final toggle = find.byKey(const Key('dashboard-visibility-fleet'));
    expect(
      tester.getSize(toggle),
      const Size(flatHeaderHeight, flatEditRowHeight),
    );
    final header = find.descendant(
      of: find.byKey(const Key('card-fleet')),
      matching: find.byKey(const Key('dashboard-card-header')),
    );
    expect(tester.getSize(header).height, flatEditRowHeight);
    expect(tester.getCenter(toggle).dy, tester.getCenter(header).dy);
    expect(
      tester
          .getCenter(find.byKey(const Key('fleet-display-settings-button')))
          .dy,
      tester.getCenter(header).dy,
    );
    expect(
      find.descendant(
        of: toggle,
        matching: find.byIcon(Icons.check_box_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('dashboard-visibility-repair')),
        matching: find.byIcon(Icons.check_box_outline_blank_rounded),
      ),
      findsOneWidget,
    );
    await tester.tap(toggle);
    expect(calls.toggled, ['fleet']);
  });

  testWidgets('flat 点条目任意位置切换显隐，点齿轮不切换', (tester) async {
    final calls = _Calls();
    await tester.pumpWidget(_host(style: PanelStyle.flat, calls: calls));
    await tester.tap(find.text('repair'));
    expect(calls.toggled, ['repair']);
    await tester.tap(find.byKey(const Key('fleet-display-settings-button')));
    expect(calls.toggled, ['repair']);
  });

  testWidgets('flat 整行可点后仍能长按拖动排序', (tester) async {
    final calls = _Calls();
    await tester.pumpWidget(_host(style: PanelStyle.flat, calls: calls));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('fleet')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(
      tester.getCenter(find.byKey(const Key('dashboard-target-end'))),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls.moves, ['fleet>null']);
    expect(calls.toggled, isEmpty);
  });

  testWidgets('card 样式点标题不切换显隐', (tester) async {
    final calls = _Calls();
    await tester.pumpWidget(_host(style: PanelStyle.card, calls: calls));
    await tester.tap(find.text('repair'));
    expect(calls.toggled, isEmpty);
  });

  testWidgets('flat 列表不留左右内边距', (tester) async {
    await tester.pumpWidget(_host(style: PanelStyle.flat, calls: _Calls()));
    expect(
      tester.getTopLeft(find.byKey(const Key('dashboard-visibility-fleet'))).dx,
      0,
    );
    expect(tester.getTopRight(find.byKey(const Key('card-fleet'))).dx, 300);
  });

  testWidgets('flat 顶栏是 24 高的文字按钮', (tester) async {
    final calls = _Calls();
    await tester.pumpWidget(_host(style: PanelStyle.flat, calls: calls));
    final bar = find.byKey(const Key('dashboard-edit-bar'));
    expect(tester.getSize(bar).height, flatHeaderHeight);
    expect(find.text('还原默认排序'), findsOneWidget);
    expect(find.text('完成编辑'), findsOneWidget);
    expect(tester.getTopRight(find.text('完成编辑')).dx, lessThan(300));
    await tester.tap(find.byKey(const Key('dashboard-edit-reset')));
    await tester.tap(find.byKey(const Key('dashboard-edit-done')));
    expect(calls.resets, 1);
    expect(calls.dones, 1);
  });

  testWidgets('flat 顶栏英文窄屏放大字号时不溢出且完成按钮可见', (tester) async {
    final calls = _Calls();
    await tester.pumpWidget(
      _host(
        style: PanelStyle.flat,
        calls: calls,
        width: 180,
        locale: 'en',
        textScale: 1.3,
      ),
    );
    expect(tester.takeException(), isNull);
    final done = find.byKey(const Key('dashboard-edit-done'));
    expect(tester.getTopRight(done).dx, lessThanOrEqualTo(180));
    await tester.tap(done);
    expect(calls.dones, 1);
  });

  testWidgets('card 样式仍用复选框和图标按钮', (tester) async {
    await tester.pumpWidget(_host(style: PanelStyle.card, calls: _Calls()));
    expect(find.byType(Checkbox), findsNWidgets(2));
    expect(find.byKey(const Key('dashboard-visibility-fleet')), findsNothing);
    expect(find.byKey(const Key('dashboard-edit-bar')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('dashboard-edit-done')),
        matching: find.byIcon(Icons.check_rounded),
      ),
      findsOneWidget,
    );
    expect(tester.getTopLeft(find.byType(Checkbox).first).dx, 12);
  });

  testWidgets('flat 编辑态卡片不构建摘要或折叠箭头', (tester) async {
    await tester.pumpWidget(_host(style: PanelStyle.flat, calls: _Calls()));
    expect(find.byKey(const Key('card-fleet')), findsOneWidget);
    expect(
      find.byKey(const Key('dashboard-card-summary'), skipOffstage: false),
      findsNothing,
    );
    expect(find.text('最低疲劳 49'), findsNothing);
    expect(find.text('进行中 2'), findsNothing);
    expect(find.text('fleet'), findsOneWidget);
    expect(find.text('repair'), findsOneWidget);
    expect(find.byIcon(Icons.sailing), findsNWidgets(2));
    expect(find.byType(FlatCollapseChevron), findsNothing);
  });

  testWidgets('card 样式编辑态保留折叠按钮', (tester) async {
    await tester.pumpWidget(_host(style: PanelStyle.card, calls: _Calls()));
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNWidgets(2));
  });

  final gear = find.byKey(const Key('repair-display-settings-button'));
  final gearIcon = find.descendant(
    of: gear,
    matching: find.byIcon(Icons.settings_outlined),
  );

  testWidgets('flat 齿轮不被标题行缩小', (tester) async {
    await tester.pumpWidget(_host(style: PanelStyle.flat, calls: _Calls()));
    expect(tester.getSize(gear), const Size.square(flatHeaderHeight));
    expect(
      tester.getRect(gearIcon).size,
      const Size.square(flatActionIconSize),
    );
  });

  testWidgets('card 样式齿轮尺寸不变', (tester) async {
    await tester.pumpWidget(_host(style: PanelStyle.card, calls: _Calls()));
    expect(tester.getSize(gearIcon), const Size.square(19));
    expect(tester.getSize(gear), const Size.square(48));
  });
}
