import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_reducer.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_state.dart';

import 'fixtures/kcsapi_fixtures.dart';

DateTime _at(int hour, [int minute = 0, int second = 0]) => DateTime.utc(
  2026,
  10,
  20,
  hour,
  minute,
  second,
).subtract(const Duration(hours: 9));

SenkaState _sample(
  SenkaState state,
  String path,
  int experience,
  DateTime at,
) => const SenkaReducer().reduce(
  state,
  kcsapiEvent(
    path,
    path == '/kcsapi/api_port/port'
        ? {
            'api_basic': {'api_member_id': 1001, 'api_experience': experience},
          }
        : path == '/kcsapi/api_get_member/basic'
        ? {'api_member_id': 1001, 'api_experience': experience}
        : {'api_member_exp': experience},
    capturedAt: at,
  ),
);

SenkaState _port(SenkaState state, int experience, DateTime at) =>
    _sample(state, '/kcsapi/api_port/port', experience, at);

SenkaState _roundTrip(SenkaState state) =>
    SenkaState.fromJson(jsonDecode(jsonEncode(state.toJson())));

void main() {
  group('independent final review of EXP observation integrity', () {
    test('a lower EXP port cannot release an unconfirmed sortie gain', () {
      var state = _port(SenkaState.forMonth('2026-10'), 100000, _at(12));
      state = _sample(
        state,
        '/kcsapi/api_req_sortie/battleresult',
        110000,
        _at(13, 59),
      );
      expect(state.pendingSortieExperience, 10000);

      // The cumulative value contradicts an already observed battle result.
      // Do not treat this stale cached value as confirmation of that gain.
      state = _port(_roundTrip(state), 100000, _at(14, 1));
      expect(state.pendingSortieExperience, 10000);
      state = _sample(
        state,
        '/kcsapi/api_get_member/basic',
        110000,
        _at(14, 2),
      );
      expect(state.monthExperienceSenka, 0);
      state = _port(_roundTrip(state), 110000, _at(14, 3));
      expect(state.pendingSortieExperience, 0);
      expect(state.monthExperienceSenka, closeTo(7, 1e-9));
    });

    test('a contradictory older EXP cannot poison the observed high water', () {
      var state = _port(SenkaState.forMonth('2026-10'), 100000, _at(12));
      state = _sample(state, '/kcsapi/api_get_member/basic', 200000, _at(11));
      expect(state.latestExperience, 100000);

      state = _port(_roundTrip(state), 101000, _at(13));
      state = _sample(
        state,
        '/kcsapi/api_req_sortie/battleresult',
        102000,
        _at(13, 59),
      );
      expect(state.pendingSortieExperience, 1000);
      state = _sample(
        state,
        '/kcsapi/api_get_member/basic',
        102000,
        _at(14, 1),
      );
      expect(state.monthExperienceSenka, closeTo(.7, 1e-9));
      state = _port(state, 102000, _at(14, 2));
      expect(state.monthExperienceSenka, closeTo(1.4, 1e-9));
    });

    test(
      'compacted samples keep totals after reload and old sample replay',
      () {
        var state = _port(SenkaState.forMonth('2026-10'), 100000, _at(12));
        for (var i = 1; i <= 2060; i++) {
          state = _sample(
            state,
            '/kcsapi/api_get_member/basic',
            100000 + i,
            _at(12).add(Duration(seconds: i)),
          );
        }
        state = _roundTrip(state);
        expect(state.experienceSamples, hasLength(2048));
        expect(state.monthExperienceSenka, closeTo(2060 * .0007, 1e-9));
        state = _sample(
          state,
          '/kcsapi/api_get_member/basic',
          100001,
          _at(12).add(const Duration(seconds: 1)),
        );
        expect(state.monthExperienceSenka, closeTo(2060 * .0007, 1e-9));
        state = _port(state, 102061, _at(13));
        expect(state.monthExperienceSenka, closeTo(2061 * .0007, 1e-9));
      },
    );
  });

  test('compaction and JSON preserve a sortie held across the cutoff', () {
    var state = _port(SenkaState.forMonth('2026-10'), 100000, _at(12));
    for (var i = 1; i <= 2060; i++) {
      state = _sample(
        state,
        '/kcsapi/api_req_sortie/battleresult',
        100000 + i,
        _at(12).add(Duration(seconds: i)),
      );
    }
    state = _roundTrip(state);
    expect(state.experienceSamples, hasLength(2048));
    expect(state.pendingSortieExperience, 2060);
    expect(state.monthExperienceSenka, 0);
    state = _port(state, 102000, _at(13));
    expect(state.pendingSortieExperience, 2060);
    state = _port(_roundTrip(state), 102060, _at(14, 1));
    expect(state.pendingSortieExperience, 0);
    expect(state.monthExperienceSenka, closeTo(2060 * .0007, 1e-9));
    final afternoon = senkaSettlementPeriodStart(_at(14, 1)).toIso8601String();
    expect(
      state.settlementPeriods[afternoon]!.experience,
      closeTo(2060 * .0007, 1e-9),
    );
  });

  group('independent final review of EO receipt attribution', () {
    DateTime boundary(int month, int day, int hour, [int minute = 0]) =>
        DateTime.utc(
          2026,
          month,
          day,
          hour,
          minute,
        ).subtract(const Duration(hours: 9));

    SenkaState mapInfo(SenkaState state, bool cleared, DateTime at) =>
        const SenkaReducer().reduce(
          state,
          kcsapiEvent('/kcsapi/api_get_member/mapinfo', {
            'api_map_info': [
              {'api_id': 15, 'api_cleared': cleared ? 1 : 0},
            ],
          }, capturedAt: at),
        );

    SenkaState result(SenkaState state, DateTime at) =>
        const SenkaReducer().reduce(
          state,
          kcsapiEvent('/kcsapi/api_req_sortie/battleresult', {
            'api_member_exp': 100000,
            'api_get_exmap_rate': 75,
          }, capturedAt: at),
        );

    test('unassigned EO in the invalid window cannot earn next month', () {
      var state = _port(
        SenkaState.forMonth('2026-10'),
        100000,
        boundary(10, 31, 21),
      );
      state = mapInfo(state, false, boundary(10, 31, 21, 55));
      // A restored session can observe the receipt without its sortie start.
      state = result(state, boundary(10, 31, 22, 1));
      state = mapInfo(_roundTrip(state), true, boundary(11, 1, 0, 1));
      expect(state.monthKey, '2026-11');
      expect(state.monthRecorded, 0);
      expect(state.monthArchives['2026-10']!.monthRecorded, 0);
      state = mapInfo(_roundTrip(state), true, boundary(11, 1, 0, 2));
      expect(state.monthRecorded, 0);
      state = mapInfo(state, false, boundary(11, 1, 0, 3));
      state = result(state, boundary(11, 1, 0, 5));
      state = mapInfo(state, true, boundary(11, 1, 0, 6));
      expect(state.monthRecorded, 75);
    });

    test('a delayed valid EO receipt still credits its archived month', () {
      var state = _port(
        SenkaState.forMonth('2026-10'),
        100000,
        boundary(10, 31, 21),
      );
      state = mapInfo(state, false, boundary(10, 31, 21, 45));
      state = const SenkaReducer().reduce(
        state,
        kcsapiEvent('/kcsapi/api_req_map/start', {
          'api_maparea_id': 1,
          'api_mapinfo_no': 5,
          'api_no': 1,
          'api_bosscell_no': 4,
        }, capturedAt: boundary(10, 31, 21, 50)),
      );
      state = mapInfo(_roundTrip(state), false, boundary(11, 1, 0, 1));
      state = result(state, boundary(10, 31, 21, 59));
      expect(state.monthKey, '2026-11');
      expect(state.monthRecorded, 0);
      expect(state.monthArchives['2026-10']!.monthRecorded, 75);
    });
  });
}
