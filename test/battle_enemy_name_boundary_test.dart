import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_detail_models.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_detail_strings.dart';
import 'package:yahagi_kancolle_browser/src/battle/live_battle_card.dart';
import 'package:yahagi_kancolle_browser/src/battle/prediction/battle_prediction_engine.dart';
import 'package:yahagi_kancolle_browser/src/battle/prediction/battle_prediction_executor.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_reducer.dart';
import 'package:yahagi_kancolle_browser/src/logbook/battle_detail_page.dart';

import 'fixtures/kcsapi_fixtures.dart';

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

Future<BattleController> _battle({
  String? rawName,
  bool practice = false,
}) async {
  final reducer = GameStateReducer();
  final state = reducer.reduce(
    reducer.reduce(GameState.empty, start2Event),
    portEvent,
  );
  final controller = BattleController(
    gameState: () => state,
    predictionExecutor: const _InlineExecutor(),
  );
  addTearDown(controller.dispose);
  final data = Map<String, Object?>.from(
    (jsonDecode(dayBattleEvent.responseBody) as Map)['api_data'] as Map,
  );
  if (rawName != null) data['api_formation'] = [1, 1, 1, rawName];
  if (!practice) controller.accept(mapStartEvent);
  controller.accept(
    kcsapiEvent(
      practice ? '/kcsapi/api_req_practice/battle' : dayBattleEvent.path,
      data,
      sequence: 501,
    ),
  );
  await controller.idle;
  expect(controller.current!.enemyFleetName, rawName ?? '');
  if (rawName != null) {
    final result = Map<String, Object?>.from(
      (jsonDecode(battleResultEvent.responseBody) as Map)['api_data'] as Map,
    )..['api_enemy_info'] = {'api_deck_name': rawName};
    controller.accept(
      kcsapiEvent(
        practice
            ? '/kcsapi/api_req_practice/battle_result'
            : battleResultEvent.path,
        result,
        sequence: 502,
      ),
    );
    await controller.idle;
    expect(controller.current!.enemyFleetName, rawName);
  }
  return controller;
}

Widget _app(Locale locale, Widget child) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

Future<void> _mountLive(
  WidgetTester tester,
  Locale locale,
  BattleController controller,
) async {
  await tester.pumpWidget(
    _app(
      locale,
      SingleChildScrollView(
        child: SizedBox(
          width: 600,
          child: LiveBattleCard(
            controller: controller,
            collapsed: false,
            onToggleCollapse: () {},
            showEnemyPortraits: false,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

BattleDetailSnapshot _shipNameDetail({bool fallbacks = false}) {
  final attacker = fallbacks ? '舰娘 991' : '联合舰队';
  final defender = fallbacks ? '敌舰 1501' : '我方主力';
  final npc = fallbacks ? '友军·舰船 1502' : '友军·联合舰队';
  BattleDetailAttack attack(
    String name, {
    bool npc = false,
    bool source = false,
  }) => BattleDetailAttack(
    attackerSide: npc ? BattleDetailSide.npc : BattleDetailSide.friend,
    attackerRole: source ? null : BattleDetailFleetRole.main,
    attackerPosition: source ? null : 0,
    attackerName: name,
    defenderSide: BattleDetailSide.enemy,
    defenderRole: BattleDetailFleetRole.main,
    defenderPosition: 0,
    defenderName: defender,
    attackType: '炮击',
    defenderHpBefore: 20,
    defenderHpAfter: 19,
    hits: const [
      BattleDetailHit(damage: 1, kind: BattleDetailHitKind.hit, hpAfter: 19),
    ],
  );
  return BattleDetailSnapshot(
    completedAtMillis: 0,
    mapLabel: '1-1',
    nodeLabel: 'A点',
    rank: 'S',
    enemyFleetName: '原始舰队名',
    fleets: [
      BattleDetailFleet(
        side: BattleDetailSide.friend,
        role: BattleDetailFleetRole.main,
        ships: [
          BattleDetailShip(
            masterId: 991,
            name: attacker,
            side: BattleDetailSide.friend,
            role: BattleDetailFleetRole.main,
            position: 0,
            initialHp: 20,
            maxHp: 20,
            finalHp: 20,
            equipment: const [BattleDetailEquipment(masterId: 99, name: '航空战')],
          ),
        ],
      ),
      BattleDetailFleet(
        side: BattleDetailSide.enemy,
        role: BattleDetailFleetRole.main,
        ships: [
          BattleDetailShip(
            masterId: 1501,
            name: defender,
            side: BattleDetailSide.enemy,
            role: BattleDetailFleetRole.main,
            position: 0,
            initialHp: 20,
            maxHp: 20,
            finalHp: 19,
          ),
          if (fallbacks)
            const BattleDetailShip(
              name: '未知舰船',
              side: BattleDetailSide.enemy,
              role: BattleDetailFleetRole.main,
              position: 1,
              initialHp: 20,
              maxHp: 20,
              finalHp: 20,
            ),
        ],
      ),
    ],
    stages: [
      BattleDetailStage(
        keyName: 'api_hougeki1',
        title: '第一炮击战',
        attacks: [
          attack(attacker),
          attack(npc, npc: true),
          attack('航空战', source: true),
        ],
      ),
    ],
  );
}

void main() {
  for (final locale in const [
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    Locale('ja'),
    Locale('ko'),
    Locale('en'),
  ]) {
    testWidgets('raw ship and attack names survive ${locale.toLanguageTag()}', (
      tester,
    ) async {
      final detail = _shipNameDetail();
      final stored = jsonEncode(detail.toJson());
      final strings = BattleDetailStrings.forLocale(locale);
      await tester.pumpWidget(
        _app(locale, BattleDetailPage(detail: detail, onBack: () {})),
      );
      await tester.pumpAndSettle();
      expect(find.text('联合舰队'), findsOneWidget);
      expect(find.text('我方主力'), findsOneWidget);
      await tester.tap(find.byKey(const Key('battle-detail-tab-process')));
      await tester.pumpAndSettle();
      final attackSeparator = '  ${strings.attack}  ';
      expect(
        find.text('联合舰队$attackSeparator我方主力', findRichText: true),
        findsOneWidget,
      );
      final npcPrefix = locale.languageCode == 'en'
          ? '${strings.sideName(BattleDetailSide.npc)} · '
          : '${strings.sideName(BattleDetailSide.npc)}·';
      expect(
        find.text('$npcPrefix联合舰队$attackSeparator我方主力', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.text(
          '${strings.localize('航空战')}$attackSeparator我方主力',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(jsonEncode(detail.toJson()), stored);
      expect(detail.fleets.first.ships.single.equipment.single.name, '航空战');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'ship fallbacks remain localized in ${locale.toLanguageTag()}',
      (tester) async {
        final detail = _shipNameDetail(fallbacks: true);
        final strings = BattleDetailStrings.forLocale(locale);
        final (attacker, defender, npc) = switch (locale.toLanguageTag()) {
          'zh-Hant' => ('艦娘 991', '敵艦 1501', '友軍·艦船 1502'),
          'ja' => ('艦娘 991', '敵艦 1501', '友軍·艦船 1502'),
          'ko' => ('함선 991', '적 함선 1501', '우군·함선 1502'),
          'en' => ('Ship 991', 'Enemy ship 1501', 'Allied fleet · Ship 1502'),
          _ => ('舰娘 991', '敌舰 1501', '友军·舰船 1502'),
        };
        await tester.pumpWidget(
          _app(locale, BattleDetailPage(detail: detail, onBack: () {})),
        );
        await tester.pumpAndSettle();
        expect(find.text(attacker), findsOneWidget);
        expect(find.text(defender), findsOneWidget);
        expect(find.text(strings.localize('未知舰船')), findsOneWidget);
        await tester.tap(find.byKey(const Key('battle-detail-tab-process')));
        await tester.pumpAndSettle();
        final separator = '  ${strings.attack}  ';
        expect(
          find.text('$attacker$separator$defender', findRichText: true),
          findsOneWidget,
        );
        expect(
          find.text('$npc$separator$defender', findRichText: true),
          findsOneWidget,
        );
        expect(
          find.text(
            '${strings.localize('航空战')}$separator$defender',
            findRichText: true,
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    for (final practice in [false, true]) {
      testWidgets(
        'raw fleet names survive ${locale.toLanguageTag()} practice=$practice',
        (tester) async {
          for (final rawName in ['联合舰队', '我方主力', '敌 联合舰队']) {
            final controller = await _battle(
              rawName: rawName,
              practice: practice,
            );
            await _mountLive(tester, locale, controller);
            for (final compact in [false, true]) {
              if (compact) {
                await tester.tap(find.byKey(const Key('battle-mode-compact')));
                await tester.pump();
              }
              expect(find.text(rawName), findsOneWidget);
              expect(tester.takeException(), isNull);
            }

            final detail = controller.records.single.detail!;
            expect(detail.enemyFleetName, rawName);
            final stored = jsonEncode(detail.toJson());
            final restored = BattleDetailSnapshot.fromJson(detail.toJson());
            await tester.pumpWidget(
              _app(locale, BattleDetailPage(detail: restored, onBack: () {})),
            );
            await tester.pumpAndSettle();
            expect(find.text(rawName), findsOneWidget);
            expect(jsonEncode(restored.toJson()), stored);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          }
        },
      );
    }

    testWidgets(
      'missing fleet names remain localized in ${locale.toLanguageTag()}',
      (tester) async {
        final controller = await _battle();
        await _mountLive(tester, locale, controller);
        final fallback = BattleDetailStrings.forLocale(locale).localize('敌方舰队');
        expect(find.text(fallback), findsOneWidget);
        await tester.tap(find.byKey(const Key('battle-mode-compact')));
        await tester.pump();
        expect(find.text(fallback), findsOneWidget);
        expect(controller.current!.enemyFleetName, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
