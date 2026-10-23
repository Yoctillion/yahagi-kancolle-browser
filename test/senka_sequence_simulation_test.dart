import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_reducer.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_state.dart';

import 'fixtures/kcsapi_fixtures.dart';

void main() {
  test(
    '80 reordered multi-source month-boundary sequences preserve every gain',
    () {
      const paths = [
        '/kcsapi/api_req_sortie/battleresult',
        '/kcsapi/api_req_combined_battle/battleresult',
        '/kcsapi/api_req_mission/result',
        '/kcsapi/api_port/port',
        '/kcsapi/api_get_member/basic',
        '/kcsapi/api_req_practice/battle_result',
      ];
      final start = DateTime.utc(2026, 10, 30, 15); // October 31 00:00 JST.
      final events = <({String path, DateTime at, int experience})>[];
      final expected = <String, double>{};
      var experience = 100000;
      var pending = 0;
      for (var i = 0; i < 72; i++) {
        final path = paths[i % paths.length];
        final at = start.add(Duration(hours: i));
        final gained = 101 + i * 13;
        experience += gained;
        events.add((path: path, at: at, experience: experience));
        if (path.contains('battleresult')) {
          pending += gained;
          continue;
        }
        var credited = gained;
        if (path.endsWith('/port')) {
          credited += pending;
          pending = 0;
        }
        final jst = at.add(const Duration(hours: 9));
        final end = DateTime.utc(jst.year, jst.month + 1, 0).day;
        final operation = jst.day == end && jst.hour >= 22
            ? DateTime.utc(jst.year, jst.month + 1)
            : jst;
        final month =
            '${operation.year}-${operation.month.toString().padLeft(2, '0')}';
        expected[month] = (expected[month] ?? 0) + credited * 7 / 10000;
      }
      for (var seed = 0; seed < 80; seed++) {
        final order = events.toList()..shuffle(Random(seed));
        var state = SenkaState.forMonth(
          '2026-10',
        ).copyWith(memberId: 1001, latestExperience: 100000);
        for (var i = 0; i < order.length; i++) {
          final observation = order[i];
          final data = observation.path.endsWith('/port')
              ? {
                  'api_basic': {'api_experience': observation.experience},
                }
              : observation.path.endsWith('/basic')
              ? {'api_experience': observation.experience}
              : {'api_member_exp': observation.experience};
          final event = kcsapiEvent(
            observation.path,
            data,
            capturedAt: observation.at,
          );
          state = const SenkaReducer().reduce(state, event);
          if (i % 13 == 0) state = const SenkaReducer().reduce(state, event);
          if (i % 7 == 0) {
            state = SenkaState.fromJson(jsonDecode(jsonEncode(state.toJson())));
          }
        }
        for (final entry in expected.entries) {
          final month = entry.key == state.monthKey
              ? state
              : state.monthArchives[entry.key]!;
          expect(
            month.monthExperienceSenka,
            closeTo(entry.value, 1e-8),
            reason: 'seed $seed / ${entry.key}',
          );
        }
        expect(state.pendingSortieExperience, pending, reason: 'seed $seed');
        expect(state.latestExperience, experience, reason: 'seed $seed');
      }
    },
  );
}
