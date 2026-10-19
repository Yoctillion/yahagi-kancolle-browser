import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/fcd_map_dataset.dart';
import 'package:yahagi_kancolle_browser/src/battle/live_battle_card.dart';
import 'package:yahagi_kancolle_browser/src/battle/prediction/battle_prediction_executor.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_reducer.dart';
import 'package:yahagi_kancolle_browser/src/settings/battle_prediction_settings.dart';

import 'fixtures/kcsapi_fixtures.dart';

const _map = Key('sortie-map-section');
const _preview = Key('official-enemy-preview');
const _navigationFleet = Key('navigation-friendly-fleets');
const _mapToggle = Key('sortie-map-toggle');
const _mapBody = Key('sortie-map-body');

const _orders = <List<BattlePredictionSection>>[
  [
    BattlePredictionSection.sortieMap,
    BattlePredictionSection.enemyPreview,
    BattlePredictionSection.predictionResult,
  ],
  [
    BattlePredictionSection.sortieMap,
    BattlePredictionSection.predictionResult,
    BattlePredictionSection.enemyPreview,
  ],
  [
    BattlePredictionSection.enemyPreview,
    BattlePredictionSection.sortieMap,
    BattlePredictionSection.predictionResult,
  ],
  [
    BattlePredictionSection.enemyPreview,
    BattlePredictionSection.predictionResult,
    BattlePredictionSection.sortieMap,
  ],
  [
    BattlePredictionSection.predictionResult,
    BattlePredictionSection.sortieMap,
    BattlePredictionSection.enemyPreview,
  ],
  [
    BattlePredictionSection.predictionResult,
    BattlePredictionSection.enemyPreview,
    BattlePredictionSection.sortieMap,
  ],
];

CapturedApiEvent _navigation(
  int route,
  int sequence, {
  bool start = false,
  bool preview = false,
}) => kcsapiEvent(
  '/kcsapi/api_req_map/${start ? 'start' : 'next'}',
  <String, Object?>{
    'api_maparea_id': 2,
    'api_mapinfo_no': 5,
    'api_no': route,
    if (start) 'api_from_no': 0,
    'api_bosscell_no': 15,
    'api_event_id': 4,
    'api_event_kind': 1,
    if (preview)
      'api_e_deck_info': <Object?>[
        <String, Object?>{
          'api_ship_ids': <int>[101, 102],
          'api_deck_type': 0,
        },
      ],
  },
  sequence: sequence,
  requestParams: start
      ? <String, Object?>{
          'api_maparea_id': '2',
          'api_mapinfo_no': '5',
          'api_deck_id': '1',
        }
      : const <String, Object?>{},
);

Finder _navigationSection(BattlePredictionSection section) =>
    find.byKey(switch (section) {
      BattlePredictionSection.sortieMap => _map,
      BattlePredictionSection.enemyPreview => _preview,
      BattlePredictionSection.predictionResult => _navigationFleet,
    });

void _expectVerticalOrder(WidgetTester tester, List<Finder> sections) {
  for (final section in sections) {
    expect(section, findsOneWidget);
  }
  for (var index = 1; index < sections.length; index++) {
    expect(
      tester.getBottomLeft(sections[index - 1]).dy,
      lessThan(tester.getTopLeft(sections[index]).dy),
      reason: 'Each complete section must appear before the next section.',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FcdMapDataset dataset;
  late GameState state;
  late BattleController controller;
  var controllerCreated = false;
  final reducer = GameStateReducer();

  setUpAll(() async {
    dataset = FcdMapDataset.parse(
      await rootBundle.loadString('assets/data/fcd/map.json'),
    );
  });

  setUp(() {
    state = reducer.reduce(GameState.empty, start2Event);
    state = reducer.reduce(state, portEvent);
    controllerCreated = false;
  });

  tearDown(() {
    if (controllerCreated) controller.dispose();
  });

  Future<void> send(CapturedApiEvent event) async {
    // Construct in the widget test's async zone so its controller queue can run.
    if (!controllerCreated) {
      controller = BattleController(
        gameState: () => state,
        nodeLabelResolver: dataset,
        predictionExecutor: const ImmediateBattlePredictionExecutor(),
      );
      controllerCreated = true;
    }
    state = reducer.reduce(state, event);
    controller.accept(event);
    await controller.idle;
  }

  Future<void> pumpCard(
    WidgetTester tester, {
    required List<BattlePredictionSection> order,
    bool compact = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 360,
              child: LiveBattleCard(
                key: const PageStorageKey('prediction-section-order'),
                controller: controller,
                collapsed: false,
                onToggleCollapse: () {},
                showEnemyPortraits: false,
                sectionOrder: order,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(Key(compact ? 'battle-mode-compact' : 'battle-mode-detailed')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  for (final compact in [false, true]) {
    for (final order in _orders) {
      testWidgets(
        'navigation follows ${order.map((section) => section.name).join('/')} '
        '(compact: $compact)',
        (tester) async {
          await send(_navigation(3, 100, start: true, preview: true));
          await pumpCard(tester, order: order, compact: compact);

          final sections = order.map(_navigationSection).toList();
          _expectVerticalOrder(tester, sections);
          expect(
            tester.getBottomLeft(find.byIcon(Icons.explore_outlined)).dy,
            lessThan(tester.getTopLeft(sections.first).dy),
            reason: 'The navigation overview stays above the ordered modules.',
          );
          expect(find.byKey(const Key('sortie-map-canvas')), findsOneWidget);
          final map = find.byKey(_map);
          final preview = find.byKey(_preview);
          final fleets = find.byKey(_navigationFleet);
          expect(find.descendant(of: preview, matching: map), findsNothing);
          expect(find.descendant(of: fleets, matching: map), findsNothing);
          expect(
            tester.getSize(preview).width,
            closeTo(tester.getSize(map).width, 1),
            reason:
                'The official enemy preview uses the complete module width.',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final mapLast in [false, true]) {
      testWidgets(
        'map-${mapLast ? 'last' : 'first'} moves past the complete battle '
        'result (compact: $compact)',
        (tester) async {
          await send(_navigation(3, 100, start: true, preview: true));
          await send(dayBattleEvent);
          await pumpCard(
            tester,
            order: mapLast ? _orders.last : _orders.first,
            compact: compact,
          );

          final map = find.byKey(_map);
          final rank = find.byKey(const Key('battle-rank-badge'));
          final fleets = find.byKey(
            Key(compact ? 'compact-fleet-grid' : 'battle-side-by-side-fleets'),
          );
          _expectVerticalOrder(
            tester,
            mapLast ? [rank, fleets, map] : [map, rank, fleets],
          );
          expect(
            find.descendant(of: fleets, matching: find.textContaining('我方')),
            findsWidgets,
          );
          expect(
            find.descendant(of: fleets, matching: find.textContaining('敌方')),
            findsWidgets,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'missing enemy preview leaves no space in the order (compact: $compact)',
      (tester) async {
        await send(_navigation(3, 100, start: true));
        await pumpCard(tester, order: _orders.last, compact: compact);
        expect(find.byKey(_preview), findsNothing);
        final map = find.byKey(_map);
        final fleets = find.byKey(_navigationFleet);
        _expectVerticalOrder(tester, [fleets, map]);
        final gapWithMissingPreviewBetween =
            tester.getTopLeft(map).dy - tester.getBottomLeft(fleets).dy;
        final mapTop = tester.getTopLeft(map).dy;

        await pumpCard(tester, order: _orders[4], compact: compact);

        expect(find.byKey(_preview), findsNothing);
        _expectVerticalOrder(tester, [fleets, map]);
        expect(tester.getTopLeft(map).dy, closeTo(mapTop, .1));
        expect(
          tester.getTopLeft(map).dy - tester.getBottomLeft(fleets).dy,
          closeTo(gapWithMissingPreviewBetween, .1),
          reason: 'Moving an unavailable module must not move visible content.',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('practice skips an ordered sortie map (compact: $compact)', (
      tester,
    ) async {
      await send(_navigation(3, 100, start: true));
      final data = jsonDecode(dayBattleEvent.responseBody) as Map;
      await send(
        kcsapiEvent(
          '/kcsapi/api_req_practice/battle',
          Map<String, Object?>.from(data['api_data'] as Map),
          sequence: 200,
        ),
      );
      await pumpCard(tester, order: _orders.last, compact: compact);

      expect(find.byKey(_map), findsNothing);
      expect(find.byKey(_mapToggle), findsNothing);
      expect(
        find.byKey(
          Key(compact ? 'compact-fleet-grid' : 'battle-side-by-side-fleets'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'map folding survives reorder, mode changes, and route progress',
    (tester) async {
      await send(_navigation(3, 100, start: true, preview: true));
      await pumpCard(tester, order: _orders.first);
      await tester.tap(find.byKey(_mapToggle));
      await tester.pump();
      expect(find.byKey(_mapBody), findsNothing);

      await pumpCard(tester, order: _orders.last);
      _expectVerticalOrder(tester, [
        find.byKey(_navigationFleet),
        find.byKey(_preview),
        find.byKey(_map),
      ]);
      expect(find.byKey(_mapBody), findsNothing);
      await tester.tap(find.byKey(const Key('battle-mode-compact')));
      await tester.pump();
      expect(find.byKey(_mapBody), findsNothing);

      await send(_navigation(5, 101, preview: true));
      await send(_navigation(9, 102, preview: true));
      await tester.pump();
      expect(find.byKey(_mapBody), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(_map),
          matching: find.textContaining('I'),
        ),
        findsWidgets,
      );
      _expectVerticalOrder(tester, [
        find.byKey(_navigationFleet),
        find.byKey(_preview),
        find.byKey(_map),
      ]);
      await tester.tap(find.byKey(const Key('battle-mode-detailed')));
      await tester.pump();
      expect(find.byKey(_mapBody), findsNothing);
      await tester.tap(find.byKey(_mapToggle));
      await tester.pump();
      expect(find.byKey(_mapBody), findsOneWidget);
      expect(find.byKey(const Key('sortie-map-canvas')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
