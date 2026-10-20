import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../layout/adaptive_layout.dart';
import '../settings/display_mode_store.dart';

/// Displays the platform game surface while strictly maintaining the
/// KanColle 1200:720 aspect ratio.
///
/// In split-screen, vertical, or compact workspaces, width alignment is
/// prioritized so that the game occupies 100% of the available width with
/// zero horizontal pillarbox black borders. Vertical margins can be adjusted
/// by the user via the multi-window split divider.
///
/// In widescreen landscape displays (e.g. standard phone landscape gaming),
/// contain behavior is preserved with safe edge padding to avoid camera
/// notches and vertical cropping.
///
/// Uses [CustomSingleChildLayout] so that the widget subtree hierarchy above
/// the game surface remains completely stable across fullscreen toggles,
/// orientation changes, and layout resizing, guaranteeing that the platform
/// view is never disposed or recreated during UI reflows.
class GameSurfaceViewport extends StatefulWidget {
  const GameSurfaceViewport({
    super.key,
    required this.child,
    this.aspectRatio = 1200 / 720,
    this.fullscreen = false,
    this.isLandscape = false,
    this.displayMode = DisplayMode.auto,
    this.fitWithinBounds = false,
    this.avoidBottomInset = false,
    this.viewPadding,
    this.backgroundColor = const Color(0xff0a1823),
  });

  final Widget child;
  final double aspectRatio;
  final bool fullscreen;
  final bool isLandscape;
  final DisplayMode displayMode;
  final bool fitWithinBounds;

  /// Keeps the game above the bottom system inset (home indicator) wherever
  /// it overlaps this viewport, also while docked in the workspace, shrinking
  /// it instead of letting width-priority layout run under the inset.
  ///
  /// Docked side insets are deliberately ignored: they carry no system
  /// gesture, so avoiding them would only shrink the game.
  final bool avoidBottomInset;
  final EdgeInsets? viewPadding;
  final Color backgroundColor;

  /// Determines whether width-first alignment should be used.
  ///
  /// Returns true for portrait display mode, vertical workspaces, or compact
  /// windows (such as Android split-screen on a mobile device).
  static bool shouldUseWidthPriority({
    required double width,
    required double height,
    required bool isLandscape,
    DisplayMode displayMode = DisplayMode.auto,
    bool fullscreen = false,
  }) {
    if (displayMode == DisplayMode.portrait) {
      return true;
    }
    if (!isLandscape) {
      return true;
    }
    // Mobile split-screen / compact window width
    if (width <= compactWindowShortestSide) {
      return true;
    }
    // Height-constrained multi-window / foldable unfolded horizontal split
    // (e.g. 768x380, 800x400, 1024x500) where width exceeds standard phone width
    // but vertical space is constrained by multi-window division.
    if (height > 0 &&
        height <= compactWindowShortestSide &&
        (width / height) <= 2.1) {
      return true;
    }
    return false;
  }

  /// Computes the layout rectangle for the game surface in width-priority mode.
  ///
  /// The game always fills the container's width (width-first alignment).
  /// If safe area height is sufficient, it is centered within the safe area.
  /// Otherwise, it is centered within the container height.
  static Rect computeWidthPriorityGameRect({
    required double containerWidth,
    required double containerHeight,
    required double aspectRatio,
    EdgeInsets padding = EdgeInsets.zero,
  }) {
    final gameWidth = containerWidth;
    final gameHeight = gameWidth / aspectRatio;
    final safeHeight = containerHeight - padding.vertical;

    final double topOffset;
    if (safeHeight >= gameHeight) {
      topOffset = padding.top + (safeHeight - gameHeight) / 2;
    } else {
      topOffset = (containerHeight - gameHeight) / 2;
    }

    return Rect.fromLTWH(0, topOffset, gameWidth, gameHeight);
  }

  /// Computes the layout rectangle for the game surface in contain mode.
  static Rect computeContainGameRect({
    required double containerWidth,
    required double containerHeight,
    required double aspectRatio,
    EdgeInsets padding = EdgeInsets.zero,
  }) {
    final availW = math.max(0.0, containerWidth - padding.horizontal);
    final availH = math.max(0.0, containerHeight - padding.vertical);

    final double gameWidth;
    final double gameHeight;
    if (availH > 0 && availW / availH > aspectRatio) {
      gameHeight = availH;
      gameWidth = gameHeight * aspectRatio;
    } else {
      gameWidth = availW;
      gameHeight = aspectRatio > 0 ? gameWidth / aspectRatio : availH;
    }

    final left = padding.left + (availW - gameWidth) / 2;
    final top = padding.top + (availH - gameHeight) / 2;
    return Rect.fromLTWH(left, top, gameWidth, gameHeight);
  }

  @override
  State<GameSurfaceViewport> createState() => _GameSurfaceViewportState();
}

class _GameSurfaceViewportState extends State<GameSurfaceViewport> {
  double _dockedBottomInset = 0;

  @override
  Widget build(BuildContext context) {
    final padding = widget.viewPadding ?? MediaQuery.viewPaddingOf(context);
    final EdgeInsets effectivePadding;
    if (widget.fullscreen) {
      effectivePadding = padding;
    } else if (widget.avoidBottomInset) {
      // The docked position is only known after layout, so the overlap is
      // measured post-frame. Every workspace reflow that moves this box goes
      // through a rebuild of it, which re-measures.
      final screenHeight = MediaQuery.sizeOf(context).height;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _measureDockedBottomInset(padding.bottom, screenHeight),
      );
      effectivePadding = EdgeInsets.only(bottom: _dockedBottomInset);
    } else {
      effectivePadding = EdgeInsets.zero;
    }

    return ColoredBox(
      color: widget.backgroundColor,
      child: ClipRect(
        child: CustomSingleChildLayout(
          delegate: _GameSurfaceLayoutDelegate(
            aspectRatio: widget.aspectRatio,
            fullscreen: widget.fullscreen,
            isLandscape: widget.isLandscape,
            displayMode: widget.displayMode,
            fitWithinBounds: widget.fitWithinBounds,
            strictBottomInset: widget.avoidBottomInset,
            padding: effectivePadding,
          ),
          child: widget.child,
        ),
      ),
    );
  }

  void _measureDockedBottomInset(double bottomPadding, double screenHeight) {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
    final inset = (bottom - (screenHeight - bottomPadding)).clamp(
      0.0,
      bottomPadding,
    );
    if (inset != _dockedBottomInset) {
      setState(() => _dockedBottomInset = inset);
    }
  }
}

class _GameSurfaceLayoutDelegate extends SingleChildLayoutDelegate {
  const _GameSurfaceLayoutDelegate({
    required this.aspectRatio,
    required this.fullscreen,
    required this.isLandscape,
    required this.displayMode,
    required this.fitWithinBounds,
    required this.strictBottomInset,
    required this.padding,
  });

  final double aspectRatio;
  final bool fullscreen;
  final bool isLandscape;
  final DisplayMode displayMode;
  final bool fitWithinBounds;
  final bool strictBottomInset;
  final EdgeInsets padding;

  // Width priority falls back to centering in the whole container when the
  // safe height is short, which would put the game under the bottom inset.
  bool _widthPriorityFitsSafeHeight(Size size) =>
      size.height - padding.vertical >= size.width / aspectRatio;

  Rect _calculateRect(Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return Rect.zero;
    }

    final isWidthPriority = GameSurfaceViewport.shouldUseWidthPriority(
      width: size.width,
      height: size.height,
      isLandscape: isLandscape,
      displayMode: displayMode,
      fullscreen: fullscreen,
    );

    if (isWidthPriority &&
        !fitWithinBounds &&
        (!strictBottomInset || _widthPriorityFitsSafeHeight(size))) {
      return GameSurfaceViewport.computeWidthPriorityGameRect(
        containerWidth: size.width,
        containerHeight: size.height,
        aspectRatio: aspectRatio,
        padding: padding,
      );
    } else {
      return GameSurfaceViewport.computeContainGameRect(
        containerWidth: size.width,
        containerHeight: size.height,
        aspectRatio: aspectRatio,
        padding: padding,
      );
    }
  }

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final rect = _calculateRect(constraints.biggest);
    return BoxConstraints.tight(Size(rect.width, rect.height));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final rect = _calculateRect(size);
    return Offset(rect.left, rect.top);
  }

  @override
  bool shouldRelayout(_GameSurfaceLayoutDelegate oldDelegate) {
    return oldDelegate.aspectRatio != aspectRatio ||
        oldDelegate.fullscreen != fullscreen ||
        oldDelegate.isLandscape != isLandscape ||
        oldDelegate.displayMode != displayMode ||
        oldDelegate.fitWithinBounds != fitWithinBounds ||
        oldDelegate.strictBottomInset != strictBottomInset ||
        oldDelegate.padding != padding;
  }
}
