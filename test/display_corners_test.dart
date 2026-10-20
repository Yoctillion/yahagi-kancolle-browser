import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/layout/display_corners.dart';

const _channel = MethodChannel('app.yahagi.kancollebrowser/display_corners');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('cornerInset removes the part of the radius a square corner covers', () {
    expect(cornerInset(32), closeTo(9.37, 0.01));
    expect(cornerInset(0), 0);
  });

  test('refresh converts px to dp and falls back per missing corner', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          expect(call.method, 'getRoundedCorners');
          return <String, Object?>{
            'topLeft': 96,
            'topRight': 96,
            'bottomLeft': null,
            'bottomRight': 96,
          };
        });
    final controller = DisplayCornersController();
    addTearDown(controller.dispose);

    await controller.refresh(3.0);

    expect(controller.radii.topLeft, 32);
    expect(controller.radii.topRight, 32);
    expect(controller.radii.bottomLeft, 24);
    expect(controller.radii.bottomRight, 32);
  });

  test('null channel result uses the fallback radii', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async => null);
    final controller = DisplayCornersController();
    addTearDown(controller.dispose);

    await controller.refresh(2.0);

    expect(controller.radii, CornerRadii.fallback);
  });

  test('missing plugin uses the fallback radii', () async {
    final controller = DisplayCornersController();
    addTearDown(controller.dispose);

    await controller.refresh(2.0);

    expect(controller.radii, CornerRadii.fallback);
  });

  testWidgets('DisplayCorners.of returns fallback without an ancestor', (
    tester,
  ) async {
    late CornerRadii radii;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          radii = DisplayCorners.of(context);
          return const SizedBox.shrink();
        },
      ),
    );

    expect(radii, CornerRadii.fallback);
  });

  Future<CornerRadii> radiiOn(
    WidgetTester tester,
    TargetPlatform platform,
    EdgeInsets padding,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    late CornerRadii radii;
    try {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(viewPadding: padding),
          child: Builder(
            builder: (context) {
              radii = DisplayCorners.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    return radii;
  }

  testWidgets('iOS with safe area uses the full-screen iPhone radius', (
    tester,
  ) async {
    final radii = await radiiOn(
      tester,
      TargetPlatform.iOS,
      const EdgeInsets.only(left: 59, bottom: 21),
    );
    expect(radii, const CornerRadii.all(55));
  });

  testWidgets('iOS without safe area keeps the fallback', (tester) async {
    final radii = await radiiOn(tester, TargetPlatform.iOS, EdgeInsets.zero);
    expect(radii, CornerRadii.fallback);
  });

  testWidgets('Android with safe area keeps the fallback', (tester) async {
    final radii = await radiiOn(
      tester,
      TargetPlatform.android,
      const EdgeInsets.only(left: 59, bottom: 21),
    );
    expect(radii, CornerRadii.fallback);
  });

  testWidgets('DisplayCorners.of reads the controller radii', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          _channel,
          (call) async => <String, Object?>{
            'topLeft': 40,
            'topRight': 40,
            'bottomLeft': 40,
            'bottomRight': 40,
          },
        );
    final controller = DisplayCornersController();
    addTearDown(controller.dispose);
    late CornerRadii radii;
    await tester.pumpWidget(
      DisplayCorners(
        notifier: controller,
        child: Builder(
          builder: (context) {
            radii = DisplayCorners.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await controller.refresh(2.0);
    await tester.pump();

    expect(radii.topLeft, 20);
  });
}
