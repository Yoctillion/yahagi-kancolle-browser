import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/layout/display_corners.dart';
import 'package:yahagi_kancolle_browser/src/layout/minimal_layout.dart';
import 'package:yahagi_kancolle_browser/src/settings/ui_display_size.dart';

void main() {
  test('minimal size values', () {
    const size = UiDisplaySize.minimal;
    expect(workspaceNavigationExtent(size), 34.0);
    expect(topHeaderHeight(size), 28.0);
    expect(headerCapsuleHeight(size), 22.0);
    expect(browserToolbarHeight(size), 30.0);
  });

  test('isCompactOrSmaller', () {
    expect(UiDisplaySize.normal.isCompactOrSmaller, isFalse);
    expect(UiDisplaySize.compact.isCompactOrSmaller, isTrue);
    expect(UiDisplaySize.minimal.isCompactOrSmaller, isTrue);
    expect(UiDisplaySize.minimal.isMinimal, isTrue);
    expect(UiDisplaySize.compact.isMinimal, isFalse);
  });

  test('usesMinimalShell only for minimal landscape non-hd', () {
    bool shell(UiDisplaySize size, bool landscape, bool hd) =>
        usesMinimalShell(size: size, isLandscape: landscape, hd: hd);
    expect(shell(UiDisplaySize.minimal, true, false), isTrue);
    expect(shell(UiDisplaySize.minimal, false, false), isFalse);
    expect(shell(UiDisplaySize.minimal, true, true), isFalse);
    expect(shell(UiDisplaySize.compact, true, false), isFalse);
  });

  test('usesFlatPanel', () {
    expect(usesFlatPanel(size: UiDisplaySize.minimal, hd: false), isTrue);
    expect(usesFlatPanel(size: UiDisplaySize.minimal, hd: true), isFalse);
    expect(usesFlatPanel(size: UiDisplaySize.compact, hd: false), isFalse);
  });
  test('effectiveUiDisplaySize treats minimal as compact under HD', () {
    expect(
      effectiveUiDisplaySize(UiDisplaySize.minimal, hd: true),
      UiDisplaySize.compact,
    );
    expect(
      effectiveUiDisplaySize(UiDisplaySize.minimal, hd: false),
      UiDisplaySize.minimal,
    );
    for (final size in [UiDisplaySize.normal, UiDisplaySize.compact]) {
      expect(effectiveUiDisplaySize(size, hd: true), size);
      expect(effectiveUiDisplaySize(size, hd: false), size);
    }
  });

  group('minimalNavigationInsets', () {
    const corners = CornerRadii(
      topLeft: 10,
      topRight: 20,
      bottomLeft: 30,
      bottomRight: 40,
    );

    test('vertical rail clears its own corners and the bottom inset', () {
      expect(
        minimalNavigationInsets(
          corners: corners,
          bottomSafeArea: 0,
          horizontal: false,
          onRight: false,
        ),
        EdgeInsets.only(top: cornerInset(10), bottom: cornerInset(30)),
      );
      expect(
        minimalNavigationInsets(
          corners: corners,
          bottomSafeArea: 48,
          horizontal: false,
          onRight: true,
        ),
        EdgeInsets.only(top: cornerInset(20), bottom: 48),
      );
    });

    test('horizontal bar clears bottom corners only at screen edges', () {
      expect(
        minimalNavigationInsets(
          corners: corners,
          bottomSafeArea: 48,
          horizontal: true,
          onRight: false,
        ),
        EdgeInsets.only(left: cornerInset(30), right: cornerInset(40)),
      );
      expect(
        minimalNavigationInsets(
          corners: corners,
          bottomSafeArea: 48,
          horizontal: true,
          onRight: false,
          rightAtEdge: false,
        ),
        EdgeInsets.only(left: cornerInset(30)),
      );
    });
  });
}
