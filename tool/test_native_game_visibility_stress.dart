// Run with dart tool/test_native_game_visibility_stress.dart.
// Uses the actual visibility coordinator; no Android or account is required.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:yahagi_kancolle_browser/src/browser/native_game_surface_visibility.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final gate = Completer<void>();
  final calls = <bool>[];
  final visibility = NativeGameSurfaceVisibility((visible) async {
    calls.add(visible);
    if (calls.length == 1) await gate.future;
  });
  final requests = <Future<void>>[visibility.setSlotAttached(true)];
  for (var index = 0; index < 20000; index++) {
    requests.add(visibility.setAppVisible(index.isOdd));
  }
  requests.add(visibility.setAppVisible(false));
  gate.complete();
  await Future.wait(requests);
  check(calls.last == false, 'burst final state must be hidden');
  check(
    calls.length <= 2,
    'obsolete lifecycle transitions replayed ${calls.length} native writes',
  );

  const seedCount = 400;
  const actionsPerSeed = 128;
  var maxCalls = calls.length;
  var failureCases = 0;
  for (var seed = 0; seed < seedCount; seed++) {
    final random = Random(0x20261021 + seed);
    final pending = Completer<void>();
    final nativeCalls = <bool>[];
    var actualVisible = false;
    final coordinator = NativeGameSurfaceVisibility((visible) async {
      nativeCalls.add(visible);
      if (nativeCalls.length == 1) {
        await pending.future;
        if (seed % 14 == 0) throw StateError('failure before effect');
        actualVisible = visible;
        if (seed % 7 == 0) throw StateError('failure after effect');
      }
      actualVisible = visible;
    });
    var route = true, app = true, workspace = true, attached = true;
    final waiting = <Future<void>>[];
    void track(Future<void> request) {
      waiting.add(
        request.catchError((Object _) {
          failureCases++;
        }),
      );
    }

    track(coordinator.setSlotAttached(true));
    for (var step = 0; step < actionsPerSeed; step++) {
      final value = random.nextBool();
      switch (random.nextInt(4)) {
        case 0:
          route = value;
          track(coordinator.setRouteVisible(value));
        case 1:
          app = value;
          track(coordinator.setAppVisible(value));
        case 2:
          workspace = value;
          track(coordinator.setWorkspaceVisible(value));
        case 3:
          attached = value;
          track(coordinator.setSlotAttached(value));
      }
    }
    pending.complete();
    await Future.wait(waiting);
    final expected = route && app && workspace && attached;
    // A failed current write may be retried explicitly by the existing API.
    if (actualVisible != expected) {
      await coordinator.setSlotAttached(attached);
    }
    check(
      actualVisible == expected,
      'seed=$seed latest visibility differs from independent model',
    );
    check(
      nativeCalls.length <= 3,
      'seed=$seed obsolete states replayed ${nativeCalls.length} times',
    );
    final beforeDispose = nativeCalls.length;
    await coordinator.dispose();
    check(actualVisible == false, 'seed=$seed dispose must hide');
    check(
      nativeCalls.length <= beforeDispose + 1,
      'seed=$seed dispose must need at most one write',
    );
    maxCalls = max(maxCalls, nativeCalls.length);
  }
  stdout.writeln(
    jsonEncode({
      'burstTransitions': 20001,
      'burstNativeWrites': calls.length,
      'seedStart': 0x20261021,
      'seeds': seedCount,
      'actionsPerSeed': actionsPerSeed,
      'randomTransitions': seedCount * actionsPerSeed,
      'maxNativeWritesIncludingDispose': maxCalls,
      'observedInjectedFailures': failureCases,
      'result': 'passed',
    }),
  );
}
