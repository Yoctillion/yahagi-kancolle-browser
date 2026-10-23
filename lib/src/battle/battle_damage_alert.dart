import 'package:flutter/services.dart';

import '../fleet/ship_damage_level.dart';
import 'battle_models.dart';

enum BattleDamageAlertSeverity { moderate, heavy }

abstract interface class BattleDamageAlertPort {
  Future<void> alert(BattleDamageAlertSeverity severity);
}

abstract interface class CancellableBattleDamageAlertPort {
  Future<void> cancel();
}

final class MethodChannelBattleDamageAlertPort
    implements BattleDamageAlertPort, CancellableBattleDamageAlertPort {
  const MethodChannelBattleDamageAlertPort([
    this._channel = const MethodChannel(
      'app.yahagi.kancollebrowser/battle_damage_alert',
    ),
  ]);

  final MethodChannel _channel;

  @override
  Future<void> alert(BattleDamageAlertSeverity severity) =>
      _channel.invokeMethod<void>('alert', <String, Object?>{
        'severity': severity.name,
      });

  @override
  Future<void> cancel() => _channel.invokeMethod<void>('cancel');
}

BattleDamageAlertSeverity? detectFriendlyDamageAlert({
  required List<BattleShipSnapshot> before,
  required List<BattleShipSnapshot> after,
  bool includeModerate = true,
  bool includeHeavy = true,
}) {
  final beforeByKey = <(BattleFleetRole, int), BattleShipSnapshot>{
    for (final ship in before) (ship.fleetRole, ship.position): ship,
  };
  BattleDamageAlertSeverity? strongest;
  for (final ship in after) {
    if (ship.isEscaped) continue;
    final previous = beforeByKey[(ship.fleetRole, ship.position)];
    if (previous == null || ship.currentHp >= previous.currentHp) continue;
    final previousBand = shipDamageLevel(
      currentHp: previous.currentHp,
      maxHp: previous.maxHp,
    );
    final currentBand = shipDamageLevel(
      currentHp: ship.currentHp,
      maxHp: ship.maxHp,
    );
    if (currentBand.index <= previousBand.index ||
        currentBand.index < ShipDamageLevel.moderate.index) {
      continue;
    }
    final alert = currentBand == ShipDamageLevel.heavy
        ? BattleDamageAlertSeverity.heavy
        : BattleDamageAlertSeverity.moderate;
    if (alert == BattleDamageAlertSeverity.heavy) {
      if (includeHeavy) return alert;
    } else if (includeModerate) {
      strongest = alert;
    }
  }
  return strongest;
}
