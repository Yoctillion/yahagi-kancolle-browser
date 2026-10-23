import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// 立绘铺在文字底下时，用与文字反差的描边保证可读：深色主题是黑边，
/// 浅色主题的文字是深色，描边改成面板底色。
List<Shadow> flatOnImageShadows(BuildContext context) => <Shadow>[
  Shadow(
    color: AppPalette.of(context).isDark
        ? Colors.black
        : AppPalette.of(context).surface,
    blurRadius: 3,
  ),
];

/// 极简档行底下的立绘：靠左占 60% 宽，不接收点按。
class FlatPortraitBackdrop extends StatelessWidget {
  const FlatPortraitBackdrop({
    super.key,
    this.imageKey,
    required this.image,
    required this.child,
  });

  final Key? imageKey;
  final Widget Function(double width, double height) image;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: <Widget>[
      Positioned.fill(
        child: IgnorePointer(
          key: imageKey,
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: 0.6,
            child: LayoutBuilder(
              // 渐变起点 alpha 0.5，同一层里完成半透明与左→右渐隐。
              builder: (context, box) => ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => const LinearGradient(
                  colors: <Color>[Color(0x80000000), Color(0x00000000)],
                ).createShader(bounds),
                child: image(box.maxWidth, box.maxHeight),
              ),
            ),
          ),
        ),
      ),
      child,
    ],
  );
}
