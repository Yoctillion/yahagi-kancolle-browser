import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_calculation.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_reducer.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_state.dart';

void main() {
  const reducer = SenkaReducer();

  group('重复读取官方排名', () {
    test('同一份榜单在新的捕获时间保留本人变化与预计战果', () {
      var state = _stateWithMorningRanking(reducer);
      state = reducer.reduce(
        state,
        _experience(110000, atJst: DateTime(2026, 8, 10, 12)),
      );
      _expectProgress(state, pending: 7, projected: 1007);

      for (final instant in [
        DateTime(2026, 8, 10, 12, 30),
        DateTime(2026, 8, 10, 13),
        DateTime(2026, 8, 10, 13, 59),
      ]) {
        state = reducer.reduce(state, _ranking(1000, atJst: instant));
        _expectProgress(state, pending: 7, projected: 1007);
      }
    });

    test('重复打开排名不改变日历素战果和今日剩余', () {
      var state = _stateWithMorningRanking(reducer);
      state = reducer.reduce(
        state,
        _experience(110000, atJst: DateTime(2026, 8, 10, 12)),
      );
      final before = _calculation(state);
      final beforeCalendar = state.days.map(
        (key, record) => MapEntry(key, record.toJson()),
      );
      final after = reducer.reduce(
        state,
        _ranking(1000, atJst: DateTime(2026, 8, 10, 13, 30)),
      );

      expect(
        after.days.map((key, record) => MapEntry(key, record.toJson())),
        beforeCalendar,
      );
      expect(after.monthExperienceSenka, closeTo(7, 1e-9));
      expect(_calculation(after).todayRemaining, before.todayRemaining);
      expect(_calculation(after).dailyRequired, before.dailyRequired);
      _expectProgress(after, pending: 7, projected: 1007);
    });

    test('JSON 保存再加载后重复打开仍保留尚未结算增量', () {
      var state = _stateWithMorningRanking(reducer);
      state = reducer.reduce(
        state,
        _experience(110000, atJst: DateTime(2026, 8, 10, 12)),
      );
      state = reducer.reduce(
        state,
        _ranking(1000, atJst: DateTime(2026, 8, 10, 13)),
      );
      state = SenkaState.fromJson(jsonDecode(jsonEncode(state.toJson())));
      _expectProgress(state, pending: 7, projected: 1007);

      state = reducer.reduce(
        state,
        _ranking(1000, atJst: DateTime(2026, 8, 10, 13, 30)),
      );
      _expectProgress(state, pending: 7, projected: 1007);
    });
  });

  group('官方排名结算', () {
    test('结算前捕获的经验迟于新榜入账时不会重复计入预计战果', () {
      var state = _stateWithMorningRanking(reducer);
      state = reducer.reduce(
        state,
        _ranking(1007, atJst: DateTime(2026, 8, 10, 15, 5)),
      );
      final delayed = _experience(110000, atJst: DateTime(2026, 8, 10, 13));
      state = reducer.reduce(state, delayed);
      _expectProgress(state, pending: 0, projected: 1007);
      state = reducer.reduce(state, delayed);
      state = reducer.reduce(
        state,
        _ranking(1007, atJst: DateTime(2026, 8, 10, 16)),
      );
      _expectProgress(state, pending: 0, projected: 1007);
      expect(state.monthExperienceSenka, closeTo(7, 1e-9));
    });

    test('迟到的已结算 EO 和任务仅保留日历记录且不重复入账', () {
      var state = _stateWithMorningRanking(reducer);
      state = reducer.reduce(
        state,
        _mapInfo(cleared: false, atJst: DateTime(2026, 8, 10, 4)),
      );
      state = reducer.reduce(
        state,
        _ranking(1155, atJst: DateTime(2026, 8, 10, 15, 5)),
      );
      final delayedEo = _mapInfo(
        cleared: true,
        atJst: DateTime(2026, 8, 10, 13),
      );
      final delayedQuest = _quest(atJst: DateTime(2026, 8, 10, 13, 30));
      for (var i = 0; i < 2; i++) {
        state = reducer.reduce(state, delayedEo);
        state = reducer.reduce(state, delayedQuest);
        _expectProgress(state, pending: 0, projected: 1155);
      }
      expect(state.day(DateTime(2026, 8, 10)).eo, 75);
      expect(state.day(DateTime(2026, 8, 10)).quest, 80);
    });

    test('迟到收益依据最后确认截止点而非旧榜的新捕获时间结算', () {
      var state = _stateWithMorningRanking(reducer);
      state = reducer.reduce(
        state,
        _experience(105000, atJst: DateTime(2026, 8, 10, 12)),
      );
      state = reducer.reduce(
        state,
        _ranking(1000, atJst: DateTime(2026, 8, 10, 15, 5)),
      );
      state = reducer.reduce(
        state,
        _experience(110000, atJst: DateTime(2026, 8, 10, 13)),
      );
      _expectProgress(state, pending: 7, projected: 1007);
    });

    test('下午榜结算截止前收益但保留十四点之后的小数增量', () {
      var state = _stateWithMorningRanking(reducer);
      state = reducer.reduce(
        state,
        _experience(105000, atJst: DateTime(2026, 8, 10, 12)),
      );
      state = reducer.reduce(
        state,
        _experience(107750, atJst: DateTime(2026, 8, 10, 14, 30)),
      );
      _expectProgress(state, pending: 5.425, projected: 1005.425);
      final before = _calculation(state);

      state = reducer.reduce(
        state,
        _ranking(1003.5, atJst: DateTime(2026, 8, 10, 15, 5)),
      );

      expect(state.calculatorCurrentSenka, 1003.5);
      _expectProgress(state, pending: 1.925, projected: 1005.425);
      expect(state.day(DateTime(2026, 8, 10)).experience, closeTo(5.425, 1e-9));
      expect(_calculation(state).todayRemaining, before.todayRemaining);
      expect(_calculation(state).dailyRequired, before.dailyRequired);
    });

    test('真正结算后反复查看同一新榜不会再次扣除未结算收益', () {
      var state = _stateWithMorningRanking(reducer);
      state = reducer.reduce(
        state,
        _experience(105000, atJst: DateTime(2026, 8, 10, 12)),
      );
      state = reducer.reduce(
        state,
        _experience(107750, atJst: DateTime(2026, 8, 10, 14, 30)),
      );
      state = reducer.reduce(
        state,
        _ranking(1003.5, atJst: DateTime(2026, 8, 10, 15, 5)),
      );
      state = reducer.reduce(
        state,
        _experience(108000, atJst: DateTime(2026, 8, 10, 16)),
      );
      state = SenkaState.fromJson(jsonDecode(jsonEncode(state.toJson())));
      state = reducer.reduce(
        state,
        _ranking(1003.5, atJst: DateTime(2026, 8, 10, 17)),
      );

      _expectProgress(state, pending: 2.1, projected: 1005.6);
      expect(state.monthExperienceSenka, closeTo(5.6, 1e-9));
    });

    test('首次读取排名保留当期结算截止之后已记录的收益', () {
      var state = _initialState();
      state = reducer.reduce(
        state,
        _experience(110000, atJst: DateTime(2026, 8, 10, 14, 30)),
      );
      state = reducer.reduce(
        state,
        _ranking(1000, atJst: DateTime(2026, 8, 10, 15, 5)),
      );

      _expectProgress(state, pending: 7, projected: 1007);
      expect(state.day(DateTime(2026, 8, 10)).experience, closeTo(7, 1e-9));
    });

    test('收益全部包含在新榜时未结算增量正确归零', () {
      var state = _stateWithMorningRanking(reducer);
      state = reducer.reduce(
        state,
        _experience(110000, atJst: DateTime(2026, 8, 10, 12)),
      );
      state = reducer.reduce(
        state,
        _ranking(1007, atJst: DateTime(2026, 8, 10, 15, 5)),
      );

      _expectProgress(state, pending: 0, projected: 1007);
      expect(state.monthExperienceSenka, closeTo(7, 1e-9));
    });

    test('凌晨二到三点仍读旧榜时不能提前结算新一期收益', () {
      var state = reducer.reduce(
        _initialState(),
        _ranking(1000, atJst: DateTime(2026, 8, 9, 15, 5)),
      );
      state = reducer.reduce(
        state,
        _experience(105000, atJst: DateTime(2026, 8, 10, 1, 30)),
      );
      state = reducer.reduce(
        state,
        _experience(107750, atJst: DateTime(2026, 8, 10, 2, 30)),
      );
      state = reducer.reduce(
        state,
        _ranking(1000, atJst: DateTime(2026, 8, 10, 2, 45)),
      );
      _expectProgress(state, pending: 5.425, projected: 1005.425);

      state = reducer.reduce(
        state,
        _ranking(1003.5, atJst: DateTime(2026, 8, 10, 3, 5)),
      );

      _expectProgress(state, pending: 1.925, projected: 1005.425);
      expect(state.day(DateTime(2026, 8, 9)).experience, closeTo(3.5, 1e-9));
      expect(state.day(DateTime(2026, 8, 10)).experience, closeTo(1.925, 1e-9));
    });

    test('官方榜单取整不能把新一期小数收益抵扣掉', () {
      var state = _stateWithMorningRanking(reducer);
      state = reducer.reduce(
        state,
        _experience(105500, atJst: DateTime(2026, 8, 10, 12)),
      );
      state = reducer.reduce(
        state,
        _experience(108250, atJst: DateTime(2026, 8, 10, 14, 30)),
      );
      state = reducer.reduce(
        state,
        _ranking(1004, atJst: DateTime(2026, 8, 10, 15, 5)),
      );

      _expectProgress(state, pending: 1.925, projected: 1005.925);
      expect(state.monthExperienceSenka, closeTo(5.775, 1e-9));
    });

    for (final eoBeforeCutoff in [true, false]) {
      test('${eoBeforeCutoff ? 'EO' : '任务'}在十四点前结算，'
          '${eoBeforeCutoff ? '任务' : 'EO'}在十四点后继续保留', () {
        var state = _stateWithMorningRanking(reducer);
        state = reducer.reduce(
          state,
          _mapInfo(cleared: false, atJst: DateTime(2026, 8, 10, 3, 10)),
        );
        state = reducer.reduce(
          state,
          eoBeforeCutoff
              ? _mapInfo(cleared: true, atJst: DateTime(2026, 8, 10, 12))
              : _quest(atJst: DateTime(2026, 8, 10, 12)),
        );
        state = reducer.reduce(
          state,
          eoBeforeCutoff
              ? _quest(atJst: DateTime(2026, 8, 10, 14, 30))
              : _mapInfo(cleared: true, atJst: DateTime(2026, 8, 10, 14, 30)),
        );
        state = reducer.reduce(
          state,
          _ranking(
            eoBeforeCutoff ? 1075 : 1080,
            atJst: DateTime(2026, 8, 10, 15, 5),
          ),
        );

        _expectProgress(
          state,
          pending: eoBeforeCutoff ? 80 : 75,
          projected: 1155,
        );
        expect(state.day(DateTime(2026, 8, 10)).eo, 75);
        expect(state.day(DateTime(2026, 8, 10)).quest, 80);
        expect(state.monthRecorded, 155);
      });
    }

    test('旧存档无分期数据时同一发榜周期重复读取仍保留原增量', () {
      final legacyJson = {
        'monthKey': '2026-08',
        'experienceTrackingVersion': currentSenkaExperienceTrackingVersion,
        'memberId': 123,
        'nickname': '本人',
        'latestExperience': 110000,
        'targetSenka': 1220,
        'dailyTargetDateKey': '2026-08-10',
        'dailyProjectedSenkaAtStart': 1000,
        'days': {
          '2026-08-10': {'experience': 7, 'eo': 0, 'quest': 0},
        },
        'calculatorCurrentSenka': 1000,
        'calculatorLocalSenkaAtSet': 0,
        'rankingHistory': {
          'player': [
            {
              'rank': 397,
              'senka': 1000,
              'capturedAt': DateTime.utc(2026, 8, 9, 18, 5).toIso8601String(),
              'localSenkaAtCapture': 0,
            },
          ],
        },
      };
      var state = SenkaState.fromJson(legacyJson);
      _expectProgress(state, pending: 7, projected: 1007);

      state = reducer.reduce(
        state,
        _ranking(1000, atJst: DateTime(2026, 8, 10, 13)),
      );
      state = SenkaState.fromJson(jsonDecode(jsonEncode(state.toJson())));
      state = reducer.reduce(
        state,
        _ranking(1000, atJst: DateTime(2026, 8, 10, 13, 30)),
      );

      _expectProgress(state, pending: 7, projected: 1007);
    });

    test('月初二点半仍返回上月旧榜时不污染新月计算', () {
      var state = reducer.reduce(
        _initialState(),
        _ranking(4000, atJst: DateTime(2026, 8, 31, 21)),
      );
      state = reducer.reduce(
        state,
        _experience(100000, atJst: DateTime(2026, 9, 1, 2, 5)),
      );
      state = reducer.reduce(
        state,
        _experience(110000, atJst: DateTime(2026, 9, 1, 2, 10)),
      );
      expect(state.monthKey, '2026-09');
      final before = SenkaCalculationResult.fromState(
        state,
        now: DateTime.utc(2026, 8, 31, 17, 30),
      );
      state = reducer.reduce(
        state,
        _ranking(4000, atJst: DateTime(2026, 9, 1, 2, 30)),
      );
      final after = SenkaCalculationResult.fromState(
        state,
        now: DateTime.utc(2026, 8, 31, 17, 30),
      );

      expect(state.monthKey, '2026-09');
      expect(state.calculatorCurrentSenka, 0);
      expect(state.playerRankingRow.senka, isNull);
      expect(after.projected, before.projected);
      expect(after.unsettledSenka, before.unsettledSenka);
      expect(state.day(DateTime(2026, 9, 1)).experience, closeTo(7, 1e-9));
    });

    test('新发榜时段仍返回旧分数时保留增量直到榜单真正更新', () {
      var state = _stateWithMorningRanking(reducer);
      state = reducer.reduce(
        state,
        _experience(110000, atJst: DateTime(2026, 8, 10, 12)),
      );
      for (final hour in [15, 16, 17]) {
        state = reducer.reduce(
          state,
          _ranking(1000, atJst: DateTime(2026, 8, 10, hour)),
        );
        _expectProgress(state, pending: 7, projected: 1007);
        state = SenkaState.fromJson(jsonDecode(jsonEncode(state.toJson())));
      }
      state = reducer.reduce(
        state,
        _experience(111000, atJst: DateTime(2026, 8, 10, 17, 30)),
      );
      state = reducer.reduce(
        state,
        _ranking(1007, atJst: DateTime(2026, 8, 10, 18)),
      );
      _expectProgress(state, pending: .7, projected: 1007.7);
    });

    test('默认解密系数被首次推导为相同值时仍保护延迟旧榜', () {
      var state = _stateWithMorningRanking(reducer);
      expect(state.magic, 0);
      state = reducer.reduce(
        state,
        _experience(110000, atJst: DateTime(2026, 8, 10, 12)),
      );
      state = reducer.reduce(
        state,
        _ranking(
          1000,
          atJst: DateTime(2026, 8, 10, 15, 5),
          includeNeighbor: true,
        ),
      );
      expect(state.magic, 97);
      _expectProgress(state, pending: 7, projected: 1007);
    });

    test('新周期不足一点的收益可在官方整数分数未变时正常结算', () {
      var state = _stateWithMorningRanking(reducer);
      state = reducer.reduce(
        state,
        _experience(101000, atJst: DateTime(2026, 8, 10, 12)),
      );
      state = reducer.reduce(
        state,
        _experience(101500, atJst: DateTime(2026, 8, 10, 14, 30)),
      );
      state = reducer.reduce(
        state,
        _ranking(1000, atJst: DateTime(2026, 8, 10, 15)),
      );
      _expectProgress(state, pending: .35, projected: 1000.35);
    });

    test('十四点整属于下一期且十五点前不提前结算', () {
      var state = _stateWithMorningRanking(reducer);
      state = reducer.reduce(
        state,
        _experience(105000, atJst: DateTime(2026, 8, 10, 13, 59, 59)),
      );
      state = reducer.reduce(
        state,
        _experience(107750, atJst: DateTime(2026, 8, 10, 14)),
      );
      state = reducer.reduce(
        state,
        _ranking(1000, atJst: DateTime(2026, 8, 10, 14, 59, 59)),
      );
      _expectProgress(state, pending: 5.425, projected: 1005.425);
      state = reducer.reduce(
        state,
        _ranking(1003.5, atJst: DateTime(2026, 8, 10, 15)),
      );
      _expectProgress(state, pending: 1.925, projected: 1005.425);
    });
  });
}

SenkaState _initialState() => SenkaState.forMonth('2026-08').copyWith(
  memberId: 123,
  nickname: '本人',
  latestExperience: 100000,
  targetSenka: 1220,
  dailyTargetDateKey: '2026-08-10',
  dailyProjectedSenkaAtStart: 1000,
);

SenkaState _stateWithMorningRanking(SenkaReducer reducer) => reducer.reduce(
  _initialState(),
  _ranking(1000, atJst: DateTime(2026, 8, 10, 3, 5)),
);

SenkaCalculationResult _calculation(SenkaState state) =>
    SenkaCalculationResult.fromState(state, now: DateTime.utc(2026, 8, 10, 8));

void _expectProgress(
  SenkaState state, {
  required double pending,
  required double projected,
}) {
  expect(state.playerRankingRow.senkaDelta, closeTo(pending, 1e-9));
  expect(state.unsettledSenka, closeTo(pending, 1e-9));
  final result = _calculation(state);
  expect(result.unsettledSenka, closeTo(pending, 1e-9));
  expect(result.projected, closeTo(projected, 1e-9));
}

CapturedApiEvent _experience(int total, {required DateTime atJst}) => _apiEvent(
  '/kcsapi/api_get_member/basic',
  {'api_experience': total},
  atJst: atJst,
);

CapturedApiEvent _mapInfo({required bool cleared, required DateTime atJst}) =>
    _apiEvent('/kcsapi/api_get_member/mapinfo', {
      'api_map_info': [
        {'api_id': 15, 'api_cleared': cleared ? 1 : 0},
      ],
    }, atJst: atJst);

CapturedApiEvent _quest({required DateTime atJst}) => _apiEvent(
  '/kcsapi/api_req_quest/clearitemget',
  const {},
  params: const {'api_quest_id': '284'},
  atJst: atJst,
);

CapturedApiEvent _ranking(
  double officialSenka, {
  required DateTime atJst,
  bool includeNeighbor = false,
}) => _apiEvent('/kcsapi/api_req_ranking/mxltvkpyuklh', {
  'api_disp_page': 40,
  'api_list': [
    {
      'api_mxltvkpyuklh': 397,
      'api_mtjmdcwtvhdr': '本人',
      // A real encrypted integer payload; rank 397 and member 123 use
      // right factor 4568 and account factor 97, respectively.
      'api_wuhnhojjxmke': ((officialSenka + 91) * 4568 * 97).round(),
    },
    if (includeNeighbor)
      {
        'api_mxltvkpyuklh': 398,
        'api_mtjmdcwtvhdr': '其他人',
        'api_wuhnhojjxmke': ((officialSenka + 92) * 5695 * 97).round(),
      },
  ],
}, atJst: atJst);

CapturedApiEvent _apiEvent(
  String path,
  Object? data, {
  Map<String, Object?> params = const {},
  required DateTime atJst,
}) => CapturedApiEvent(
  path: path,
  requestParams: params,
  responseBody: jsonEncode({'api_result': 1, 'api_data': data}),
  source: CaptureSource.manual,
  capturedAt: DateTime.utc(
    atJst.year,
    atJst.month,
    atJst.day,
    atJst.hour,
    atJst.minute,
    atJst.second,
  ).subtract(const Duration(hours: 9)),
);
