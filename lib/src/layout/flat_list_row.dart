import 'package:flutter/material.dart';

const flatRowSpacing = 2.0;
const flatRowFontSize = 11.0;
const flatTimeColor = Color(0xffd4a85f);
const flatDoneColor = Color(0xff4cc06a);
const flatIdleColor = Color(0xff8197a5);

/// 极简档的模块行：无底色，左侧标签和名称，右侧右对齐的时间或状态。
/// 标签按自身宽度排布且各自封顶，trailing 封顶一半宽度，名称独占其余空间。
/// 两个标签和 trailing 都顶到封顶时，固定部分是 0.9 倍行宽加约 10dp 间隙，
/// 行宽约 100dp 以下会溢出；信息栏常见宽度下只会截断名称。
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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: flatRowSpacing / 2),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              for (var index = 0; index < tags.length; index++) ...[
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * _tagMaxFraction,
                  ),
                  child: tags[index],
                ),
                SizedBox(width: index == tags.length - 1 ? 6 : 4),
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
          ),
        ),
      ),
    );
  }
}

TextStyle flatRowTextStyle({
  Color color = Colors.white,
  FontWeight weight = FontWeight.w700,
  List<Shadow>? shadows,
}) => TextStyle(
  fontSize: flatRowFontSize,
  fontWeight: weight,
  color: color,
  shadows: shadows,
);

Widget flatRowName(
  String text, {
  Key? key,
  Color color = Colors.white,
  List<Shadow>? shadows,
}) => Text(
  text,
  key: key,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: flatRowTextStyle(color: color, shadows: shadows),
);

/// 右侧状态控件：宽度不够时整体缩小而不是换行或溢出。
Widget flatRowTrailing(Widget child) => FittedBox(
  fit: BoxFit.scaleDown,
  alignment: Alignment.centerRight,
  child: child,
);
