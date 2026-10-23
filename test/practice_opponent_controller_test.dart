import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/account/account_session.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/practice/practice_opponent_controller.dart';

CapturedApiEvent _event(String api, Object? data) => CapturedApiEvent(
  path: '/kcsapi/$api',
  responseBody: jsonEncode({'api_result': 1, 'api_data': data}),
  source: CaptureSource.manual,
  capturedAt: DateTime(2026, 10, 24),
);

Map<String, Object?> _opponent(int id, {String rank = '大佐', int state = 0}) => {
  'api_enemy_id': id,
  'api_enemy_name': '提督$id',
  'api_enemy_level': 100 + id,
  'api_enemy_rank': rank,
  'api_enemy_comment': 'よろしく',
  'api_enemy_flag_ship': 131,
  'api_state': state,
  'api_medals': 0,
};

final _list = {
  'api_entry_limit': null,
  'api_list': [
    _opponent(1, rank: '中堅少佐', state: 6),
    _opponent(2, rank: '謎の階級'),
  ],
};

final _enemyInfo = {
  'api_member_id': 1,
  'api_nickname': '提督1',
  'api_level': 101,
  'api_rank': 5,
  'api_deckname': '第一艦隊',
  'api_deck': {
    'api_ships': [
      {'api_id': 11, 'api_ship_id': 131, 'api_level': 99, 'api_star': 4},
      {'api_id': -1},
      {'api_id': 12, 'api_ship_id': 143, 'api_level': 80, 'api_star': 3},
    ],
  },
};

void main() {
  late AccountSession account;
  late PracticeOpponentController controller;

  setUp(() {
    account = AccountSession(initialMemberId: 1001);
    controller = PracticeOpponentController(accountSession: account);
  });

  tearDown(() => controller.dispose());

  Future<void> send(String api, Object? data) async {
    controller.accept(_event(api, data));
    await controller.idle;
  }

  test('parses the opponent list', () async {
    await send('api_get_member/practice', _list);
    expect(controller.view, PracticeView.list);
    expect(controller.opponents, hasLength(2));
    final first = controller.opponents.first;
    expect(first.memberId, 1);
    expect(first.name, '提督1');
    expect(first.level, 101);
    expect(first.rankId, 9);
    expect(first.comment, 'よろしく');
    expect(first.flagshipMasterId, 131);
    expect(first.result, 6);
    expect(controller.opponents.last.rankId, 0);
  });

  test('parses the opponent fleet and skips empty slots', () async {
    await send('api_req_member/get_practice_enemyinfo', _enemyInfo);
    expect(controller.view, PracticeView.detail);
    final fleet = controller.selected!;
    expect(fleet.name, '提督1');
    expect(fleet.level, 101);
    expect(fleet.rankId, 5);
    expect(fleet.deckName, '第一艦隊');
    expect([for (final s in fleet.ships) s.masterId], [131, 143]);
    expect(fleet.ships.first.level, 99);
    expect(fleet.ships.first.star, 4);
  });

  test('returning to the list keeps the last selected fleet', () async {
    await send('api_req_member/get_practice_enemyinfo', _enemyInfo);
    await send('api_get_member/practice', _list);
    expect(controller.view, PracticeView.list);
    expect(controller.selected, isNotNull);
  });

  test('account switch clears the data', () async {
    await send('api_get_member/practice', _list);
    await send('api_req_member/get_practice_enemyinfo', _enemyInfo);
    account.selectMember(2002);
    expect(controller.view, PracticeView.list);
    expect(controller.opponents, isEmpty);
    expect(controller.selected, isNull);
  });

  test('malformed payloads keep the previous data', () async {
    await send('api_get_member/practice', _list);
    await send('api_req_member/get_practice_enemyinfo', _enemyInfo);
    await send('api_get_member/practice', {'api_list': 'oops'});
    await send('api_req_member/get_practice_enemyinfo', {'api_deck': 3});
    expect(controller.opponents, hasLength(2));
    expect(controller.selected!.ships, hasLength(2));
  });
}
