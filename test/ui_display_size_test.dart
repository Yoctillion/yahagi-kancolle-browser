import 'package:flutter_test/flutter_test.dart';
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

  test('usesMinimalGameShell only for minimal game page landscape non-hd', () {
    bool shell(UiDisplaySize size, int index, bool landscape, bool hd) =>
        usesMinimalGameShell(
          size: size,
          workspaceIndex: index,
          isLandscape: landscape,
          hd: hd,
        );
    expect(shell(UiDisplaySize.minimal, 0, true, false), isTrue);
    expect(shell(UiDisplaySize.minimal, 1, true, false), isFalse);
    expect(shell(UiDisplaySize.minimal, 0, false, false), isFalse);
    expect(shell(UiDisplaySize.minimal, 0, true, true), isFalse);
    expect(shell(UiDisplaySize.compact, 0, true, false), isFalse);
  });

  test('usesFlatPanel', () {
    expect(usesFlatPanel(size: UiDisplaySize.minimal, hd: false), isTrue);
    expect(usesFlatPanel(size: UiDisplaySize.minimal, hd: true), isFalse);
    expect(usesFlatPanel(size: UiDisplaySize.compact, hd: false), isFalse);
  });
}
