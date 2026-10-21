import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_ledger.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_reducer.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_state.dart';

import 'fixtures/kcsapi_fixtures.dart';

void main() {
  test(
    'manual base correction preserves EXP still awaiting return to port',
    () {
      final at = DateTime.utc(2026, 10, 20, 5);
      var state = SenkaState.forMonth(
        '2026-10',
      ).copyWith(latestExperience: 100000);
      state = const SenkaReducer().reduce(
        state,
        kcsapiEvent('/kcsapi/api_req_sortie/battleresult', {
          'api_member_exp': 110000,
        }, capturedAt: at),
      );
      state = replaceSenkaBaseExperience(
        state,
        12.34,
        at.add(const Duration(minutes: 1)),
      );
      state = SenkaState.fromJson(jsonDecode(jsonEncode(state.toJson())));
      state = const SenkaReducer().reduce(
        state,
        kcsapiEvent('/kcsapi/api_port/port', {
          'api_basic': {'api_experience': 110000},
        }, capturedAt: at.add(const Duration(minutes: 2))),
      );
      expect(state.monthExperienceSenka, closeTo(19.34, 1e-9));
      expect(state.pendingSortieExperience, 0);
    },
  );
}
