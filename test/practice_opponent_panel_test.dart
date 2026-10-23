import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/layout/panel_style.dart';
import 'package:yahagi_kancolle_browser/src/practice/practice_opponent_controller.dart';
import 'package:yahagi_kancolle_browser/src/practice/practice_opponent_panel.dart';

CapturedApiEvent _event(String api, Object? data) => CapturedApiEvent(
  path: '/kcsapi/$api',
  responseBody: jsonEncode({'api_result': 1, 'api_data': data}),
  source: CaptureSource.manual,
  capturedAt: DateTime(2026, 10, 24),
);

final _list = {
  'api_list': [
    for (var id = 1; id <= 5; id++)
      {
        'api_enemy_id': id,
        'api_enemy_name': '提督$id',
        'api_enemy_level': 100 + id,
        'api_enemy_rank': '中堅少佐',
        'api_enemy_comment': '',
        'api_enemy_flag_ship': 131,
        'api_state': id == 1 ? 6 : 0,
      },
  ],
};

Map<String, Object?> _enemyInfo(List<Map<String, Object?>> ships) => {
  'api_nickname': '提督1',
  'api_level': 101,
  'api_rank': 9,
  'api_deckname': '第一艦隊',
  'api_deck': {'api_ships': ships},
};

void main() {
  late GameStateController gameState;
  late PracticeOpponentController practice;

  setUp(() async {
    gameState = GameStateController();
    practice = PracticeOpponentController();
    await gameState.idle;
  });

  tearDown(() {
    practice.dispose();
    gameState.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('zh'),
    PanelStyle style = PanelStyle.card,
  }) => tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: PanelStyleScope(
            style: style,
            child: PracticeOpponentPanel(
              controller: practice,
              gameStateController: gameState,
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('shows a hint before any practice data', (tester) async {
    await pump(tester);
    final l10n = lookupAppLocalizations(const Locale('zh'));
    expect(find.text(l10n.practicePanelEmpty), findsOneWidget);
  });

  for (final style in PanelStyle.values) {
    testWidgets('lists every opponent with last result ($style)', (
      tester,
    ) async {
      practice.accept(_event('api_get_member/practice', _list));
      await pump(tester, style: style);
      for (var id = 1; id <= 5; id++) {
        expect(find.text('提督$id'), findsOneWidget);
      }
      expect(find.text('S'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('list shows the Japanese rank in ja', (tester) async {
    practice.accept(_event('api_get_member/practice', _list));
    await pump(tester, locale: const Locale('ja'));
    expect(find.text('中堅少佐'), findsNWidgets(5));
  });

  testWidgets('detail shows S-rank base exp for a single Lv50 ship', (
    tester,
  ) async {
    practice.accept(
      _event(
        'api_req_member/get_practice_enemyinfo',
        _enemyInfo([
          {'api_id': 1, 'api_ship_id': 131, 'api_level': 50, 'api_star': 1},
        ]),
      ),
    );
    await pump(tester);
    expect(
      tester.widget<Text>(find.byKey(const Key('practice-exp-s'))).data,
      contains('631'),
    );
  });

  testWidgets('detail renders only real ships', (tester) async {
    practice.accept(
      _event(
        'api_req_member/get_practice_enemyinfo',
        _enemyInfo([
          {'api_id': 1, 'api_ship_id': 131, 'api_level': 99, 'api_star': 1},
          {'api_id': -1},
          {'api_id': 2, 'api_ship_id': 143, 'api_level': 80, 'api_star': 1},
        ]),
      ),
    );
    await pump(tester);
    expect(find.byKey(const Key('practice-ship-0')), findsOneWidget);
    expect(find.byKey(const Key('practice-ship-1')), findsOneWidget);
    expect(find.byKey(const Key('practice-ship-2')), findsNothing);
  });

  testWidgets('empty opponent fleet shows no exp', (tester) async {
    practice.accept(
      _event('api_req_member/get_practice_enemyinfo', _enemyInfo([])),
    );
    await pump(tester);
    expect(find.byKey(const Key('practice-exp-s')), findsNothing);
  });
}
