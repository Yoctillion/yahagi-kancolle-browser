import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_calculation.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_reducer.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_state.dart';

// Mechanism references, checked 2026-10-20:
// https://wikiwiki.jp/kancolle/称号・戦果#l6f22cde
// Normal senka = cumulative admiral EXP gained * 7/10000, credited on return
// to port. Results before a cutoff do not settle a sortie returned afterward.
// https://wikiwiki.jp/kancolle/経験値#o1abadeb
// The current admiral EXP cap is 554,400,000; capped cumulative snapshots must
// never create EXP from a result's separate per-battle reward display.
void main() {
  const reducer = SenkaReducer();

  group('experience snapshot integrity audit', () {
    for (final path in [
      '/kcsapi/api_get_member/basic',
      '/kcsapi/api_get_member/record',
      '/kcsapi/api_req_mission/result',
      '/kcsapi/api_req_practice/battle_result',
      '/kcsapi/api_req_sortie/battleresult',
      '/kcsapi/api_req_combined_battle/battleresult',
    ]) {
      test('$path uses cumulative EXP and port repetition adds nothing', () {
        var state = _state();
        state = reducer.reduce(
          state,
          _experience(path, 110000, DateTime(2026, 8, 10, 12)),
        );
        state = reducer.reduce(
          state,
          _port(110000, DateTime(2026, 8, 10, 12, 1)),
        );
        state = _roundTrip(state);
        state = reducer.reduce(
          state,
          _port(110000, DateTime(2026, 8, 10, 12, 2)),
        );
        expect(state.monthExperienceSenka, closeTo(7, 1e-9));
        expect(state.latestExperience, 110000);
      });
    }

    test('one point of EXP keeps the full 0.0007 senka fraction', () {
      final state = reducer.reduce(
        _state(),
        _port(100001, DateTime(2026, 8, 10, 12)),
      );
      expect(state.monthExperienceSenka, closeTo(.0007, 1e-12));
    });

    test('cap snapshots do not mint EXP from displayed reward fields', () {
      const cap = 554400000;
      var state = _state().copyWith(latestExperience: cap - 100);
      state = reducer.reduce(state, _port(cap, DateTime(2026, 8, 10, 12)));
      for (final path in [
        '/kcsapi/api_req_mission/result',
        '/kcsapi/api_req_practice/battle_result',
        '/kcsapi/api_req_sortie/battleresult',
        '/kcsapi/api_req_combined_battle/battleresult',
      ]) {
        state = reducer.reduce(
          state,
          _event(path, {
            'api_member_exp': cap,
            'api_get_exp': 10000,
            'api_get_ship_exp': [10000],
          }, DateTime(2026, 8, 10, 13)),
        );
      }
      state = reducer.reduce(
        _roundTrip(state),
        _port(cap, DateTime(2026, 8, 10, 14)),
      );
      expect(state.latestExperience, cap);
      expect(state.monthExperienceSenka, closeTo(.07, 1e-9));
    });

    test('decreasing or repeated snapshots cannot inflate same-period EXP', () {
      var state = _state();
      for (final exp in [100100, 100050, 100100, 100500, 100200, 100500]) {
        state = reducer.reduce(
          state,
          _experience(
            '/kcsapi/api_get_member/basic',
            exp,
            DateTime(2026, 8, 10, 12),
          ),
        );
      }
      expect(state.latestExperience, 100500);
      expect(state.monthExperienceSenka, closeTo(.35, 1e-9));
    });

    test('zero is a valid initial cumulative EXP baseline', () {
      var state = SenkaState.forMonth('2026-08');
      state = reducer.reduce(state, _port(0, DateTime(2026, 8, 10, 12)));
      state = reducer.reduce(state, _port(100, DateTime(2026, 8, 10, 13)));
      expect(state.monthExperienceSenka, closeTo(.07, 1e-9));
    });
  });

  group('return-to-port cutoff audit', () {
    for (final path in [
      '/kcsapi/api_req_sortie/battleresult',
      '/kcsapi/api_req_combined_battle/battleresult',
    ]) {
      test('$path ending before 02:00 credits EXP to the return day', () {
        var state = _state();
        state = reducer.reduce(state, _start(DateTime(2026, 8, 10, 1, 50)));
        state = reducer.reduce(
          state,
          _experience(path, 101000, DateTime(2026, 8, 10, 1, 59)),
        );
        state = reducer.reduce(
          state,
          _port(101000, DateTime(2026, 8, 10, 2, 1)),
        );

        expect(state.day(DateTime(2026, 8, 9)).experience, 0);
        expect(state.day(DateTime(2026, 8, 10)).experience, closeTo(.7, 1e-9));
      });

      test('$path ending before 14:00 stays pending after 15:00 ranking', () {
        var state = reducer.reduce(
          _state(),
          _ranking(1000, DateTime(2026, 8, 10, 3, 5)),
        );
        state = reducer.reduce(state, _start(DateTime(2026, 8, 10, 13, 50)));
        state = reducer.reduce(
          state,
          _experience(path, 101000, DateTime(2026, 8, 10, 13, 59)),
        );
        state = reducer.reduce(
          state,
          _port(101000, DateTime(2026, 8, 10, 14, 1)),
        );
        state = reducer.reduce(
          state,
          _ranking(1000, DateTime(2026, 8, 10, 15, 5)),
        );

        expect(state.unsettledSenka, closeTo(.7, 1e-9));
        expect(senkaProjected(state), closeTo(1000.7, 1e-9));
      });
    }

    test('multi-battle sortie commits every battle to the return day', () {
      var state = reducer.reduce(
        _state(),
        _start(DateTime(2026, 8, 10, 1, 40)),
      );
      state = reducer.reduce(
        state,
        _experience(
          '/kcsapi/api_req_sortie/battleresult',
          100100,
          DateTime(2026, 8, 10, 1, 50),
        ),
      );
      state = reducer.reduce(
        state,
        _experience(
          '/kcsapi/api_req_sortie/battleresult',
          100500,
          DateTime(2026, 8, 10, 2, 5),
        ),
      );
      state = reducer.reduce(
        _roundTrip(state),
        _port(100500, DateTime(2026, 8, 10, 2, 10)),
      );

      expect(state.day(DateTime(2026, 8, 9)).experience, 0);
      expect(state.day(DateTime(2026, 8, 10)).experience, closeTo(.35, 1e-9));
    });

    test('month-end return after 22:00 belongs to the following operation', () {
      var state = reducer.reduce(
        _state(),
        _start(DateTime(2026, 8, 31, 21, 50)),
      );
      state = reducer.reduce(
        state,
        _experience(
          '/kcsapi/api_req_sortie/battleresult',
          101000,
          DateTime(2026, 8, 31, 21, 59),
        ),
      );
      state = reducer.reduce(
        state,
        _port(101000, DateTime(2026, 8, 31, 22, 1)),
      );

      expect(state.monthKey, '2026-09');
      expect(state.monthExperienceSenka, closeTo(.7, 1e-9));
    });
  });

  test(
    'out-of-order cumulative snapshots preserve before-cutoff settlement',
    () {
      final early = _experience(
        '/kcsapi/api_get_member/basic',
        110000,
        DateTime(2026, 8, 10, 13),
      );
      final late = _experience(
        '/kcsapi/api_get_member/basic',
        120000,
        DateTime(2026, 8, 10, 16),
      );
      SenkaState simulate(List<CapturedApiEvent> snapshots) {
        var state = reducer.reduce(
          _state(),
          _ranking(1000, DateTime(2026, 8, 10, 3, 5)),
        );
        for (final snapshot in snapshots) {
          state = reducer.reduce(state, snapshot);
        }
        return reducer.reduce(
          _roundTrip(state),
          _ranking(1007, DateTime(2026, 8, 10, 17)),
        );
      }

      final chronological = simulate([early, late]);
      final reordered = simulate([late, early]);
      expect(chronological.unsettledSenka, closeTo(7, 1e-9));
      expect(reordered.monthExperienceSenka, closeTo(14, 1e-9));
      expect(reordered.unsettledSenka, closeTo(7, 1e-9));
      expect(senkaProjected(reordered), closeTo(1014, 1e-9));
    },
  );

  for (final month in [
    (year: 2026, month: 2, days: 28),
    (year: 2028, month: 2, days: 29),
    (year: 2026, month: 4, days: 30),
    (year: 2026, month: 8, days: 31),
  ]) {
    test('ordered ${month.days}-day simulation settles twice each day', () {
      final key = '${month.year}-${month.month.toString().padLeft(2, '0')}';
      var state = _state(month: key);
      var cumulative = 100000;
      var official = 1000.0;
      for (var day = 1; day <= month.days; day++) {
        DateTime at(int hour, [int minute = 0]) =>
            DateTime(month.year, month.month, day, hour, minute);
        if (day > 1) official += 14;
        state = reducer.reduce(state, _ranking(official, at(3, 5)));
        expect(state.unsettledSenka, closeTo(0, 1e-9));
        for (final hour in [4, 13]) {
          cumulative += 10000;
          state = reducer.reduce(state, _port(cumulative, at(hour, 30)));
        }
        official += 14;
        state = reducer.reduce(state, _ranking(official, at(15, 5)));
        expect(state.unsettledSenka, closeTo(0, 1e-9));
        // Stop the final day before the separately audited 22:00 month edge.
        for (final hour in [16, 21]) {
          cumulative += 10000;
          state = reducer.reduce(state, _port(cumulative, at(hour, 30)));
        }
        state = _roundTrip(state);
        expect(state.unsettledSenka, closeTo(14, 1e-9));
        expect(state.monthExperienceSenka, closeTo(day * 28, 1e-9));
        expect(senkaProjected(state), closeTo(1000 + day * 28, 1e-9));
      }
    });
  }
}

SenkaState _state({String month = '2026-08'}) => SenkaState.forMonth(
  month,
).copyWith(memberId: 123, nickname: 'audit-player', latestExperience: 100000);

SenkaState _roundTrip(SenkaState state) =>
    SenkaState.fromJson(jsonDecode(jsonEncode(state.toJson())));

CapturedApiEvent _port(int total, DateTime atJst) =>
    _event('/kcsapi/api_port/port', {
      'api_basic': {'api_experience': total},
    }, atJst);

CapturedApiEvent _experience(String path, int total, DateTime atJst) =>
    _event(path, switch (path) {
      '/kcsapi/api_get_member/basic' => {'api_experience': total},
      '/kcsapi/api_get_member/record' => {
        'api_experience': [total, 0],
      },
      _ => {'api_member_exp': total, 'api_win_rank': 'S'},
    }, atJst);

CapturedApiEvent _start(DateTime atJst) => _event('/kcsapi/api_req_map/start', {
  'api_maparea_id': 3,
  'api_mapinfo_no': 2,
  'api_no': 1,
}, atJst);

CapturedApiEvent _ranking(double official, DateTime atJst) =>
    _event('/kcsapi/api_req_ranking/mxltvkpyuklh', {
      'api_disp_page': 40,
      'api_list': [
        {
          'api_mxltvkpyuklh': 397,
          'api_mtjmdcwtvhdr': 'audit-player',
          'api_wuhnhojjxmke': ((official + 91) * 4568 * 97).round(),
        },
      ],
    }, atJst);

CapturedApiEvent _event(String path, Object? data, DateTime atJst) =>
    CapturedApiEvent(
      path: path,
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
