import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_frame_rate_policy.dart';
import 'package:yahagi_kancolle_browser/src/settings/game_frame_rate_settings.dart';

void main() {
  group('game frame-rate sampling page', () {
    test('accepts the DMM game shell and Kancolle server pages', () {
      expect(
        isGameFrameRateSamplingPage(
          'https://www.dmm.com/netgame/social/-/gadgets/=/app_id=854854/',
        ),
        isTrue,
      );
      expect(
        isGameFrameRateSamplingPage(
          'https://w01y.kancolle-server.com/kcs2/index.php',
        ),
        isTrue,
      );
    });

    test('rejects login, generic DMM and malformed pages', () {
      expect(
        isGameFrameRateSamplingPage('https://accounts.dmm.com/login'),
        isFalse,
      );
      expect(isGameFrameRateSamplingPage('https://www.dmm.com/'), isFalse);
      expect(isGameFrameRateSamplingPage('not a url'), isFalse);
    });
  });

  test('downgrades only after two consecutive unstable CreateJS windows', () {
    final policy = GameFrameRatePolicy(mode: GameFrameRateMode.automatic);

    _addUnstableCreateJsWindow(policy);
    expect(policy.completeWindow(), FrameRateDecision.keep60);
    _addUnstableCreateJsWindow(policy);
    expect(policy.completeWindow(), FrameRateDecision.downgradeTo30);
    expect(policy.completeWindow(), FrameRateDecision.lock30);
  });

  test('a stable window resets the consecutive unstable count', () {
    final policy = GameFrameRatePolicy(mode: GameFrameRateMode.automatic);
    _addUnstableCreateJsWindow(policy);
    expect(policy.completeWindow(), FrameRateDecision.keep60);

    for (final fps in <double>[58, 59, 60, 58, 60]) {
      policy.addCreateJsSample(fps);
    }
    expect(policy.completeWindow(), FrameRateDecision.keep60);

    _addUnstableCreateJsWindow(policy);
    expect(policy.completeWindow(), FrameRateDecision.keep60);
  });

  test('slow Flutter frames alone never downgrade the game', () {
    final insufficient = GameFrameRatePolicy(mode: GameFrameRateMode.automatic);
    for (var index = 0; index < 9; index++) {
      insufficient.addFlutterFrame(const Duration(milliseconds: 40));
    }
    expect(insufficient.completeWindow(), FrameRateDecision.keep60);

    final policy = GameFrameRatePolicy(mode: GameFrameRateMode.automatic);
    for (var window = 0; window < 2; window++) {
      for (var index = 0; index < 8; index++) {
        policy.addFlutterFrame(const Duration(milliseconds: 16));
      }
      for (var index = 0; index < 2; index++) {
        policy.addFlutterFrame(const Duration(milliseconds: 40));
      }
      expect(policy.completeWindow(), FrameRateDecision.keep60);
    }
  });

  test('switching away from automatic clears its old downgrade', () {
    final policy = GameFrameRatePolicy(mode: GameFrameRateMode.automatic);
    _addUnstableCreateJsWindow(policy);
    policy.completeWindow();
    _addUnstableCreateJsWindow(policy);
    expect(policy.completeWindow(), FrameRateDecision.downgradeTo30);

    policy.setMode(GameFrameRateMode.stable60);
    expect(policy.isLockedTo30, isFalse);
    policy.setMode(GameFrameRateMode.automatic);
    expect(policy.completeWindow(), FrameRateDecision.keep60);
  });

  test('automatic recovery waits at least thirty seconds at stable 30', () {
    final policy = _downgradedPolicy();
    for (var i = 0; i < 5; i++) {
      _addStable30Window(policy);
      expect(policy.completeWindow(), FrameRateDecision.lock30);
    }
    _addStable30Window(policy);
    expect(policy.completeWindow().name, 'upgradeTo60');
    expect(policy.isLockedTo30, isFalse);
  });

  test('missing measurements break consecutive recovery windows', () {
    final policy = _downgradedPolicy();
    for (var i = 0; i < 6; i++) {
      expect(policy.completeWindow(), FrameRateDecision.lock30);
    }
    for (var i = 0; i < 2; i++) {
      _addStable30Window(policy);
      expect(policy.completeWindow(), FrameRateDecision.lock30);
    }
    expect(policy.completeWindow(), FrameRateDecision.lock30);
    for (var i = 0; i < 2; i++) {
      _addStable30Window(policy);
      expect(policy.completeWindow(), FrameRateDecision.lock30);
    }
    _addStable30Window(policy);
    expect(policy.completeWindow().name, 'upgradeTo60');
  });

  test(
    'one missing sample invalidates an otherwise stable recovery window',
    () {
      final policy = _downgradedPolicy();
      for (var i = 0; i < 6; i++) {
        policy.completeWindow();
      }
      for (var i = 0; i < 4; i++) {
        _addStable30Window(policy);
        policy.addCreateJsSample(null);
        expect(policy.completeWindow(), FrameRateDecision.lock30);
      }
      _addStable30Window(policy);
      expect(policy.completeWindow(), FrameRateDecision.lock30);
    },
  );

  test(
    'recovery cooldown uses elapsed time instead of the number of windows',
    () {
      final policy = _downgradedPolicy();
      for (var i = 0; i < 10; i++) {
        _addStable30Window(policy);
        expect(
          policy.completeWindow(elapsed: const Duration(seconds: 1)),
          FrameRateDecision.lock30,
        );
      }
      _addStable30Window(policy);
      expect(
        policy.completeWindow(elapsed: const Duration(seconds: 20)),
        FrameRateDecision.upgradeTo60,
      );
    },
  );

  test('a failed recovery doubles the next cooldown', () {
    final policy = _downgradedPolicy();
    for (var i = 0; i < 6; i++) {
      _addStable30Window(policy);
      policy.completeWindow();
    }
    expect(policy.isLockedTo30, isFalse);
    _addUnstableCreateJsWindow(policy);
    policy.completeWindow();
    _addUnstableCreateJsWindow(policy);
    expect(policy.completeWindow(), FrameRateDecision.downgradeTo30);
    for (var i = 0; i < 11; i++) {
      _addStable30Window(policy);
      expect(policy.completeWindow(), FrameRateDecision.lock30);
    }
    _addStable30Window(policy);
    expect(policy.completeWindow().name, 'upgradeTo60');
  });

  test('stable 30 mode remains locked under unstable samples', () {
    final policy = GameFrameRatePolicy(mode: GameFrameRateMode.stable30);
    _addUnstableCreateJsWindow(policy);
    _addUnstableFlutterWindow(policy);
    expect(policy.completeWindow(), FrameRateDecision.lock30);
  });

  test('stable 60 and high refresh never auto-downgrade', () {
    for (final mode in <GameFrameRateMode>[
      GameFrameRateMode.stable60,
      GameFrameRateMode.highRefresh,
    ]) {
      final policy = GameFrameRatePolicy(mode: mode);
      for (var window = 0; window < 3; window++) {
        _addUnstableCreateJsWindow(policy);
        _addUnstableFlutterWindow(policy);
        expect(policy.completeWindow(), FrameRateDecision.keep60);
      }
      expect(policy.isLockedTo30, isFalse);
    }
  });
}

void _addUnstableCreateJsWindow(GameFrameRatePolicy policy) {
  for (final fps in <double>[49, 48, 47, 55, 56]) {
    policy.addCreateJsSample(fps);
  }
}

GameFrameRatePolicy _downgradedPolicy() {
  final policy = GameFrameRatePolicy(mode: GameFrameRateMode.automatic);
  for (var i = 0; i < 2; i++) {
    _addUnstableCreateJsWindow(policy);
    policy.completeWindow();
  }
  return policy;
}

void _addStable30Window(GameFrameRatePolicy policy) {
  for (final fps in <double>[29, 30, 30, 29, 30]) {
    policy.addCreateJsSample(fps);
  }
}

void _addUnstableFlutterWindow(GameFrameRatePolicy policy) {
  for (var index = 0; index < 8; index++) {
    policy.addFlutterFrame(const Duration(milliseconds: 16));
  }
  for (var index = 0; index < 2; index++) {
    policy.addFlutterFrame(const Duration(milliseconds: 40));
  }
}
