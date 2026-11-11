import 'package:flutter/material.dart';

import '../game_state/game_state.dart';
import '../layout/flat_style.dart';
import '../localization/game_name_localizations.dart';
import 'battle_air_report.dart';
import 'battle_detail_strings.dart';
import 'battle_models.dart';

const _none = '—';

String _equipmentLabel(
  BuildContext context,
  Map<int, MasterSlotItem> slotItems,
  int id,
) {
  final raw = slotItems[id]?.name;
  return raw == null ? 'ID: $id' : gameNames(context).equipmentName(raw);
}

// lost 为 0 也显示「−0」，让「没损失」与「没数据」可区分。
TextSpan _planeSpan(PlaneCount count, Color lossColor) => TextSpan(
  children: [
    TextSpan(text: '${count.count} '),
    TextSpan(
      text: '−${count.lost}',
      style: TextStyle(color: lossColor),
    ),
  ],
);

class _SectionFrame extends StatelessWidget {
  const _SectionFrame({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: flatDividerColor)),
    ),
    child: Padding(
      padding: const EdgeInsets.only(top: flatSectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}

class FlatAirBattleSection extends StatelessWidget {
  const FlatAirBattleSection({
    super.key = const Key('flat-air-section'),
    required this.report,
    required this.friendShips,
    required this.slotItems,
  });

  final DayAirReport report;

  /// `[...friendMain, ...friendEscort]`; AACI positions >= 6 index the escort.
  final List<BattleShipSnapshot> friendShips;
  final Map<int, MasterSlotItem> slotItems;

  String _phaseLabel(BattleDetailStrings s, AirPhaseLine line) =>
      switch (line.kind) {
        AirPhaseKind.landBaseJet => s.landBaseJet,
        AirPhaseKind.landBase => s.landBaseWave(
          line.baseId ?? 0,
          line.wave ?? 0,
        ),
        AirPhaseKind.friendly => s.friendlyAir,
        AirPhaseKind.supportAir => s.supportAir,
        AirPhaseKind.supportShelling => s.supportShelling,
        AirPhaseKind.supportTorpedo => s.supportTorpedo,
        AirPhaseKind.supportAntiSub => s.supportAntiSub,
      };

  @override
  Widget build(BuildContext context) {
    final s = BattleDetailStrings.of(context);
    final children = <Widget>[];
    if (report.hasMainTable) {
      children.add(_mainTable(context, s));
      for (final ci in report.antiAirCutIns) {
        final index = ci.position;
        final ship = index >= 0 && index < friendShips.length
            ? friendShips[index]
            : null;
        final name = ship == null
            ? '#${index + 1}'
            : gameNames(context).shipName(ship.name, shipId: ship.masterId);
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: flatRowSpacing),
            child: Text(
              '${s.antiAirCutIn} $name（${s.antiAirKind(ci.kind)}）',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: flatAirPhaseFontSize,
                color: flatMutedColor,
              ),
            ),
          ),
        );
      }
    }
    if (report.phases.isNotEmpty) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: flatSectionGap));
      }
      children.add(_phaseRows(context, s));
    }
    return _SectionFrame(children: children);
  }

  Widget _mainTable(BuildContext context, BattleDetailStrings s) {
    const headStyle = TextStyle(
      fontSize: flatAirHeadFontSize,
      color: flatMutedColor,
    );
    const cellStyle = TextStyle(fontSize: flatAirTableFontSize);
    final hasContact =
        report.friendContactPlaneId > 0 || report.enemyContactPlaneId > 0;
    final friendContact = report.friendContactPlaneId > 0
        ? _equipmentLabel(context, slotItems, report.friendContactPlaneId)
        : _none;
    final enemyContact = report.enemyContactPlaneId > 0
        ? _equipmentLabel(context, slotItems, report.enemyContactPlaneId)
        : _none;
    final title = report.secondWave ? '${s.airBattle} ×2' : s.airBattle;

    Widget cell(PlaneCount? count, Color lossColor) => count == null
        ? const Text(_none, style: cellStyle)
        : Text.rich(_planeSpan(count, lossColor), style: cellStyle);

    TableRow row(String label, PlaneExchange? exchange) => TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Text(label, style: headStyle),
        ),
        cell(exchange?.friend, flatAllyLossColor),
        cell(exchange?.enemy, flatEnemyLossColor),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: flatAirHeadFontSize,
                color: flatSectionTitleColor,
              ),
            ),
            if (hasContact) ...[
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${s.airContact} $friendContact / $enemyContact',
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: headStyle,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: flatRowSpacing),
        Table(
          columnWidths: const {
            0: IntrinsicColumnWidth(),
            1: FlexColumnWidth(),
            2: FlexColumnWidth(),
          },
          children: [
            TableRow(
              children: [
                const SizedBox.shrink(),
                Text(s.airAlly, style: headStyle),
                Text(s.airEnemy, style: headStyle),
              ],
            ),
            if (report.jet != null) row(s.airJet, report.jet),
            row(s.airFighter, report.fighter),
            row(s.airAntiAir, report.antiAir),
          ],
        ),
      ],
    );
  }

  Widget _phaseRows(BuildContext context, BattleDetailStrings s) {
    const style = TextStyle(fontSize: flatAirPhaseFontSize);
    const labelStyle = TextStyle(
      fontSize: flatAirPhaseFontSize,
      color: flatMutedColor,
    );
    final labels = [for (final line in report.phases) _phaseLabel(s, line)];
    final scaler = MediaQuery.textScalerOf(context);
    var labelWidth = 0.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      if (painter.width > labelWidth) labelWidth = painter.width;
      painter.dispose();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: flatRowSpacing),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: labelWidth.ceilToDouble() + 1,
                  child: Text(labels[i], style: labelStyle, softWrap: false),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text.rich(
                    _phaseSpan(s, report.phases[i]),
                    style: style,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  TextSpan _phaseSpan(BattleDetailStrings s, AirPhaseLine line) {
    final parts = <InlineSpan>[];
    void add(InlineSpan span) {
      if (parts.isNotEmpty) parts.add(const TextSpan(text: ' · '));
      parts.add(span);
    }

    final friend = line.planes.friend;
    final enemy = line.planes.enemy;
    if (friend != null) {
      add(
        TextSpan(
          children: [
            TextSpan(text: '${s.airAllyShort} '),
            _planeSpan(friend, flatAllyLossColor),
          ],
        ),
      );
    }
    if (enemy != null) {
      add(
        TextSpan(
          children: [
            TextSpan(text: '${s.airEnemyShort} '),
            _planeSpan(enemy, flatEnemyLossColor),
          ],
        ),
      );
    }
    if (line.damage != null) {
      add(
        TextSpan(
          text: '${s.airDamage} ${line.damage}',
          style: const TextStyle(color: flatAccentColor),
        ),
      );
    }
    return TextSpan(children: parts);
  }
}

class FlatNightBattleSection extends StatelessWidget {
  const FlatNightBattleSection({
    super.key = const Key('flat-night-section'),
    required this.report,
    required this.friendMain,
    required this.friendEscort,
    required this.enemyEscort,
    required this.slotItems,
  });

  final NightReport report;
  final List<BattleShipSnapshot> friendMain;
  final List<BattleShipSnapshot> friendEscort;
  final List<BattleShipSnapshot> enemyEscort;
  final Map<int, MasterSlotItem> slotItems;

  @override
  Widget build(BuildContext context) {
    final s = BattleDetailStrings.of(context);
    const style = TextStyle(fontSize: flatAirPhaseFontSize);
    const labelStyle = TextStyle(
      fontSize: flatAirPhaseFontSize,
      color: flatMutedColor,
    );
    Widget line(String label, String body, {Color? bodyColor}) => Padding(
      padding: const EdgeInsets.only(top: flatRowSpacing),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$label  ', style: labelStyle),
            TextSpan(
              text: body,
              style: bodyColor == null ? null : TextStyle(color: bodyColor),
            ),
          ],
        ),
        style: style,
      ),
    );

    final children = <Widget>[
      Text(
        s.nightBattle,
        style: const TextStyle(
          fontSize: flatAirHeadFontSize,
          color: flatSectionTitleColor,
        ),
      ),
    ];
    final friendContact = report.friendContactPlaneId > 0;
    final enemyContact = report.enemyContactPlaneId > 0;
    if (friendContact || enemyContact) {
      final parts = <String>[
        if (friendContact)
          '${s.airAllyShort} ${_equipmentLabel(context, slotItems, report.friendContactPlaneId)}',
        if (enemyContact)
          '${s.airEnemyShort} ${_equipmentLabel(context, slotItems, report.enemyContactPlaneId)}',
      ];
      children.add(line(s.nightContact, parts.join(' · ')));
    }
    final friendFlare = report.friendFlarePosition;
    final enemyFlare = report.enemyFlarePosition;
    if (friendFlare >= 0 || enemyFlare >= 0) {
      final enemyIndex = enemyEscort.isNotEmpty ? enemyFlare % 6 : enemyFlare;
      final parts = <String>[
        if (friendFlare >= 0)
          '${s.airAllyShort} ${_friendFlare(context, friendFlare)}',
        if (enemyFlare >= 0) '${s.airEnemyShort} #${enemyIndex + 1}',
      ];
      children.add(line(s.starShell, parts.join(' · ')));
    }
    if (report.supportDamage != null) {
      children.add(
        line(
          s.nightSupport,
          '· ${s.airDamage} ${report.supportDamage}',
          bodyColor: flatAccentColor,
        ),
      );
    }
    return _SectionFrame(children: children);
  }

  // 联合舰队夜战由随伴舰队打，api_flare_pos 要折回随伴；单舰队 7 艘时 raw 可为 6。
  String _friendFlare(BuildContext context, int raw) {
    final combined = friendEscort.isNotEmpty;
    final index = combined ? raw % 6 : raw;
    final fleet = combined ? friendEscort : friendMain;
    final label = '#${index + 1}';
    if (index >= fleet.length) return label;
    final ship = fleet[index];
    return '$label ${gameNames(context).shipName(ship.name, shipId: ship.masterId)}';
  }
}
