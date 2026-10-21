import 'package:flutter/material.dart';

/// 立绘铺在文字底下时，深色描边保证文字在亮色图上仍可读。
const flatOnImageShadows = <Shadow>[Shadow(color: Colors.black, blurRadius: 3)];

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
