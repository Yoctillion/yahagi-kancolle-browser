import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'window_metrics_change.dart';

const displayCornersChannelName = 'app.yahagi.kancollebrowser/display_corners';

/// How far a rectangle must be pulled in along each axis to clear a corner of
/// the given radius.
double cornerInset(double radiusDp) => radiusDp * (1 - 1 / math.sqrt2);

@immutable
class CornerRadii {
  const CornerRadii({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
  });

  const CornerRadii.all(double radius)
    : topLeft = radius,
      topRight = radius,
      bottomLeft = radius,
      bottomRight = radius;

  static const fallback = CornerRadii.all(24);

  final double topLeft;
  final double topRight;
  final double bottomLeft;
  final double bottomRight;

  @override
  bool operator ==(Object other) =>
      other is CornerRadii &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomLeft == bottomLeft &&
      other.bottomRight == bottomRight;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomLeft, bottomRight);
}

class DisplayCornersController extends ChangeNotifier {
  DisplayCornersController([
    this._channel = const MethodChannel(displayCornersChannelName),
  ]);

  final MethodChannel _channel;
  CornerRadii _radii = CornerRadii.fallback;
  bool _disposed = false;

  CornerRadii get radii => _radii;

  Future<void> refresh(double devicePixelRatio) async {
    Map<Object?, Object?>? raw;
    try {
      raw = await _channel.invokeMapMethod<Object?, Object?>(
        'getRoundedCorners',
      );
    } on MissingPluginException {
      raw = null;
    } on PlatformException {
      raw = null;
    }
    if (_disposed) return;

    double corner(String key) {
      final px = raw?[key];
      if (px is! num || devicePixelRatio <= 0) {
        return CornerRadii.fallback.topLeft;
      }
      return px / devicePixelRatio;
    }

    final next = CornerRadii(
      topLeft: corner('topLeft'),
      topRight: corner('topRight'),
      bottomLeft: corner('bottomLeft'),
      bottomRight: corner('bottomRight'),
    );
    if (next == _radii) return;
    _radii = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class DisplayCorners extends InheritedNotifier<DisplayCornersController> {
  const DisplayCorners({
    super.key,
    required DisplayCornersController super.notifier,
    required super.child,
  });

  static CornerRadii of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<DisplayCorners>();
    return scope?.notifier?.radii ?? CornerRadii.fallback;
  }
}

/// Owns a [DisplayCornersController] and re-reads the radii whenever the
/// window geometry changes (rotation, fold, split-screen).
class DisplayCornersHost extends StatefulWidget {
  const DisplayCornersHost({super.key, required this.child});

  final Widget child;

  @override
  State<DisplayCornersHost> createState() => _DisplayCornersHostState();
}

class _DisplayCornersHostState extends State<DisplayCornersHost>
    with WidgetsBindingObserver {
  final DisplayCornersController _controller = DisplayCornersController();
  WindowMetricsChangeTracker? _tracker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final view = mounted ? View.maybeOf(context) : null;
      if (view != null) {
        _tracker = WindowMetricsChangeTracker(
          WindowMetricsSnapshot.fromView(view),
        );
      }
      _refresh();
    });
  }

  @override
  void didChangeMetrics() {
    final view = View.maybeOf(context);
    if (view == null) return;
    final snapshot = WindowMetricsSnapshot.fromView(view);
    final tracker = _tracker ??= WindowMetricsChangeTracker(snapshot);
    if (tracker.update(snapshot) == WindowMetricsChange.geometry) {
      _refresh();
    }
  }

  void _refresh() {
    if (!mounted) return;
    final view = View.maybeOf(context);
    if (view == null) return;
    _controller.refresh(view.devicePixelRatio);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      DisplayCorners(notifier: _controller, child: widget.child);
}
