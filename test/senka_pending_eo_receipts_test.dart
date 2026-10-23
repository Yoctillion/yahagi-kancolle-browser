import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_reducer.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_state.dart';

import 'fixtures/kcsapi_fixtures.dart';

DateTime _at(int month, int day, int hour, [int minute = 0]) => DateTime.utc(
  2026,
  month,
  day,
  hour,
  minute,
).subtract(const Duration(hours: 9));

SenkaState _receipt(SenkaState state, int amount, DateTime at) =>
    const SenkaReducer().reduce(
      state,
      kcsapiEvent('/kcsapi/api_req_sortie/battleresult', {
        'api_get_exmap_rate': amount,
      }, capturedAt: at),
    );

SenkaState _maps(SenkaState state, List<int> cleared, DateTime at) =>
    const SenkaReducer().reduce(
      state,
      kcsapiEvent('/kcsapi/api_get_member/mapinfo', {
        'api_map_info': [
          for (final id in [15, 25])
            {'api_id': id, 'api_cleared': cleared.contains(id) ? 1 : 0},
        ],
      }, capturedAt: at),
    );

SenkaState _reload(SenkaState state) =>
    SenkaState.fromJson(jsonDecode(jsonEncode(state.toJson())));

void main() {
  test(
    'unassigned receipts on both sides of midnight retain independent times',
    () {
      var state = _maps(SenkaState.forMonth('2026-10'), [], _at(10, 31, 21));
      state = _receipt(state, 75, _at(10, 31, 22, 1)); // Displayed, but void.
      state = _receipt(_reload(state), 75, _at(11, 1, 0, 5));
      state = _maps(_reload(state), [15], _at(11, 1, 0, 6));
      expect(state.monthRecorded, 75);
      expect(state.day(DateTime.utc(2026, 11, 1)).eo, 75);
      expect(state.monthArchives['2026-10']!.monthRecorded, 0);
      state = _maps(_reload(state), [15], _at(11, 1, 0, 7));
      expect(state.monthRecorded, 75);
    },
  );

  test(
    'multiple unassigned actual EO rewards do not merge into a fictitious amount',
    () {
      var state = _maps(SenkaState.forMonth('2026-10'), [], _at(10, 20, 12));
      state = _receipt(state, 77, _at(10, 20, 13));
      state = _receipt(_reload(state), 101, _at(10, 20, 14));
      state = _maps(_reload(state), [15, 25], _at(10, 20, 15));
      expect(state.monthRecorded, 178);
      state = _maps(_reload(state), [15, 25], _at(10, 20, 16));
      expect(state.monthRecorded, 178);
    },
  );
}
