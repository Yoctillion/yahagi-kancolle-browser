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

  test('cornerInsetAt follows the arc at a given distance from the edge', () {
    expect(cornerInsetAt(55, 0), 55);
    expect(cornerInsetAt(55, 6.5), closeTo(29.06, 0.01));
    expect(cornerInsetAt(55, 55), 0);
    expect(cornerInsetAt(55, 80), 0);
    expect(cornerInsetAt(55, -3), 55);
    expect(cornerInsetAt(0, 6.5), 0);
    // 45° 处与 cornerInset 一致。
    expect(cornerInsetAt(32, cornerInset(32)), closeTo(cornerInset(32), 1e-9));
  });

  test(
    'refresh converts px to dp and treats a null corner as square',
    () async {
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

      final radii = controller.radii!;
      expect(radii.topLeft, 32);
      expect(radii.topRight, 32);
      expect(radii.bottomLeft, 0);
      expect(radii.bottomRight, 32);
    },
  );

  test('null channel result leaves the radii unknown', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async => null);
    final controller = DisplayCornersController();
    addTearDown(controller.dispose);

    await controller.refresh(2.0);

    expect(controller.radii, isNull);
  });

  test('missing plugin leaves the radii unknown', () async {
    final controller = DisplayCornersController();
    addTearDown(controller.dispose);

    await controller.refresh(2.0);

    expect(controller.radii, isNull);
  });

  testWidgets('DisplayCorners.of treats Android as square without radii', (
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

    expect(radii, const CornerRadii.all(0));
  });

  Future<CornerRadii> radiiOn(
    WidgetTester tester,
    TargetPlatform platform,
    EdgeInsets padding, {
    Size size = const Size(852, 393),
  }) async {
    debugDefaultTargetPlatformOverride = platform;
    late CornerRadii radii;
    try {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: size, viewPadding: padding),
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

  testWidgets('iPhone SE style status bar keeps the fallback', (tester) async {
    final radii = await radiiOn(
      tester,
      TargetPlatform.iOS,
      const EdgeInsets.only(top: 20),
      size: const Size(375, 667),
    );
    expect(radii, CornerRadii.fallback);
  });

  testWidgets('iPad keeps the fallback', (tester) async {
    final radii = await radiiOn(
      tester,
      TargetPlatform.iOS,
      const EdgeInsets.only(top: 24),
      size: const Size(1180, 820),
    );
    expect(radii, CornerRadii.fallback);
  });

  testWidgets('iOS without safe area keeps the fallback', (tester) async {
    final radii = await radiiOn(tester, TargetPlatform.iOS, EdgeInsets.zero);
    expect(radii, CornerRadii.fallback);
  });

  testWidgets('Android without a reported radius stays square', (tester) async {
    final radii = await radiiOn(
      tester,
      TargetPlatform.android,
      const EdgeInsets.only(left: 59, bottom: 21),
    );
    expect(radii, const CornerRadii.all(0));
  });

  testWidgets('desktop without a reported radius keeps the fallback', (
    tester,
  ) async {
    final radii = await radiiOn(
      tester,
      TargetPlatform.windows,
      EdgeInsets.zero,
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
