import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/performance/frame_notification_coalescer.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_calculation.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_controller.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_state.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_store.dart';

void main() {
  group('排名结算与真实 JSON 存档往返', () {
    test('同榜反复查看和重启后继续捕获都保留累计增量', () async {
      final store = _JsonSenkaStore();
      var instant = _jst(10, 3, 5);
      var controller = _controller(store, () => instant);
      await controller.initialize();
      await _initializePlayer(controller, instant);
      await _accept(controller, _ranking(1000, at: instant));

      instant = _jst(10, 12);
      await _accept(controller, _experience(110000, at: instant));
      _expectProgress(controller, pending: 7, projected: 1007);
      for (final minute in [0, 15, 45]) {
        instant = _jst(10, 13, minute);
        await _accept(controller, _ranking(1000, at: instant));
        _expectProgress(controller, pending: 7, projected: 1007);
      }
      final persisted = jsonDecode(store.json!);
      expect(persisted, controller.state.toJson());
      expect(store.saveCount, greaterThan(0));
      controller.dispose();

      controller = _controller(store, () => instant);
      addTearDown(controller.dispose);
      await controller.initialize();
      _expectProgress(controller, pending: 7, projected: 1007);
      instant = _jst(10, 14, 10);
      await _accept(controller, _experience(111000, at: instant));
      instant = _jst(10, 14, 30);
      await _accept(controller, _ranking(1000, at: instant));

      _expectProgress(controller, pending: 7.7, projected: 1007.7);
      expect(controller.monthBaseSenka, closeTo(7.7, 1e-9));
      expect(
        controller.state.day(DateTime.utc(2026, 8, 10)).experience,
        closeTo(7.7, 1e-9),
      );
    });

    test('跨下午结算和存档重启后次日凌晨结算只消耗对应期间', () async {
      final store = _JsonSenkaStore();
      var instant = _jst(10, 3, 5);
      var controller = _controller(store, () => instant);
      await controller.initialize();
      await _initializePlayer(controller, instant);
      await _accept(controller, _ranking(1000, at: instant));

      instant = _jst(10, 13, 59);
      await _accept(controller, _experience(105000, at: instant));
      instant = _jst(10, 14, 30);
      await _accept(controller, _experience(107750, at: instant));
      instant = _jst(10, 15, 5);
      // Official scores are integers; their rounded delta cannot determine the
      // amount of local fractional gain included before the 14:00 cutoff.
      await _accept(controller, _ranking(1003, at: instant));
      _expectProgress(controller, pending: 1.925, projected: 1004.925);
      expect(controller.monthBaseSenka, closeTo(5.425, 1e-9));
      controller.dispose();

      instant = _jst(10, 16);
      controller = _controller(store, () => instant);
      addTearDown(controller.dispose);
      await controller.initialize();
      _expectProgress(controller, pending: 1.925, projected: 1004.925);
      await _accept(controller, _experience(108000, at: instant));
      instant = _jst(10, 16, 5);
      await _accept(controller, _ranking(1003, at: instant));
      _expectProgress(controller, pending: 2.1, projected: 1005.1);

      instant = _jst(11, 2, 30);
      await _accept(controller, _experience(109000, at: instant));
      _expectProgress(controller, pending: 2.8, projected: 1005.8);
      instant = _jst(11, 3, 5);
      await _accept(controller, _ranking(1005, at: instant));
      _expectProgress(controller, pending: 0.7, projected: 1005.7);
      expect(controller.monthBaseSenka, closeTo(6.3, 1e-9));
      expect(
        controller.state.day(DateTime.utc(2026, 8, 10)).experience,
        closeTo(5.6, 1e-9),
      );
      expect(
        controller.state.day(DateTime.utc(2026, 8, 11)).experience,
        closeTo(0.7, 1e-9),
      );
    });

    test('重设素战果后跨结算及重启不会复活旧经验且保留奖励', () async {
      final store = _JsonSenkaStore();
      var instant = _jst(10, 3, 5);
      var controller = _controller(store, () => instant);
      await controller.initialize();
      await _initializePlayer(controller, instant);
      await _accept(controller, _ranking(1000, at: instant));
      await _accept(controller, _mapInfo(cleared: false, at: instant));
      instant = _jst(10, 12);
      await _accept(controller, _experience(110000, at: instant));
      await _accept(controller, _mapInfo(cleared: true, at: instant));
      await _accept(
        controller,
        _apiEvent(
          '/kcsapi/api_req_quest/clearitemget',
          const {},
          at: instant,
          params: const {'api_quest_id': '284'},
        ),
      );
      expect(controller.monthBaseSenka, closeTo(7, 1e-9));
      final rewards = controller.state.day(DateTime.utc(2026, 8, 10));
      expect(rewards.eo, 75);
      expect(rewards.quest, 80);

      instant = _jst(10, 12, 30);
      expect(await controller.setBaseSenka(12.34), isTrue);
      _expectProgress(controller, pending: 0, projected: 1000);
      expect(controller.monthBaseSenka, 12.34);
      final resetDay = controller.state.day(DateTime.utc(2026, 8, 10));
      expect(resetDay.experience, 0);
      expect(resetDay.eo, 75);
      expect(resetDay.quest, 80);
      controller.dispose();

      controller = _controller(store, () => instant);
      addTearDown(controller.dispose);
      await controller.initialize();
      instant = _jst(10, 13);
      await _accept(controller, _experience(112000, at: instant));
      instant = _jst(10, 14, 30);
      await _accept(controller, _experience(113000, at: instant));
      _expectProgress(controller, pending: 2.1, projected: 1002.1);
      instant = _jst(10, 15, 5);
      await _accept(controller, _ranking(1163, at: instant));

      _expectProgress(controller, pending: 0.7, projected: 1163.7);
      expect(controller.monthBaseSenka, closeTo(14.44, 1e-9));
      final settledDay = controller.state.day(DateTime.utc(2026, 8, 10));
      expect(settledDay.experience, closeTo(2.1, 1e-9));
      expect(settledDay.eo, 75);
      expect(settledDay.quest, 80);
      expect(controller.state.completedEoIds, {15});
      expect(controller.state.completedQuestIds, {284});
      instant = _jst(10, 16);
      await _accept(controller, _ranking(1163, at: instant));
      _expectProgress(controller, pending: 0.7, projected: 1163.7);
    });

    test('缺少结算字段的旧 JSON 同周期刷新保留原有基线及小数增量', () async {
      var instant = _jst(10, 12);
      final legacy = SenkaState.forMonth('2026-08').copyWith(
        memberId: 123,
        nickname: '本人',
        latestExperience: 110000,
        days: const {'2026-08-10': SenkaDayRecord(experience: 7)},
        calculatorCurrentSenka: 1000,
        calculatorLocalSenkaAtSet: 3.5,
        dailyTargetDateKey: '2026-08-10',
        dailyProjectedSenkaAtStart: 1000,
        rankingUpdatedAt: instant,
        rankingHistory: {
          'player': [
            SenkaRankingSnapshot(
              rank: 397,
              senka: 1000,
              capturedAt: instant,
              localSenkaAtCapture: 3.5,
            ),
          ],
        },
      );
      final legacyJson = legacy.toJson()..remove('settlementPeriods');
      final history = legacyJson['rankingHistory']! as Map;
      for (final snapshots in history.values) {
        for (final snapshot in snapshots as List) {
          (snapshot as Map).remove('settlementCutoff');
        }
      }
      final store = _JsonSenkaStore(jsonEncode(legacyJson));
      final controller = _controller(store, () => instant);
      addTearDown(controller.dispose);
      await controller.initialize();
      _expectProgress(controller, pending: 3.5, projected: 1003.5);

      instant = _jst(10, 13);
      await _accept(controller, _ranking(1000, at: instant));
      _expectProgress(controller, pending: 3.5, projected: 1003.5);
      instant = _jst(10, 13, 30);
      await _accept(controller, _experience(111000, at: instant));
      await _accept(controller, _ranking(1000, at: instant));
      _expectProgress(controller, pending: 4.2, projected: 1004.2);
    });
  });
}

class _JsonSenkaStore implements SenkaStore {
  _JsonSenkaStore([this.json]);

  String? json;
  int saveCount = 0;

  @override
  Future<SenkaState?> load() async =>
      json == null ? null : SenkaState.fromJson(jsonDecode(json!));

  @override
  Future<void> save(SenkaState state) async {
    json = jsonEncode(state.toJson());
    saveCount++;
  }
}

SenkaController _controller(_JsonSenkaStore store, DateTime Function() now) =>
    SenkaController(
      store: store,
      now: now,
      captureNotifications: FrameNotificationCoalescer(scheduleFrame: (_) {}),
    );

Future<void> _initializePlayer(SenkaController controller, DateTime at) =>
    _accept(
      controller,
      _apiEvent('/kcsapi/api_get_member/basic', {
        'api_member_id': 123,
        'api_nickname': '本人',
        'api_experience': 100000,
      }, at: at),
    );

Future<void> _accept(SenkaController controller, CapturedApiEvent event) async {
  controller.accept(event);
  await controller.idle;
  expect(controller.hasPersistenceError, isFalse);
}

void _expectProgress(
  SenkaController controller, {
  required double pending,
  required double projected,
}) {
  final state = controller.state;
  expect(state.playerRankingRow.senkaDelta, closeTo(pending, 1e-9));
  expect(state.unsettledSenka, closeTo(pending, 1e-9));
  final calculation = SenkaCalculationResult.fromState(state);
  expect(calculation.unsettledSenka, closeTo(pending, 1e-9));
  expect(calculation.projected, closeTo(projected, 1e-9));
}

CapturedApiEvent _experience(int total, {required DateTime at}) => _apiEvent(
  '/kcsapi/api_get_member/basic',
  {'api_experience': total},
  at: at,
);

CapturedApiEvent _mapInfo({required bool cleared, required DateTime at}) =>
    _apiEvent('/kcsapi/api_get_member/mapinfo', {
      'api_map_info': [
        {'api_id': 15, 'api_cleared': cleared ? 1 : 0},
      ],
    }, at: at);

CapturedApiEvent _ranking(int senka, {required DateTime at}) =>
    _apiEvent('/kcsapi/api_req_ranking/mxltvkpyuklh', {
      'api_disp_page': 40,
      'api_list': [
        {
          'api_mxltvkpyuklh': 397,
          'api_mtjmdcwtvhdr': '本人',
          'api_wuhnhojjxmke': (senka + 91) * 4568 * 97,
        },
      ],
    }, at: at);

CapturedApiEvent _apiEvent(
  String path,
  Object data, {
  required DateTime at,
  Map<String, String> params = const {},
}) => CapturedApiEvent(
  path: path,
  requestParams: params,
  responseBody: jsonEncode({'api_result': 1, 'api_data': data}),
  source: CaptureSource.manual,
  capturedAt: at,
);

DateTime _jst(int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, 8, day, hour, minute).subtract(const Duration(hours: 9));
