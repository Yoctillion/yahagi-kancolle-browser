import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/main.dart';
import 'package:yahagi_kancolle_browser/src/fleet/resource_grid.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/layout/hd_home_editor.dart';
import 'package:yahagi_kancolle_browser/src/layout/panel_style.dart';
import 'package:yahagi_kancolle_browser/src/layout/ui_scale.dart';
import 'package:yahagi_kancolle_browser/src/settings/header_resource_settings.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_store.dart';

Widget _host(Widget child) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Align(alignment: Alignment.topLeft, child: child),
    ),
  ),
);

// WidgetTester.getSize reports local layout dimensions, before ancestor scale.
Rect _paintedRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return Rect.fromPoints(
    box.localToGlobal(Offset.zero),
    box.localToGlobal(box.size.bottomRight(Offset.zero)),
  );
}

void _expectSize(Size actual, Size expected) {
  expect(actual.width, closeTo(expected.width, .01));
  expect(actual.height, closeTo(expected.height, .01));
}

void _expectOffset(Offset actual, Offset expected) {
  expect(actual.dx, closeTo(expected.dx, .01));
  expect(actual.dy, closeTo(expected.dy, .01));
}

Future<LayoutSettingsController> _settings() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return LayoutSettingsController.load(SharedPreferencesLayoutSettingsStore());
}

void main() {
  testWidgets('scaled dashboard drag keeps feedback size and finger anchor', (
    tester,
  ) async {
    Widget dashboard(double scale) => _host(
      UiScale(
        scale: scale,
        child: SizedBox(
          width: 240,
          height: 56,
          child: PanelStyleScope(
            style: PanelStyle.flat,
            child: DashboardEditItem(
              id: 'fleet',
              hidden: false,
              onToggle: () {},
              child: const SizedBox(height: 32, child: Text('fleet')),
            ),
          ),
        ),
      ),
    );
    final region = find.byKey(const Key('dashboard-drag-region-fleet'));
    await tester.pumpWidget(dashboard(1));
    final baseline = _paintedRect(tester, region);
    await tester.pumpWidget(dashboard(minimalUiScale));
    final before = _paintedRect(tester, region);
    _expectSize(before.size, baseline.size * minimalUiScale);

    final draggable = tester.widget<LongPressDraggable<String>>(region);
    final gesture = await tester.startGesture(
      before.topLeft + const Offset(60, 12),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    final feedback = find.byWidget(draggable.feedback);
    expect(feedback, findsOneWidget);
    _expectSize(_paintedRect(tester, feedback).size, before.size);
    _expectOffset(_paintedRect(tester, feedback).topLeft, before.topLeft);

    const movement = Offset(35, 18);
    await gesture.moveBy(movement);
    await tester.pump();
    _expectOffset(
      _paintedRect(tester, feedback).topLeft,
      before.topLeft + movement,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(feedback, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scaled resource editor preserves its drag proxy and reorders', (
    tester,
  ) async {
    final controller = await _settings();
    const firstIds = ['material-1', 'material-2', 'material-3'];
    await controller.setHeaderResourceOrder([
      ...firstIds,
      ...allHeaderResourceIds.where((id) => !firstIds.contains(id)),
    ]);
    Widget resources(double scale) => _host(
      SizedBox(
        width: 640,
        height: 64,
        child: UiScale(
          scale: scale,
          child: Align(
            alignment: Alignment.topLeft,
            child: CompactResourceBar(
              state: GameState.empty,
              settingsController: controller,
              uiSize: UiDisplaySize.compact,
              flatStyle: true,
            ),
          ),
        ),
      ),
    );
    final item = find.byKey(const Key('header-resource-edit-material-1'));
    await tester.pumpWidget(resources(1));
    await tester.longPress(find.byKey(const Key('header-resource-material-1')));
    await tester.pumpAndSettle();
    final baseline = _paintedRect(tester, item);
    await tester.pumpWidget(resources(minimalUiScale));
    await tester.pumpAndSettle();
    final before = _paintedRect(tester, item);
    _expectSize(before.size, baseline.size * minimalUiScale);

    // Empty resources show a short dash; the center of the wider item can be
    // blank, and the existing drag listener defers hits to its painted child.
    final icon = find.descendant(of: item, matching: find.byType(Image)).first;
    final gesture = await tester.startGesture(
      _paintedRect(tester, icon).center,
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    expect(item, findsOneWidget);
    expect(
      find.ancestor(of: item, matching: find.byType(ReorderableListView)),
      findsNothing,
    );
    _expectSize(_paintedRect(tester, item).size, before.size);
    _expectOffset(_paintedRect(tester, item).topLeft, before.topLeft);
    await gesture.moveBy(Offset(before.width * .85, 0));
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.headerResourceOrder.take(3), [
      'material-2',
      'material-1',
      'material-3',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('minimal navigation drag keeps size and route identities', (
    tester,
  ) async {
    final controller = await _settings();
    var selectedPage = -1;
    Widget navigation() => _host(
      SizedBox(
        height: 400,
        child: WorkspaceNavigation(
          controller: controller,
          selectedIndex: 0,
          onRight: false,
          onSelected: (page) => selectedPage = page,
        ),
      ),
    );
    final item = find.byKey(const Key('workspace-nav-item-game'));
    await controller.setUiDisplaySize(UiDisplaySize.compact);
    await tester.pumpWidget(navigation());
    final baseline = _paintedRect(tester, item);
    await controller.setUiDisplaySize(UiDisplaySize.minimal);
    await tester.pumpWidget(navigation());
    await tester.pumpAndSettle();
    final before = _paintedRect(tester, item);
    _expectSize(before.size, baseline.size);

    final gesture = await tester.startGesture(before.center);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    expect(item, findsOneWidget);
    expect(
      find.ancestor(of: item, matching: find.byType(ReorderableListView)),
      findsNothing,
    );
    _expectSize(_paintedRect(tester, item).size, before.size);
    _expectOffset(_paintedRect(tester, item).topLeft, before.topLeft);
    await gesture.moveBy(Offset(0, before.height * .85));
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.workspaceMenuOrder.take(2), ['fleet', 'game']);
    expect(selectedPage, -1);
    await tester.tap(find.byKey(const Key('workspace-nav-fleet')));
    await tester.pump();
    expect(selectedPage, 1);
    expect(tester.takeException(), isNull);
  });
}
