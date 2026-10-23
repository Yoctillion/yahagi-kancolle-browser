import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_calculation.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_reducer.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_state.dart';

void main() {
  const reducer = SenkaReducer();

  test('同一新榜重复读取仍显示相对上一榜的门槛涨幅', () {
    var state = _initial();
    state = reducer.reduce(state, _ranking(rank: 5, senka: 4755, hour: 3));
    state = reducer.reduce(state, _ranking(rank: 5, senka: 4828, hour: 15));
    expect(state.rankingRow(5).senkaDelta, 73);
    state = reducer.reduce(
      state,
      _ranking(rank: 5, senka: 4828, hour: 15, minute: 1),
    );
    expect(state.rankingRow(5).senkaDelta, 73);
  });

  test('同一新榜重复读取仍显示本人相对上一榜的名次变化', () {
    var state = _initial();
    state = reducer.reduce(
      state,
      _ranking(rank: 431, senka: 1000, hour: 3, self: true),
    );
    state = reducer.reduce(
      state,
      _ranking(rank: 397, senka: 1007, hour: 15, self: true),
    );
    expect(state.playerRankingRow.rankDelta, 34);
    state = reducer.reduce(
      state,
      _ranking(rank: 397, senka: 1007, hour: 15, minute: 1, self: true),
    );
    expect(state.playerRankingRow.rankDelta, 34);
    expect(state.playerRankingRow.rankDirection, SenkaRankDirection.up);
  });

  test('迟到的未通关地图快照不会导致同一个 EO 重复加分', () {
    var state = _initial();
    state = reducer.reduce(state, _mapInfo(false, hour: 9));
    state = reducer.reduce(state, _mapInfo(true, hour: 10));
    expect(state.monthRecorded, 75);
    state = reducer.reduce(state, _mapInfo(false, hour: 9, minute: 30));
    state = reducer.reduce(state, _mapInfo(true, hour: 11));
    expect(state.monthRecorded, 75);
  });

  test('949任务选择装备奖励时不能虚构800战果', () {
    final state = reducer.reduce(
      _initial(),
      _event(
        '/kcsapi/api_req_quest/clearitemget',
        {
          'api_material': [0, 0, 0, 0],
          'api_bounus_count': 1,
          'api_bounus': [
            {
              'api_type': 12,
              'api_count': 1,
              'api_item': {'api_id': 422, 'api_name': 'FR-1 Fireball'},
            },
          ],
        },
        params: const {'api_quest_id': '949', 'api_select_no': '1'},
        hour: 12,
      ),
    );
    expect(state.completedQuestIds, contains(949));
    expect(state.day(DateTime.utc(2026, 8, 10)).quest, 0);
    expect(state.unsettledSenka, 0);
  });

  test('九月五点以后迟到的旧季度事件不会反向恢复旧季度状态', () {
    final current = SenkaState.forMonth('2026-09').copyWith(
      memberId: 123,
      nickname: '本人',
      quarterlyQuestCycleKey: '2026-09',
      questStatuses: const {854: SenkaRewardStatus.completed},
      recordedQuestIds: const {854},
    );
    final state = reducer.reduce(
      current,
      CapturedApiEvent(
        path: '/kcsapi/api_get_member/basic',
        responseBody: jsonEncode({
          'api_result': 1,
          'api_data': {'api_experience': 100000},
        }),
        source: CaptureSource.manual,
        capturedAt: DateTime.utc(2026, 8, 31, 19), // Sep 1 04:00 JST.
      ),
    );
    expect(state.quarterlyQuestCycleKey, '2026-09');
    expect(state.questStatuses[854], SenkaRewardStatus.completed);
    expect(state.recordedQuestIds, contains(854));
  });

  test('错误游戏响应不伪造战果且已有累计保持不变', () {
    final state = _initial().copyWith(
      days: const {'2026-08-10': SenkaDayRecord(experience: 7)},
    );
    final bad = CapturedApiEvent(
      path: '/kcsapi/api_req_quest/clearitemget',
      requestParams: const {'api_quest_id': '854'},
      responseBody: jsonEncode({'api_result': 0, 'api_result_msg': 'error'}),
      source: CaptureSource.manual,
      capturedAt: _jst(12),
    );
    expect(() => reducer.reduce(state, bad), throwsException);
    expect(state.monthRecorded, 7);
    expect(state.recordedQuestIds, isEmpty);
  });

  test('非本人排名页和重名页都不会吞掉本地待结算增量', () {
    var state = _initial();
    state = reducer.reduce(
      state,
      _ranking(rank: 397, senka: 1000, hour: 3, self: true),
    );
    state = reducer.reduce(
      state,
      _event('/kcsapi/api_get_member/basic', {
        'api_experience': 110000,
      }, hour: 10),
    );
    state = reducer.reduce(state, _ranking(rank: 5, senka: 4755, hour: 11));
    expect(state.unsettledSenka, 7);
    final calculation = SenkaCalculationResult.fromState(state, now: _jst(12));
    expect(calculation.projected, 1007);
    final rows = [_row(397, 1000, '本人'), _row(398, 999, '本人')];
    state = reducer.reduce(
      state,
      _event('/kcsapi/api_req_ranking/mxltvkpyuklh', {
        'api_disp_page': 40,
        'api_list': rows,
      }, hour: 12),
    );
    expect(state.unsettledSenka, 7);
  });
}

SenkaState _initial() => SenkaState.forMonth(
  '2026-08',
).copyWith(memberId: 123, nickname: '本人', latestExperience: 100000);

DateTime _jst(int hour, [int minute = 0]) =>
    DateTime.utc(2026, 8, 10, hour - 9, minute);

CapturedApiEvent _event(
  String path,
  Object data, {
  Map<String, Object?> params = const {},
  required int hour,
  int minute = 0,
}) => CapturedApiEvent(
  path: path,
  responseBody: jsonEncode({'api_result': 1, 'api_data': data}),
  requestParams: params,
  source: CaptureSource.manual,
  capturedAt: _jst(hour, minute),
);

const _right = [
  8931,
  1201,
  1156,
  5061,
  4569,
  4732,
  3779,
  4568,
  5695,
  4619,
  4912,
  5669,
  6586,
];
Map<String, Object?> _row(int rank, int senka, String nickname) => {
  'api_mxltvkpyuklh': rank,
  'api_mtjmdcwtvhdr': nickname,
  'api_wuhnhojjxmke': (senka + 91) * _right[rank % 13] * 97,
};

CapturedApiEvent _ranking({
  required int rank,
  required int senka,
  required int hour,
  int minute = 0,
  bool self = false,
}) => _event(
  '/kcsapi/api_req_ranking/mxltvkpyuklh',
  {
    'api_disp_page': (rank / 10).ceil(),
    'api_list': [_row(rank, senka, self ? '本人' : '其他')],
  },
  hour: hour,
  minute: minute,
);

CapturedApiEvent _mapInfo(bool cleared, {required int hour, int minute = 0}) =>
    _event(
      '/kcsapi/api_get_member/mapinfo',
      {
        'api_map_info': [
          {'api_id': 15, 'api_cleared': cleared ? 1 : 0},
        ],
      },
      hour: hour,
      minute: minute,
    );
