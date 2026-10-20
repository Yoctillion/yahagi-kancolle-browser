import 'package:flutter/material.dart';

const flatRowSpacing = 2.0;
const flatRowFontSize = 11.0;
const flatTimeColor = Color(0xffd4a85f);
const flatDoneColor = Color(0xff4cc06a);
const flatIdleColor = Color(0xff8197a5);

/// 极简档的模块行：无底色，左侧编号和名称，右侧右对齐的时间或状态。
/// 窄面板下名称先被截断；trailing 最多占一半宽度，超出由调用方的控件自行收缩。
class FlatListRow extends StatelessWidget {
  const FlatListRow({
    super.key,
    required this.onTap,
    this.leading = const <Widget>[],
    this.name,
    this.trailing,
  });

  final VoidCallback onTap;
  final List<Widget> leading;
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
              ...leading,
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
}) => TextStyle(fontSize: flatRowFontSize, fontWeight: weight, color: color);

Widget flatRowName(String text, {Key? key, Color color = Colors.white}) => Text(
  text,
  key: key,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: flatRowTextStyle(color: color),
);

/// 右侧状态控件：宽度不够时整体缩小而不是换行或溢出。
Widget flatRowTrailing(Widget child) => FittedBox(
  fit: BoxFit.scaleDown,
  alignment: Alignment.centerRight,
  child: child,
);
