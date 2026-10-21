import 'package:flutter/widgets.dart';

/// 模块编辑列表里的卡片一律强制折叠，标题行的折叠按钮点了也不会展开。
class DashboardEditingScope extends InheritedWidget {
  const DashboardEditingScope({super.key, required super.child});
  static bool isEditing(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DashboardEditingScope>() !=
      null;
  @override
  bool updateShouldNotify(DashboardEditingScope oldWidget) => false;
}
