import 'package:flutter/material.dart';

/// 极简档（扁平面板）的折叠箭头。图标贴着点击框右缘，信息栏里资源区和各模块的
/// 箭头才能右缘对齐；M3 的 IconButton 会把图标居中在至少 40 宽的按钮里，对不齐。
class FlatCollapseChevron extends StatelessWidget {
  const FlatCollapseChevron({
    super.key,
    required this.collapsed,
    required this.label,
    required this.onTap,
    this.width = 24,
    this.iconAlignment = Alignment.centerRight,
    this.iconInset = 0,
  });

  final bool collapsed;
  final String label;
  final VoidCallback onTap;
  final double width;
  final AlignmentGeometry iconAlignment;

  /// 点击框伸出图标右缘的宽度。
  final double iconInset;

  static const double height = 24;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      // 自带透明 Material：墨水画在最近的 Material 上，若借用整屏那层，就被铺在
      // 它上面的信息栏底色盖住。
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          width: width,
          height: height,
          child: InkResponse(
            radius: height / 2,
            // 透明 Material 会把墨水裁成点击框的矩形，圆形边界让水波也保持圆形。
            containedInkWell: true,
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.only(right: iconInset),
              child: Align(
                alignment: iconAlignment,
                child: Icon(
                  collapsed
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_up_rounded,
                  size: 15,
                  color: const Color(0xff8fa8b6),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
