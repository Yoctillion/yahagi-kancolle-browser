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

const _mapSection = Key('sortie-map-section');
const _mapToggle = Key('sortie-map-toggle');
const _mapBody = Key('sortie-map-body');

CapturedApiEvent _navigation(
  int routeId,
  int sequence, {
  bool start = false,
  bool preview = false,
}) => kcsapiEvent(
  '/kcsapi/api_req_map/${start ? 'start' : 'next'}',
  <String, Object?>{
    'api_maparea_id': 2,
    'api_mapinfo_no': 5,
    'api_no': routeId,
    if (start) 'api_from_no': 0,
    'api_bosscell_no': 15,
    'api_event_id': routeId == 9 ? 1 : 4,
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
    double width = 320,
    bool compact = false,
    EnemyPreviewPosition position = EnemyPreviewPosition.above,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: LiveBattleCard(
                key: const PageStorageKey('sortie-map-integration'),
                controller: controller,
                collapsed: false,
                onToggleCollapse: () {},
                showEnemyPortraits: false,
                enemyPreviewPosition: position,
              ),
            ),
          ),
        ),
      ),
    );
    if (compact) {
      await tester.tap(find.byKey(const Key('battle-mode-compact')));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 200));
  }

  for (final compact in [false, true]) {
    for (final position in EnemyPreviewPosition.values) {
      testWidgets(
        'map is independent from navigation preview and fleet ($compact/$position)',
        (tester) async {
          await send(_navigation(3, 100, start: true, preview: true));
          await pumpCard(tester, compact: compact, position: position);

          final map = find.byKey(_mapSection);
          final preview = find.byKey(const Key('official-enemy-preview'));
          final fleet = find.byKey(const Key('navigation-friendly-fleets'));
          expect(map, findsOneWidget);
          expect(find.descendant(of: preview, matching: map), findsNothing);
          expect(find.descendant(of: fleet, matching: map), findsNothing);
          expect(
            tester.getBottomLeft(map).dy,
            lessThan(tester.getTopLeft(preview).dy),
          );
          expect(
            tester.getBottomLeft(map).dy,
            lessThan(tester.getTopLeft(fleet).dy),
          );
          expect(
            tester.getSize(map).width,
            closeTo(tester.getSize(fleet).width, 1),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('folded map follows navigation and survives mode changes', (
    tester,
  ) async {
    await send(_navigation(3, 100, start: true));
    await pumpCard(tester);
    expect(find.byKey(_mapSection), findsOneWidget);
    await tester.tap(find.byKey(_mapToggle));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(_mapBody).hitTestable(), findsNothing);

    await send(_navigation(5, 101));
    await send(_navigation(9, 102));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.descendant(
        of: find.byKey(_mapSection),
        matching: find.textContaining('I'),
      ),
      findsWidgets,
    );
    await tester.tap(find.byKey(const Key('battle-mode-compact')));
    await tester.pump();
    expect(find.byKey(_mapBody).hitTestable(), findsNothing);
    await tester.tap(find.byKey(const Key('battle-mode-detailed')));
    await tester.pump();
    expect(find.byKey(_mapBody).hitTestable(), findsNothing);
    await tester.tap(find.byKey(_mapToggle));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(_mapBody), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('return to port and practice remove the sortie map', (
    tester,
  ) async {
    await send(_navigation(3, 100, start: true));
    await pumpCard(tester);
    expect(find.byKey(_mapSection), findsOneWidget);
    await send(portEvent);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(_mapSection), findsNothing);

    final body = jsonDecode(dayBattleEvent.responseBody) as Map;
    await send(
      kcsapiEvent(
        '/kcsapi/api_req_practice/battle',
        Map<String, Object?>.from(body['api_data'] as Map),
        sequence: 200,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(_mapSection), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown new map never reuses a label from the preceding map', (
    tester,
  ) async {
    await send(_navigation(3, 100, start: true));
    await send(
      kcsapiEvent(
        '/kcsapi/api_req_map/start',
        <String, Object?>{
          'api_no': 3,
          'api_from_no': 0,
          'api_event_id': 4,
          'api_event_kind': 1,
        },
        requestParams: <String, Object?>{
          'api_maparea_id': '99',
          'api_mapinfo_no': '5',
          'api_deck_id': '1',
        },
        sequence: 101,
      ),
    );
    await pumpCard(tester);
    expect(
      find.descendant(
        of: find.byKey(_mapSection),
        matching: find.text('99-5 · 当前 节点 3'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final width in [240.0, 280.0, 360.0, 640.0]) {
    testWidgets('real map fits existing battle UI at $width dp', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 390);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await send(_navigation(3, 100, start: true));
      await send(_navigation(5, 101));
      await send(_navigation(9, 102));
      await pumpCard(tester, width: width);
      expect(find.byKey(_mapSection), findsOneWidget);
      expect(
        tester.getSize(find.byKey(_mapSection)).width,
        closeTo(width - 24, 1),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
