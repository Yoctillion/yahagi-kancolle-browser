import 'package:flutter/material.dart';

import '../layout/flat_style.dart';
import '../layout/panel_style.dart';
import '../theme/app_palette.dart';
import 'prophet_hp_bar.dart';

Color battleDividerColor(BuildContext context) => appColor(
  context,
  PanelStyleScope.isFlat(context) ? flatDividerColor : const Color(0xff203746),
);

const battleFleetTitleStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w800,
);

/// Reserves the height of a ship row's HP column, so a row without one still
/// lines up with its neighbor in the next fleet column.
class BattleShipRowStrut extends StatelessWidget {
  const BattleShipRowStrut({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 0,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
        SizedBox(height: 2 + prophetHpBarHeight),
      ],
    ),
  );
}

/// 战斗面板里一支舰队的分块：标题加分隔线隔开的各行；扁平档去掉底块。
class BattleFleetBlock extends StatelessWidget {
  const BattleFleetBlock({super.key, required this.title, required this.rows});

  final Widget title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final flat = PanelStyleScope.isFlat(context);
    final divider = Divider(height: 1, color: battleDividerColor(context));
    return Container(
      decoration: flat
          ? null
          : BoxDecoration(
              color: appColor(context, const Color(0xff10212e)),
              borderRadius: BorderRadius.circular(8),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: flat
                ? const EdgeInsets.fromLTRB(0, 2, 0, 2)
                : const EdgeInsets.fromLTRB(9, 7, 9, 5),
            child: title,
          ),
          for (var index = 0; index < rows.length; index++) ...<Widget>[
            if (index > 0) divider,
            rows[index],
          ],
        ],
      ),
    );
  }
}
