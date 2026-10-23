import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_reducer.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_state.dart';

// Rule source: https://wikiwiki.jp/kancolle/称号・戦果
// Ordinary senka: previous month 22:00 through current month 21:59.
// EO: calendar month 00:00 through the last day 21:59; 22:00-23:59 is void.
// Quests: last day 14:00 starts the next operation. Expiring quarterly
// rewards are void until the next quarter's 05:00 reset. Annual rewards
// carry across that window, and the new annual cycle can award them again.
void main() {
  const reducer = SenkaReducer();

  SenkaState tick(SenkaState state, DateTime jst) => reducer.reduce(
    state,
    _api('/kcsapi/api_get_member/basic', const {}, jst),
  );

  SenkaState port(SenkaState state, int experience, DateTime jst) =>
      reducer.reduce(
        state,
        _api('/kcsapi/api_port/port', {
          'api_basic': {'api_experience': experience},
        }, jst),
      );

  SenkaState eo(SenkaState state, DateTime jst) {
    // Include the actual gauge-clear result so this scenario establishes the
    // clearing time, rather than inferring it from a later map snapshot.
    // The displayed 75-point reward can still be present during the void
    // window; the Wiki explicitly distinguishes display from operation credit.
    final cleared = reducer.reduce(
      state,
      _api('/kcsapi/api_req_sortie/battleresult', {
        'api_get_exmap_rate': '75',
        'api_first_clear': 1,
        'api_win_rank': 'S',
      }, jst),
    );
    return reducer.reduce(
      cleared,
      _api('/kcsapi/api_get_member/mapinfo', {
        'api_map_info': [
          {'api_id': 15, 'api_cleared': 1},
        ],
      }, jst.add(const Duration(milliseconds: 1))),
    );
  }

  SenkaState quest(SenkaState state, int id, DateTime jst) => reducer.reduce(
    state,
    _api(
      '/kcsapi/api_req_quest/clearitemget',
      const {},
      jst,
      params: {'api_quest_id': '$id'},
    ),
  );

  group('ordinary experience operation boundaries', () {
    test('last day 21:59:59 still belongs to the ending operation', () {
      final state = port(
        SenkaState.forMonth('2026-10').copyWith(latestExperience: 100000),
        101000,
        DateTime.utc(2026, 10, 31, 21, 59, 59),
      );
      expect(state.monthKey, '2026-10');
      expect(state.monthRecorded, closeTo(.7, 1e-9));
    });

    for (final instant in [
      DateTime.utc(2026, 10, 31, 22),
      DateTime.utc(2026, 10, 31, 23, 59, 59),
      DateTime.utc(2026, 11, 1),
      DateTime.utc(2026, 11, 1, 1, 59, 59),
    ]) {
      test('gain at $instant JST survives into November operation', () {
        var state = port(
          SenkaState.forMonth('2026-10').copyWith(latestExperience: 100000),
          101000,
          instant,
        );
        state = tick(state, DateTime.utc(2026, 11, 1, 3));
        expect(state.monthKey, '2026-11');
        expect(state.monthRecorded, closeTo(.7, 1e-9));
      });
    }

    test('baseline survives rollover so first later return loses no gain', () {
      var state = port(
        SenkaState.forMonth('2026-10').copyWith(latestExperience: 100000),
        101000,
        DateTime.utc(2026, 10, 31, 22, 10),
      );
      state = port(state, 102000, DateTime.utc(2026, 11, 1, 3));
      expect(state.monthRecorded, closeTo(1.4, 1e-9));
    });

    test('December 31 after 22:00 is January ordinary senka', () {
      var state = port(
        SenkaState.forMonth('2026-12').copyWith(latestExperience: 100000),
        101000,
        DateTime.utc(2026, 12, 31, 22),
      );
      state = tick(state, DateTime.utc(2027, 1, 1, 3));
      expect(state.monthKey, '2027-01');
      expect(state.monthRecorded, closeTo(.7, 1e-9));
    });
  });

  group('EO has a separate calendar and void window', () {
    test('last day 21:59:59 awards current month EO senka', () {
      final state = eo(
        SenkaState.forMonth('2026-10').copyWith(eoTrackingInitialized: true),
        DateTime.utc(2026, 10, 31, 21, 59, 59),
      );
      expect(state.monthRecorded, 75);
    });

    for (final instant in [
      DateTime.utc(2026, 10, 31, 22),
      DateTime.utc(2026, 10, 31, 23, 59, 59),
    ]) {
      test('cleared EO at $instant JST grants no operation senka', () {
        final state = eo(
          SenkaState.forMonth('2026-10').copyWith(eoTrackingInitialized: true),
          instant,
        );
        expect(state.monthRecorded, 0);
      });
    }

    test('new month EO cleared before 02:00 survives later rollover', () {
      var state = eo(
        SenkaState.forMonth('2026-10').copyWith(eoTrackingInitialized: true),
        DateTime.utc(2026, 11, 1, 0, 30),
      );
      state = tick(state, DateTime.utc(2026, 11, 1, 3));
      expect(state.monthKey, '2026-11');
      expect(state.monthRecorded, 75);
      expect(state.completedEoIds, contains(15));
    });

    test('same EO can award again after a fresh monthly map snapshot', () {
      var state = SenkaState.forMonth(
        '2026-10',
      ).copyWith(eoTrackingInitialized: true, completedEoIds: {15});
      state = reducer.reduce(
        state,
        _api('/kcsapi/api_get_member/mapinfo', {
          'api_map_info': [
            {'api_id': 15, 'api_cleared': 0},
          ],
        }, DateTime.utc(2026, 11, 1, 0, 5)),
      );
      state = eo(state, DateTime.utc(2026, 11, 1, 0, 30));
      state = tick(state, DateTime.utc(2026, 11, 1, 3));
      expect(state.monthRecorded, 75);
      expect(state.completedEoIds, contains(15));
    });
  });

  group('quest month attribution and cycle exceptions', () {
    test('quest received at 13:59:59 belongs to ending operation', () {
      var state = quest(
        SenkaState.forMonth('2026-10'),
        854,
        DateTime.utc(2026, 10, 31, 13, 59, 59),
      );
      expect(state.monthRecorded, 350);
      state = tick(state, DateTime.utc(2026, 11, 1, 3));
      expect(state.monthRecorded, 0);
    });

    for (final instant in [
      DateTime.utc(2026, 10, 31, 14),
      DateTime.utc(2026, 10, 31, 21, 59, 59),
      DateTime.utc(2026, 10, 31, 23, 59, 59),
      DateTime.utc(2026, 11, 1, 1, 59, 59),
    ]) {
      test('quest received at $instant JST carries into November', () {
        var state = quest(SenkaState.forMonth('2026-10'), 854, instant);
        state = tick(state, DateTime.utc(2026, 11, 1, 3));
        expect(state.monthKey, '2026-11');
        expect(state.monthRecorded, 350);
        expect(state.recordedQuestIds, contains(854));
      });
    }

    test('late quest carry survives storage restart before month rollover', () {
      var state = quest(
        SenkaState.forMonth('2026-10'),
        854,
        DateTime.utc(2026, 10, 31, 14),
      );
      state = SenkaState.fromJson(jsonDecode(jsonEncode(state.toJson())));
      state = tick(state, DateTime.utc(2026, 11, 1, 3));
      expect(state.monthRecorded, 350);
    });

    for (final instant in [
      DateTime.utc(2026, 5, 31, 14),
      DateTime.utc(2026, 5, 31, 23, 59, 59),
      DateTime.utc(2026, 6, 1),
      DateTime.utc(2026, 6, 1, 4, 59, 59),
    ]) {
      test('expiring quarterly quest at $instant JST grants zero senka', () {
        final state = quest(SenkaState.forMonth('2026-05'), 854, instant);
        expect(state.monthRecorded, 0);
        expect(state.completedQuestIds, contains(854));
      });
    }

    test('new quarterly cycle starts at June 1 05:00', () {
      var state = quest(
        SenkaState.forMonth('2026-05'),
        854,
        DateTime.utc(2026, 5, 31, 14),
      );
      state = quest(state, 854, DateTime.utc(2026, 6, 1, 5));
      expect(state.quarterlyQuestCycleKey, '2026-06');
      expect(state.monthRecorded, 350);
    });

    test('annual old and new cycles both credit June after May 31 14:00', () {
      var state = quest(
        SenkaState.forMonth('2026-05'),
        947,
        DateTime.utc(2026, 5, 31, 14),
      );
      state = tick(state, DateTime.utc(2026, 6, 1, 3));
      state = quest(state, 947, DateTime.utc(2026, 6, 1, 5));
      expect(state.annualQuestCycleKey, '2026-06');
      expect(state.monthRecorded, 960);
    });

    test('annual old cycle at June 1 04:59 remains valid before reset', () {
      var state = quest(
        SenkaState.forMonth('2026-05'),
        947,
        DateTime.utc(2026, 6, 1, 4, 59, 59),
      );
      state = quest(state, 947, DateTime.utc(2026, 6, 1, 5));
      expect(state.monthRecorded, 960);
    });
  });

  group('all twelve month lengths plus leap February', () {
    final months = [
      for (var month = 1; month <= 12; month++) (year: 2026, month: month),
      (year: 2028, month: 2),
    ];
    for (final month in months) {
      final end = DateTime.utc(month.year, month.month + 1, 0);
      final next = DateTime.utc(month.year, month.month + 1, 1, 3);
      final key = '${month.year}-${month.month.toString().padLeft(2, '0')}';

      test('$key last valid ordinary, EO and quest rewards remain valid', () {
        var state = SenkaState.forMonth(
          key,
        ).copyWith(latestExperience: 100000, eoTrackingInitialized: true);
        state = quest(
          state,
          854,
          DateTime.utc(end.year, end.month, end.day, 13, 59, 59),
        );
        state = port(
          state,
          101000,
          DateTime.utc(end.year, end.month, end.day, 21, 59, 59),
        );
        state = eo(
          state,
          DateTime.utc(end.year, end.month, end.day, 21, 59, 59),
        );
        expect(state.monthRecorded, closeTo(425.7, 1e-9));
      });

      test('$key ordinary 22:00 gain belongs to next operation', () {
        var state = port(
          SenkaState.forMonth(key).copyWith(latestExperience: 100000),
          101000,
          DateTime.utc(end.year, end.month, end.day, 22),
        );
        state = tick(state, next);
        expect(state.monthRecorded, closeTo(.7, 1e-9));
      });

      test('$key EO 22:00 gain is void', () {
        final state = eo(
          SenkaState.forMonth(key).copyWith(eoTrackingInitialized: true),
          DateTime.utc(end.year, end.month, end.day, 22),
        );
        expect(state.monthRecorded, 0);
      });

      final expires = [2, 5, 8, 11].contains(month.month);
      test('$key quest 14:00 ${expires ? 'is void' : 'carries forward'}', () {
        var state = quest(
          SenkaState.forMonth(key),
          854,
          DateTime.utc(end.year, end.month, end.day, 14),
        );
        if (expires) expect(state.monthRecorded, 0);
        state = tick(state, next);
        expect(state.monthRecorded, expires ? 0 : 350);
      });
    }
  });
}

CapturedApiEvent _api(
  String path,
  Map<String, Object?> data,
  DateTime jst, {
  Map<String, Object?> params = const {},
}) => CapturedApiEvent(
  path: path,
  requestParams: params,
  responseBody: jsonEncode({'api_result': 1, 'api_data': data}),
  statusCode: 200,
  source: CaptureSource.manual,
  capturedAt: jst.subtract(const Duration(hours: 9)),
);
