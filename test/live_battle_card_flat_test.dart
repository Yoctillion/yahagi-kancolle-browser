import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_node_label_resolver.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_pills.dart';
import 'package:yahagi_kancolle_browser/src/battle/fcd_map_dataset.dart';
import 'package:yahagi_kancolle_browser/src/battle/formation_memory.dart';
import 'package:yahagi_kancolle_browser/src/battle/live_battle_card.dart';
import 'package:yahagi_kancolle_browser/src/battle/prediction/battle_prediction_executor.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_reducer.dart';
import 'package:yahagi_kancolle_browser/src/layout/panel_style.dart';

import 'fixtures/kcsapi_fixtures.dart';

const _mapSection = Key('sortie-map-section');
const _tagLine = Key('battle-navigation-tag-line');

const _pillKeys = <Key>[
  Key('node-type-pill'),
  Key('battle-last-formation-pill'),
  Key('battle-resource-changes-pill'),
  Key('battle-reward-items-pill'),
];

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

final _resourceNavigation = kcsapiEvent(
  '/kcsapi/api_req_map/next',
  <String, Object?>{
    'api_maparea_id': 2,
    'api_mapinfo_no': 2,
    'api_no': 3,
    'api_event_id': 2,
    'api_itemget': <Object?>[
      <String, Object?>{'api_usemst': 4, 'api_id': 1, 'api_getcount': 80},
      <String, Object?>{'api_usemst': 4, 'api_id': 2, 'api_getcount': 30},
      <String, Object?>{
        'api_usemst': 11,
        'api_id': 11,
        'api_getcount': 1,
        'api_name': '家具箱（中）',
      },
    ],
  },
  sequence: 8801,
);

TextSpan? _spanWithText(InlineSpan root, String text) {
  TextSpan? found;
  root.visitChildren((span) {
    if (span is TextSpan && span.text == text) {
      found = span;
      return false;
    }
    return true;
  });
  return found;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FcdMapDataset dataset;
  late GameState state;
  final reducer = GameStateReducer();
  final controllers = <BattleController>[];

  setUpAll(() async {
    dataset = FcdMapDataset.parse(
      await rootBundle.loadString('assets/data/fcd/map.json'),
    );
  });

  setUp(() {
    state = reducer.reduce(GameState.empty, start2Event);
    state = reducer.reduce(state, portEvent);
  });

  tearDown(() {
    for (final controller in controllers) {
      controller.dispose();
    }
    controllers.clear();
  });

  BattleController createController({
    bool withMap = false,
    FormationMemoryController? formationMemory,
  }) {
    final controller = BattleController(
      gameState: () => state,
      nodeLabelResolver: withMap
          ? dataset
          : const EmptyBattleNodeLabelResolver(),
      predictionExecutor: const ImmediateBattlePredictionExecutor(),
      formationMemory: formationMemory,
    );
    controllers.add(controller);
    return controller;
  }

  Future<void> send(BattleController controller, CapturedApiEvent event) async {
    state = reducer.reduce(state, event);
    controller.accept(event);
    await controller.idle;
  }

  Future<void> pumpCard(
    WidgetTester tester,
    BattleController controller, {
    bool flat = true,
    bool compact = true,
    double width = 320,
    Locale locale = const Locale('zh'),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: SingleChildScrollView(
                child: PanelStyleScope(
                  style: flat ? PanelStyle.flat : PanelStyle.card,
                  child: LiveBattleCard(
                    key: const PageStorageKey('dashboard-live-battle'),
                    controller: controller,
                    collapsed: false,
                    onToggleCollapse: () {},
                    showEnemyPortraits: false,
                  ),
                ),
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

  String mapSummary(WidgetTester tester) {
    final toggle = find.byKey(const Key('sortie-map-toggle'));
    final texts = tester
        .widgetList<Text>(
          find.descendant(of: toggle, matching: find.byType(Text)),
        )
        .map((text) => text.data ?? '')
        .toList();
    // The first Text is the section title; the summary follows it.
    return texts[1];
  }

  group('flat navigation header', () {
    for (final compact in [true, false]) {
      testWidgets('node type is text, not a pill (compact: $compact)', (
        tester,
      ) async {
        final memory = await FormationMemoryController.load(
          MemoryFormationMemoryStore(<String, int>{'1-1-1': 5}),
        );
        final controller = createController(formationMemory: memory);
        await send(controller, mapStartEvent);

        await pumpCard(tester, controller, compact: compact);

        for (final key in _pillKeys) {
          expect(find.byKey(key), findsNothing, reason: '$key');
        }
        expect(find.byType(NodeTypePill), findsNothing);
        expect(find.byType(MetaChip), findsNothing);
        final tagLine = find.byKey(_tagLine);
        expect(tagLine, findsOneWidget);
        final text = tester.widget<Text>(tagLine);
        expect(text.maxLines, 2);
        expect(text.overflow, TextOverflow.ellipsis);
        expect(text.textSpan!.toPlainText(), '节点 1 · 上次：单横阵 · 普通战斗');
        expect(
          _spanWithText(text.textSpan!, '普通战斗')!.style!.color,
          nodeTypePillColors('普通战斗').foreground,
        );
        expect(
          _spanWithText(text.textSpan!, '上次：单横阵')!.style!.color,
          const Color(0xff8197a5),
        );
        final node = _spanWithText(text.textSpan!, '节点 1')!.style!;
        expect(node.fontSize, 11);
        expect(node.fontWeight, FontWeight.w700);
        if (compact) {
          expect(
            find.descendant(
              of: find.byKey(const Key('battle-navigation-header')),
              matching: tagLine,
            ),
            findsOneWidget,
          );
        }
      });
    }

    testWidgets('resources and rewards replace the node type as text', (
      tester,
    ) async {
      final controller = createController();
      await send(controller, _resourceNavigation);

      await pumpCard(tester, controller, width: 360);

      for (final key in _pillKeys) {
        expect(find.byKey(key), findsNothing, reason: '$key');
      }
      final tagLine = find.byKey(_tagLine);
      final span = tester.widget<Text>(tagLine).textSpan!;
      final plain = span.toPlainText();
      expect(plain, contains('+80'));
      expect(plain, contains('+30'));
      expect(plain, contains('家具箱（中） ×1'));
      expect(plain, isNot(contains('资源获得')));
      expect(_spanWithText(span, '+80')!.style!.color, const Color(0xff83d5c8));
      expect(
        _spanWithText(span, '家具箱（中） ×1')!.style!.color,
        const Color(0xffd4a85f),
      );
      final icon = tester.widget<Image>(
        find.byKey(const Key('battle-resource-icon-1')),
      );
      expect(icon.width, 11);
      expect(icon.height, 11);
      expect(tester.takeException(), isNull);
    });

    testWidgets('non-flat navigation keeps its pills', (tester) async {
      final controller = createController();
      await send(controller, mapStartEvent);

      await pumpCard(tester, controller, flat: false);

      expect(find.byKey(_tagLine), findsNothing);
      expect(find.byKey(const Key('node-type-pill')), findsOneWidget);
    });

    for (final locale in const [Locale('zh'), Locale('en')]) {
      for (final compact in [true, false]) {
        testWidgets(
          'navigation fits 170 dp (${locale.languageCode}, compact: $compact)',
          (tester) async {
            final memory = await FormationMemoryController.load(
              MemoryFormationMemoryStore(<String, int>{'2-5-3': 14}),
            );
            final controller = createController(
              withMap: true,
              formationMemory: memory,
            );
            await send(
              controller,
              _navigation(3, 100, start: true, preview: true),
            );

            await pumpCard(
              tester,
              controller,
              compact: compact,
              width: 170,
              locale: locale,
            );

            expect(tester.takeException(), isNull);
            expect(find.byType(ErrorWidget), findsNothing);
            expect(find.byKey(_tagLine), findsOneWidget);
          },
        );
      }
    }
  });

  group('flat sortie map', () {
    testWidgets('navigation summary keeps only the sea area', (tester) async {
      final controller = createController(withMap: true);
      await send(controller, _navigation(3, 100, start: true));
      await send(controller, _navigation(5, 101));

      await pumpCard(tester, controller);

      final summary = mapSummary(tester);
      expect(summary, '2-5');
      expect(
        find.descendant(
          of: find.byKey(_mapSection),
          matching: find.textContaining('当前'),
        ),
        findsNothing,
      );
    });

    testWidgets('non-flat summary still names the current node', (
      tester,
    ) async {
      final controller = createController(withMap: true);
      await send(controller, _navigation(3, 100, start: true));
      await send(controller, _navigation(5, 101));

      await pumpCard(tester, controller, flat: false);

      expect(mapSummary(tester), allOf(contains('2-5'), contains('当前')));
    });

    testWidgets('idle summary still names the current node', (tester) async {
      final controller = createController(withMap: true);
      // Only the game state knows about the sortie (attached mid-sortie), so
      // the card is idle while the fallback map progress exists.
      state = reducer.reduce(state, _navigation(3, 100, start: true));

      await pumpCard(tester, controller, compact: false);

      expect(find.byKey(const Key('battle-idle-content')), findsOneWidget);
      expect(find.byKey(_mapSection), findsOneWidget);
      expect(mapSummary(tester), allOf(contains('2-5'), contains('当前')));
    });

    testWidgets('section has no fill and a short header', (tester) async {
      final controller = createController(withMap: true);
      await send(controller, _navigation(3, 100, start: true));

      await pumpCard(tester, controller, flat: false);
      final cardToggleHeight = tester
          .getSize(find.byKey(const Key('sortie-map-toggle')))
          .height;
      final cardMaterial = tester.widget<Material>(find.byKey(_mapSection));
      expect(cardMaterial.color, const Color(0xff10212e));

      await pumpCard(tester, controller);
      final material = tester.widget<Material>(find.byKey(_mapSection));
      expect(material.type, MaterialType.transparency);
      expect(material.borderRadius, isNull);
      final toggleHeight = tester
          .getSize(find.byKey(const Key('sortie-map-toggle')))
          .height;
      expect(toggleHeight, lessThan(30));
      expect(toggleHeight, lessThan(cardToggleHeight));
      final body = tester.widget<Container>(
        find.byKey(const Key('sortie-map-body')),
      );
      expect(body.decoration, isNull);
      expect(body.padding, const EdgeInsets.fromLTRB(0, 2, 0, 4));
    });
  });

  group('flat navigation sections', () {
    for (final compact in [true, false]) {
      testWidgets('enemy preview and fleets lose their blocks ($compact)', (
        tester,
      ) async {
        final controller = createController(withMap: true);
        await send(controller, _navigation(3, 100, start: true, preview: true));

        await pumpCard(tester, controller, compact: compact);

        final preview = find.byKey(const Key('official-enemy-preview'));
        expect(tester.widget<Container>(preview).decoration, isNull);
        final fleets = find.byKey(const Key('navigation-friendly-fleets'));
        for (final container in tester.widgetList<Container>(
          find.descendant(of: fleets, matching: find.byType(Container)),
        )) {
          final decoration = container.decoration;
          if (decoration is BoxDecoration) {
            expect(decoration.color, isNot(const Color(0xff10212e)));
          }
        }
        for (final divider in tester.widgetList<Divider>(
          find.descendant(of: fleets, matching: find.byType(Divider)),
        )) {
          expect(divider.color, const Color(0xff1b3142));
        }
        // Sections stack at the flat 4 dp rhythm.
        expect(
          tester.getTopLeft(preview).dy -
              tester.getBottomLeft(find.byKey(_mapSection)).dy,
          4,
        );
        final firstShip = find.byKey(const Key('battle-ship-friend-0'));
        expect(
          tester.widget<Padding>(firstShip).padding,
          const EdgeInsets.symmetric(vertical: 2),
        );
      });
    }
  });
}
