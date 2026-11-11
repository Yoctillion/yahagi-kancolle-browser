import '../theme/app_palette.dart';
import 'package:flutter/material.dart';

const _prophetHpThresholds = <double>[0.25, 0.50, 0.75];

const prophetHpBarHeight = 6.0;

const _ghostOpacity = 0.32;

class ProphetHpBar extends StatelessWidget {
  const ProphetHpBar({
    super.key,
    required this.value,
    required this.color,
    required this.backgroundColor,
    this.height = prophetHpBarHeight,
    this.ghostValue,
    this.ghostColor,
  });

  final double value;
  final Color color;
  final Color backgroundColor;
  final double height;
  final double? ghostValue;
  final Color? ghostColor;

  @override
  Widget build(BuildContext context) {
    final ratio = value.clamp(0.0, 1.0).toDouble();
    final ghostRatio = ghostValue?.clamp(0.0, 1.0).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ColoredBox(color: appColor(context, backgroundColor)),
              if (ghostRatio != null && ghostRatio > ratio)
                Positioned(
                  key: const Key('prophet-hp-ghost'),
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: constraints.maxWidth * ghostRatio,
                  child: ColoredBox(
                    color: appColor(
                      context,
                      (ghostColor ?? color).withValues(alpha: _ghostOpacity),
                    ),
                  ),
                ),
              // 圆角只交给外层 ClipRRect；指示器自带圆角/轨道间隙会在虚影接缝处露底。
              LinearProgressIndicator(
                minHeight: height,
                value: ratio,
                color: appColor(context, color),
                backgroundColor: Colors.transparent,
                borderRadius: BorderRadius.zero,
                trackGap: 0,
                stopIndicatorRadius: 0,
              ),
              ClipRect(
                clipper: _ProphetHpFillClipper(ratio),
                child: Stack(
                  children: <Widget>[
                    for (final threshold in _prophetHpThresholds)
                      if (ratio > threshold)
                        Positioned(
                          key: Key(
                            'prophet-hp-threshold-${(threshold * 100).round()}',
                          ),
                          left: constraints.maxWidth * threshold,
                          top: 1,
                          width: 1,
                          height: (constraints.maxHeight - 2).clamp(
                            0.0,
                            constraints.maxHeight,
                          ),
                          child: ColoredBox(
                            color: appColor(
                              context,
                              Color.fromRGBO(2, 11, 16, 0.78),
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProphetHpFillClipper extends CustomClipper<Rect> {
  const _ProphetHpFillClipper(this.ratio);

  final double ratio;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * ratio, size.height);

  @override
  bool shouldReclip(covariant _ProphetHpFillClipper oldClipper) =>
      ratio != oldClipper.ratio;
}
