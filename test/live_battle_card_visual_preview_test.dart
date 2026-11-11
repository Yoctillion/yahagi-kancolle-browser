// Renders the flat compact battle panel to PNGs for visual review.
//
// Skipped unless BATTLE_PANEL_PREVIEW_DIR names an output directory:
//   BATTLE_PANEL_PREVIEW_DIR=build/battle_panel_preview \
//     flutter test test/live_battle_card_visual_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/enemy_fleet_name_memory.dart';
import 'package:yahagi_kancolle_browser/src/battle/fcd_map_dataset.dart';
import 'package:yahagi_kancolle_browser/src/battle/formation_memory.dart';
import 'package:yahagi_kancolle_browser/src/battle/live_battle_card.dart';
import 'package:yahagi_kancolle_browser/src/battle/prediction/battle_prediction_executor.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_reducer.dart';
import 'package:yahagi_kancolle_browser/src/layout/panel_style.dart';

import 'fixtures/kcsapi_fixtures.dart';

const _boundary = Key('battle-panel-preview-root');
final _outputDirectory = Platform.environment['BATTLE_PANEL_PREVIEW_DIR'];
const _font = 'HarmonyOS_Sans_SC';

CapturedApiEvent _map(int route, int sequence, {bool preview = false}) =>
    kcsapiEvent(
      '/kcsapi/api_req_map/${sequence % 10 == 0 ? 'start' : 'next'}',
      <String, Object?>{
        'api_maparea_id': 7,
        'api_mapinfo_no': 1,
        'api_no': route,
        if (sequence % 10 == 0) 'api_from_no': 0,
        'api_bosscell_no': 11,
        'api_event_id': 5,
        'api_event_kind': 1,
        if (preview)
          'api_e_deck_info': <Object?>[
            <String, Object?>{
              'api_ship_ids': <int>[101, 102, 102],
              'api_deck_type': 0,
            },
          ],
      },
      sequence: sequence,
      requestParams: <String, Object?>{'api_deck_id': '1'},
    );

CapturedApiEvent _battle(int sequence) =>
    kcsapiEvent('/kcsapi/api_req_sortie/battle', <String, Object?>{
      'api_deck_id': 1,
      'api_formation': <int>[5, 4, 1],
      'api_disp_seiku': 1,
      'api_f_nowhps': <int>[31, 47],
      'api_f_maxhps': <int>[31, 47],
      'api_e_nowhps': <int>[48, 34, 34],
      'api_e_maxhps': <int>[48, 34, 34],
      'api_ship_ke': <int>[101, 102, 102],
      'api_ship_lv': <int>[1, 1, 1],
      'api_raigeki': <String, Object?>{
        'api_fdam': <num>[0, 0],
        'api_edam': <num>[138, 117, 108],
      },
    }, sequence: sequence);

Map<String, Object?> _stage1(
  int fc,
  int fl,
  int ec,
  int el, {
  bool touch = false,
}) => <String, Object?>{
  'api_f_count': fc,
  'api_f_lostcount': fl,
  'api_e_count': ec,
  'api_e_lostcount': el,
  'api_disp_seiku': 1,
  if (touch) 'api_touch_plane': <int>[54, 102],
};

Map<String, Object?> _stage2(
  int fc,
  int fl,
  int ec,
  int el, {
  bool cutIn = false,
}) => <String, Object?>{
  'api_f_count': fc,
  'api_f_lostcount': fl,
  'api_e_count': ec,
  'api_e_lostcount': el,
  if (cutIn)
    'api_air_fire': <String, Object?>{
      'api_idx': 1,
      'api_kind': 5,
      'api_use_items': <int>[1],
    },
};

Map<String, Object?> _stage3(List<num> fdam, List<num> edam) =>
    <String, Object?>{
      'api_fdam': fdam,
      'api_edam': edam,
      'api_fbak_flag': <int>[for (final d in fdam) d > 0 ? 1 : 0],
      'api_ebak_flag': <int>[for (final d in edam) d > 0 ? 1 : 0],
      'api_frai_flag': <int>[for (final _ in fdam) 0],
      'api_erai_flag': <int>[for (final _ in edam) 0],
    };

Map<String, Object?> _landBase(int id) => <String, Object?>{
  'api_base_id': id,
  'api_stage1': _stage1(18, 0, 50, 10),
  'api_stage2': _stage2(18, 0, 40, 0),
  'api_stage3': _stage3(const <num>[0, 0], <num>[40, 0, 0]),
};

CapturedApiEvent _airBattle(int sequence) =>
    kcsapiEvent('/kcsapi/api_req_sortie/battle', <String, Object?>{
      'api_deck_id': 1,
      'api_formation': <int>[5, 4, 1],
      'api_disp_seiku': 1,
      'api_f_nowhps': <int>[31, 47],
      'api_f_maxhps': <int>[31, 47],
      'api_e_nowhps': <int>[48, 34, 34],
      'api_e_maxhps': <int>[48, 34, 34],
      'api_ship_ke': <int>[101, 102, 102],
      'api_ship_lv': <int>[1, 1, 1],
      'api_injection_kouku': <String, Object?>{
        'api_stage1': _stage1(12, 1, 135, 9),
        'api_stage2': _stage2(12, 1, 100, 4),
        'api_stage3': _stage3(<num>[0, 0], <num>[30, 0, 0]),
      },
      'api_air_base_injection': <String, Object?>{
        'api_stage1': _stage1(36, 0, 80, 8),
        'api_stage2': _stage2(36, 14, 60, 0),
        'api_stage3': _stage3(const <num>[0, 0], <num>[50, 0, 0]),
      },
      'api_air_base_attack': <Object?>[_landBase(1), _landBase(1)],
      'api_support_flag': 1,
      'api_support_info': <String, Object?>{
        'api_support_airatack': <String, Object?>{
          'api_stage3': _stage3(const <num>[0, 0], <num>[20, 10, 0]),
        },
      },
      'api_kouku': <String, Object?>{
        'api_stage1': _stage1(168, 10, 156, 90, touch: true),
        'api_stage2': _stage2(102, 6, 58, 25, cutIn: true),
        'api_stage3': _stage3(<num>[0, 28], <num>[20, 15, 0]),
      },
      'api_kouku2': <String, Object?>{
        'api_stage1': _stage1(0, 2, 0, 8),
        'api_stage2': _stage2(0, 2, 0, 6),
        'api_stage3': _stage3(<num>[0, 0], <num>[10, 0, 0]),
      },
    }, sequence: sequence);

CapturedApiEvent _nightBattle(int sequence) =>
    kcsapiEvent('/kcsapi/api_req_battle_midnight/battle', <String, Object?>{
      'api_f_nowhps': <int>[31, 19],
      'api_f_maxhps': <int>[31, 47],
      'api_e_nowhps': <int>[0, 34, 34],
      'api_e_maxhps': <int>[48, 34, 34],
      'api_flare_pos': <int>[0, 2],
      'api_touch_plane': <int>[100, -1],
      'api_hougeki': <String, Object?>{
        'api_at_eflag': <int>[0],
        'api_at_list': <int>[0],
        'api_at_type': <int>[0],
        'api_df_list': <Object?>[
          <int>[0],
        ],
        'api_damage': <Object?>[
          <num>[48],
        ],
      },
    }, sequence: sequence);

CapturedApiEvent _result(int sequence, String name) =>
    kcsapiEvent('/kcsapi/api_req_sortie/battleresult', <String, Object?>{
      'api_win_rank': 'S',
      'api_mvp': 2,
      'api_enemy_info': <String, Object?>{'api_deck_name': name},
      'api_get_ship': <String, Object?>{'api_ship_id': 102},
    }, sequence: sequence);

void main() {
  late FcdMapDataset dataset;
  late GameState state;
  final reducer = GameStateReducer();

  setUpAll(() async {
    dataset = FcdMapDataset.parse(
      await rootBundle.loadString('assets/data/fcd/map.json'),
    );
    if (_outputDirectory == null) return;
    await Directory(_outputDirectory!).create(recursive: true);
    await _loadFont(_font, 'assets/fonts/HarmonyOS_Sans_SC.ttf');
    var directory = File(Platform.resolvedExecutable).parent;
    while (directory.parent.path != directory.path) {
      final font = File(
        '${directory.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      );
      if (font.existsSync()) {
        await _loadFont('MaterialIcons', font.path);
        break;
      }
      directory = directory.parent;
    }
  });

  testWidgets('flat compact battle panel previews', (tester) async {
    state = reducer.reduce(GameState.empty, start2Event);
    state = reducer.reduce(state, portEvent);
    final names = await EnemyFleetNameMemory.load(MemoryEnemyFleetNameStore());
    final controller = BattleController(
      gameState: () => state,
      nodeLabelResolver: dataset,
      predictionExecutor: const ImmediateBattlePredictionExecutor(),
      formationMemory: await FormationMemoryController.load(
        MemoryFormationMemoryStore(),
      ),
      enemyFleetNames: names,
    );
    addTearDown(controller.dispose);
    Future<void> send(CapturedApiEvent event) async {
      state = reducer.reduce(state, event);
      controller.accept(event);
      await controller.idle;
    }

    Future<void> sortieToK(int base, {required bool preview}) async {
      await send(_map(6, base));
      await send(_map(15, base + 1));
      await send(_map(8, base + 2));
      await send(_map(11, base + 3, preview: preview));
    }

    await _pump(tester, controller);
    await tester.tap(find.byKey(const Key('battle-mode-compact')));
    await tester.pump();

    await sortieToK(10, preview: true);
    await _capture(tester, '1-navigation-first-visit');

    await send(_battle(14));
    await send(_result(15, '深海潜水艦隊集団 旗艦戦隊'));
    // The map starts expanded.
    await _capture(tester, '2-result-map-expanded');
    await tester.tap(find.byKey(const Key('sortie-map-toggle')));
    await tester.pump();
    await _capture(tester, '3-result-map-collapsed');

    await sortieToK(20, preview: true);
    await _capture(tester, '4-navigation-remembered-preview');
    await sortieToK(30, preview: false);
    await _capture(tester, '5-navigation-remembered-no-preview');

    await send(_battle(34));
    await send(_result(35, '深海東洋艦隊 機動部隊群 前衛主力打撃艦隊'));
    await _capture(tester, '6-result-long-name');
  }, skip: _outputDirectory == null);

  testWidgets('flat detailed battle panel previews', (tester) async {
    state = reducer.reduce(GameState.empty, start2Event);
    state = reducer.reduce(state, portEvent);
    final controller = BattleController(
      gameState: () => state,
      nodeLabelResolver: dataset,
      predictionExecutor: const ImmediateBattlePredictionExecutor(),
      formationMemory: await FormationMemoryController.load(
        MemoryFormationMemoryStore(),
      ),
      enemyFleetNames: await EnemyFleetNameMemory.load(
        MemoryEnemyFleetNameStore(),
      ),
    );
    addTearDown(controller.dispose);
    Future<void> send(CapturedApiEvent event) async {
      state = reducer.reduce(state, event);
      controller.accept(event);
      await controller.idle;
    }

    Future<void> sortieToK(int base) async {
      await send(_map(6, base));
      await send(_map(15, base + 1));
      await send(_map(8, base + 2));
      await send(_map(11, base + 3, preview: true));
    }

    await _pump(tester, controller);
    // A warm-up sortie fills formation memory so navigation shows the grid.
    await sortieToK(40);
    await send(_battle(44));
    await send(_result(45, '深海潜水艦隊集団 旗艦戦隊'));

    await sortieToK(50);
    await tester.pump(const Duration(seconds: 2));
    await _capture(tester, '7-detailed-navigation');

    await send(_battle(54));
    await send(_result(55, '深海潜水艦隊集団 旗艦戦隊'));
    await _capture(tester, '8-detailed-result-plain');

    await sortieToK(60);
    await send(_airBattle(64));
    await _capture(tester, '9-detailed-result-air');

    await send(_nightBattle(65));
    await _capture(tester, '10-detailed-night');

    await tester.tap(find.byKey(const Key('battle-mode-compact')));
    await tester.pump();
    await _capture(tester, '11-compact-ghost');
  }, skip: _outputDirectory == null);
}

Future<void> _loadFont(String family, String path) async {
  await (FontLoader(family)..addFont(
        Future<ByteData>.value(
          ByteData.sublistView(await File(path).readAsBytes()),
        ),
      ))
      .load();
}

Future<void> _pump(WidgetTester tester, BattleController controller) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(420, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      theme: ThemeData(brightness: Brightness.dark, fontFamily: _font),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        backgroundColor: const Color(0xff0f1b26),
        body: Align(
          alignment: Alignment.topLeft,
          child: SingleChildScrollView(
            child: RepaintBoundary(
              key: _boundary,
              child: Container(
                width: 210,
                color: const Color(0xff0f1b26),
                child: PanelStyleScope(
                  style: PanelStyle.flat,
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
    ),
  );
}

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 200));
  expect(tester.takeException(), isNull, reason: name);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundary),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$_outputDirectory/$name.png').writeAsBytes(
        data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  });
}
