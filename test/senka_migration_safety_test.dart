import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/performance/frame_notification_coalescer.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_calculation.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_controller.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_reducer.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_state.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_store.dart';

// Source rules checked 2026-10-20:
// https://wikiwiki.jp/kancolle/称号・戦果
// https://github.com/kcwiki/kancolle-main/blob/master/dist/main.js
// DutyEndModel passes api_bounus[type=18].api_count unchanged to
// RewardModelWarResult; this is a point amount, not an item multiplier.
// NextCellModel.getEOSupplyWarResult reads api_get_eo_rate for 1-6.
// Keep these tests on public reducer/controller/JSON APIs so schema additions
// can change without weakening the requirement to preserve recorded data.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const reducer = SenkaReducer();

  group('version 1 archive migration preserves recorded data', () {
    test(
      'initialization preserves daily records, ranking, goals and rewards',
      () async {
        final store = _JsonStore(jsonEncode(_legacyArchive()));
        var instant = _at(10, 20, 12);
        var controller = _controller(store, () => instant);
        await controller.initialize();
        _expectLegacyRecords(controller.state);
        expect(controller.state.unsettledSenka, closeTo(3.5, 1e-9));
        expect(senkaProjected(controller.state), closeTo(1003.5, 1e-9));

        // A repeated cumulative snapshot must not replay historical income.
        instant = _at(10, 20, 12, 1);
        await _accept(controller, _port(110000, instant));
        _expectLegacyRecords(controller.state);
        controller.dispose();

        controller = _controller(store, () => instant);
        addTearDown(controller.dispose);
        await controller.initialize();
        _expectLegacyRecords(controller.state);
        expect(controller.state.unsettledSenka, closeTo(3.5, 1e-9));
      },
    );

    test('absent observation metadata uses old EXP as an anchor', () {
      var state = SenkaState.fromJson(_legacyArchive());
      state = reducer.reduce(state, _port(110000, _at(10, 20, 12, 1)));
      expect(state.monthExperienceSenka, closeTo(77, 1e-9));
      state = reducer.reduce(_roundTrip(state), _port(111000, _at(10, 20, 13)));
      expect(state.day(DateTime.utc(2026, 10, 19)).experience, 70);
      expect(
        state.day(DateTime.utc(2026, 10, 20)).experience,
        closeTo(7.7, 1e-9),
      );
      expect(state.monthExperienceSenka, closeTo(77.7, 1e-9));
      expect(state.latestExperience, 111000);
      expect(state.playerRankingRow.senka, 1000);
    });

    test(
      'missing settlement fields retain old fractional ranking baseline',
      () {
        final old = _legacyArchive()..remove('settlementPeriods');
        final histories = old['rankingHistory']! as Map;
        for (final history in histories.values) {
          for (final snapshot in history as List) {
            (snapshot as Map).remove('settlementCutoff');
          }
        }
        var state = SenkaState.fromJson(old);
        state = reducer.reduce(state, _ranking(1000, _at(10, 20, 13)));
        expect(state.monthExperienceSenka, 77);
        expect(state.unsettledSenka, closeTo(3.5, 1e-9));
        state = reducer.reduce(
          _roundTrip(state),
          _port(111000, _at(10, 20, 13, 30)),
        );
        state = reducer.reduce(state, _ranking(1000, _at(10, 20, 13, 31)));
        expect(state.unsettledSenka, closeTo(4.2, 1e-9));
        expect(senkaProjected(state), closeTo(1004.2, 1e-9));
      },
    );

    test('out of order observations redistribute only new income', () {
      final old = _legacyArchive()
        ..['latestExperience'] = 100000
        ..['days'] = {
          '2026-10-19': {'experience': 70, 'eo': 75, 'quest': 80},
        }
        ..['settlementPeriods'] = {
          _at(10, 19, 2).toIso8601String(): {
            'experience': 70,
            'eo': 75,
            'quest': 80,
          },
        }
        ..['calculatorLocalSenkaAtSet'] = 225
        ..['rankingUpdatedAt'] = _at(10, 20, 3, 5).toIso8601String()
        ..['rankingHistory'] = {
          'player': [
            {
              'rank': 397,
              'senka': 1000,
              'capturedAt': _at(10, 20, 3, 5).toIso8601String(),
              'localSenkaAtCapture': 225,
              'settlementCutoff': _at(10, 20, 2).toIso8601String(),
            },
          ],
        };
      var state = SenkaState.fromJson(old);
      state = reducer.reduce(state, _basic(120000, _at(10, 20, 16)));
      state = reducer.reduce(
        _roundTrip(state),
        _basic(110000, _at(10, 20, 13)),
      );
      state = reducer.reduce(
        _roundTrip(state),
        _ranking(1007, _at(10, 20, 17)),
      );

      expect(state.day(DateTime.utc(2026, 10, 19)).experience, 70);
      expect(state.day(DateTime.utc(2026, 10, 19)).eo, 75);
      expect(state.day(DateTime.utc(2026, 10, 19)).quest, 80);
      expect(
        state.day(DateTime.utc(2026, 10, 20)).experience,
        closeTo(14, 1e-9),
      );
      expect(state.monthExperienceSenka, closeTo(84, 1e-9));
      expect(state.unsettledSenka, closeTo(7, 1e-9));
      expect(senkaProjected(state), closeTo(1014, 1e-9));
    });

    test(
      'cycle migration seals old archive receipts before clearing IDs',
      () async {
        final old = _legacyArchive()
          ..['monthKey'] = '2026-06'
          ..['annualQuestCycleKey'] = '2025-06'
          ..['quarterlyQuestCycleKey'] = '2026-03'
          ..['recordedQuestIds'] = [947]
          ..['questStatuses'] = {'947': 'completed'}
          ..['rankingHistory'] = <String, Object?>{}
          ..['calculatorCurrentSenka'] = 0
          ..['calculatorLocalSenkaAtSet'] = 0
          ..['days'] = {
            '2026-06-01': {'quest': 480},
          }
          ..['settlementPeriods'] = <String, Object?>{};
        final store = _JsonStore(jsonEncode(old));
        final controller = _controller(store, () => _at(6, 1, 5));
        addTearDown(controller.dispose);
        await controller.initialize();
        await _accept(controller, _quest(947, 480, _at(6, 1, 4, 59)));
        expect(_questTotal(controller.state), 480);
        await _accept(controller, _quest(947, 480, _at(6, 1, 5, 1)));
        expect(_questTotal(controller.state), 960);
      },
    );
  });

  group('source cutoffs survive serialization and restart', () {
    test(
      'month end quest and ordinary EXP retain independent month routes',
      () {
        var state = _state('2026-10');
        state = reducer.reduce(state, _quest(854, 350, _at(10, 31, 14)));
        state = _roundTrip(state);
        state = reducer.reduce(state, _port(101000, _at(10, 31, 22)));
        state = _roundTrip(state);
        state = reducer.reduce(state, _port(102000, _at(11, 1, 3, 1)));
        expect(state.monthKey, '2026-11');
        expect(state.monthExperienceSenka, closeTo(1.4, 1e-9));
        expect(_questTotal(state), 350);
        expect(state.monthRecorded, closeTo(351.4, 1e-9));
        state = reducer.reduce(_roundTrip(state), _port(102000, _at(11, 1, 4)));
        expect(state.monthRecorded, closeTo(351.4, 1e-9));
      },
    );

    test(
      'controller restart carries next month reward across calendar rollover',
      () async {
        var instant = _at(10, 31, 13);
        final store = _JsonStore(jsonEncode(_state('2026-10').toJson()));
        var controller = _controller(store, () => instant);
        await controller.initialize();
        instant = _at(10, 31, 14);
        await _accept(controller, _quest(854, 350, instant));
        controller.dispose();

        instant = _at(11, 1, 3, 5);
        controller = _controller(store, () => instant);
        addTearDown(controller.dispose);
        await controller.initialize();
        expect(controller.state.monthKey, '2026-11');
        expect(_questTotal(controller.state), 350);
        await _accept(controller, _port(100000, instant));
        expect(_questTotal(controller.state), 350);
      },
    );

    test('in flight restart preserves month end return attribution', () {
      var state = _state('2026-10');
      state = reducer.reduce(state, _start(1, 1, _at(10, 31, 21, 58)));
      state = reducer.reduce(state, _result(101000, _at(10, 31, 21, 59)));
      expect(state.monthExperienceSenka, 0);
      state = _roundTrip(state);
      state = reducer.reduce(state, _port(101000, _at(10, 31, 22, 1)));
      expect(state.monthKey, '2026-11');
      expect(state.monthExperienceSenka, closeTo(.7, 1e-9));
      state = reducer.reduce(_roundTrip(state), _port(101000, _at(11, 1, 3)));
      expect(state.monthExperienceSenka, closeTo(.7, 1e-9));
    });

    test('midnight EO result retains its month across later restart', () {
      var state = _state('2026-10').copyWith(eoTrackingInitialized: true);
      state = reducer.reduce(state, _start(1, 5, _at(11, 1, 0, 20)));
      state = reducer.reduce(state, _result(100000, _at(11, 1, 0, 30), eo: 75));
      state = reducer.reduce(
        _roundTrip(state),
        _mapInfo(true, _at(11, 1, 0, 31)),
      );
      state = reducer.reduce(
        _roundTrip(state),
        _port(100000, _at(11, 1, 3, 5)),
      );
      expect(state.monthKey, '2026-11');
      expect(_eoTotal(state), 75);
      expect(state.monthExperienceSenka, 0);
    });

    test(
      'ordinary repeated results and return snapshots count exactly once',
      () {
        var state = _state('2026-10');
        state = reducer.reduce(state, _start(1, 1, _at(10, 20, 13, 55)));
        final result = _result(101000, _at(10, 20, 13, 59));
        state = reducer.reduce(state, result);
        state = reducer.reduce(_roundTrip(state), result);
        expect(state.monthExperienceSenka, 0);
        state = reducer.reduce(state, _port(101000, _at(10, 20, 14, 1)));
        state = reducer.reduce(
          _roundTrip(state),
          _basic(101000, _at(10, 20, 14, 2)),
        );
        state = reducer.reduce(state, _port(101000, _at(10, 20, 14, 3)));
        expect(state.monthExperienceSenka, closeTo(.7, 1e-9));
        expect(
          state.day(DateTime.utc(2026, 10, 20)).experience,
          closeTo(.7, 1e-9),
        );
      },
    );
  });

  group('actual reward response contracts', () {
    test('explicit zero reward count does not trigger catalog fallback', () {
      final state = reducer.reduce(
        _state('2026-10'),
        _event(
          '/kcsapi/api_req_quest/clearitemget',
          {'api_bounus_count': 0},
          _at(10, 20, 12),
          params: const {'api_quest_id': '854'},
        ),
      );
      expect(_questTotal(state), 0);
      expect(state.completedQuestIds, contains(854));
    });

    test('949 aircraft choice is completed without an 800 point gain', () {
      final state = reducer.reduce(
        _state('2026-10'),
        _event(
          '/kcsapi/api_req_quest/clearitemget',
          {
            'api_bounus': [
              {
                'api_type': 12,
                'api_count': 1,
                'api_item': {'api_id': 422, 'api_name': 'FR-1 Fireball'},
              },
            ],
          },
          _at(10, 20, 12),
          params: const {'api_quest_id': '949'},
        ),
      );
      expect(_questTotal(state), 0);
      expect(state.completedQuestIds, contains(949));
    });

    test(
      'type 18 api_count is the actual amount without an item multiplier',
      () {
        final state = reducer.reduce(
          _state('2026-10'),
          _event(
            '/kcsapi/api_req_quest/clearitemget',
            {
              'api_bounus': [
                {
                  'api_type': 18,
                  'api_count': 17,
                  'api_item': {'api_id': 901},
                },
              ],
            },
            _at(10, 20, 12),
            params: const {'api_quest_id': '854'},
          ),
        );
        expect(_questTotal(state), 17);
      },
    );

    test('949 actual point selection is counted from response', () {
      final state = reducer.reduce(
        _state('2026-10'),
        _quest(949, 800, _at(10, 20, 12)),
      );
      expect(_questTotal(state), 800);
      expect(state.completedQuestIds, contains(949));
    });

    test('non catalog tasks can carry actual type 18 rewards', () {
      final state = reducer.reduce(
        _state('2026-10'),
        _quest(999999, 12, _at(10, 20, 12)),
      );
      expect(_questTotal(state), 12);
    });

    test(
      'non catalog actual reward replay survives restart without duplication',
      () {
        final receipt = _quest(999999, 12, _at(10, 20, 12));
        var state = reducer.reduce(_state('2026-10'), receipt);
        state = reducer.reduce(_roundTrip(state), receipt);
        expect(_questTotal(state), 12);
        // A later occurrence of an unknown repeatable task must remain possible.
        state = reducer.reduce(
          _roundTrip(state),
          _quest(999999, 12, _at(10, 21, 12)),
        );
        expect(_questTotal(state), 24);
      },
    );

    test(
      'annual claims before and after 05:00 reset use separate receipts',
      () {
        var state = reducer.reduce(
          _state('2026-05'),
          _quest(947, 480, _at(5, 31, 14)),
        );
        state = reducer.reduce(
          _roundTrip(state),
          _quest(947, 480, _at(6, 1, 4, 59)),
        );
        state = reducer.reduce(
          _roundTrip(state),
          _quest(947, 480, _at(6, 1, 5)),
        );
        expect(state.monthKey, '2026-06');
        expect(_questTotal(state), 960);
      },
    );

    test(
      'EO without sortie context preserves actual timestamp across restart',
      () {
        var state = _state('2026-10').copyWith(eoTrackingInitialized: true);
        state = reducer.reduce(state, _mapInfo(false, _at(10, 20, 3)));
        state = reducer.reduce(state, _ranking(1000, _at(10, 20, 3, 5)));
        state = reducer.reduce(
          state,
          _result(100000, _at(10, 20, 13, 59), eo: 75),
        );
        state = reducer.reduce(
          _roundTrip(state),
          _mapInfo(true, _at(10, 20, 14, 1)),
        );
        expect(_eoTotal(state), 75);
        state = reducer.reduce(
          _roundTrip(state),
          _ranking(1075, _at(10, 20, 15, 5)),
        );
        expect(state.unsettledSenka, 0);
        expect(senkaProjected(state), 1075);
      },
    );

    test(
      'old pending EO cannot make an unchanged post-midnight map earn twice',
      () {
        var state = _state('2026-10').copyWith(eoTrackingInitialized: true);
        state = reducer.reduce(state, _mapInfo(false, _at(10, 31, 21, 55)));
        state = reducer.reduce(
          state,
          _result(100000, _at(10, 31, 21, 59), eo: 75),
        );
        state = reducer.reduce(
          _roundTrip(state),
          _mapInfo(true, _at(11, 1, 0, 1)),
        );
        state = reducer.reduce(
          _roundTrip(state),
          _mapInfo(true, _at(11, 1, 0, 2)),
        );
        expect(state.monthKey, '2026-11');
        expect(_eoTotal(state), 0);
        // Reloading the game resets the gauge; an actual new-month clear remains
        // eligible even though the earlier snapshot still showed the old clear.
        state = reducer.reduce(state, _mapInfo(false, _at(11, 1, 0, 3)));
        state = reducer.reduce(state, _start(1, 5, _at(11, 1, 0, 4)));
        state = reducer.reduce(
          state,
          _result(100000, _at(11, 1, 0, 10), eo: 75),
        );
        state = reducer.reduce(
          _roundTrip(state),
          _mapInfo(true, _at(11, 1, 0, 11)),
        );
        expect(_eoTotal(state), 75);
      },
    );

    test(
      'known old EO clear requires reset evidence before a new snapshot gain',
      () {
        var state = reducer.reduce(
          _state('2026-10'),
          _mapInfo(true, _at(10, 20, 12)),
        );
        expect(_eoTotal(state), 75);
        state = reducer.reduce(
          _roundTrip(state),
          _mapInfo(true, _at(11, 1, 0, 1)),
        );
        state = reducer.reduce(
          _roundTrip(state),
          _mapInfo(true, _at(11, 1, 0, 2)),
        );
        expect(state.monthKey, '2026-11');
        expect(_eoTotal(state), 0);
        state = reducer.reduce(state, _mapInfo(false, _at(11, 1, 0, 3)));
        state = reducer.reduce(
          _roundTrip(state),
          _mapInfo(true, _at(11, 1, 0, 10)),
        );
        expect(_eoTotal(state), 75);
      },
    );

    test(
      'actual new EO receipt overrides old gauge ambiguity without false snapshot',
      () {
        var state = reducer.reduce(
          _state('2026-10'),
          _mapInfo(true, _at(10, 20, 12)),
        );
        state = reducer.reduce(
          _roundTrip(state),
          _mapInfo(true, _at(11, 1, 0, 1)),
        );
        state = reducer.reduce(state, _start(1, 5, _at(11, 1, 0, 4)));
        state = reducer.reduce(
          state,
          _result(100000, _at(11, 1, 0, 10), eo: 75),
        );
        state = reducer.reduce(
          _roundTrip(state),
          _mapInfo(true, _at(11, 1, 0, 11)),
        );
        expect(_eoTotal(state), 75);
      },
    );

    test(
      'fresh initial EO snapshot without old clear evidence remains unattributed',
      () {
        final state = reducer.reduce(
          _state('2026-11'),
          _mapInfo(true, _at(11, 1, 0, 1)),
        );
        expect(_eoTotal(state), 75);
        expect(state.unattributedEoSenka, 75);
      },
    );

    test(
      'actual EO amount overrides catalog and old false snapshots do not repeat it',
      () {
        var state = _state('2026-10').copyWith(eoTrackingInitialized: true);
        state = reducer.reduce(state, _start(1, 5, _at(10, 20, 12)));
        final receipt = _result(100000, _at(10, 20, 12, 5), eo: 77);
        state = reducer.reduce(state, receipt);
        state = reducer.reduce(_roundTrip(state), receipt);
        state = reducer.reduce(state, _mapInfo(false, _at(10, 20, 12, 6)));
        state = reducer.reduce(
          _roundTrip(state),
          _mapInfo(true, _at(10, 20, 12, 7)),
        );
        expect(_eoTotal(state), 77);
      },
    );

    test(
      'pending EO with a changed amount does not fall back to catalog value',
      () {
        var state = _state('2026-10').copyWith(eoTrackingInitialized: true);
        state = reducer.reduce(state, _mapInfo(false, _at(10, 20, 12)));
        state = reducer.reduce(
          state,
          _result(100000, _at(10, 20, 12, 5), eo: 77),
        );
        state = reducer.reduce(
          _roundTrip(state),
          _mapInfo(true, _at(10, 20, 12, 6)),
        );
        expect(_eoTotal(state), 77);
      },
    );

    test(
      '1-6 EO uses the actual next response and map sync does not repeat it',
      () {
        var state = _state('2026-10').copyWith(eoTrackingInitialized: true);
        state = reducer.reduce(state, _start(1, 6, _at(10, 20, 12)));
        state = reducer.reduce(
          state,
          _event('/kcsapi/api_req_map/next', {
            'api_maparea_id': 1,
            'api_mapinfo_no': 6,
            'api_no': 8,
            'api_event_id': 9,
            'api_next': 0,
            'api_get_eo_rate': 75,
          }, _at(10, 20, 12, 5)),
        );
        state = reducer.reduce(
          _roundTrip(state),
          _event('/kcsapi/api_get_member/mapinfo', {
            'api_map_info': [
              {'api_id': 16, 'api_cleared': 1},
            ],
          }, _at(10, 20, 12, 6)),
        );
        expect(_eoTotal(state), 75);
      },
    );
  });
}

Map<String, Object?> _legacyArchive() => {
  'monthKey': '2026-10',
  'experienceTrackingVersion': 1,
  'memberId': 123,
  'nickname': 'migration-player',
  'latestExperience': 110000,
  'days': {
    '2026-10-19': {'experience': 70, 'eo': 75, 'quest': 80},
    '2026-10-20': {'experience': 7, 'eo': 0, 'quest': 0},
  },
  'settlementPeriods': {
    _at(10, 19, 2).toIso8601String(): {'experience': 70, 'eo': 75, 'quest': 80},
    _at(10, 20, 2).toIso8601String(): {'experience': 7, 'eo': 0, 'quest': 0},
  },
  'targetSenka': 3200,
  'calculatorCurrentSenka': 1000,
  'calculatorLocalSenkaAtSet': 228.5,
  'eoStatuses': {'15': 'completed'},
  'questStatuses': {'949': 'completed'},
  'recordedQuestIds': [949],
  'rankingHistory': {
    'player': [
      {
        'rank': 397,
        'senka': 1000,
        'capturedAt': _at(10, 20, 12).toIso8601String(),
        'localSenkaAtCapture': 228.5,
        'settlementCutoff': _at(10, 20, 2).toIso8601String(),
      },
    ],
  },
  'rankingUpdatedAt': _at(10, 20, 12).toIso8601String(),
};

void _expectLegacyRecords(SenkaState state) {
  expect(state.monthExperienceSenka, 77);
  expect(state.day(DateTime.utc(2026, 10, 19)).experience, 70);
  expect(state.day(DateTime.utc(2026, 10, 19)).eo, 75);
  expect(state.day(DateTime.utc(2026, 10, 19)).quest, 80);
  expect(state.day(DateTime.utc(2026, 10, 20)).experience, 7);
  expect(state.playerRankingRow.rank, 397);
  expect(state.playerRankingRow.senka, 1000);
  expect(state.targetSenka, 3200);
  expect(state.completedQuestIds, contains(949));
  expect(state.recordedQuestIds, contains(949));
}

class _JsonStore implements SenkaStore {
  _JsonStore(this.json);
  String json;

  @override
  Future<SenkaState?> load() async => SenkaState.fromJson(jsonDecode(json));

  @override
  Future<void> save(SenkaState state) async {
    json = jsonEncode(state.toJson());
  }
}

SenkaController _controller(_JsonStore store, DateTime Function() now) =>
    SenkaController(
      store: store,
      now: now,
      captureNotifications: FrameNotificationCoalescer(scheduleFrame: (_) {}),
    );

Future<void> _accept(SenkaController controller, CapturedApiEvent event) async {
  controller.accept(event);
  await controller.idle;
  expect(controller.hasPersistenceError, isFalse);
}

SenkaState _state(String month) => SenkaState.forMonth(month).copyWith(
  memberId: 123,
  nickname: 'migration-player',
  latestExperience: 100000,
);

SenkaState _roundTrip(SenkaState state) =>
    SenkaState.fromJson(jsonDecode(jsonEncode(state.toJson())));

double _questTotal(SenkaState state) =>
    state.days.values.fold(0.0, (sum, day) => sum + day.quest);
double _eoTotal(SenkaState state) =>
    state.unattributedEoSenka +
    state.days.values.fold(0.0, (sum, day) => sum + day.eo);

CapturedApiEvent _basic(int total, DateTime at) =>
    _event('/kcsapi/api_get_member/basic', {'api_experience': total}, at);
CapturedApiEvent _port(int total, DateTime at) =>
    _event('/kcsapi/api_port/port', {
      'api_basic': {
        'api_member_id': 123,
        'api_nickname': 'migration-player',
        'api_experience': total,
      },
    }, at);
CapturedApiEvent _start(int area, int map, DateTime at) => _event(
  '/kcsapi/api_req_map/start',
  {'api_maparea_id': area, 'api_mapinfo_no': map, 'api_no': 1, 'api_next': 1},
  at,
  params: {'api_maparea_id': '$area', 'api_mapinfo_no': '$map'},
);
CapturedApiEvent _result(int total, DateTime at, {int eo = 0}) => _event(
  '/kcsapi/api_req_sortie/battleresult',
  {'api_member_exp': total, 'api_win_rank': 'S', 'api_get_exmap_rate': eo},
  at,
);
CapturedApiEvent _mapInfo(bool cleared, DateTime at) =>
    _event('/kcsapi/api_get_member/mapinfo', {
      'api_map_info': [
        {'api_id': 15, 'api_cleared': cleared ? 1 : 0},
      ],
    }, at);
CapturedApiEvent _quest(int id, int amount, DateTime at) => _event(
  '/kcsapi/api_req_quest/clearitemget',
  {
    'api_bounus': [
      {'api_type': 18, 'api_count': amount, 'api_item': null},
    ],
  },
  at,
  params: {'api_quest_id': '$id'},
);
CapturedApiEvent _ranking(int senka, DateTime at) =>
    _event('/kcsapi/api_req_ranking/mxltvkpyuklh', {
      'api_disp_page': 40,
      'api_list': [
        {
          'api_mxltvkpyuklh': 397,
          'api_mtjmdcwtvhdr': 'migration-player',
          'api_wuhnhojjxmke': (senka + 91) * 4568 * 97,
        },
      ],
    }, at);

CapturedApiEvent _event(
  String path,
  Object data,
  DateTime at, {
  Map<String, String> params = const {},
}) => CapturedApiEvent(
  path: path,
  requestParams: params,
  responseBody: jsonEncode({'api_result': 1, 'api_data': data}),
  source: CaptureSource.manual,
  capturedAt: at,
);

DateTime _at(int month, int day, int hour, [int minute = 0]) => DateTime.utc(
  2026,
  month,
  day,
  hour,
  minute,
).subtract(const Duration(hours: 9));
