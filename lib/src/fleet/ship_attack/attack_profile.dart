class CutinDef {
  const CutinDef(this.label, this.powerMod, this.typeFactor, this.hits);

  /// Display source string, translated by the UI through `fleetText`.
  final String label;
  final double powerMod;
  final int typeFactor;

  /// Expected hit count; destroyer cut-ins mix single and double variants,
  /// hence fractional values.
  final double hits;
}

class AttackStyleRow {
  const AttackStyleRow({
    required this.label,
    required this.rate,
    required this.powerMod,
    required this.hits,
    required this.powerPerHit,
    required this.capped,
  });

  final String label;
  final double rate;
  final double powerMod;
  final double hits;
  final int powerPerHit;
  final bool capped;

  double get totalPower => powerPerHit * hits;
}

class AttackPhaseProfile {
  const AttackPhaseProfile(this.rows);

  final List<AttackStyleRow> rows;

  double get expectedPower =>
      rows.fold<double>(0, (sum, row) => sum + row.rate * row.totalPower);
}

const normalAttackLabel = '通常攻撃';

/// Each cut-in is rolled only if all earlier ones failed; whatever
/// probability remains falls through to the normal attack.
List<(CutinDef?, double)> sequentialRates(
  Iterable<CutinDef> cutins,
  double Function(CutinDef def) individualRate,
) {
  var triggered = 0.0;
  final result = <(CutinDef?, double)>[];
  for (final def in cutins) {
    final actual = (1 - triggered) * individualRate(def).clamp(0.0, 1.0);
    triggered += actual;
    if (actual > 0) result.add((def, actual));
  }
  final normal = 1 - triggered;
  if (normal > 1e-12) result.add((null, normal));
  return result;
}
