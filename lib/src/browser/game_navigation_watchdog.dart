import 'dart:async';

typedef GameNavigationTimerFactory =
    Timer Function(Duration duration, void Function() callback);

/// A document/body deadline measured only while the application is foreground.
final class GameNavigationWatchdog {
  GameNavigationWatchdog({
    this.timeout = const Duration(seconds: 45),
    required this.onTimeout,
    DateTime Function()? now,
    GameNavigationTimerFactory? timerFactory,
  }) : _now = now ?? DateTime.now,
       _timerFactory = timerFactory ?? Timer.new;

  final Duration timeout;
  final void Function(int navigationEpoch) onTimeout;
  final DateTime Function() _now;
  final GameNavigationTimerFactory _timerFactory;
  Timer? _timer;
  int? _epoch;
  int _revision = 0;
  Duration _remaining = Duration.zero;
  DateTime? _armedAt;
  bool _foreground = true;
  bool _disposed = false;

  void start(int navigationEpoch, {Duration? timeout}) {
    if (_disposed) return;
    cancel();
    _epoch = navigationEpoch;
    _remaining = timeout ?? this.timeout;
    if (_remaining.isNegative) _remaining = Duration.zero;
    if (_foreground) _arm();
  }

  void complete(int navigationEpoch) {
    if (_epoch == navigationEpoch) cancel();
  }

  void cancel() {
    _revision += 1;
    _timer?.cancel();
    _timer = null;
    _armedAt = null;
    _epoch = null;
    _remaining = Duration.zero;
  }

  void setForeground(bool foreground) {
    if (_disposed || _foreground == foreground) return;
    _foreground = foreground;
    if (!foreground) {
      if (_armedAt case final armedAt?) {
        final elapsed = _now().difference(armedAt);
        if (!elapsed.isNegative) _remaining -= elapsed;
        if (_remaining.isNegative) _remaining = Duration.zero;
      }
      _revision += 1;
      _timer?.cancel();
      _timer = null;
      _armedAt = null;
    } else if (_epoch != null) {
      _arm();
    }
  }

  void _arm() {
    final epoch = _epoch;
    if (epoch == null || _disposed || !_foreground) return;
    final revision = ++_revision;
    _armedAt = _now();
    _timer = _timerFactory(_remaining, () {
      if (_disposed ||
          !_foreground ||
          _revision != revision ||
          _epoch != epoch) {
        return;
      }
      cancel();
      onTimeout(epoch);
    });
  }

  void dispose() {
    if (_disposed) return;
    cancel();
    _disposed = true;
  }
}
