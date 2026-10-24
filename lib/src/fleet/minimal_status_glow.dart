import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../settings/battle_status_effect_settings.dart';
import '../theme/app_palette.dart';
import 'ship_damage_level.dart';
import 'ship_status_style.dart';

/// The minimal briefing's existing damage glow, driven directly by paint.
/// Other layouts retain their original DamagePulseGlow implementation.
class MinimalDamagePulseGlow extends StatelessWidget {
  const MinimalDamagePulseGlow({
    super.key,
    required this.currentHp,
    required this.maxHp,
    required this.filter,
    required this.normalColor,
    this.borderRadius,
    required this.child,
  });

  final int currentHp;
  final int maxHp;
  final DamagePulseFilter filter;
  final Color normalColor;
  final BorderRadius? borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (filter == DamagePulseFilter.off) return child;
    return _MinimalDamagePulseAnimation(
      currentHp: currentHp,
      maxHp: maxHp,
      filter: filter,
      normalColor: normalColor,
      borderRadius: borderRadius,
      child: child,
    );
  }
}

class _MinimalDamagePulseAnimation extends StatefulWidget {
  const _MinimalDamagePulseAnimation({
    required this.currentHp,
    required this.maxHp,
    required this.filter,
    required this.normalColor,
    required this.borderRadius,
    required this.child,
  });

  final int currentHp;
  final int maxHp;
  final DamagePulseFilter filter;
  final Color normalColor;
  final BorderRadius? borderRadius;
  final Widget child;

  @override
  State<_MinimalDamagePulseAnimation> createState() =>
      _MinimalDamagePulseAnimationState();
}

class _MinimalDamagePulseAnimationState
    extends State<_MinimalDamagePulseAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;

  DamagePulseVisualSpec get _spec => damagePulseVisualSpec(
    damageLevel: shipDamageLevel(
      currentHp: widget.currentHp,
      maxHp: widget.maxHp,
    ),
    filter: widget.filter,
    normalColor: widget.normalColor,
  );

  @override
  void initState() {
    super.initState();
    final spec = _spec;
    _animation = AnimationController(vsync: this, duration: spec.duration);
    if (spec.pulses) {
      _animation.repeat();
    }
  }

  @override
  void didUpdateWidget(_MinimalDamagePulseAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    final spec = _spec;
    if (_animation.duration != spec.duration) {
      _animation.duration = spec.duration;
    }
    if (spec.pulses) {
      if (!_animation.isAnimating) {
        _animation.repeat();
      }
    } else {
      _animation
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec;
    if (!spec.pulses) return widget.child;
    final color = appColor(context, spec.color);
    return RepaintBoundary(
      child: MinimalAnimatedDecoration(
        animation: _animation,
        decorationBuilder: (value) {
          final trianglePhase = value <= 0.5 ? value * 2 : (1 - value) * 2;
          final phase = Curves.easeInOut.transform(trianglePhase);
          return BoxDecoration(
            borderRadius: widget.borderRadius,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: color.withValues(alpha: 0.3 + 0.5 * phase),
                blurRadius: 2 + 3 * phase,
              ),
            ],
          );
        },
        child: widget.child,
      ),
    );
  }
}

typedef MinimalDecorationBuilder = BoxDecoration Function(double value);

/// Updates only paint: rebuilding beneath a LayoutBuilder would also schedule
/// layout for the surrounding briefing on every animation tick.
class MinimalAnimatedDecoration extends SingleChildRenderObjectWidget {
  const MinimalAnimatedDecoration({
    super.key,
    required this.animation,
    required this.decorationBuilder,
    required super.child,
  });

  final Animation<double> animation;
  final MinimalDecorationBuilder decorationBuilder;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMinimalAnimatedDecoration(
        animation: animation,
        decorationBuilder: decorationBuilder,
        configuration: createLocalImageConfiguration(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderDecoratedBox renderObject,
  ) => (renderObject as _RenderMinimalAnimatedDecoration).update(
    animation,
    decorationBuilder,
    createLocalImageConfiguration(context),
  );
}

class _RenderMinimalAnimatedDecoration extends RenderDecoratedBox {
  _RenderMinimalAnimatedDecoration({
    required Animation<double> animation,
    required MinimalDecorationBuilder decorationBuilder,
    required super.configuration,
  }) : _animation = animation,
       _decorationBuilder = decorationBuilder,
       super(decoration: decorationBuilder(animation.value));

  Animation<double> _animation;
  MinimalDecorationBuilder _decorationBuilder;

  void _updateDecoration() {
    decoration = _decorationBuilder(_animation.value);
  }

  void update(
    Animation<double> animation,
    MinimalDecorationBuilder decorationBuilder,
    ImageConfiguration imageConfiguration,
  ) {
    if (_animation != animation) {
      if (attached) _animation.removeListener(_updateDecoration);
      _animation = animation;
      if (attached) _animation.addListener(_updateDecoration);
    }
    _decorationBuilder = decorationBuilder;
    configuration = imageConfiguration;
    _updateDecoration();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _animation.addListener(_updateDecoration);
    _updateDecoration();
  }

  @override
  void detach() {
    _animation.removeListener(_updateDecoration);
    super.detach();
  }
}
