import 'package:flutter/material.dart';

import '../game_state/game_state.dart';
import '../layout/flat_style.dart';
import '../localization/game_name_localizations.dart';
import '../theme/app_palette.dart';
import 'battle_air_report.dart';
import 'battle_detail_strings.dart';
import 'battle_models.dart';

String _equipmentLabel(
  BuildContext context,
  Map<int, MasterSlotItem> slotItems,
  int id,
) {
  final raw = slotItems[id]?.name;
  return raw == null ? 'ID: $id' : gameNames(context).equipmentName(raw);
}

// lost 为 0 也显示「−0」，让「没损失」与「没数据」可区分。
TextSpan _planeSpan(BuildContext context, PlaneCount count, Color lossColor) =>
    TextSpan(
      children: [
        TextSpan(text: '${count.count} '),
        TextSpan(
          text: '−${count.lost}',
          style: TextStyle(color: appColor(context, lossColor)),
        ),
      ],
    );

class _SectionFrame extends StatelessWidget {
  const _SectionFrame({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: appColor(context, flatDividerColor)),
      ),
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
  });

  final DayAirReport report;

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

  /// Land-base and support rows; the main exchange is [FlatAirSummaryLine].
  static bool hasContent(DayAirReport? report) =>
      report != null && report.phases.isNotEmpty;

  @override
  Widget build(BuildContext context) => _SectionFrame(
    children: [_phaseRows(context, BattleDetailStrings.of(context))],
  );

  Widget _phaseRows(BuildContext context, BattleDetailStrings s) {
    const style = TextStyle(fontSize: flatAirPhaseFontSize);
    final labelStyle = TextStyle(
      fontSize: flatAirPhaseFontSize,
      color: appColor(context, flatMutedColor),
    );
    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
      children: [
        for (final line in report.phases)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  right: 6,
                  bottom: flatRowSpacing,
                ),
                child: Text(
                  _phaseLabel(s, line),
                  style: labelStyle,
                  softWrap: false,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: flatRowSpacing),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    _phaseSpan(context, s, line),
                    style: style,
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  TextSpan _phaseSpan(
    BuildContext context,
    BattleDetailStrings s,
    AirPhaseLine line,
  ) {
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
            _planeSpan(context, friend, flatAllyLossColor),
          ],
        ),
      );
    }
    if (enemy != null) {
      add(
        TextSpan(
          children: [
            TextSpan(text: '${s.airEnemyShort} '),
            _planeSpan(context, enemy, flatEnemyLossColor),
          ],
        ),
      );
    }
    if (line.damage != null) {
      add(
        TextSpan(
          text: '${s.airDamage} ${line.damage}',
          style: TextStyle(color: appColor(context, flatAccentColor)),
        ),
      );
    }
    return TextSpan(children: parts);
  }
}

/// The day air exchange as one full-width line split like the fleet grid:
/// friend on the left half, enemy on the right. Each half lists the stages
/// in battle order as "sortie −lost", the loss set smaller and the jet strike
/// in gold. A ground behind it would follow the two text sizes unevenly.
class FlatAirExchangeLine extends StatelessWidget {
  const FlatAirExchangeLine({
    super.key = const Key('flat-air-exchange'),
    required this.report,
  });

  final DayAirReport report;

  static bool hasContent(DayAirReport? report) =>
      report != null && report.hasMainTable;

  static const double fontSize = 10;
  static const double lossFontSize = 8.5;

  Widget _half(BuildContext context, {required bool friend}) {
    PlaneCount? pick(PlaneExchange? exchange) =>
        friend ? exchange?.friend : exchange?.enemy;
    final lossColor = appColor(
      context,
      friend ? flatAllyLossColor : flatEnemyLossColor,
    );
    final jetColor = appColor(context, flatJetColor);
    final spans = <InlineSpan>[];
    void stage(PlaneCount? count, {bool jet = false}) {
      if (count == null) return;
      if (spans.isNotEmpty) spans.add(const TextSpan(text: '  '));
      spans.add(
        TextSpan(
          text: '${count.count}',
          style: jet ? TextStyle(color: jetColor) : null,
        ),
      );
      spans.add(
        TextSpan(
          text: '−${count.lost}',
          style: TextStyle(
            fontSize: lossFontSize,
            color: jet ? jetColor : lossColor,
          ),
        ),
      );
    }

    stage(pick(report.jet), jet: true);
    stage(pick(report.fighter));
    stage(pick(report.antiAir));
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Text.rich(
        TextSpan(children: spans),
        key: Key(
          friend ? 'flat-air-exchange-friend' : 'flat-air-exchange-enemy',
        ),
        maxLines: 1,
        softWrap: false,
        style: appTextStyle(
          context,
          const TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: _half(context, friend: true)),
      // The fleet grid's gap, so each half sits over its fleet.
      const SizedBox(width: 6),
      Expanded(child: _half(context, friend: false)),
    ],
  );
}

/// Contact planes and anti-air cut-ins of the day air battle, as tag line
/// segments.
List<String> flatAirExtras(
  BuildContext context, {
  required DayAirReport report,
  required List<BattleShipSnapshot> friendMain,
  // AACI positions >= 6 index the escort when the fleet is combined.
  required List<BattleShipSnapshot> friendEscort,
  required Map<int, MasterSlotItem> slotItems,
}) {
  final s = BattleDetailStrings.of(context);
  String plane(int id) => _equipmentLabel(context, slotItems, id);
  String cutInShip(int index) {
    final inEscort = friendEscort.isNotEmpty && index >= 6;
    final fleet = inEscort ? friendEscort : friendMain;
    final fleetIndex = inEscort ? index - 6 : index;
    if (fleetIndex < 0 || fleetIndex >= fleet.length) return '#${index + 1}';
    final ship = fleet[fleetIndex];
    return gameNames(context).shipName(ship.name, shipId: ship.masterId);
  }

  final contacts = <String>[
    if (report.friendContactPlaneId > 0)
      '${s.airAllyShort} ${plane(report.friendContactPlaneId)}',
    if (report.enemyContactPlaneId > 0)
      '${s.airEnemyShort} ${plane(report.enemyContactPlaneId)}',
  ];
  return <String>[
    if (report.secondWave) s.airBattleTwice,
    if (contacts.isNotEmpty) '${s.airContact} ${contacts.join(' / ')}',
    for (final ci in report.antiAirCutIns)
      '${s.antiAirCutIn} ${cutInShip(ci.position)}(${ci.kind})',
  ];
}

class FlatNightBattleSection extends StatelessWidget {
  const FlatNightBattleSection({
    super.key = const Key('flat-night-section'),
    required this.report,
    required this.friendMain,
    required this.friendEscort,
    required this.enemyMain,
    required this.enemyEscort,
    required this.slotItems,
  });

  final NightReport report;
  final List<BattleShipSnapshot> friendMain;
  final List<BattleShipSnapshot> friendEscort;
  final List<BattleShipSnapshot> enemyMain;
  final List<BattleShipSnapshot> enemyEscort;
  final Map<int, MasterSlotItem> slotItems;

  @override
  Widget build(BuildContext context) {
    final s = BattleDetailStrings.of(context);
    const style = TextStyle(fontSize: flatAirPhaseFontSize);
    final labelStyle = TextStyle(
      fontSize: flatAirPhaseFontSize,
      color: appColor(context, flatMutedColor),
    );
    Widget line(String label, String body, {Color? bodyColor}) => Padding(
      padding: const EdgeInsets.only(top: flatRowSpacing),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$label  ', style: labelStyle),
            TextSpan(
              text: body,
              style: bodyColor == null
                  ? null
                  : TextStyle(color: appColor(context, bodyColor)),
            ),
          ],
        ),
        style: style,
      ),
    );

    final children = <Widget>[
      Text(
        s.nightBattle,
        style: TextStyle(
          fontSize: flatAirHeadFontSize,
          color: appColor(context, flatSectionTitleColor),
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
        if (enemyFlare >= 0)
          '${s.airEnemyShort} ${_enemyFlare(context, enemyIndex)}',
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

  // 敌联合舰队时 raw 所属舰队不可考，只给序号。
  String _enemyFlare(BuildContext context, int index) {
    final label = '#${index + 1}';
    if (enemyEscort.isNotEmpty || index < 0 || index >= enemyMain.length) {
      return label;
    }
    final ship = enemyMain[index];
    return '$label ${gameNames(context).shipName(ship.name, shipId: ship.masterId)}';
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
