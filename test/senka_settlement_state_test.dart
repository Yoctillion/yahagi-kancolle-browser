import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_state.dart';

void main() {
  test('结算周期使用 JST 二点和十四点且发榜延迟一小时', () {
    final cases = [
      (DateTime.utc(2026, 8, 9, 16, 59, 59), DateTime.utc(2026, 8, 9, 5)),
      (DateTime.utc(2026, 8, 9, 17), DateTime.utc(2026, 8, 9, 17)),
      (DateTime.utc(2026, 8, 10, 4, 59, 59), DateTime.utc(2026, 8, 9, 17)),
      (DateTime.utc(2026, 8, 10, 5), DateTime.utc(2026, 8, 10, 5)),
    ];
    for (final (instant, expected) in cases) {
      expect(senkaSettlementPeriodStart(instant), expected);
      expect(
        senkaRankingCutoff(instant.add(const Duration(hours: 1))),
        expected,
      );
    }
  });

  test('周期记录不可通过传入或暴露的 Map 原地修改', () {
    final period = DateTime.utc(2026, 8, 10, 5).toIso8601String();
    final input = {period: const SenkaDayRecord(experience: .7, eo: 75)};
    final state = SenkaState(monthKey: '2026-08', settlementPeriods: input);
    input.clear();
    expect(state.settlementPeriods[period]!.total, 75.7);
    expect(() => state.settlementPeriods.clear(), throwsUnsupportedError);
    expect(state.copyWith().settlementPeriods[period]!.total, 75.7);
  });

  test('JSON 保留分期小数和延迟榜单最后确认的截止时间', () {
    final period = DateTime.utc(2026, 8, 10, 5).toIso8601String();
    final state = SenkaState(
      monthKey: '2026-08',
      settlementPeriods: {
        period: const SenkaDayRecord(experience: .7, quest: 80),
      },
      rankingHistory: {
        'player': [
          SenkaRankingSnapshot(
            rank: 397,
            senka: 1000,
            capturedAt: DateTime.utc(2026, 8, 10, 7),
            localSenkaAtCapture: 3.85,
            settlementCutoff: DateTime.utc(2026, 8, 9, 17),
          ),
        ],
      },
    );
    final restored = SenkaState.fromJson(
      jsonDecode(jsonEncode(state.toJson())),
    );
    expect(restored.toJson(), state.toJson());
  });

  test('无效或跨月周期记录被忽略且非法计数不会进入结算', () {
    final restored = SenkaState.fromJson({
      'monthKey': '2026-08',
      'experienceTrackingVersion': currentSenkaExperienceTrackingVersion,
      'settlementPeriods': {
        'invalid': {'experience': 10},
        // The final 14:00 period can hold legitimate 22:00 carryover.
        '2026-07-31T00:00:00.000Z': {'experience': 10},
        '2026-08-10T05:01:00.000Z': {'experience': 10},
        '2026-08-10T05:00:00.000Z': {
          'experience': -10,
          'eo': 'NaN',
          'quest': 80,
        },
      },
    });
    expect(restored.settlementPeriods.length, 1);
    final record = restored.settlementPeriods.values.single;
    expect(record.experience, 0);
    expect(record.eo, 0);
    expect(record.quest, 80);
  });

  test('未来或不属于结算边界的快照截止时间回退到兼容路径', () {
    for (final invalid in [
      '2027-08-10T05:00:00.000Z',
      '2026-08-10T05:01:00.000Z',
      'invalid',
    ]) {
      final snapshot = SenkaRankingSnapshot.fromJson({
        'rank': 397,
        'senka': 1000,
        'capturedAt': '2026-08-10T07:00:00.000Z',
        'localSenkaAtCapture': 3.85,
        'settlementCutoff': invalid,
      });
      expect(snapshot.settlementCutoff, isNull, reason: invalid);
    }
  });

  test('旧经验追踪迁移同步清理分期经验但保留分期奖励', () {
    final period = DateTime.utc(2026, 8, 10, 5).toIso8601String();
    final old = SenkaState(
      monthKey: '2026-08',
      experienceTrackingVersion: 0,
      days: const {
        '2026-08-10': SenkaDayRecord(experience: 7, eo: 75, quest: 80),
      },
      settlementPeriods: {
        period: const SenkaDayRecord(experience: 7, eo: 75, quest: 80),
      },
    );
    final migrated = migrateSenkaExperienceTracking(old);
    expect(migrated.settlementPeriods[period]!.experience, 0);
    expect(migrated.settlementPeriods[period]!.eo, 75);
    expect(migrated.settlementPeriods[period]!.quest, 80);
    expect(migrated.day(DateTime.utc(2026, 8, 10)).experience, 0);
    expect(migrateSenkaExperienceTracking(migrated), same(migrated));
  });

  test('换月不携带上一月结算记录或排名截止时间', () {
    final old = SenkaState(
      monthKey: '2026-08',
      settlementPeriods: {
        DateTime.utc(2026, 8, 10, 5).toIso8601String(): const SenkaDayRecord(
          experience: 7,
        ),
      },
    );
    final next = migrateSenkaStateToMonth(old, '2026-09');
    expect(next.settlementPeriods, isEmpty);
    expect(next.rankingHistory, isEmpty);
  });
}
