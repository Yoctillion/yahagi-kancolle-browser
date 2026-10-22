import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/layout/flat_collapse_chevron.dart';

// 信息栏的底色铺在整屏 Material 之上；墨水若画在那层 Material 上就被盖住。
const _background = Color(0xff0d1a26);
const _margin = 8;

/// 把箭头放在不透明底色上，四周留 [_margin]，返回按坐标（相对箭头左上角）取色的函数。
Future<Future<Color> Function(double x, double y)> _pumpChevron(
  WidgetTester tester, {
  double width = 24,
  double iconInset = 0,
  AlignmentGeometry iconAlignment = Alignment.centerRight,
}) async {
  final boundary = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      home: Material(
        child: Center(
          child: RepaintBoundary(
            key: boundary,
            child: ColoredBox(
              color: _background,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: FlatCollapseChevron(
                  collapsed: false,
                  label: 'collapse',
                  onTap: () {},
                  width: width,
                  iconInset: iconInset,
                  iconAlignment: iconAlignment,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return (x, y) async {
    final bytes = await tester.runAsync(() async {
      final image = await captureImage(boundary.currentContext! as Element);
      return image.toByteData(format: ui.ImageByteFormat.rawRgba);
    });
    final stride = tester.getSize(find.byKey(boundary)).width.round();
    final i = ((y + _margin).round() * stride + (x + _margin).round()) * 4;
    return Color.fromARGB(
      bytes!.getUint8(i + 3),
      bytes.getUint8(i),
      bytes.getUint8(i + 1),
      bytes.getUint8(i + 2),
    );
  };
}

Future<TestGesture> _press(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(FlatCollapseChevron)),
  );
  // 淡入动画在按下后的第一帧才开始计时。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return gesture;
}

void main() {
  testWidgets('press highlight is not hidden by an opaque panel background', (
    tester,
  ) async {
    final pixel = await _pumpChevron(tester);
    // 点击框左半边、高亮圆内、图标左侧的一点。
    expect(await pixel(6, 12), _background);

    final gesture = await _press(tester);
    expect(await pixel(6, 12), isNot(_background));
    await gesture.cancel();
  });

  testWidgets('press highlight centers on the right-aligned icon', (
    tester,
  ) async {
    // 模块标题行：点击框 30 宽，图标贴右缘，圆心在 x = 22.5。
    final pixel = await _pumpChevron(tester, width: 30);
    final gesture = await _press(tester);
    expect(await pixel(32, 12), isNot(_background), reason: '伸出点击框右缘');
    expect(await pixel(2, 12), _background, reason: '离图标 20 以上');
    await gesture.cancel();
  });

  testWidgets('press highlight follows an inset, lowered icon', (tester) async {
    // 资源区：点击框伸出图标右缘 8，图标对齐末行中线，圆心在 (8.5, 14)。
    final pixel = await _pumpChevron(
      tester,
      iconInset: 8,
      iconAlignment: const Alignment(1, 4 / 9),
    );
    final gesture = await _press(tester);
    expect(await pixel(-2, 14), isNot(_background), reason: '伸出点击框左缘');
    expect(await pixel(8, 25), isNot(_background), reason: '伸出点击框底边');
    expect(await pixel(22, 2), _background, reason: '离图标 12 以上');
    await gesture.cancel();
  });
}
