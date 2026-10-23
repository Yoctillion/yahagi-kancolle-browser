import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_surface_viewport.dart';
import 'package:yahagi_kancolle_browser/src/settings/display_mode_store.dart';

const _gameAspectRatio = 1200.0 / 720.0;
const _surfaceKey = Key('test-game-surface');

void _expectFullyVisible(
  Rect rect,
  Size bounds,
  EdgeInsets padding, {
  String? reason,
}) {
  const tolerance = 0.001;
  expect(rect.width, greaterThan(0), reason: reason);
  expect(rect.height, greaterThan(0), reason: reason);
  expect(
    rect.width / rect.height,
    closeTo(_gameAspectRatio, tolerance),
    reason: reason,
  );
  expect(
    rect.left,
    greaterThanOrEqualTo(padding.left - tolerance),
    reason: reason,
  );
  expect(
    rect.top,
    greaterThanOrEqualTo(padding.top - tolerance),
    reason: reason,
  );
  expect(
    rect.right,
    lessThanOrEqualTo(bounds.width - padding.right + tolerance),
    reason: reason,
  );
  expect(
    rect.bottom,
    lessThanOrEqualTo(bounds.height - padding.bottom + tolerance),
    reason: reason,
  );
}

Future<void> _pumpViewport(
  WidgetTester tester, {
  required Size size,
  EdgeInsets padding = EdgeInsets.zero,
  double dpr = 1,
  bool isLandscape = true,
  DisplayMode displayMode = DisplayMode.auto,
}) async {
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = Size(size.width * dpr, size.height * dpr);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: size,
        devicePixelRatio: dpr,
        viewPadding: padding,
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: GameSurfaceViewport(
          aspectRatio: _gameAspectRatio,
          fullscreen: true,
          isLandscape: isLandscape,
          displayMode: displayMode,
          child: const SizedBox.expand(key: _surfaceKey),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('GameSurfaceViewport decision logic', () {
    test('uses width-priority for vertical layout and mobile split-screen', () {
      // Mobile portrait full-screen (412 x 915)
      expect(
        GameSurfaceViewport.shouldUseWidthPriority(
          width: 412,
          height: 915,
          isLandscape: false,
        ),
        isTrue,
      );

      // Split-screen window on phone (456 x 326, user reported issue)
      expect(
        GameSurfaceViewport.shouldUseWidthPriority(
          width: 456,
          height: 326,
          isLandscape: true, // Even if aspect ratio exceeds 1.35
          fullscreen: true,
        ),
        isTrue,
      );

      // Compact split-screen window (412 x 300)
      expect(
        GameSurfaceViewport.shouldUseWidthPriority(
          width: 412,
          height: 300,
          isLandscape: false,
        ),
        isTrue,
      );

      // Forced portrait mode
      expect(
        GameSurfaceViewport.shouldUseWidthPriority(
          width: 1280,
          height: 800,
          isLandscape: true,
          displayMode: DisplayMode.portrait,
        ),
        isTrue,
      );

      // Foldable unfolded split-screen (768 x 380, 800 x 400, 1024 x 500)
      for (final size in [
        const Size(768, 380),
        const Size(800, 400),
        const Size(1024, 500),
      ]) {
        expect(
          GameSurfaceViewport.shouldUseWidthPriority(
            width: size.width,
            height: size.height,
            isLandscape: true,
            displayMode: DisplayMode.auto,
          ),
          isTrue,
          reason:
              'Foldable split-screen $size must use width-priority in auto mode',
        );
        expect(
          GameSurfaceViewport.shouldUseWidthPriority(
            width: size.width,
            height: size.height,
            isLandscape: true,
            displayMode: DisplayMode.landscape,
          ),
          isTrue,
          reason:
              'Foldable split-screen $size must use width-priority in landscape mode',
        );
      }
    });

    test('uses contain mode for widescreen landscape displays', () {
      // Standard phone landscape gaming (915 x 412)
      expect(
        GameSurfaceViewport.shouldUseWidthPriority(
          width: 915,
          height: 412,
          isLandscape: true,
          displayMode: DisplayMode.auto,
        ),
        isFalse,
      );

      // Tablet / Desktop widescreen (1280 x 800)
      expect(
        GameSurfaceViewport.shouldUseWidthPriority(
          width: 1280,
          height: 800,
          isLandscape: true,
          displayMode: DisplayMode.auto,
        ),
        isFalse,
      );
    });
  });

  group('GameSurfaceViewport geometry calculation', () {
    test('contains the entire game when safe height cannot fit full width', () {
      const size = Size(456, 326);
      const padding = EdgeInsets.only(top: 48, bottom: 16);
      final rect = GameSurfaceViewport.computeWidthPriorityGameRect(
        containerWidth: size.width,
        containerHeight: size.height,
        aspectRatio: _gameAspectRatio,
        padding: padding,
      );

      _expectFullyVisible(rect, size, padding);
      expect(rect.height, closeTo(262, 0.001));
      expect(rect.width, closeTo(436.6666667, 0.001));
      expect(rect.left, closeTo(9.6666667, 0.001));
      expect(rect.top, closeTo(48, 0.001));
      expect(rect.bottom, closeTo(310, 0.001));
    });

    test('fills width and centers within sufficient safe height', () {
      const size = Size(400, 400);
      const padding = EdgeInsets.only(top: 40, bottom: 20);
      final rect = GameSurfaceViewport.computeWidthPriorityGameRect(
        containerWidth: size.width,
        containerHeight: size.height,
        aspectRatio: _gameAspectRatio,
        padding: padding,
      );

      _expectFullyVisible(rect, size, padding);
      expect(rect.left, 0);
      expect(rect.width, 400);
      expect(rect.height, closeTo(240, 0.001));
      expect(rect.top, closeTo(90, 0.001));
      expect(rect.bottom, closeTo(330, 0.001));
    });

    test(
      'fills only the available safe width when side insets are present',
      () {
        const size = Size(456, 326);
        const padding = EdgeInsets.fromLTRB(20, 48, 12, 16);
        final rect = GameSurfaceViewport.computeWidthPriorityGameRect(
          containerWidth: size.width,
          containerHeight: size.height,
          aspectRatio: _gameAspectRatio,
          padding: padding,
        );

        _expectFullyVisible(rect, size, padding);
        expect(rect.left, closeTo(20, 0.001));
        expect(rect.width, closeTo(424, 0.001));
        expect(rect.height, closeTo(254.4, 0.001));
        expect(rect.top, closeTo(51.8, 0.001));
      },
    );

    test('very short windows use safe height without clipping either edge', () {
      const size = Size(456, 80);
      const padding = EdgeInsets.only(top: 48, bottom: 16);
      final rect = GameSurfaceViewport.computeWidthPriorityGameRect(
        containerWidth: size.width,
        containerHeight: size.height,
        aspectRatio: _gameAspectRatio,
        padding: padding,
      );

      _expectFullyVisible(rect, size, padding);
      expect(rect.height, closeTo(16, 0.001));
      expect(rect.width, closeTo(26.6666667, 0.001));
      expect(rect.top, 48);
      expect(rect.bottom, 64);
    });

    test('exhausted safe height yields an empty rect inside the window', () {
      final rect = GameSurfaceViewport.computeWidthPriorityGameRect(
        containerWidth: 456,
        containerHeight: 40,
        aspectRatio: _gameAspectRatio,
        padding: const EdgeInsets.only(top: 48, bottom: 16),
      );

      expect(rect.size, Size.zero);
      expect(rect.left, inInclusiveRange(0, 456));
      expect(rect.top, inInclusiveRange(0, 40));
    });

    test('minimal centers contain rect above bottom inset', () {
      const ratio = 1200.0 / 720.0;
      const padding = EdgeInsets.only(bottom: 16);

      final wide = GameSurfaceViewport.computeContainGameRect(
        containerWidth: 629,
        containerHeight: 393,
        aspectRatio: ratio,
        padding: padding,
      );
      expect(wide.left, closeTo(0.33, 0.01));
      expect(wide.top, 0.0);
      expect(wide.width, closeTo(628.33, 0.01));
      expect(wide.height, closeTo(377, 0.001));

      final narrow = GameSurfaceViewport.computeContainGameRect(
        containerWidth: 500,
        containerHeight: 393,
        aspectRatio: ratio,
        padding: padding,
      );
      expect(narrow.left, 0.0);
      expect(narrow.width, closeTo(500, 0.001));
      expect(narrow.height, closeTo(300, 0.001));
      expect(narrow.top, closeTo(38.5, 0.001));
    });
  });

  group('GameSurfaceViewport widget rendering', () {
    testWidgets(
      'short split-screen fullscreen contains the game inside all safe edges',
      (tester) async {
        const windowSize = Size(456, 326);
        const padding = EdgeInsets.only(top: 48, bottom: 16);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await _pumpViewport(tester, size: windowSize, padding: padding);
        final rect = tester.getRect(find.byKey(_surfaceKey));
        _expectFullyVisible(rect, windowSize, padding);
        expect(rect.top, closeTo(48, 0.001));
        expect(rect.height, closeTo(262, 0.001));
        expect(rect.width, closeTo(436.6666667, 0.001));
      },
    );

    testWidgets(
      'renders contain mode in normal widescreen landscape without cropping',
      (tester) async {
        const windowSize = Size(915, 412);
        const padding = EdgeInsets.only(left: 48, right: 16);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await _pumpViewport(tester, size: windowSize, padding: padding);
        _expectFullyVisible(
          tester.getRect(find.byKey(_surfaceKey)),
          windowSize,
          padding,
        );
      },
    );

    testWidgets(
      'dragging split divider switches between safe-height contain and full width without replacing the element',
      (tester) async {
        const windowWidth = 456.0;
        const padding = EdgeInsets.only(top: 48, bottom: 16);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Element? originalElement;
        for (final height in [80.0, 200.0, 326.0, 337.6, 450.0, 600.0, 200.0]) {
          final windowSize = Size(windowWidth, height);
          await _pumpViewport(tester, size: windowSize, padding: padding);
          final finder = find.byKey(_surfaceKey);
          final rect = tester.getRect(finder);
          _expectFullyVisible(rect, windowSize, padding, reason: '$windowSize');
          if (height >= 337.6) {
            expect(rect.left, closeTo(0, 0.001));
            expect(rect.width, closeTo(windowWidth, 0.001));
          } else {
            expect(rect.top, closeTo(padding.top, 0.001));
            expect(rect.height, closeTo(height - padding.vertical, 0.001));
            expect(rect.width, lessThan(windowWidth));
          }
          originalElement ??= tester.element(finder);
          expect(tester.element(finder), same(originalElement));
        }
      },
    );

    testWidgets(
      'portrait landscape and auto modes preserve full visibility and element identity in a short window',
      (tester) async {
        const windowSize = Size(456, 326);
        const padding = EdgeInsets.only(top: 48, bottom: 16);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Element? originalElement;
        for (final mode in [
          DisplayMode.auto,
          DisplayMode.portrait,
          DisplayMode.landscape,
          DisplayMode.portrait,
          DisplayMode.auto,
        ]) {
          await _pumpViewport(
            tester,
            size: windowSize,
            padding: padding,
            isLandscape: mode == DisplayMode.landscape,
            displayMode: mode,
          );
          final finder = find.byKey(_surfaceKey);
          final rect = tester.getRect(finder);
          _expectFullyVisible(rect, windowSize, padding, reason: '$mode');
          expect(rect.height, closeTo(262, 0.001));
          originalElement ??= tester.element(finder);
          expect(tester.element(finder), same(originalElement));
        }
      },
    );

    testWidgets(
      'short unfolded foldable windows contain the complete game instead of cropping vertically',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final size in [
          const Size(768, 380),
          const Size(800, 400),
          const Size(1024, 500),
        ]) {
          await _pumpViewport(tester, size: size);
          final rect = tester.getRect(find.byKey(_surfaceKey));
          _expectFullyVisible(rect, size, EdgeInsets.zero, reason: '$size');
          expect(rect.top, closeTo(0, 0.001));
          expect(rect.height, closeTo(size.height, 0.001));
          expect(rect.width, lessThan(size.width));
          expect(rect.left, closeTo((size.width - rect.width) / 2, 0.001));
        }
      },
    );

    testWidgets(
      'DPR boundaries one physical pixel around full-width height never crop the game',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const padding = EdgeInsets.only(top: 48, bottom: 16);
        for (final dpr in [1.0, 2.0, 2.75, 3.5]) {
          final logicalWidth = 1440 / dpr;
          final fullWidthHeight = logicalWidth / _gameAspectRatio;
          for (final physicalDelta in [-1.0, 0.0, 1.0]) {
            final size = Size(
              logicalWidth,
              fullWidthHeight + padding.vertical + physicalDelta / dpr,
            );
            await _pumpViewport(
              tester,
              size: size,
              padding: padding,
              dpr: dpr,
              isLandscape: false,
            );
            final rect = tester.getRect(find.byKey(_surfaceKey));
            _expectFullyVisible(
              rect,
              size,
              padding,
              reason: 'DPR $dpr, physical height delta $physicalDelta',
            );
            if (physicalDelta < 0) {
              expect(
                rect.height,
                closeTo(size.height - padding.vertical, 0.001),
              );
              expect(rect.width, lessThan(logicalWidth));
            } else {
              expect(rect.width, closeTo(logicalWidth, 0.001));
              expect(rect.left, closeTo(0, 0.001));
            }
          }
        }
      },
    );

    testWidgets('minimal centers contain rect above bottom inset', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final (size, expected) in [
        (const Size(629, 393), const Rect.fromLTWH(0.33, 0, 628.33, 377)),
        (const Size(500, 393), const Rect.fromLTWH(0, 38.5, 500, 300)),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(
              size: size,
              viewPadding: const EdgeInsets.only(left: 30, bottom: 16),
            ),
            child: const Directionality(
              textDirection: TextDirection.ltr,
              child: GameSurfaceViewport(
                isLandscape: true,
                centerAboveBottomInset: true,
                child: SizedBox.expand(key: Key('test-game-surface')),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final rect = tester.getRect(find.byKey(const Key('test-game-surface')));
        expect(rect.left, closeTo(expected.left, 0.01));
        expect(rect.top, closeTo(expected.top, 0.01));
        expect(rect.width, closeTo(expected.width, 0.01));
        expect(rect.height, closeTo(expected.height, 0.01));
      }
    });
  });
}
