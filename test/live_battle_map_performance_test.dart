import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/account/account_session.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_node_label_resolver.dart';
import 'package:yahagi_kancolle_browser/src/battle/fcd_map_dataset.dart';
import 'package:yahagi_kancolle_browser/src/battle/fcd_map_geometry.dart';
import 'package:yahagi_kancolle_browser/src/battle/live_battle_card.dart';
import 'package:yahagi_kancolle_browser/src/battle/prediction/battle_prediction_executor.dart';
import 'package:yahagi_kancolle_browser/src/battle/sortie_map_section.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_reducer.dart';

import 'fixtures/kcsapi_fixtures.dart';

CapturedApiEvent _navigation(int route, int sequence, {bool start = false}) =>
    kcsapiEvent(
      '/kcsapi/api_req_map/${start ? 'start' : 'next'}',
      <String, Object?>{
        'api_maparea_id': 2,
        'api_mapinfo_no': 5,
        'api_no': route,
        if (start) 'api_from_no': 0,
        'api_bosscell_no': 15,
        'api_event_id': 4,
        'api_event_kind': 1,
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

class _CountingResolver
    implements BattleNodeLabelResolver, BattleMapGeometryResolver {
  _CountingResolver(this.dataset)
    : geometry = dataset.geometryFor(mapAreaId: 2, mapInfoNo: 5);

  final FcdMapDataset dataset;
  FcdMapGeometry? geometry;
  int geometryReads = 0;
  final labels = <int, String>{};

  @override
  FcdMapGeometry? geometryFor({
    required int mapAreaId,
    required int mapInfoNo,
  }) {
    geometryReads++;
    return mapAreaId == 2 && mapInfoNo == 5 ? geometry : null;
  }

  @override
  String? resolve({
    required int mapAreaId,
    required int mapInfoNo,
    required int internalNodeId,
  }) =>
      labels[internalNodeId] ??
      dataset.resolve(
        mapAreaId: mapAreaId,
        mapInfoNo: mapInfoNo,
        internalNodeId: internalNodeId,
      );
}

class _Harness {
  _Harness(FcdMapDataset dataset, {this.account})
    : resolver = _CountingResolver(dataset) {
    state = reducer.reduce(GameState.empty, start2Event);
    state = reducer.reduce(state, portEvent);
  }

  final reducer = GameStateReducer();
  final _CountingResolver resolver;
  final AccountSession? account;
  late GameState state;
  late final BattleController controller = BattleController(
    gameState: () => state,
    nodeLabelResolver: resolver,
    accountSession: account,
    predictionExecutor: const ImmediateBattlePredictionExecutor(),
  );

  Future<void> send(CapturedApiEvent event) async {
    state = reducer.reduce(state, event);
    controller.accept(event);
    await controller.idle;
  }

  void dispose() => controller.dispose();
}

Future<void> _flush(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _pumpCard(
  WidgetTester tester,
  _Harness harness, {
  bool collapsed = false,
  double width = 320,
  Locale locale = const Locale('zh'),
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: width,
            child: LiveBattleCard(
              key: const PageStorageKey('live-map-performance'),
              controller: harness.controller,
              collapsed: collapsed,
              onToggleCollapse: () {},
              showEnemyPortraits: false,
            ),
          ),
        ),
      ),
    ),
  );
  await _flush(tester);
}

SortieMapSection _map(WidgetTester tester) =>
    tester.widget<SortieMapSection>(find.byType(SortieMapSection));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FcdMapDataset dataset;
  late _Harness harness;

  setUpAll(() async {
    dataset = FcdMapDataset.parse(
      await rootBundle.loadString('assets/data/fcd/map.json'),
    );
  });

  setUp(() => harness = _Harness(dataset));
  tearDown(() => harness.dispose());

  testWidgets('collapsed card never queries geometry until it is opened', (
    tester,
  ) async {
    await harness.send(_navigation(3, 100, start: true));
    await _pumpCard(tester, harness, collapsed: true);
    expect(find.byType(SortieMapSection), findsNothing);
    expect(harness.resolver.geometryReads, 0);

    harness.controller.refreshNodeLabel();
    await _flush(tester);
    expect(harness.resolver.geometryReads, 0);

    await _pumpCard(tester, harness);
    final firstMap = _map(tester);
    expect(harness.resolver.geometryReads, 1);
    await _pumpCard(tester, harness, collapsed: true);
    harness.controller.refreshNodeLabel();
    await _flush(tester);
    expect(harness.resolver.geometryReads, 1);

    await _pumpCard(tester, harness);
    expect(identical(_map(tester), firstMap), isFalse);
    expect(harness.resolver.geometryReads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('battle stages reuse the map widget until navigation changes', (
    tester,
  ) async {
    await harness.send(_navigation(3, 100, start: true));
    await _pumpCard(tester, harness);
    final firstMap = _map(tester);
    final progress = harness.controller.sortieMapProgress;
    var createdMaps = 1;
    var previousMap = firstMap;

    for (final event in [dayBattleEvent, nightBattleEvent, battleResultEvent]) {
      await harness.send(event);
      await _flush(tester);
      expect(identical(harness.controller.sortieMapProgress, progress), isTrue);
      final currentMap = _map(tester);
      if (!identical(currentMap, previousMap)) createdMaps++;
      previousMap = currentMap;
      expect(identical(currentMap, firstMap), isTrue, reason: event.path);
    }
    expect(createdMaps, 1);

    await harness.send(_navigation(5, 101));
    await _flush(tester);
    final nextMap = _map(tester);
    expect(identical(nextMap, firstMap), isFalse);
    expect(nextMap.progress.currentRouteId, 5);
    expect(find.text('2-5 · 当前 E'), findsOneWidget);

    await harness.send(_navigation(15, 102));
    await _flush(tester);
    expect(identical(_map(tester), nextMap), isFalse);
    expect(_map(tester).progress.currentRouteId, 15);
    expect(find.text('2-5 · 当前 O'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('folded map still queries replacement geometry and warns', (
    tester,
  ) async {
    await harness.send(_navigation(3, 100, start: true));
    await _pumpCard(tester, harness);
    final expandedMap = _map(tester);
    await tester.tap(find.byKey(const Key('sortie-map-toggle')));
    await _flush(tester);
    final foldedMap = _map(tester);
    expect(identical(foldedMap, expandedMap), isFalse);
    expect(foldedMap.expanded, isFalse);
    final reads = harness.resolver.geometryReads;

    harness.resolver.geometry = null;
    harness.controller.refreshNodeLabel();
    await _flush(tester);
    expect(harness.resolver.geometryReads, reads + 1);
    expect(identical(_map(tester), foldedMap), isFalse);
    expect(_map(tester).geometry, isNull);
    expect(find.byKey(const Key('sortie-map-body')), findsNothing);
    expect(find.text('该地图未更新'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('geometry and label refresh invalidate the last map widget', (
    tester,
  ) async {
    await harness.send(_navigation(3, 100, start: true));
    await _pumpCard(tester, harness);
    final firstMap = _map(tester);
    final geometry = harness.resolver.geometry!;
    harness.resolver.geometry = FcdMapGeometry(
      routes: {
        ...geometry.routes,
        3: FcdMapRoute(from: geometry.routes[3]!.from, to: 'Z'),
      },
      spots: {...geometry.spots, 'Z': geometry.spots['C']!},
    );
    harness.resolver.labels[3] = 'Z';
    harness.controller.refreshNodeLabel();
    await _flush(tester);
    final replacedMap = _map(tester);
    expect(identical(replacedMap, firstMap), isFalse);
    expect(replacedMap.geometry, same(harness.resolver.geometry));
    expect(find.text('2-5 · 当前 Z'), findsOneWidget);

    harness.resolver.geometry = null;
    harness.controller.refreshNodeLabel();
    await _flush(tester);
    final labelMap = _map(tester);
    harness.resolver.labels[3] = 'Updated';
    harness.controller.refreshNodeLabel();
    await _flush(tester);
    expect(identical(_map(tester), labelMap), isFalse);
    expect(_map(tester).currentNodeLabel, 'Updated');
    expect(find.text('2-5 · 当前 Updated'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reused map responds to width locale and text scale changes', (
    tester,
  ) async {
    await harness.send(_navigation(3, 100, start: true));
    await _pumpCard(tester, harness);
    final firstMap = _map(tester);
    final canvas = find.byKey(const Key('sortie-map-canvas'));
    final firstSize = tester.getSize(canvas);

    await _pumpCard(tester, harness, width: 640);
    expect(identical(_map(tester), firstMap), isTrue);
    expect(tester.getSize(canvas).width, greaterThan(firstSize.width));

    await _pumpCard(tester, harness, width: 640, locale: const Locale('en'));
    expect(identical(_map(tester), firstMap), isTrue);
    expect(find.text('2-5 · Current C'), findsOneWidget);
    expect(find.text('2-5 · 当前 C'), findsNothing);

    await _pumpCard(
      tester,
      harness,
      width: 640,
      locale: const Locale('en'),
      textScale: 1.4,
    );
    expect(identical(_map(tester), firstMap), isTrue);
    expect(
      MediaQuery.textScalerOf(tester.element(canvas)).scale(10),
      closeTo(14, .001),
    );
    final summary = tester.renderObject<RenderParagraph>(
      find.text('2-5 · Current C'),
    );
    expect(summary.textScaler.scale(10), closeTo(14, .001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('controller replacement and account reset discard the old map', (
    tester,
  ) async {
    await harness.send(_navigation(3, 100, start: true));
    await _pumpCard(tester, harness);
    final firstMap = _map(tester);
    final account = AccountSession(initialMemberId: 42);
    final replacement = _Harness(dataset, account: account);
    addTearDown(account.dispose);
    addTearDown(replacement.dispose);
    replacement.resolver.geometry = null;
    replacement.resolver.labels[3] = 'New account';
    await replacement.send(_navigation(3, 100, start: true));
    await _pumpCard(tester, replacement);
    expect(identical(_map(tester), firstMap), isFalse);
    expect(_map(tester).geometry, isNull);
    expect(find.text('2-5 · 当前 New account'), findsOneWidget);

    account.reset();
    await _flush(tester);
    expect(find.byType(SortieMapSection), findsNothing);
    final reads = replacement.resolver.geometryReads;
    replacement.controller.refreshNodeLabel();
    await _flush(tester);
    expect(replacement.resolver.geometryReads, reads);

    account.selectMember(43);
    replacement.resolver.labels[3] = 'Next account';
    await replacement.send(_navigation(3, 101, start: true));
    await _flush(tester);
    expect(find.text('2-5 · 当前 Next account'), findsOneWidget);
    expect(find.text('2-5 · 当前 New account'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('port and practice remove the last map without geometry reads', (
    tester,
  ) async {
    await harness.send(_navigation(3, 100, start: true));
    await _pumpCard(tester, harness);
    final firstMap = _map(tester);
    final reads = harness.resolver.geometryReads;
    await harness.send(portEvent);
    await _flush(tester);
    expect(find.byType(SortieMapSection), findsNothing);
    expect(harness.resolver.geometryReads, reads);

    await harness.send(_navigation(3, 101, start: true));
    await _flush(tester);
    expect(identical(_map(tester), firstMap), isFalse);
    final afterRestartReads = harness.resolver.geometryReads;
    final body = jsonDecode(dayBattleEvent.responseBody) as Map;
    await harness.send(
      kcsapiEvent(
        '/kcsapi/api_req_practice/battle',
        Map<String, Object?>.from(body['api_data'] as Map),
        sequence: 200,
      ),
    );
    await _flush(tester);
    expect(find.byType(SortieMapSection), findsNothing);
    expect(harness.resolver.geometryReads, afterRestartReads);
    expect(tester.takeException(), isNull);
  });
}
