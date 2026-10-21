import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'window_metrics_change.dart';

const displayCornersChannelName = 'app.yahagi.kancollebrowser/display_corners';

/// How far a rectangle must be pulled in along each axis to clear a corner of
/// the given radius.
double cornerInset(double radiusDp) => radiusDp * (1 - 1 / math.sqrt2);

/// How far content starting [y] dp from one screen edge must be pulled in
/// along that edge to clear a corner of the given radius. [cornerInset] is the
/// 45° case; a thin bar needs the arc at its own content line, which for a
/// large radius intrudes much further than the 45° point.
double cornerInsetAt(double radiusDp, double y) {
  if (radiusDp <= 0 || y >= radiusDp) return 0;
  final dy = radiusDp - math.max(0.0, y);
  return radiusDp - math.sqrt(radiusDp * radiusDp - dy * dy);
}

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
  CornerRadii? _radii;
  bool _disposed = false;

  /// null when the platform reports nothing; [DisplayCorners.of] then infers
  /// the radii from the platform.
  CornerRadii? get radii => _radii;

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

    // Android 12+ reports null for a corner that is not rounded: a square
    // screen, or a split-screen window that does not reach that corner.
    double corner(Map<Object?, Object?> raw, String key) {
      final px = raw[key];
      return px is num && devicePixelRatio > 0 ? px / devicePixelRatio : 0;
    }

    final next = raw == null
        ? null
        : CornerRadii(
            topLeft: corner(raw, 'topLeft'),
            topRight: corner(raw, 'topRight'),
            bottomLeft: corner(raw, 'bottomLeft'),
            bottomRight: corner(raw, 'bottomRight'),
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
    final radii = scope?.notifier?.radii;
    if (radii != null) return radii;
    return switch (defaultTargetPlatform) {
      // Below Android 12 there is no radius API; guessing a radius would give
      // up space on the many square-cornered screens, so treat it as square.
      TargetPlatform.android => const CornerRadii.all(0),
      // iOS has no way to query the radius. Only notch/island iPhones have
      // ~55dp corners; iPads and home-button iPhones have a status bar but
      // near-square corners, so they keep the 24dp fallback.
      TargetPlatform.iOS when _isFullScreenIphone(context) =>
        iosFullScreenCorners,
      _ => CornerRadii.fallback,
    };
  }

  static bool _isFullScreenIphone(BuildContext context) {
    final padding = MediaQuery.maybeViewPaddingOf(context);
    final size = MediaQuery.maybeSizeOf(context);
    if (padding == null || size == null || size.shortestSide >= 600) {
      return false;
    }
    final largest = math.max(
      padding.top,
      math.max(padding.left, padding.right),
    );
    return largest >= 44;
  }

  static const iosFullScreenCorners = CornerRadii.all(55);
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
