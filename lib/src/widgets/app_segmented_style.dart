import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// Shared appearance for mode/section selectors. Compact headers keep their
/// small rounded shape; page-level selectors keep the larger pill shape.
abstract final class AppSegmentedStyle {
  static const compactHeight = 26.0;
  static const regularHeight = 38.0;

  static Color background(BuildContext context) =>
      appColor(context, const Color(0xff10212e));
  static Color border(BuildContext context) =>
      appColor(context, const Color(0xff294052));
  static Color selectedBackground(BuildContext context) =>
      appColor(context, const Color(0xff5b4829));
  static Color selectedBorder(BuildContext context) =>
      appColor(context, const Color(0xff927440));
  static Color selection(BuildContext context, bool selected) =>
      selected ? selectedBackground(context) : Colors.transparent;
  static Color foreground(BuildContext context, bool selected) => appColor(
    context,
    selected ? const Color(0xffffcf67) : const Color(0xff8197a5),
  );

  static BorderRadius radius({bool compact = false}) =>
      BorderRadius.circular(compact ? 7 : 20);
  static BorderRadius itemRadius({bool compact = false}) =>
      BorderRadius.circular(compact ? 5 : 16);
  static EdgeInsets padding({bool compact = false}) =>
      EdgeInsets.all(compact ? 2 : 3);

  static BoxDecoration decoration(
    BuildContext context, {
    bool compact = false,
  }) => BoxDecoration(
    color: background(context),
    border: Border.all(color: border(context)),
    borderRadius: radius(compact: compact),
  );

  static TextStyle textStyle(
    BuildContext context, {
    required bool selected,
    bool compact = false,
    double? fontSize,
    FontWeight? fontWeight,
  }) => TextStyle(
    color: foreground(context, selected),
    fontSize: fontSize ?? (compact ? 10 : 12),
    fontWeight: fontWeight ?? (compact ? FontWeight.w700 : FontWeight.w800),
  );

  /// Material selectors use the same color roles without changing their native
  /// tap targets, keyboard handling, disabled state or selection semantics.
  static ButtonStyle materialStyle(BuildContext context) => ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? selectedBackground(
              context,
            ).withValues(alpha: states.contains(WidgetState.disabled) ? .5 : 1)
          : background(context),
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? foreground(context, false).withValues(alpha: .5)
          : foreground(context, states.contains(WidgetState.selected)),
    ),
    side: WidgetStatePropertyAll(BorderSide(color: border(context))),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: radius()),
    ),
  );
}
