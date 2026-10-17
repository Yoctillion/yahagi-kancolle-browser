import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/fleet/operation_progress.dart';
import 'package:yahagi_kancolle_browser/src/performance/second_tick_scope.dart';

void main() {
  testWidgets('completed countdown catches up after mounting while inactive', (
    tester,
  ) async {
    final previousLifecycle = tester.binding.lifecycleState;
    final completion = DateTime.now().toUtc().subtract(
      const Duration(minutes: 1),
    );
    var now = completion.subtract(const Duration(seconds: 30));
    final showCountdown = ValueNotifier<bool>(false);

    try {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        MaterialApp(
          home: SecondTickScope(
            now: () => now,
            child: ValueListenableBuilder<bool>(
              valueListenable: showCountdown,
              builder: (context, show, _) => show
                  ? OperationCountdownText(
                      completionTime: completion,
                      completedText: '已归还',
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      now = completion.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 2));
      showCountdown.value = true;
      await tester.pump();
      expect(find.byType(OperationCountdownText), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('已归还'), findsOneWidget);

      now = now.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('已归还'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.handleAppLifecycleStateChanged(
        previousLifecycle ?? AppLifecycleState.resumed,
      );
      showCountdown.dispose();
    }
  });

  testWidgets('completed countdown catches up from a sub-second old scope tick', (
    tester,
  ) async {
    final previousLifecycle = tester.binding.lifecycleState;
    final completion = DateTime.now().toUtc().subtract(
      const Duration(minutes: 1),
    );
    var now = completion.subtract(const Duration(milliseconds: 500));
    final showCountdown = ValueNotifier<bool>(false);

    try {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        MaterialApp(
          home: SecondTickScope(
            now: () => now,
            child: ValueListenableBuilder<bool>(
              valueListenable: showCountdown,
              builder: (context, show, _) => show
                  ? OperationCountdownText(
                      completionTime: completion,
                      completedText: '已归还',
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      );

      // A rebuild can happen after completion but before the scope's next tick.
      now = completion.add(const Duration(milliseconds: 500));
      showCountdown.value = true;
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('已归还'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.handleAppLifecycleStateChanged(
        previousLifecycle ?? AppLifecycleState.resumed,
      );
      showCountdown.dispose();
    }
  });
}
