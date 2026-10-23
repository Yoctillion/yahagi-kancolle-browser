import 'package:flutter/widgets.dart';

enum PanelStyle { card, flat }

class PanelStyleScope extends InheritedWidget {
  const PanelStyleScope({super.key, required this.style, required super.child});
  final PanelStyle style;
  static PanelStyle of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PanelStyleScope>()?.style ??
      PanelStyle.card;
  static bool isFlat(BuildContext context) => of(context) == PanelStyle.flat;
  @override
  bool updateShouldNotify(PanelStyleScope oldWidget) =>
      style != oldWidget.style;
}
