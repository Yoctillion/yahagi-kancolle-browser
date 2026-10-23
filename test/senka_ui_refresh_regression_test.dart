import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_calculation.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_calendar_view.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_controller.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_page.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_state.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_store.dart';

void main() {
  testWidgets('JST evening leaves tomorrow unrecorded in the calendar', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        SenkaCalendarView(
          state: SenkaState.forMonth('2026-08'),
          now: _jst(2026, 8, 10, 23),
          compact: false,
        ),
      ),
    );
    final tomorrow = find.byKey(const Key('calendar-cell-11'));
    expect(
      find.descendant(of: tomorrow, matching: find.text('-')),
      findsOneWidget,
    );
  });

  testWidgets('opening a stale page refreshes outside its ancestor build', (
    tester,
  ) async {
    var now = _jst(2026, 8, 31, 21);
    final controller = SenkaController(store: _MemoryStore(), now: () => now);
    addTearDown(controller.dispose);
    await controller.initialize();
    now = _jst(2026, 9, 1, 3);
    await tester.pumpWidget(
      _app(
        AnimatedBuilder(
          animation: controller,
          builder: (context, _) =>
              SenkaPage(controller: controller, mode: SenkaCenterMode.calendar),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(controller.state.monthKey, '2026-09');
    expect(find.text('2026年9月战果日历'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('replacing the controller immediately refreshes the new owner', (
    tester,
  ) async {
    var now = _jst(2026, 8, 31, 21);
    final first = SenkaController(store: _MemoryStore(), now: () => now);
    final second = SenkaController(store: _MemoryStore(), now: () => now);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await first.initialize();
    await second.initialize();
    await tester.pumpWidget(_app(SenkaPage(controller: first)));
    await tester.pump();
    now = _jst(2026, 9, 1, 3);
    await tester.pumpWidget(_app(SenkaPage(controller: second)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(second.state.monthKey, '2026-09');
    expect(first.state.monthKey, '2026-08');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('returning to the foreground refreshes the month immediately', (
    tester,
  ) async {
    var now = _jst(2026, 8, 31, 21);
    final controller = SenkaController(store: _MemoryStore(), now: () => now);
    addTearDown(controller.dispose);
    await controller.initialize();
    await tester.pumpWidget(_app(SenkaPage(controller: controller)));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = _jst(2026, 9, 1, 3);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(controller.state.monthKey, '2026-09');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'refreshes cover publication, settlement, task and midnight boundaries',
    () {
      for (final year in [2027, 2028]) {
        for (var month = 1; month <= 12; month++) {
          final lastDay = DateTime.utc(year, month + 1, 0).day;
          for (final day in [1, lastDay]) {
            for (final hour in [0, 2, 3, 5, 14, 15, if (day == lastDay) 22]) {
              final boundary = _jst(year, month, day, hour);
              expect(
                senkaNextRefreshInstant(
                  boundary.subtract(const Duration(microseconds: 1)),
                ),
                boundary,
                reason: '$year-$month-$day $hour:00 JST',
              );
              expect(
                senkaNextRefreshInstant(boundary).isAfter(boundary),
                isTrue,
              );
            }
          }
        }
      }
    },
  );

  test('an archived month never uses the next month available days', () {
    final state = SenkaState.forMonth('2026-08').copyWith(
      targetSenka: 310,
      dailyTargetDateKey: '2026-08-31',
      dailyProjectedSenkaAtStart: 100,
      days: const {'2026-08-31': SenkaDayRecord(experience: 5)},
    );
    final result = SenkaCalculationResult.fromState(
      state,
      now: _jst(2026, 9, 1, 3),
    );
    expect(result.remainingDays, 0);
    expect(result.dailyRequired, 0);
    expect(result.todayRemaining, 0);
    expect(ensureSenkaDailyTarget(state, _jst(2026, 9, 1, 3)), same(state));
  });

  test('late events cannot move a captured daily target back to yesterday', () {
    final state = SenkaState.forMonth('2026-08').copyWith(
      dailyTargetDateKey: '2026-08-11',
      dailyProjectedSenkaAtStart: 100,
    );
    expect(ensureSenkaDailyTarget(state, _jst(2026, 8, 11, 1)), same(state));
    final rebased = rebaseSenkaDailyTarget(
      state,
      state.copyWith(questStatuses: const {284: SenkaRewardStatus.planned}),
      _jst(2026, 8, 11, 1),
    );
    expect(rebased.dailyTargetDateKey, '2026-08-11');
    expect(rebased.dailyProjectedSenkaAtStart, 180);
  });

  test(
    'the new operation keeps day one progress from month end through 02 JST',
    () {
      final state = SenkaState.forMonth('2026-11').copyWith(
        targetSenka: 300,
        dailyTargetDateKey: '2026-11-01',
        days: const {'2026-11-01': SenkaDayRecord(experience: 7)},
      );
      for (final instant in [
        _jst(2026, 10, 31, 22),
        _jst(2026, 10, 31, 23),
        _jst(2026, 11, 1, 0),
        _jst(2026, 11, 1, 1),
        _jst(2026, 11, 1, 2),
      ]) {
        final result = SenkaCalculationResult.fromState(state, now: instant);
        expect(result.remainingDays, 30, reason: '$instant');
        expect(result.dailyRequired, 10, reason: '$instant');
        expect(result.todayRemaining, 3, reason: '$instant');
        final captured = ensureSenkaDailyTarget(state, instant);
        expect(captured.dailyTargetDateKey, '2026-11-01');
      }
    },
  );
}

DateTime _jst(int year, int month, int day, int hour) =>
    DateTime.utc(year, month, day, hour).subtract(const Duration(hours: 9));

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

class _MemoryStore implements SenkaStore {
  @override
  Future<SenkaState?> load() async => null;
  @override
  Future<void> save(SenkaState state) async {}
}
