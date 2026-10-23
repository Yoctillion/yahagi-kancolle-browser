import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/capture/sortie_warning_session.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_store.dart';

void main() {
  for (final original in AdvanceWarningTimingSettings.values) {
    for (final changed in AdvanceWarningTimingSettings.values) {
      test(
        'timings $original remain frozen through mute until $changed starts',
        () {
          final session = SortieWarningSession();
          addTearDown(session.dispose);
          session.startSortie();
          expect(session.timingsForSortie(original), original);
          session.ensureSortie();
          session.muteCurrentSortie();
          expect(session.timingsForSortie(changed), original);
          expect(session.timings, original);
          session.endSortie();
          expect(session.timings, isNull);
          session.ensureSortie();
          expect(session.timingsForSortie(changed), changed);
          session.startSortie();
          expect(session.timings, isNull);
          expect(session.timingsForSortie(original), original);
          expect(session.isMuted, isFalse);
        },
      );
    }
  }

  test(
    'mute applies only to an active sortie and resets on the next start',
    () {
      final session = SortieWarningSession();
      addTearDown(session.dispose);
      session.muteCurrentSortie();
      expect(session.isMuted, isFalse);
      session.startSortie();
      final generation = session.generation;
      session.muteCurrentSortie();
      session.ensureSortie();
      expect(session.isMuted, isTrue);
      expect(session.generation, generation);
      session.startSortie();
      expect(session.isMuted, isFalse);
      expect(session.generation, greaterThan(generation));
    },
  );

  test('returning to port clears mute before a mid-sortie attachment', () {
    final session = SortieWarningSession();
    addTearDown(session.dispose);
    session.startSortie();
    session.muteCurrentSortie();
    session.endSortie();
    expect(session.isActive, isFalse);
    expect(session.isMuted, isFalse);
    session.ensureSortie();
    expect(session.isActive, isTrue);
    expect(session.isMuted, isFalse);
  });
}
