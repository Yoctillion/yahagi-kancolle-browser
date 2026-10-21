import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_detail_strings.dart';
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
const _formationLine = Key('compact-formation-line');
const _dropLine = Key('battle-drop-line');
const _battleTagLine = Key('battle-tag-line');
const _appFont = 'HarmonyOS_Sans_SC';

CapturedApiEvent _battleWithFormation(List<int>? formation) =>
    kcsapiEvent('/kcsapi/api_req_sortie/battle', <String, Object?>{
      'api_deck_id': 1,
      'api_formation': ?formation,
      'api_f_nowhps': <int>[30, 15],
      'api_f_maxhps': <int>[30, 15],
      'api_e_nowhps': <int>[20, 10],
      'api_e_maxhps': <int>[20, 10],
      'api_ship_ke': <int>[501, 502],
      'api_ship_lv': <int>[1, 1],
    }, sequence: 21);

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

List<RenderParagraph> _paragraphsUnder(WidgetTester tester, Finder root) =>
    tester
        .renderObjectList<RenderParagraph>(
          find.descendant(of: root, matching: find.byType(RichText)),
        )
        .toList();

String _plainTextUnder(WidgetTester tester, Finder root) => _paragraphsUnder(
  tester,
  root,
).map((paragraph) => paragraph.text.toPlainText()).join('\n');

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
    String? fontFamily,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        theme: fontFamily == null ? null : ThemeData(fontFamily: fontFamily),
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
    // The summary is the single-line end-aligned Text; the "map needs an
    // update" notice is end-aligned too but allows two lines.
    final summary = tester
        .widgetList<Text>(
          find.descendant(of: toggle, matching: find.byType(Text)),
        )
        .where((text) => text.textAlign == TextAlign.end && text.maxLines == 1)
        .single;
    return summary.data ?? '';
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
        final containers = tester
            .widgetList<Container>(
              find.descendant(of: fleets, matching: find.byType(Container)),
            )
            .toList();
        expect(containers, isNotEmpty);
        for (final container in containers) {
          final decoration = container.decoration;
          if (decoration is BoxDecoration) {
            expect(decoration.color, isNot(const Color(0xff10212e)));
          }
        }
        final dividers = tester
            .widgetList<Divider>(
              find.descendant(of: fleets, matching: find.byType(Divider)),
            )
            .toList();
        expect(dividers, isNotEmpty);
        for (final divider in dividers) {
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

  group('flat battle result', () {
    setUpAll(() async {
      await (FontLoader(
        _appFont,
      )..addFont(rootBundle.load('assets/fonts/HarmonyOS_Sans_SC.ttf'))).load();
    });

    Future<BattleController> resultController() async {
      final controller = createController();
      await send(controller, mapStartEvent);
      await send(controller, dayBattleEvent);
      await send(controller, battleResultEvent);
      return controller;
    }

    for (final locale in const [Locale('zh'), Locale('en')]) {
      final strings = BattleDetailStrings.forLocale(locale);
      final engagement = strings.localize('同航战');
      final formation = strings.localize('单纵阵');
      for (final width in const <double>[170, 210]) {
        testWidgets('engagement, drop and tags stay whole at $width dp '
            '(${locale.languageCode})', (tester) async {
          final controller = await resultController();

          await pumpCard(
            tester,
            controller,
            width: width,
            locale: locale,
            fontFamily: _appFont,
          );

          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const Key('compact-fleet-side-title-friend')),
            findsNothing,
          );
          expect(
            find.byKey(const Key('compact-fleet-side-title-enemy')),
            findsNothing,
          );
          final line = find.byKey(_formationLine);
          expect(line, findsOneWidget);
          final lineText = _plainTextUnder(tester, line);
          expect(lineText, contains(engagement));
          expect(lineText, contains(formation));
          for (final paragraph in _paragraphsUnder(tester, line)) {
            expect(paragraph.didExceedMaxLines, isFalse);
          }

          final drop = find.byKey(_dropLine);
          expect(drop, findsOneWidget);
          final dropText = tester.widget<Text>(
            find.descendant(of: drop, matching: find.byType(Text)),
          );
          expect(dropText.maxLines, isNull);
          expect(dropText.overflow, isNot(TextOverflow.ellipsis));
          final dropPlain = _plainTextUnder(tester, drop);
          if (locale.languageCode == 'zh') {
            expect(dropPlain, contains('掉落：吹雪'));
          } else {
            expect(dropPlain, contains('Drop: '));
          }
          expect(dropPlain, contains(' ×1'));
          for (final paragraph in _paragraphsUnder(tester, drop)) {
            expect(paragraph.didExceedMaxLines, isFalse);
          }

          final tags = find.byKey(_battleTagLine);
          final tagText = _plainTextUnder(tester, tags);
          expect(tagText, isNot(contains(engagement)));
          expect(tagText, isNot(contains(dropPlain)));
          // The tag line may still ellipsize its tail (the phase at 170 dp in
          // English), but never the air state.
          final tagParagraph = _paragraphsUnder(tester, tags).single;
          final air = lookupAppLocalizations(
            locale,
          ).airStateLabel(strings.localize('未知'));
          final airStart = tagText.indexOf(air);
          expect(airStart, isNonNegative);
          final visibleEnd = tagParagraph
              .getPositionForOffset(
                Offset(tagParagraph.size.width, tagParagraph.size.height - 1),
              )
              .offset;
          expect(visibleEnd, greaterThanOrEqualTo(airStart + air.length));
          expect(
            find.descendant(
              of: find.byKey(const Key('battle-rank-badge')),
              matching: find.text('S'),
            ),
            findsOneWidget,
          );
        });
      }
    }

    testWidgets('wide line aligns formations to the fleet edges', (
      tester,
    ) async {
      final controller = await resultController();

      await pumpCard(tester, controller, width: 360, fontFamily: _appFont);

      final line = find.byKey(_formationLine);
      final grid = find.byKey(const Key('compact-fleet-grid'));
      final formations = find.descendant(of: line, matching: find.text('单纵阵'));
      expect(formations, findsNWidgets(2));
      final engagement = find.descendant(of: line, matching: find.text('同航战'));
      expect(engagement, findsOneWidget);
      expect(
        tester.getTopLeft(formations.first).dx,
        tester.getTopLeft(grid).dx,
      );
      expect(
        tester.getTopRight(formations.last).dx,
        moreOrLessEquals(tester.getTopRight(grid).dx),
      );
      expect(
        tester.getCenter(engagement).dx,
        moreOrLessEquals(tester.getCenter(grid).dx),
      );
      final engagementStyle = tester.widget<Text>(engagement).style!;
      expect(engagementStyle.color, const Color(0xffdfe8ee));
      expect(engagementStyle.fontSize, 10.5);
      expect(engagementStyle.fontWeight, FontWeight.w700);
      expect(
        tester.widget<Text>(formations.first).style!.color,
        const Color(0xff70c7bc),
      );
      expect(
        tester.widget<Text>(formations.last).style!.color,
        const Color(0xffff8c78),
      );
      final dropText = tester.widget<Text>(
        find.descendant(of: find.byKey(_dropLine), matching: find.byType(Text)),
      );
      expect(dropText.style!.color, const Color(0xffd4a85f));
      expect(dropText.style!.fontSize, 10.5);
      expect(dropText.style!.fontWeight, FontWeight.w600);
      expect(
        tester
                .getTopLeft(
                  find.descendant(
                    of: find.byKey(_dropLine),
                    matching: find.byType(Text),
                  ),
                )
                .dy -
            tester.getBottomLeft(find.byKey(_battleTagLine)).dy,
        2,
      );
    });

    testWidgets('without engagement the formations keep the fleet edges', (
      tester,
    ) async {
      final controller = createController();
      await send(controller, mapStartEvent);
      await send(controller, _battleWithFormation(<int>[1, 2, 0]));

      await pumpCard(tester, controller, width: 360, fontFamily: _appFont);

      final line = find.byKey(_formationLine);
      final grid = find.byKey(const Key('compact-fleet-grid'));
      expect(_plainTextUnder(tester, line), isNot(contains('同航战')));
      final friend = find.descendant(of: line, matching: find.text('单纵阵'));
      final enemy = find.descendant(of: line, matching: find.text('复纵阵'));
      expect(tester.getTopLeft(friend).dx, tester.getTopLeft(grid).dx);
      expect(
        tester.getTopRight(enemy).dx,
        moreOrLessEquals(tester.getTopRight(grid).dx),
      );
    });

    testWidgets('a missing formation leaves the other slots in place', (
      tester,
    ) async {
      final controller = createController();
      await send(controller, mapStartEvent);
      await send(controller, _battleWithFormation(<int>[0, 1, 1]));

      await pumpCard(tester, controller, width: 360, fontFamily: _appFont);

      final line = find.byKey(_formationLine);
      final grid = find.byKey(const Key('compact-fleet-grid'));
      final enemy = find.descendant(of: line, matching: find.text('单纵阵'));
      expect(enemy, findsOneWidget);
      final engagement = find.descendant(of: line, matching: find.text('同航战'));
      expect(
        tester.getCenter(engagement).dx,
        moreOrLessEquals(tester.getCenter(grid).dx),
      );
      expect(
        tester.getTopRight(enemy).dx,
        moreOrLessEquals(tester.getTopRight(grid).dx),
      );
    });

    testWidgets('line is omitted when formations and engagement are unknown', (
      tester,
    ) async {
      final controller = createController();
      await send(controller, mapStartEvent);
      await send(controller, _battleWithFormation(null));

      await pumpCard(tester, controller);

      expect(find.byKey(const Key('compact-fleet-grid')), findsOneWidget);
      expect(find.byKey(_formationLine), findsNothing);
      expect(
        find.descendant(of: find.byKey(_dropLine), matching: find.byType(Text)),
        findsNothing,
      );
      expect(tester.getSize(find.byKey(_dropLine)).height, 0);
    });

    testWidgets('non-flat compact keeps the side titles', (tester) async {
      final controller = await resultController();

      await pumpCard(tester, controller, flat: false);

      expect(
        find.byKey(const Key('compact-fleet-side-title-friend')),
        findsOneWidget,
      );
      expect(find.byKey(_formationLine), findsNothing);
      expect(find.byKey(_dropLine), findsNothing);
    });
  });
}
