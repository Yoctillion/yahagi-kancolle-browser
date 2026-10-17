import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_navigation_watchdog.dart';

void main() {
  test('deadline counts foreground time and pauses its remaining budget', () {
    fakeAsync((async) {
      final epochs = <int>[];
      final watchdog = GameNavigationWatchdog(
        timeout: const Duration(seconds: 45),
        now: () => DateTime(2026).add(async.elapsed),
        onTimeout: epochs.add,
      );
      watchdog.start(1);
      async.elapse(const Duration(seconds: 20));
      watchdog.setForeground(false);
      async.elapse(const Duration(minutes: 5));
      expect(epochs, isEmpty);
      watchdog.setForeground(true);
      async.elapse(const Duration(seconds: 24));
      expect(epochs, isEmpty);
      async.elapse(const Duration(seconds: 1));
      expect(epochs, <int>[1]);
      async.elapse(const Duration(minutes: 1));
      expect(epochs, <int>[1]);
      watchdog.dispose();
    });
  });

  test('old completion cannot cancel a newer navigation deadline', () {
    fakeAsync((async) {
      final epochs = <int>[];
      final watchdog = GameNavigationWatchdog(onTimeout: epochs.add);
      watchdog.start(1);
      watchdog.start(2, timeout: const Duration(seconds: 3));
      watchdog.complete(1);
      async.elapse(const Duration(seconds: 3));
      expect(epochs, <int>[2]);
      watchdog.dispose();
    });
  });

  test('completion cancel and dispose invalidate pending callbacks', () {
    fakeAsync((async) {
      final epochs = <int>[];
      final watchdog = GameNavigationWatchdog(onTimeout: epochs.add);
      watchdog.start(1);
      watchdog.complete(1);
      async.elapse(const Duration(minutes: 1));
      watchdog.start(2);
      watchdog.cancel();
      async.elapse(const Duration(minutes: 1));
      watchdog.start(3);
      watchdog.dispose();
      async.elapse(const Duration(minutes: 1));
      expect(epochs, isEmpty);
    });
  });
}
