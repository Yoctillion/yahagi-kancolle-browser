import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import 'flat_style.dart';
import 'game_edge_tap_guard.dart';

/// 极简档的模块行：无底色，左侧标签和名称，右侧右对齐的时间或状态。
/// 标签按自身宽度排布且各自封顶，trailing 封顶一半宽度，名称独占其余空间。
/// 两个标签和 trailing 都顶到封顶时占 0.9 倍行宽；极窄列只压缩标签间距，
/// 避免剩余一成宽度放不下原来的 10dp 间隙。常见宽度仍保留原间距。
const _tagMaxFraction = 0.2;

class FlatListRow extends StatelessWidget {
  const FlatListRow({
    super.key,
    this.onTap,
    this.tags = const <Widget>[],
    this.name,
    this.trailing,
  });

  final VoidCallback? onTap;
  final List<Widget> tags;
  final Widget? name;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final row = InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: flatRowSpacing / 2),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desiredSpacing = tags.isEmpty
                ? 0.0
                : (tags.length - 1) * 4.0 + 6;
            final reservedWidth =
                constraints.maxWidth * _tagMaxFraction * tags.length +
                (trailing == null ? 0 : constraints.maxWidth * .5);
            final spacingBudget = (constraints.maxWidth - reservedWidth).clamp(
              0.0,
              desiredSpacing,
            );
            final spacingScale =
                desiredSpacing == 0 || spacingBudget >= desiredSpacing
                ? 1.0
                // Leave a tiny margin against rounding once the row is full.
                : (spacingBudget - 1e-6).clamp(0.0, spacingBudget) /
                      desiredSpacing;
            return Row(
              children: [
                for (var index = 0; index < tags.length; index++) ...[
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * _tagMaxFraction,
                    ),
                    child: tags[index],
                  ),
                  SizedBox(
                    width: (index == tags.length - 1 ? 6 : 4) * spacingScale,
                  ),
                ],
                Expanded(child: name ?? const SizedBox.shrink()),
                if (trailing != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * 0.5,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: trailing,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
    return onTap == null ? row : GameEdgeTapGuard(child: row);
  }
}

/// 极简档的提示行：左侧小图标，文字占满其余宽度。
class FlatIconLine extends StatelessWidget {
  const FlatIconLine({
    super.key,
    required this.icon,
    required this.color,
    this.size = 13,
    required this.child,
  });

  final IconData icon;
  final Color color;
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Icon(icon, size: size, color: appColor(context, color)),
      const SizedBox(width: 4),
      Expanded(child: child),
    ],
  );
}

TextStyle flatRowTextStyle(
  BuildContext context, {
  Color color = Colors.white,
  FontWeight weight = FontWeight.w700,
  List<Shadow>? shadows,
}) => TextStyle(
  fontSize: flatRowFontSize,
  fontWeight: weight,
  color: appColor(context, color),
  shadows: shadows,
);

Widget flatRowText(
  BuildContext context,
  String text, {
  Key? key,
  Color color = Colors.white,
  List<Shadow>? shadows,
}) => Text(
  text,
  key: key,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: flatRowTextStyle(context, color: color, shadows: shadows),
);

/// 右侧状态控件：宽度不够时整体缩小而不是换行或溢出。
Widget flatRowTrailing(Widget child) => FittedBox(
  fit: BoxFit.scaleDown,
  alignment: Alignment.centerRight,
  child: child,
);
