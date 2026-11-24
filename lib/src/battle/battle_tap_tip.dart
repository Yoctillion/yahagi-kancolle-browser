import 'package:flutter/material.dart';

import '../layout/flat_style.dart';
import '../theme/app_palette.dart';

/// A small tip for the battle panels that opens on tap, since phones have no
/// hover; a mouse still opens it by hovering.
class BattleTapTip extends StatelessWidget {
  const BattleTapTip({
    super.key,
    this.message,
    this.richMessage,
    required this.child,
  }) : assert((message == null) != (richMessage == null));

  final String? message;
  final InlineSpan? richMessage;
  final Widget child;

  static const double fontSize = 10;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: message,
    richMessage: richMessage,
    triggerMode: TooltipTriggerMode.tap,
    showDuration: const Duration(seconds: 4),
    preferBelow: true,
    verticalOffset: 10,
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    textStyle: appTextStyle(
      context,
      const TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        height: 1.35,
        color: Color(0xffe5ebee),
      ),
    ),
    decoration: BoxDecoration(
      color: appColor(context, const Color(0xff192f3d)),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: appColor(context, flatDividerColor)),
    ),
    child: child,
  );
}
