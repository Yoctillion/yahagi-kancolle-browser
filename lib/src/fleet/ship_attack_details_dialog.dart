import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import 'fleet_ui_strings.dart';
import 'ship_attack/attack_profile.dart';

const _conditionSegments = <String>[
  FleetUiKeys.lineAhead,
  FleetUiKeys.parallelEngagement,
  FleetUiKeys.airSupremacy,
  FleetUiKeys.undamaged,
  FleetUiKeys.ignoresArmorAndAccuracy,
];

Future<void> showShipAttackDetailsDialog(
  BuildContext context, {
  required String title,
  required AttackPhaseProfile? phase,
  required bool omitsBombingBonus,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final textColor = appColor(context, const Color(0xffe1e9ed));
      final mutedColor = appColor(context, const Color(0xffa9bac4));
      final conditions = <String>[
        ..._conditionSegments,
        if (omitsBombingBonus) FleetUiKeys.bombingBonusExcluded,
      ].map((segment) => fleetText(context, segment)).join(' · ');
      return AlertDialog(
        backgroundColor: appColor(context, const Color(0xff142735)),
        title: Text(
          fleetText(context, title),
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: phase == null
              ? Text(
                  fleetText(context, FleetUiKeys.notParticipating),
                  style: TextStyle(color: textColor),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AttackTable(
                      phase: phase,
                      textColor: textColor,
                      mutedColor: mutedColor,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${fleetText(context, FleetUiKeys.expected)} '
                      '${phase.expectedPower.round()}',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      conditions,
                      style: TextStyle(color: mutedColor, fontSize: 11),
                    ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(fleetText(context, FleetUiKeys.confirm)),
          ),
        ],
      );
    },
  );
}

class _AttackTable extends StatelessWidget {
  const _AttackTable({
    required this.phase,
    required this.textColor,
    required this.mutedColor,
  });

  final AttackPhaseProfile phase;
  final Color textColor;
  final Color mutedColor;

  @override
  Widget build(BuildContext context) {
    final header = TextStyle(
      color: mutedColor,
      fontSize: 11,
      fontWeight: FontWeight.w700,
    );
    final cell = TextStyle(
      color: textColor,
      fontSize: 13,
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget padded(Widget child, {bool end = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: Align(
        alignment: end ? Alignment.centerRight : Alignment.centerLeft,
        child: child,
      ),
    );
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(3),
        1: FlexColumnWidth(2),
        2: FlexColumnWidth(2),
        3: FlexColumnWidth(2),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            padded(
              Text(fleetText(context, FleetUiKeys.attackStyle), style: header),
            ),
            padded(
              Text(fleetText(context, FleetUiKeys.triggerRate), style: header),
              end: true,
            ),
            padded(
              Text(
                fleetText(context, FleetUiKeys.powerModifier),
                style: header,
              ),
              end: true,
            ),
            padded(
              Text(fleetText(context, FleetUiKeys.attackPower), style: header),
              end: true,
            ),
          ],
        ),
        for (final row in phase.rows)
          TableRow(
            children: [
              padded(Text(fleetText(context, row.label), style: cell)),
              padded(
                Text('${(row.rate * 100).round()}%', style: cell),
                end: true,
              ),
              padded(Text(_modifierText(row), style: cell), end: true),
              padded(
                row.capped
                    ? Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '${row.powerPerHit}'),
                            TextSpan(
                              text:
                                  ' ${fleetText(context, FleetUiKeys.powerCap)}',
                              style: TextStyle(color: mutedColor, fontSize: 9),
                            ),
                          ],
                        ),
                        style: cell,
                      )
                    : Text('${row.powerPerHit}', style: cell),
                end: true,
              ),
            ],
          ),
      ],
    );
  }

  static String _modifierText(AttackStyleRow row) {
    final hits = row.hits == 1 ? '' : '×${_number(row.hits)}';
    return '×${_number(row.powerMod)}$hits';
  }

  static String _number(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}
