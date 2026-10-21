import 'package:flutter/widgets.dart';
import '../theme/app_palette.dart';

TextDirection workspaceNavigationTextDirection({required bool menuOnRight}) =>
    menuOnRight ? TextDirection.rtl : TextDirection.ltr;

Border workspaceNavigationBorder({
  required bool menuOnRight,
  BuildContext? context,
}) {
  const source = Color(0xff294052);
  final divider = BorderSide(
    color: context == null ? source : appColor(context, source),
  );
  return menuOnRight ? Border(left: divider) : Border(right: divider);
}
