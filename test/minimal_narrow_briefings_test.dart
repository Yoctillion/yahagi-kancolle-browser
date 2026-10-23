import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/fleet/fleet_summary_card.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_store.dart';
import 'package:yahagi_kancolle_browser/src/layout/flat_list_row.dart';
import 'package:yahagi_kancolle_browser/src/layout/panel_style.dart';
import 'package:yahagi_kancolle_browser/src/layout/ui_scale.dart';
import 'package:yahagi_kancolle_browser/src/settings/battle_status_effect_settings.dart';

import 'fixtures/fleet_display_sample.dart';

class _Store extends GameStateStore {
  _Store(this.state);

  final GameState state;

  @override
  Future<GameState> load() async => state;
}

Widget _host(double physicalWidth, Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: physicalWidth,
        child: UiScale(
          scale: minimalUiScale,
          child: PanelStyleScope(style: PanelStyle.flat, child: child),
        ),
      ),
    ),
  ),
);

Rect _paintedRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return Rect.fromPoints(
    box.localToGlobal(Offset.zero),
    box.localToGlobal(box.size.bottomRight(Offset.zero)),
  );
}

void main() {
  for (final metric in const [
    ('minimum-condition', 'Minimum morale', '15'),
    ('recovery-countdown', 'Recovery countdown', 'Recovered'),
  ]) {
    testWidgets('190dp minimal fleet keeps ${metric.$1} inside its column', (
      tester,
    ) async {
      final controller = GameStateController(
        gameStateStore: _Store(demoState()),
      );
      await controller.initialize();
      addTearDown(controller.dispose);
      // The physical column stays 190dp; 1.1 scaling leaves about 160.7dp
      // inside DashboardCard's 6dp padding on each side.
      await tester.pumpWidget(
        _host(
          190,
          FleetSummaryCard(
            controller: controller,
            collapsed: false,
            onToggleCollapse: () {},
            onOpenFleet: (_) {},
            visible: {metric.$1},
            damagePulseFilter: DamagePulseFilter.off,
            moraleSparkleMode: MoraleSparkleMode.off,
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      final row = find.byKey(Key('fleet-summary-metric-${metric.$1}'));
      final value = find.byKey(Key('fleet-summary-metric-${metric.$1}-value'));
      final label = find.descendant(of: row, matching: find.text(metric.$2));
      expect(tester.widget<Text>(value).data, metric.$3);
      expect(
        tester.renderObject<RenderParagraph>(value).didExceedMaxLines,
        isFalse,
      );
      final bounds = _paintedRect(tester, row);
      final valueBounds = _paintedRect(tester, value);
      final labelBounds = _paintedRect(tester, label);
      expect(valueBounds.width, greaterThan(0));
      expect(valueBounds.left, greaterThanOrEqualTo(bounds.left - .01));
      expect(valueBounds.right, lessThanOrEqualTo(bounds.right + .01));
      expect(labelBounds.right, lessThanOrEqualTo(valueBounds.left + .01));
    });
  }

  testWidgets('narrow HD row fits two tags and its complete progress value', (
    tester,
  ) async {
    // A 400dp HD bottom strip, split into three cells, leaves this physical
    // content width after its padding, column gaps and card padding:
    // ((400 / 1.1 - 32) / 3 - 12) * 1.1 = 108.4dp, or 98.55 logical dp.
    const physicalWidth = 108.4;
    await tester.pumpWidget(
      _host(
        physicalWidth,
        Builder(
          builder: (context) => FlatListRow(
            key: const Key('narrow-quest-row'),
            tags: [
              flatRowText(
                context,
                'Formation',
                key: const Key('narrow-quest-type'),
              ),
              flatRowText(
                context,
                '#1234',
                key: const Key('narrow-quest-number'),
              ),
            ],
            name: flatRowText(
              context,
              'A long task name',
              key: const Key('narrow-quest-name'),
            ),
            trailing: flatRowTrailing(
              flatRowText(
                context,
                '999/1000',
                key: const Key('narrow-quest-progress'),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    final keys = [
      'narrow-quest-type',
      'narrow-quest-number',
      'narrow-quest-name',
      'narrow-quest-progress',
    ];
    final rects = [
      for (final key in keys) _paintedRect(tester, find.byKey(Key(key))),
    ];
    for (var i = 0; i + 1 < rects.length; i++) {
      expect(rects[i].right, lessThanOrEqualTo(rects[i + 1].left + .01));
    }
    final row = _paintedRect(tester, find.byKey(const Key('narrow-quest-row')));
    expect(rects.last.right, lessThanOrEqualTo(row.right + .01));
    expect(rects.last.width, greaterThan(0));
    expect(
      tester
          .renderObject<RenderParagraph>(
            find.byKey(const Key('narrow-quest-progress')),
          )
          .didExceedMaxLines,
      isFalse,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('narrow-quest-progress'))).data,
      '999/1000',
    );
  });
}
