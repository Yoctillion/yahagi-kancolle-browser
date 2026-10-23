// Cumulative EXP observations are kept separately from already recorded days.
// This lets a delayed observation refine a cutoff without replaying old saves.
class SenkaExperienceSample {
  SenkaExperienceSample({
    required DateTime at,
    required this.experience,
    this.sortieResult = false,
    this.returnedToPort = false,
    this.sequence = 0,
    this.heldAtAnchor = 0,
  }) : at = at.toUtc();

  final DateTime at;
  final int experience;
  final bool sortieResult;
  final bool returnedToPort;
  final int sequence;
  final int heldAtAnchor;

  SenkaExperienceSample asAnchor(int held) => SenkaExperienceSample(
    at: at,
    experience: experience,
    sortieResult: sortieResult,
    returnedToPort: returnedToPort,
    sequence: sequence,
    heldAtAnchor: held,
  );

  Map<String, Object?> toJson() => {
    'at': at.toIso8601String(),
    'experience': experience,
    'sortieResult': sortieResult,
    'returnedToPort': returnedToPort,
    'sequence': sequence,
    'heldAtAnchor': heldAtAnchor,
  };
}

class SenkaContribution {
  SenkaContribution({
    required DateTime at,
    required this.monthKey,
    required this.experience,
  }) : at = at.toUtc();

  final DateTime at;
  final String monthKey;
  final double experience;

  Map<String, Object?> toJson() => {
    'at': at.toIso8601String(),
    'monthKey': monthKey,
    'experience': experience,
  };
}

class SenkaEoReceipt {
  SenkaEoReceipt({required DateTime at, required this.amount})
    : at = at.toUtc();
  final DateTime at;
  final double amount;
  Map<String, Object?> toJson() => {
    'at': at.toIso8601String(),
    'amount': amount,
  };
}
