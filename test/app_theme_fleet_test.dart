import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/fleet/dashboard_card.dart';
import 'package:yahagi_kancolle_browser/src/fleet/fleet_ship_status_capsule.dart';
import 'package:yahagi_kancolle_browser/src/fleet/fleet_summary_card.dart';
import 'package:yahagi_kancolle_browser/src/fleet/resource_trend_chart.dart';
import 'package:yahagi_kancolle_browser/src/fleet/resource_trend_data.dart';
import 'package:yahagi_kancolle_browser/src/fleet/resource_trend_sampler.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/theme/app_palette.dart';
import 'package:yahagi_kancolle_browser/src/theme/app_theme.dart';

import 'fixtures/kcsapi_fixtures.dart';

void main() {
  for (final width in [390.0, 844.0]) {
    testWidgets(
      'fleet theme changes preserve selection, state and geometry at $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 950);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final oldTimerSetting = GameStateController.disableTimerForTest;
        GameStateController.disableTimerForTest = true;
        addTearDown(
          () => GameStateController.disableTimerForTest = oldTimerSetting,
        );
        final controller = GameStateController()
          ..accept(start2Event)
          ..accept(portEvent)
          ..accept(slotItemEvent);
        await controller.idle;
        addTearDown(controller.dispose);
        final mode = ValueNotifier(AppThemeMode.dark);
        addTearDown(mode.dispose);
        int? opened;
        await tester.pumpWidget(
          _themed(
            mode,
            FleetSummaryCard(
              controller: controller,
              collapsed: false,
              onToggleCollapse: () {},
              onOpenFleet: (id) => opened = id,
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('fleet-summary-selector-2')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        final originalState = tester.state(find.byType(FleetSummaryCard));
        final originalCard = tester.getRect(find.byType(DashboardCard));
        final originalShip = tester.getRect(
          find.byType(FleetShipStatusCapsule),
        );
        final originalSelector = tester.getRect(
          find.byKey(const Key('fleet-summary-selector-2')),
        );
        final shipName = tester.widget<Text>(find.text('吹雪')).data;
        for (final nextMode in [...AppThemeMode.values, AppThemeMode.dark]) {
          mode.value = nextMode;
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 250));
          expect(
            tester.state(find.byType(FleetSummaryCard)),
            same(originalState),
          );
          expect(tester.getRect(find.byType(DashboardCard)), originalCard);
          expect(
            tester.getRect(find.byType(FleetShipStatusCapsule)),
            originalShip,
          );
          expect(
            tester.getRect(find.byKey(const Key('fleet-summary-selector-2'))),
            originalSelector,
          );
          expect(find.text(shipName!), findsOneWidget);
          final title = tester.widget<Text>(find.text('编队简报'));
          expect(
            title.style?.color,
            AppPalette(nextMode).color(const Color(0xffd4a85f)),
          );
          await tester.tap(find.byType(FleetShipStatusCapsule));
          expect(opened, 2);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets('resource chart themes preserve inspection and plot dimensions', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 10, 20, 12);
    final window = ResourceTrendWindow.at(now, 1);
    final data = ResourceTrendData.fromRows(window, [
      for (var i = 0; i < 3; i++)
        {
          'timestamp': now
              .subtract(Duration(hours: 2 - i))
              .millisecondsSinceEpoch,
          for (final key in resourceTrendKeys) key: 1000 + i * 100,
        },
    ]);
    final mode = ValueNotifier(AppThemeMode.dark);
    addTearDown(mode.dispose);
    await tester.pumpWidget(
      _themed(
        mode,
        ResourceTrendChart(
          data: data,
          resourceKey: 'fuel',
          label: '燃料',
          color: const Color(0xff6bcd91),
          iconId: '01',
          plotHeight: 180,
          onExpand: () {},
        ),
      ),
    );
    await tester.pump();
    tester.widget<Slider>(find.byType(Slider)).onChanged!(.5);
    await tester.pump();
    final originalState = tester.state(find.byType(ResourceTrendChart));
    final originalRect = tester.getRect(find.byType(ResourceTrendChart));
    final canvas = find.byKey(const ValueKey('resource-trend-canvas'));
    final canvasSize = tester.getSize(canvas);
    final originalPainter =
        tester.widget<CustomPaint>(canvas).painter! as ResourceTrendPainter;
    final originalPlot = originalPainter.plotRect(canvasSize);
    for (final nextMode in [...AppThemeMode.values, AppThemeMode.dark]) {
      mode.value = nextMode;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      final painter =
          tester.widget<CustomPaint>(canvas).painter! as ResourceTrendPainter;
      expect(
        tester.state(find.byType(ResourceTrendChart)),
        same(originalState),
      );
      expect(tester.getRect(find.byType(ResourceTrendChart)), originalRect);
      expect(tester.getSize(canvas), canvasSize);
      expect(painter.plotRect(canvasSize), originalPlot);
      expect(painter.palette.mode, nextMode);
      expect(painter.selected, originalPainter.selected);
      expect(tester.widget<Slider>(find.byType(Slider)).value, .5);
      final label = painter.text('1000').text! as TextSpan;
      expect(
        label.style!.color,
        AppPalette(nextMode).color(const Color(0xff8da8b8)),
      );
      expect(tester.takeException(), isNull);
    }
  });
}

Widget _themed(ValueNotifier<AppThemeMode> mode, Widget child) =>
    ValueListenableBuilder<AppThemeMode>(
      valueListenable: mode,
      builder: (context, value, _) => MaterialApp(
        theme: createAppTheme(mode: value),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
