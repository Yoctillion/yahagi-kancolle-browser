import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_damage_alert.dart';
import 'package:yahagi_kancolle_browser/src/battle/prediction/battle_prediction_executor.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/settings/battle_status_effect_settings.dart';

void main() {
  for (final filter in DamageVibrationFilter.values) {
    for (final muted in <bool>[false, true]) {
      for (final heavyFirst in <bool>[false, true]) {
        test(
          'mixed new damage honors $filter with muted=$muted and heavyFirst=$heavyFirst',
          () async {
            final alerts = await _runAlertScenario(
              filter: filter,
              muted: muted,
              damages: heavyFirst ? <int>[80, 60] : <int>[60, 80],
            );
            final expected = switch (filter) {
              DamageVibrationFilter.off => <BattleDamageAlertSeverity>[],
              DamageVibrationFilter.moderateOnly => <BattleDamageAlertSeverity>[
                BattleDamageAlertSeverity.moderate,
              ],
              DamageVibrationFilter.heavyOnly => <BattleDamageAlertSeverity>[
                if (!muted) BattleDamageAlertSeverity.heavy,
              ],
              DamageVibrationFilter.all => <BattleDamageAlertSeverity>[
                muted
                    ? BattleDamageAlertSeverity.moderate
                    : BattleDamageAlertSeverity.heavy,
              ],
            };
            expect(alerts, expected);
          },
        );
      }
    }
  }

  for (final muted in <bool>[false, true]) {
    test('global disabled suppresses mixed alerts with muted=$muted', () async {
      expect(
        await _runAlertScenario(
          filter: DamageVibrationFilter.all,
          muted: muted,
          damages: <int>[60, 80],
          enabled: false,
        ),
        isEmpty,
      );
    });
  }

  test('muting heavy warnings preserves a lone new moderate alert', () async {
    expect(
      await _runAlertScenario(
        filter: DamageVibrationFilter.all,
        muted: true,
        damages: <int>[60],
      ),
      <BattleDamageAlertSeverity>[BattleDamageAlertSeverity.moderate],
    );
  });

  test('muting a lone heavy alert does not invent a moderate alert', () async {
    expect(
      await _runAlertScenario(
        filter: DamageVibrationFilter.all,
        muted: true,
        damages: <int>[80],
      ),
      isEmpty,
    );
  });

  test('moderate-only filter excludes a lone new heavy alert', () async {
    expect(
      await _runAlertScenario(
        filter: DamageVibrationFilter.moderateOnly,
        muted: false,
        damages: <int>[80],
      ),
      isEmpty,
    );
  });

  test('heavy-only filter excludes a lone new moderate alert', () async {
    expect(
      await _runAlertScenario(
        filter: DamageVibrationFilter.heavyOnly,
        muted: false,
        damages: <int>[60],
      ),
      isEmpty,
    );
  });
}

Future<List<BattleDamageAlertSeverity>> _runAlertScenario({
  required DamageVibrationFilter filter,
  required bool muted,
  required List<int> damages,
  bool enabled = true,
}) async {
  final state = GameState(
    hasPortData: true,
    ships: <int, OwnedShip>{
      for (var shipId = 1; shipId <= damages.length + 1; shipId++)
        shipId: OwnedShip(
          id: shipId,
          masterId: shipId,
          level: 50,
          currentHp: 100,
          maxHp: 100,
        ),
    },
    fleets: <Fleet>[
      Fleet(
        id: 1,
        name: 'First',
        shipIds: <int>[
          for (var shipId = 1; shipId <= damages.length + 1; shipId++) shipId,
        ],
      ),
    ],
  );
  final alerts = _RecordingAlertPort();
  final controller = BattleController(
    gameState: () => state,
    damageAlertPort: alerts,
    battleStatusEffectSettings: () => BattleStatusEffectSettings(
      enabled: enabled,
      damageVibrationFilter: filter,
    ),
    predictionExecutor: const ImmediateBattlePredictionExecutor(),
  );
  addTearDown(controller.dispose);
  controller.accept(
    _event('/kcsapi/api_req_map/start', <String, Object?>{
      'api_maparea_id': 1,
      'api_mapinfo_no': 1,
      'api_no': 1,
    }, 1),
  );
  await controller.idle;
  if (muted) controller.warningSession.muteCurrentSortie();
  expect(controller.warningSession.isMuted, muted);
  controller.accept(
    _event('/kcsapi/api_req_sortie/battle', <String, Object?>{
      'api_deck_id': 1,
      'api_f_nowhps': <int>[-1, ...List<int>.filled(damages.length + 1, 100)],
      'api_f_maxhps': <int>[-1, ...List<int>.filled(damages.length + 1, 100)],
      'api_e_nowhps': <int>[-1, 20],
      'api_e_maxhps': <int>[-1, 20],
      'api_ship_ke': <int>[-1, 501],
      'api_hougeki1': <String, Object?>{
        'api_at_eflag': List<int>.filled(damages.length, 1),
        'api_at_list': List<int>.filled(damages.length, 0),
        'api_df_list': <Object?>[
          for (var index = 0; index < damages.length; index++) <int>[index + 1],
        ],
        'api_damage': <Object?>[
          for (final damage in damages) <int>[damage],
        ],
      },
    }, 2),
  );
  await controller.idle;
  expect(controller.lastError, isNull);
  expect(controller.isDamageControlStateTrusted, isTrue);
  expect(controller.current!.friendMain.map((ship) => ship.currentHp), <int>[
    100,
    for (final damage in damages) 100 - damage,
  ]);
  return alerts.severities;
}

CapturedApiEvent _event(String path, Map<String, Object?> data, int sequence) =>
    CapturedApiEvent(
      path: path,
      responseBody: jsonEncode(<String, Object?>{
        'api_result': 1,
        'api_data': data,
      }),
      requestParams: path.endsWith('/start')
          ? const <String, Object?>{'api_deck_id': '1'}
          : const <String, Object?>{},
      source: CaptureSource.xhr,
      sourceOrigin: 'https://w01y.kancolle-server.com',
      capturedAt: DateTime.utc(2026, 10, 23),
      sequence: sequence,
    );

final class _RecordingAlertPort implements BattleDamageAlertPort {
  final severities = <BattleDamageAlertSeverity>[];

  @override
  Future<void> alert(BattleDamageAlertSeverity severity) async {
    severities.add(severity);
  }
}
