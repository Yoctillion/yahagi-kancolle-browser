import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:yahagi_kancolle_browser/src/theme/app_palette.dart';
import 'package:yahagi_kancolle_browser/src/theme/app_theme.dart';

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
  double width = 210,
}) => tester.pumpWidget(
  MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: PanelStyleScope(style: PanelStyle.flat, child: child),
        ),
      ),
    ),
  ),
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

Future<List<String>> _extras(
  WidgetTester tester,
  DayAirReport report, {
  List<BattleShipSnapshot>? friendMain,
  List<BattleShipSnapshot> friendEscort = const [],
  Locale locale = const Locale('zh'),
}) async {
  late List<String> extras;
  await _pump(
    tester,
    Builder(
      builder: (context) {
        extras = flatAirExtras(
          context,
          report: report,
          friendMain: friendMain ?? _main,
          friendEscort: friendEscort,
          slotItems: _slotItems,
        );
        return const SizedBox.shrink();
      },
    ),
    locale: locale,
  );
  return extras;
}

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
  testWidgets('exchange line puts friend left and enemy right in order', (
    tester,
  ) async {
    await _pump(
      tester,
      const FlatAirExchangeLine(report: _fullReport),
      // The test font draws every glyph a full em wide.
      width: 500,
    );
    final friend = find.byKey(const Key('flat-air-exchange-friend'));
    final enemy = find.byKey(const Key('flat-air-exchange-enemy'));
    final friendText = tester.widget<RichText>(
      find.descendant(of: friend, matching: find.byType(RichText)),
    );
    final enemyText = tester.widget<RichText>(
      find.descendant(of: enemy, matching: find.byType(RichText)),
    );
    expect(friendText.text.toPlainText(), ' 8−0   12−1  30−2');
    expect(enemyText.text.toPlainText(), ' 20−4   135−9  40−5');
    expect(
      tester.getTopLeft(enemy).dx,
      greaterThan(tester.getTopRight(friend).dx),
    );
    final jet = _spanWithText(friendText.text, ' 8')!;
    expect(jet.style!.background, isNotNull);
    final loss = _spanWithText(friendText.text, '−1')!;
    expect(loss.style!.fontSize, FlatAirExchangeLine.lossFontSize);
    expect(loss.style!.background, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exchange halves shrink rather than overflow', (tester) async {
    await _pump(
      tester,
      const FlatAirExchangeLine(report: _fullReport),
      width: 110,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('exchange leaves out stages without data', (tester) async {
    await _pump(
      tester,
      const FlatAirExchangeLine(
        report: DayAirReport(
          fighter: PlaneExchange(
            friend: PlaneCount(12, 0),
            enemy: PlaneCount(3, 3),
          ),
        ),
      ),
    );
    String plain(String key) => tester
        .widget<RichText>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(RichText),
          ),
        )
        .text
        .toPlainText();
    expect(plain('flat-air-exchange-friend'), '12−0');
    expect(plain('flat-air-exchange-enemy'), '3−3');
  });

  testWidgets('extras list the second wave, contact and cut-ins', (
    tester,
  ) async {
    final extras = await _extras(
      tester,
      _fullReport,
      friendMain: _main.take(6).toList(),
      friendEscort: _escort,
    );
    expect(extras, ['航空战×2', '触接 我 彩云 / 敌 九七式艦攻', '对空CI 主1(5)', '对空CI 随1(9)']);
  });

  testWidgets('no extras without contact, cut-ins or a second wave', (
    tester,
  ) async {
    final extras = await _extras(
      tester,
      const DayAirReport(fighter: PlaneExchange(friend: PlaneCount(1, 0))),
    );
    expect(extras, isEmpty);
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
        enemyMain: _main.take(6).toList(),
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
        enemyMain: _main,
        enemyEscort: const [],
        slotItems: _slotItems,
      ),
    );
    expect(_rich('我 #7 主6'), findsOneWidget);
    expect(_rich('敌 #7 主6'), findsOneWidget);
  });

  testWidgets('guards out-of-range flare index', (tester) async {
    await _pump(
      tester,
      FlatNightBattleSection(
        report: const NightReport(friendFlarePosition: 5),
        friendMain: _main.take(2).toList(),
        friendEscort: const [],
        enemyMain: _main,
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
            FlatAirBattleSection(report: report),
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
              enemyMain: _main.take(6).toList(),
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

  testWidgets('writes the AACI kind the same way in every locale', (
    tester,
  ) async {
    final extras = await _extras(
      tester,
      _fullReport,
      friendMain: _main.take(6).toList(),
      friendEscort: _escort,
      locale: const Locale('en'),
    );
    expect(extras, contains('AACI 主1(5)'));
  });

  testWidgets('resolves AACI position past a short main fleet to the escort', (
    tester,
  ) async {
    final extras = await _extras(
      tester,
      const DayAirReport(
        fighter: PlaneExchange(friend: PlaneCount(1, 0)),
        antiAirCutIns: [AntiAirCutIn(position: 7, kind: 5)],
      ),
      friendMain: _main.take(5).toList(),
      friendEscort: _escort,
    );
    expect(extras, ['对空CI 随1(5)']);
  });

  testWidgets('names the enemy star shell ship only for a single fleet', (
    tester,
  ) async {
    await _pump(
      tester,
      FlatNightBattleSection(
        report: const NightReport(enemyFlarePosition: 2),
        friendMain: _main,
        friendEscort: const [],
        enemyMain: _main,
        enemyEscort: const [],
        slotItems: _slotItems,
      ),
    );
    expect(_rich('敌 #3 主2'), findsOneWidget);
  });

  testWidgets('keeps phase labels untruncated at a larger text scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 210,
                child: FlatAirBattleSection(
                  report: const DayAirReport(
                    phases: [
                      AirPhaseLine(
                        kind: AirPhaseKind.landBase,
                        baseId: 1,
                        wave: 2,
                        planes: PlaneExchange(enemy: PlaneCount(8, 1)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final label = find.text('基地 1-2');
    final paragraph = tester.renderObject<RenderParagraph>(label);
    expect(paragraph.didExceedMaxLines, isFalse);
    final scaled = TextPainter(
      text: const TextSpan(
        text: '基地 1-2',
        style: TextStyle(fontSize: flatAirPhaseFontSize),
      ),
      textDirection: TextDirection.ltr,
      textScaler: const TextScaler.linear(1.3),
    )..layout();
    expect(tester.getSize(label).width, greaterThanOrEqualTo(scaled.width));
    scaled.dispose();
  });

  testWidgets('maps loss colors through the light palette', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: createAppTheme(mode: AppThemeMode.skyBlue),
        home: const Scaffold(
          body: SizedBox(
            width: 500,
            child: FlatAirExchangeLine(report: _fullReport),
          ),
        ),
      ),
    );
    final context = tester.element(find.byType(FlatAirExchangeLine));
    final expected = appColor(context, flatAllyLossColor);
    expect(expected, isNot(flatAllyLossColor));
    final text = tester.widget<RichText>(
      find.descendant(
        of: find.byKey(const Key('flat-air-exchange-friend')),
        matching: find.byType(RichText),
      ),
    );
    expect(_spanWithText(text.text, '−1')!.style!.color, expected);
  });

  testWidgets('panel shows the air exchange only in detailed mode', (
    tester,
  ) async {
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
    expect(find.byKey(const Key('flat-air-exchange')), findsOneWidget);
    // Without land-base or support rows there is no section below the grid.
    expect(find.byKey(const Key('flat-air-section')), findsNothing);
    expect(_rich('制空：确保'), findsOneWidget);
    expect(_rich('昼战'), findsNothing);

    await tester.tap(find.byKey(const Key('battle-mode-compact')));
    await tester.pump();
    expect(find.byKey(const Key('flat-air-exchange')), findsNothing);
    expect(_rich('制空：确保'), findsOneWidget);
    expect(_rich('昼战'), findsNothing);
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
