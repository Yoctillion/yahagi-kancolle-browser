import '../settings/game_frame_rate_settings.dart';

enum FrameRateDecision { keep60, downgradeTo30, lock30, upgradeTo60 }

bool isGameFrameRateSamplingPage(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;

  final host = uri.host.toLowerCase();
  if (host == 'accounts.dmm.com') return false;
  if (host == 'kancolle-server.com' || host.endsWith('.kancolle-server.com')) {
    return true;
  }
  final isDmm =
      host == 'dmm.com' ||
      host.endsWith('.dmm.com') ||
      host == 'dmm.co.jp' ||
      host.endsWith('.dmm.co.jp');
  if (!isDmm) return false;

  final path = uri.path.toLowerCase();
  return host == 'osapi.dmm.com' ||
      path.contains('kancolle') ||
      path.contains('854854') ||
      path.contains('/kcs');
}

final class GameFrameRatePolicy {
  GameFrameRatePolicy({
    required this.mode,
    this.recoveryCooldown = const Duration(seconds: 30),
    this.maxRecoveryCooldown = const Duration(seconds: 120),
  });

  GameFrameRateMode mode;
  final Duration recoveryCooldown;
  final Duration maxRecoveryCooldown;
  final List<double> _createJsSamples = <double>[];
  int _flutterFrameCount = 0;
  bool _hasMissingSample = false;
  int _consecutiveUnstableWindows = 0;
  int _consecutiveStableWindows = 0;
  bool _lockedTo30 = false;
  bool _tryingRecovery = false;
  Duration _cooldownRemaining = Duration.zero;
  late Duration _nextCooldown = recoveryCooldown;

  bool get isLockedTo30 => _lockedTo30;
  int get flutterFrameCount => _flutterFrameCount;

  void setMode(GameFrameRateMode mode) {
    if (this.mode == mode) return;
    this.mode = mode;
    _lockedTo30 = false;
    _tryingRecovery = false;
    _cooldownRemaining = Duration.zero;
    _nextCooldown = recoveryCooldown;
    resetObservation();
  }

  void addCreateJsSample(double? fps) {
    if (fps == null || !fps.isFinite || fps < 0) {
      _hasMissingSample = true;
      return;
    }
    _createJsSamples.add(fps);
  }

  void addFlutterFrame(Duration totalSpan) {
    // Flutter measures the surrounding UI, not the Android WebView renderer.
    // Keep this diagnostic counter without using it to throttle the game.
    _flutterFrameCount += 1;
  }

  FrameRateDecision completeWindow({
    Duration elapsed = const Duration(seconds: 5),
  }) {
    if (mode == GameFrameRateMode.stable30) {
      resetWindow();
      return FrameRateDecision.lock30;
    }
    if (mode != GameFrameRateMode.automatic) {
      resetWindow();
      _consecutiveUnstableWindows = 0;
      _lockedTo30 = false;
      return FrameRateDecision.keep60;
    }
    if (_lockedTo30) {
      if (!elapsed.isNegative) _cooldownRemaining -= elapsed;
      final stable =
          !_hasMissingSample &&
          _createJsSamples.length >= 4 &&
          _createJsSamples.every((fps) => fps >= 27 && fps <= 33);
      _consecutiveStableWindows = stable ? _consecutiveStableWindows + 1 : 0;
      resetWindow();
      if (_cooldownRemaining <= Duration.zero &&
          _consecutiveStableWindows >= 3) {
        _lockedTo30 = false;
        _tryingRecovery = true;
        resetObservation();
        return FrameRateDecision.upgradeTo60;
      }
      return FrameRateDecision.lock30;
    }
    final createJsUnstable =
        _createJsSamples.length >= 4 &&
        _createJsSamples.where((fps) => fps < 50).length >= 3;
    if (createJsUnstable) {
      _consecutiveUnstableWindows += 1;
    } else {
      _consecutiveUnstableWindows = 0;
    }
    final stable =
        !_hasMissingSample &&
        _createJsSamples.length >= 4 &&
        _createJsSamples.every((fps) => fps >= 55);
    _consecutiveStableWindows = stable ? _consecutiveStableWindows + 1 : 0;
    if (_tryingRecovery && _consecutiveStableWindows >= 3) {
      _tryingRecovery = false;
      _nextCooldown = recoveryCooldown;
    }
    resetWindow();

    if (_consecutiveUnstableWindows >= 2) {
      if (_tryingRecovery) {
        final longer = _nextCooldown * 2;
        _nextCooldown = longer > maxRecoveryCooldown
            ? maxRecoveryCooldown
            : longer;
      }
      _lockedTo30 = true;
      _tryingRecovery = false;
      _cooldownRemaining = _nextCooldown;
      resetObservation();
      return FrameRateDecision.downgradeTo30;
    }
    return FrameRateDecision.keep60;
  }

  void resetWindow() {
    _createJsSamples.clear();
    _hasMissingSample = false;
    _flutterFrameCount = 0;
  }

  /// Discard evidence across page, lifecycle or target changes while retaining
  /// the automatic fallback and its cooldown.
  void resetObservation() {
    resetWindow();
    _consecutiveUnstableWindows = 0;
    _consecutiveStableWindows = 0;
  }
}
