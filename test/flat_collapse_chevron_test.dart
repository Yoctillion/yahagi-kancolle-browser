import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/layout/flat_collapse_chevron.dart';

void main() {
  testWidgets('press highlight is not hidden by an opaque panel background', (
    tester,
  ) async {
    // 信息栏的底色铺在整屏 Material 之上；墨水若画在那层 Material 上就被盖住。
    const background = Color(0xff0d1a26);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: RepaintBoundary(
              key: boundary,
              child: ColoredBox(
                color: background,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: FlatCollapseChevron(
                    collapsed: false,
                    label: 'collapse',
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Future<Color> pixel(int x, int y) async {
      final bytes = await tester.runAsync(() async {
        final image = await captureImage(boundary.currentContext! as Element);
        return image.toByteData(format: ui.ImageByteFormat.rawRgba);
      });
      final width = tester.getSize(find.byKey(boundary)).width.round();
      final i = (y * width + x) * 4;
      return Color.fromARGB(
        bytes!.getUint8(i + 3),
        bytes.getUint8(i),
        bytes.getUint8(i + 1),
        bytes.getUint8(i + 2),
      );
    }

    // 点击框左半边、高亮圆内、图标左侧的一点。
    const x = 8 + 6;
    const y = 8 + 12;
    expect(await pixel(x, y), background);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(FlatCollapseChevron)),
    );
    // 淡入动画在按下后的第一帧才开始计时。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(await pixel(x, y), isNot(background));
    await gesture.cancel();
  });
}
