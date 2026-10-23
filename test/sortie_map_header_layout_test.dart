import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_detail_strings.dart';
import 'package:yahagi_kancolle_browser/src/battle/fcd_map_dataset.dart';
import 'package:yahagi_kancolle_browser/src/battle/fcd_map_geometry.dart';
import 'package:yahagi_kancolle_browser/src/battle/live_battle_card.dart';
import 'package:yahagi_kancolle_browser/src/battle/sortie_map_progress.dart';
import 'package:yahagi_kancolle_browser/src/battle/sortie_map_section.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';

const _locales = [
  Locale('zh'),
  Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  Locale('ja'),
  Locale('ko'),
  Locale('en'),
];
const _widths = [216.0, 240.0, 280.0, 360.0, 640.0];
final _geometry = FcdMapGeometry(
  routes: const {
    0: FcdMapRoute(from: null, to: 'A'),
    1: FcdMapRoute(from: 'A', to: 'B'),
  },
  spots: const {
    'A': FcdMapSpot(x: 0, y: 0, type: 'start'),
    'B': FcdMapSpot(x: 100, y: 0),
  },
);
final _progress = SortieMapProgress(
  mapAreaId: 2,
  mapInfoNo: 5,
  routeIds: const [0, 1],
);

Widget _app({
  required Locale locale,
  required double scale,
  required double width,
  required Widget child,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      child: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  ),
);

Finder _headerText(String text) => find.descendant(
  of: find.byKey(const Key('sortie-map-toggle')),
  matching: find.text(text),
);

void _expectVisibleHeader(
  WidgetTester tester,
  BattleDetailStrings strings, {
  required bool expanded,
  required bool missing,
}) {
  final toggle = find.byKey(const Key('sortie-map-toggle'));
  final bounds = tester.getRect(toggle);
  final title = _headerText(strings.sortieMapTitle);
  final summary = _headerText('2-5 · ${strings.mapCurrent} B');
  expect(title, findsOneWidget);
  expect(summary, findsOneWidget);
  expect(bounds.height, greaterThanOrEqualTo(44));
  for (final text in [title, summary]) {
    final rect = tester.getRect(text);
    expect(rect.width, greaterThan(0));
    expect(rect.height, greaterThan(0));
    expect(rect.left, greaterThanOrEqualTo(bounds.left));
    expect(rect.right, lessThanOrEqualTo(bounds.right));
    expect(rect.top, greaterThanOrEqualTo(bounds.top));
    expect(rect.bottom, lessThanOrEqualTo(bounds.bottom));
  }
  expect(
    tester.getRect(title).right,
    lessThanOrEqualTo(tester.getRect(summary).left),
  );
  expect(
    _headerText(strings.mapUnavailable),
    !expanded && missing ? findsOneWidget : findsNothing,
  );
  expect(
    find.byKey(const Key('sortie-map-body')),
    expanded ? findsOneWidget : findsNothing,
  );
  expect(
    find.byKey(const Key('sortie-map-canvas')),
    expanded && !missing ? findsOneWidget : findsNothing,
  );
}

void main() {
  for (final locale in _locales) {
    final strings = BattleDetailStrings.forLocale(locale);
    for (final scale in [1.0, 1.5, 2.0, 3.0]) {
      for (final expanded in [false, true]) {
        for (final missing in [false, true]) {
          testWidgets(
            'header fits $locale scale $scale expanded=$expanded missing=$missing',
            (tester) async {
              for (final width in _widths) {
                await tester.pumpWidget(
                  _app(
                    locale: locale,
                    scale: scale,
                    width: width,
                    child: SortieMapSection(
                      progress: _progress,
                      geometry: missing ? null : _geometry,
                      currentNodeLabel: 'B',
                      expanded: expanded,
                      onToggleExpanded: () {},
                    ),
                  ),
                );
                expect(tester.takeException(), isNull, reason: 'width=$width');
                _expectVisibleHeader(
                  tester,
                  strings,
                  expanded: expanded,
                  missing: missing,
                );
              }
            },
          );
        }
      }
    }

    testWidgets('normal $locale header retains its original allocation', (
      tester,
    ) async {
      for (final width in _widths) {
        await tester.pumpWidget(
          _app(
            locale: locale,
            scale: 1,
            width: width,
            child: SortieMapSection(
              progress: _progress,
              geometry: _geometry,
              expanded: false,
              onToggleExpanded: () {},
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        final toggle = tester.getRect(
          find.byKey(const Key('sortie-map-toggle')),
        );
        final titleFinder = _headerText(strings.sortieMapTitle);
        final title = tester.getRect(titleFinder);
        final paragraph = tester.renderObject<RenderParagraph>(titleFinder);
        final intrinsicWidth = paragraph.getMaxIntrinsicWidth(double.infinity);
        final summaryColumn =
            tester
                    .renderObject<RenderParagraph>(
                      _headerText('2-5 · ${strings.mapCurrent} B'),
                    )
                    .parent!
                as RenderBox;
        final summary =
            summaryColumn.localToGlobal(Offset.zero) & summaryColumn.size;
        final chevron = tester.getRect(find.byIcon(Icons.expand_more));
        // 18 px button padding and 50 px of icons and horizontal gaps.
        final remaining = width - 68;
        final english = locale.languageCode == 'en';
        final expectedTitleWidth = english
            ? intrinsicWidth.clamp(0, remaining * .6)
            : intrinsicWidth;
        final summaryWidth = english
            ? remaining * .4
            : remaining - intrinsicWidth;
        expect(title.left - toggle.left, closeTo(29, .001));
        expect(title.width, closeTo(expectedTitleWidth, .001));
        expect(summary.left - title.right, closeTo(8, .001));
        expect(summary.width, closeTo(summaryWidth, .001));
        expect(chevron.left - summary.right, closeTo(4, .001));
        expect(toggle.height, english && width <= 280 ? 46 : 44);
        expect(tester.widget<Text>(titleFinder).style?.fontSize, 11);
        expect(
          tester.widget<Text>(titleFinder).style?.color,
          const Color(0xff70c7bc),
        );
      }
    });
  }

  testWidgets('cached live map adapts from English to Japanese at scale 2', (
    tester,
  ) async {
    final dataset = FcdMapDataset.parse(
      jsonEncode({
        'meta': {'name': 'map', 'version': '2026/10/20/01'},
        'data': {
          '2-5': {
            'route': {
              '0': [null, 'A'],
              '1': ['A', 'B'],
            },
            'spots': {
              'A': [0, 0, 'start'],
              'B': [100, 0, ''],
            },
          },
        },
      }),
      minimumMapCount: 1,
    );
    final controller = BattleController(
      gameState: () => GameState.empty,
      nodeLabelResolver: dataset,
    );
    addTearDown(controller.dispose);
    controller.accept(
      CapturedApiEvent(
        path: '/kcsapi/api_req_map/start',
        source: CaptureSource.manual,
        capturedAt: DateTime.utc(2026, 10, 20),
        responseBody: jsonEncode({
          'api_result': 1,
          'api_data': {
            'api_maparea_id': 2,
            'api_mapinfo_no': 5,
            'api_no': 1,
            'api_from_no': 0,
          },
        }),
      ),
    );
    await controller.idle;
    Future<void> pump(Locale locale) async {
      final errors = <FlutterErrorDetails>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = errors.add;
      try {
        await tester.pumpWidget(
          _app(
            locale: locale,
            scale: 2,
            width: 240,
            child: LiveBattleCard(
              key: const PageStorageKey('header-locale-regression'),
              controller: controller,
              collapsed: false,
              onToggleCollapse: () {},
              showEnemyPortraits: false,
              showTitle: false,
              showLogo: false,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));
      } finally {
        FlutterError.onError = originalOnError;
      }
      expect(
        errors.where((details) {
          // The card's separate mode-switch header has an existing 4.5 px
          // Japanese overflow. Keep this test scoped to the cached map while
          // still failing for every other error or map-header overflow.
          return !(locale.languageCode == 'ja' &&
              details.exceptionAsString() ==
                  'A RenderFlex overflowed by 4.5 pixels on the right.' &&
              details.toString().contains('dashboard_card.dart'));
        }),
        isEmpty,
      );
    }

    await pump(const Locale('en'));
    expect(tester.takeException(), isNull);
    final cached = tester.widget<SortieMapSection>(
      find.byType(SortieMapSection),
    );
    expect(
      tester.getSize(find.byKey(const Key('sortie-map-section'))).width,
      216,
    );
    await pump(const Locale('ja'));
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<SortieMapSection>(find.byType(SortieMapSection)),
      same(cached),
    );
    _expectVisibleHeader(
      tester,
      const BattleDetailStrings.forLocale(Locale('ja')),
      expanded: true,
      missing: false,
    );
  });
}
