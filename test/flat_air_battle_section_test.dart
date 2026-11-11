import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_air_report.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_models.dart';
import 'package:yahagi_kancolle_browser/src/battle/flat_air_battle_section.dart';
import 'package:yahagi_kancolle_browser/src/battle/live_battle_card.dart';
import 'package:yahagi_kancolle_browser/src/battle/prediction/battle_prediction_engine.dart';
import 'package:yahagi_kancolle_browser/src/battle/prediction/battle_prediction_executor.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_reducer.dart';
import 'package:yahagi_kancolle_browser/src/layout/flat_style.dart';
import 'package:yahagi_kancolle_browser/src/layout/panel_style.dart';

import 'fixtures/kcsapi_fixtures.dart';

BattleShipSnapshot _ship(String name, int index, {bool escort = false}) =>
    BattleShipSnapshot(
      masterId: 100 + index,
      name: name,
      side: BattleSide.friend,
      fleetRole: escort ? BattleFleetRole.escort : BattleFleetRole.main,
      position: index,
      initialHp: 30,
      maxHp: 30,
      currentHp: 30,
    );

final _main = [for (var i = 0; i < 7; i++) _ship('主$i', i)];
final _escort = [for (var i = 0; i < 6; i++) _ship('随$i', i, escort: true)];

const _slotItems = <int, MasterSlotItem>{
  7: MasterSlotItem(id: 7, name: '彩云'),
  8: MasterSlotItem(id: 8, name: '九七式艦攻'),
};

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('zh'),
}) => tester.pumpWidget(
  MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 210,
          child: PanelStyleScope(style: PanelStyle.flat, child: child),
        ),
      ),
    ),
  ),
);

Finder _rich(String text) => find.textContaining(text, findRichText: true);

const _fullReport = DayAirReport(
  jet: PlaneExchange(friend: PlaneCount(8, 0), enemy: PlaneCount(20, 4)),
  fighter: PlaneExchange(friend: PlaneCount(12, 1), enemy: PlaneCount(135, 9)),
  antiAir: PlaneExchange(friend: PlaneCount(30, 2), enemy: PlaneCount(40, 5)),
  secondWave: true,
  friendContactPlaneId: 7,
  enemyContactPlaneId: 8,
  antiAirCutIns: [
    AntiAirCutIn(position: 1, kind: 5),
    AntiAirCutIn(position: 7, kind: 9),
  ],
);

void main() {
  testWidgets('renders main table with jet row and second wave', (
    tester,
  ) async {
    await _pump(
      tester,
      FlatAirBattleSection(
        report: _fullReport,
        friendShips: [..._main.take(6), ..._escort],
        slotItems: _slotItems,
      ),
    );
    expect(find.text('航空战 ×2'), findsOneWidget);
    expect(find.text('喷气'), findsOneWidget);
    expect(find.text('制空战'), findsOneWidget);
    expect(find.text('对空'), findsOneWidget);
    expect(_rich('12 −1'), findsOneWidget);
    expect(_rich('135 −9'), findsOneWidget);
    expect(_rich('触接 彩云 / 九七式艦攻'), findsOneWidget);
    expect(_rich('对空CI 主1'), findsOneWidget);
    expect(_rich('对空CI 随1'), findsOneWidget);
  });

  testWidgets('hides jet row without jets', (tester) async {
    await _pump(
      tester,
      FlatAirBattleSection(
        report: const DayAirReport(
          fighter: PlaneExchange(
            friend: PlaneCount(12, 0),
            enemy: PlaneCount(3, 3),
          ),
        ),
        friendShips: _main,
        slotItems: _slotItems,
      ),
    );
    expect(find.text('喷气'), findsNothing);
    expect(find.text('对空'), findsOneWidget);
    expect(_rich('12 −0'), findsOneWidget);
  });

  testWidgets('keeps a land-base jet phase row on one line at 210px', (
    tester,
  ) async {
    await _pump(
      tester,
      FlatAirBattleSection(
        report: const DayAirReport(
          phases: [
            AirPhaseLine(
              kind: AirPhaseKind.landBaseJet,
              planes: PlaneExchange(
                friend: PlaneCount(36, 14),
                enemy: PlaneCount(80, 8),
              ),
              damage: 50,
            ),
          ],
        ),
        friendShips: _main,
        slotItems: _slotItems,
      ),
    );
    final value = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().contains('伤害 50'),
    );
    expect(value, findsOneWidget);
    expect(
      tester
          .getSize(find.ancestor(of: value, matching: find.byType(FittedBox)))
          .height,
      lessThan(flatAirPhaseFontSize * 1.5),
    );
  });

  testWidgets('lists phases in order', (tester) async {
    await _pump(
      tester,
      FlatAirBattleSection(
        report: const DayAirReport(
          phases: [
            AirPhaseLine(
              kind: AirPhaseKind.landBaseJet,
              planes: PlaneExchange(enemy: PlaneCount(10, 2)),
            ),
            AirPhaseLine(
              kind: AirPhaseKind.landBase,
              baseId: 1,
              wave: 1,
              planes: PlaneExchange(enemy: PlaneCount(10, 2)),
            ),
            AirPhaseLine(
              kind: AirPhaseKind.landBase,
              baseId: 1,
              wave: 2,
              planes: PlaneExchange(enemy: PlaneCount(8, 1)),
            ),
            AirPhaseLine(kind: AirPhaseKind.supportAir, damage: 90),
          ],
        ),
        friendShips: _main,
        slotItems: _slotItems,
      ),
    );
    final ys = [
      for (final label in ['基地喷气', '基地 1-1', '基地 1-2', '支援·航空'])
        tester.getTopLeft(find.text(label)).dy,
    ];
    for (var i = 1; i < ys.length; i++) {
      expect(ys[i], greaterThan(ys[i - 1]));
    }
    expect(_rich('伤害 90'), findsOneWidget);
  });

  testWidgets('names the escort ship for combined flare', (tester) async {
    await _pump(
      tester,
      FlatNightBattleSection(
        report: const NightReport(
          friendFlarePosition: 9,
          enemyFlarePosition: 8,
        ),
        friendMain: _main.take(6).toList(),
        friendEscort: _escort,
        enemyEscort: _escort,
        slotItems: _slotItems,
      ),
    );
    expect(_rich('我 #4 随3'), findsOneWidget);
    expect(_rich('敌 #3'), findsOneWidget);
  });

  testWidgets('maps raw flare 6 to the seventh ship of a single fleet', (
    tester,
  ) async {
    await _pump(
      tester,
      FlatNightBattleSection(
        report: const NightReport(
          friendFlarePosition: 6,
          enemyFlarePosition: 6,
        ),
        friendMain: _main,
        friendEscort: const [],
        enemyEscort: const [],
        slotItems: _slotItems,
      ),
    );
    expect(_rich('我 #7 主6'), findsOneWidget);
    expect(_rich('敌 #7'), findsOneWidget);
  });

  testWidgets('guards out-of-range flare index', (tester) async {
    await _pump(
      tester,
      FlatNightBattleSection(
        report: const NightReport(friendFlarePosition: 5),
        friendMain: _main.take(2).toList(),
        friendEscort: const [],
        enemyEscort: const [],
        slotItems: _slotItems,
      ),
    );
    expect(_rich('我 #6'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits 210px in English with every phase present', (tester) async {
    final report = DayAirReport(
      jet: _fullReport.jet,
      fighter: _fullReport.fighter,
      antiAir: _fullReport.antiAir,
      secondWave: true,
      friendContactPlaneId: 7,
      enemyContactPlaneId: 8,
      antiAirCutIns: _fullReport.antiAirCutIns,
      phases: [
        const AirPhaseLine(
          kind: AirPhaseKind.landBaseJet,
          planes: PlaneExchange(
            friend: PlaneCount(18, 2),
            enemy: PlaneCount(120, 33),
          ),
          damage: 1234,
        ),
        for (var b = 1; b <= 3; b++)
          for (var w = 1; w <= 2; w++)
            AirPhaseLine(
              kind: AirPhaseKind.landBase,
              baseId: b,
              wave: w,
              planes: const PlaneExchange(
                friend: PlaneCount(18, 2),
                enemy: PlaneCount(120, 33),
              ),
              damage: 345,
            ),
        const AirPhaseLine(
          kind: AirPhaseKind.friendly,
          planes: PlaneExchange(
            friend: PlaneCount(18, 2),
            enemy: PlaneCount(120, 33),
          ),
        ),
        const AirPhaseLine(kind: AirPhaseKind.supportShelling, damage: 321),
      ],
    );
    await _pump(
      tester,
      SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlatAirBattleSection(
              report: report,
              friendShips: [..._main.take(6), ..._escort],
              slotItems: _slotItems,
            ),
            FlatNightBattleSection(
              report: const NightReport(
                friendContactPlaneId: 7,
                enemyContactPlaneId: 8,
                friendFlarePosition: 9,
                enemyFlarePosition: 2,
                supportDamage: 456,
              ),
              friendMain: _main.take(6).toList(),
              friendEscort: _escort,
              enemyEscort: _escort,
              slotItems: _slotItems,
            ),
          ],
        ),
      ),
      locale: const Locale('en'),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Night'), findsOneWidget);
  });

  testWidgets('panel shows sections only in detailed mode', (tester) async {
    final reducer = GameStateReducer();
    var state = reducer.reduce(GameState.empty, start2Event);
    state = reducer.reduce(state, portEvent);
    final controller = BattleController(
      gameState: () => state,
      predictionExecutor: const _InlineExecutor(),
    );
    addTearDown(controller.dispose);
    final decoded =
        jsonDecode(dayBattleEvent.responseBody) as Map<String, dynamic>;
    final data = Map<String, Object?>.from(decoded['api_data'] as Map);
    data['api_kouku'] = <String, Object?>{
      'api_stage1': <String, Object?>{
        'api_disp_seiku': 1,
        'api_f_count': 12,
        'api_f_lostcount': 1,
        'api_e_count': 30,
        'api_e_lostcount': 9,
      },
    };
    controller
      ..accept(mapStartEvent)
      ..accept(
        kcsapiEvent(
          dayBattleEvent.path,
          data,
          sequence: dayBattleEvent.sequence,
        ),
      );
    await controller.idle;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
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
    );
    expect(find.byKey(const Key('flat-air-section')), findsOneWidget);

    await tester.tap(find.byKey(const Key('battle-mode-compact')));
    await tester.pump();
    expect(find.byKey(const Key('flat-air-section')), findsNothing);
  });
}

final class _InlineExecutor implements BattlePredictionExecutor {
  const _InlineExecutor();

  @override
  Future<BattlePredictionAppendResult> append({
    required BattlePredictionEngine engine,
    required String path,
    required Map<String, Object?> data,
  }) async =>
      (engine: engine, prediction: engine.append(path: path, data: data));
}
