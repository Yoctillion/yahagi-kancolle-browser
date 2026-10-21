import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_calculation.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_state.dart';

void main() {
  test(
    'finite legacy fields cannot overflow aggregates or target percentages',
    () {
      final state = SenkaState.fromJson({
        'monthKey': '2026-10',
        'experienceTrackingVersion': 1,
        'calculatorCurrentSenka': 1e308,
        'calculatorLocalSenkaAtSet': 0,
        'targetSenka': .01,
        'days': {
          '2026-10-19': {'experience': 1e308, 'eo': 1e308},
          '2026-10-20': {'experience': 1e308, 'quest': 1e308},
        },
      });
      expect(state.monthRecorded.isFinite, isTrue);
      expect(state.monthExperienceSenka.isFinite, isTrue);
      final result = SenkaCalculationResult.fromState(
        state,
        now: DateTime.utc(2026, 10, 20),
      );
      expect(result.projected.isFinite, isTrue);
      expect(result.percentage.isFinite, isTrue);
      expect(result.dailyRequired.isFinite, isTrue);
      expect(result.todayRemaining.isFinite, isTrue);
    },
  );
}
