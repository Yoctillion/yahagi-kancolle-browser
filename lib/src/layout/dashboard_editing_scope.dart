import 'package:flutter/widgets.dart';

/// 模块编辑列表里的卡片一律强制折叠：折叠按钮点了也不会展开，所以不画；
/// 每行只剩标题，扁平档把行加高，方便点按和拖动。
class DashboardEditingScope extends InheritedWidget {
  const DashboardEditingScope({super.key, required super.child});
  static bool isEditing(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DashboardEditingScope>() !=
      null;
  @override
  bool updateShouldNotify(DashboardEditingScope oldWidget) => false;
}
