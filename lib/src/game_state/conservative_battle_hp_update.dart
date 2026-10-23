import 'dart:collection';

final class ConservativeBattleHpUpdate extends UnmodifiableMapView<int, int> {
  ConservativeBattleHpUpdate(Map<int, int> hpByShipId)
    : super(Map<int, int>.unmodifiable(hpByShipId));
}
