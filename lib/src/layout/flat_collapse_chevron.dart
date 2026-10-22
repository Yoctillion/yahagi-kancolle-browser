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

  static const double _iconSize = 15;

  @override
  Widget build(BuildContext context) {
    final box = Size(width, height);
    final icon = iconAlignment
        .resolve(Directionality.maybeOf(context))
        .inscribe(
          const Size.square(_iconSize),
          Offset.zero & Size(width - iconInset, height),
        );
    // 墨水以图标为圆心。图标贴着点击框边缘，圆会伸出点击框，而 Material 把墨水
    // 裁在自身范围内，所以 Material 要大到包住整个圆；点击区仍只有点击框。
    final ink = Rect.fromCircle(center: icon.center, radius: height / 2);
    final canvas = (Offset.zero & box).expandToInclude(ink);
    return Semantics(
      button: true,
      label: label,
      child: SizedBox.fromSize(
        size: box,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fromRect(
              rect: canvas,
              // 自带透明 Material：若借用整屏那层，墨水就被铺在它上面的信息栏
              // 底色盖住。
              child: Material(
                type: MaterialType.transparency,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    -canvas.left,
                    -canvas.top,
                    canvas.right - width,
                    canvas.bottom - height,
                  ),
                  child: _IconInkResponse(
                    ink: ink,
                    onTap: onTap,
                    child: Padding(
                      padding: EdgeInsets.only(right: iconInset),
                      child: Align(
                        alignment: iconAlignment,
                        child: Icon(
                          collapsed
                              ? Icons.keyboard_arrow_down_rounded
                              : Icons.keyboard_arrow_up_rounded,
                          size: _iconSize,
                          color: const Color(0xff8fa8b6),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 高亮和水波都画在 [ink] 这个圆里，而不是点击框的中心。
class _IconInkResponse extends InkResponse {
  const _IconInkResponse({
    required this.ink,
    required super.onTap,
    required super.child,
  }) : super(
         radius: FlatCollapseChevron.height / 2,
         containedInkWell: true,
         customBorder: const CircleBorder(),
       );

  final Rect ink;

  @override
  RectCallback getRectCallback(RenderBox referenceBox) =>
      () => ink;
}
