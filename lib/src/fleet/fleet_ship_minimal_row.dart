import 'package:flutter/material.dart';

import '../battle/prophet_hp_bar.dart';
import '../game_state/game_state.dart';
import '../layout/flat_portrait_backdrop.dart';
import '../layout/flat_style.dart';
import '../layout/game_edge_tap_guard.dart';
import '../localization/game_name_localizations.dart';
import '../settings/battle_status_effect_settings.dart';
import '../settings/fleet_display_options.dart';
import 'combat_mechanism.dart';
import 'equipment_display.dart';
import 'equipment_type_icon.dart';
import 'fleet_ship_type_label.dart';
import 'fleet_ui_strings.dart';
import 'ship_portrait.dart';
import 'ship_repair_status.dart';
import 'ship_speed_visual.dart';
import 'ship_status_style.dart';
import 'ship_status_visuals.dart';

enum MoraleBand { sparkle, normal, mild, tired, exhausted }

MoraleBand moraleBandOf(int value) => switch (value) {
  >= 50 => MoraleBand.sparkle,
  >= 40 => MoraleBand.normal,
  >= 30 => MoraleBand.mild,
  >= 20 => MoraleBand.tired,
  _ => MoraleBand.exhausted,
};

typedef _MoraleStyle = ({IconData icon, Color background, Color foreground});

_MoraleStyle _moraleStyle(MoraleBand band) => switch (band) {
  MoraleBand.sparkle => (
    icon: Icons.auto_awesome,
    background: const Color(0xff4a4214),
    foreground: const Color(0xfffff27a),
  ),
  MoraleBand.normal => (
    icon: Icons.sentiment_satisfied,
    background: const Color(0xff1f3443),
    foreground: const Color(0xffcbd5e1),
  ),
  MoraleBand.mild => (
    icon: Icons.sentiment_neutral,
    background: const Color(0xff2c3236),
    foreground: const Color(0xffe8c9a0),
  ),
  MoraleBand.tired => (
    icon: Icons.sentiment_dissatisfied,
    background: const Color(0xff4a2a12),
    foreground: shipFatigueColor(25),
  ),
  MoraleBand.exhausted => (
    icon: Icons.sentiment_very_dissatisfied,
    background: const Color(0xff4a1c1a),
    foreground: shipFatigueColor(10),
  ),
};

class MoraleChip extends StatefulWidget {
  const MoraleChip({super.key, required this.value, required this.sparkleMode});

  final int value;
  final MoraleSparkleMode sparkleMode;

  @override
  State<MoraleChip> createState() => _MoraleChipState();
}

class _MoraleChipState extends State<MoraleChip>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulse;

  bool get _sparkles =>
      widget.sparkleMode != MoraleSparkleMode.off &&
      moraleBandOf(widget.value) == MoraleBand.sparkle;

  bool get _blinks =>
      _sparkles && widget.sparkleMode == MoraleSparkleMode.blinking;

  void _syncPulse() {
    if (_blinks) {
      final pulse = _pulse ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1100),
      );
      if (!pulse.isAnimating) pulse.repeat(reverse: true);
    } else {
      _pulse?.stop();
    }
  }

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(MoraleChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  Widget _chip(_MoraleStyle style, double glow) => Container(
    height: 12,
    constraints: const BoxConstraints(minWidth: 28),
    padding: const EdgeInsets.symmetric(horizontal: 2),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: style.background,
      borderRadius: BorderRadius.circular(3),
      boxShadow: glow > 0
          ? [
              BoxShadow(
                color: const Color(0xfffff27a).withValues(alpha: 0.6 * glow),
                blurRadius: 5,
              ),
            ]
          : null,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(style.icon, size: 9, color: style.foreground),
        const SizedBox(width: 1),
        Text(
          '${widget.value}',
          maxLines: 1,
          style: TextStyle(
            color: style.foreground,
            fontSize: 9,
            height: 1,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final style = _moraleStyle(moraleBandOf(widget.value));
    final pulse = _pulse;
    if (!_sparkles) return _chip(style, 0);
    if (!_blinks || pulse == null) return _chip(style, 1);
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) => _chip(style, 0.3 + 0.7 * pulse.value),
    );
  }
}

class FleetShipMinimalRow extends StatelessWidget {
  const FleetShipMinimalRow({
    super.key,
    required this.state,
    required this.ship,
    required this.visible,
    required this.shipTypeLabelMode,
    required this.damagePulseFilter,
    required this.moraleSparkleMode,
    this.repairStatus,
    this.specialAttack,
    this.onTap,
  });

  final GameState state;
  final OwnedShip ship;
  final Set<String> visible;
  final FleetShipTypeLabelMode shipTypeLabelMode;
  final DamagePulseFilter damagePulseFilter;
  final MoraleSparkleMode moraleSparkleMode;
  final ShipRepairStatus? repairStatus;
  final EquipmentMechanismDisplay? specialAttack;
  final VoidCallback? onTap;

  static const _textColor = Color(0xffdce6eb);

  bool _show(String key) => visible.contains(key);

  // 与普通档无头像时一致：疲劳值关闭后，疲劳不足与闪光仍要能看到。
  bool get _moraleWarns =>
      ship.condition < 30 ||
      (ship.condition >= 50 && moraleSparkleMode != MoraleSparkleMode.off);

  Widget _moraleChip() => MoraleChip(
    key: Key('minimal-morale-${ship.id}'),
    value: ship.condition,
    sparkleMode: moraleSparkleMode,
  );

  static double _ratio(int current, int max) =>
      max <= 0 ? 0 : (current / max).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final master = state.masterForShip(ship);
    final portrait = _show('portrait');
    final shadows = portrait ? flatOnImageShadows : null;
    final hasStatus = ['hp', 'fuel', 'ammo', 'morale'].any(_show);
    final lines = Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 1),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 14, child: _identityLine(context, master, shadows)),
          if (hasStatus) ...[
            const SizedBox(height: 1),
            SizedBox(height: 12, child: _statusLine(master, shadows)),
          ],
        ],
      ),
    );
    return GameEdgeTapGuard(
      child: Material(
        key: Key('minimal-ship-row-${ship.id}'),
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: portrait
              ? FlatPortraitBackdrop(
                  image: (width, height) => _portrait(master, width, height),
                  child: lines,
                )
              : lines,
        ),
      ),
    );
  }

  Widget _portrait(MasterShip? master, double width, double height) {
    final image = ShipPortrait(
      ship: master,
      serverOrigin: state.serverOrigin,
      width: width,
      height: height,
    );
    return repairStatus == ShipRepairStatus.retreat
        ? ColorFiltered(colorFilter: shipRetreatGrayscale, child: image)
        : image;
  }

  Widget _identityLine(
    BuildContext context,
    MasterShip? master,
    List<Shadow>? shadows,
  ) {
    final typeLabel = _show('type')
        ? fleetShipTypeShortLabel(context, state, master, shipTypeLabelMode) ??
              fleetText(context, FleetUiKeys.unknownShipType)
        : null;
    final name =
        (master == null
            ? null
            : gameNames(context).shipName(master.name, shipId: master.id)) ??
        fleetText(context, FleetUiKeys.unknownShip);
    final mechanisms = [
      ...detectShipCombatMechanisms(state, ship),
      ?specialAttack,
    ].where((m) => showsMechanism(visible, m)).toList();
    final speed = ShipSpeedVisual.fromSpeed(ship.effectiveSpeed(master));
    final meta = <Widget>[
      if (!_show('morale') && _moraleWarns) _moraleChip(),
      if (_show('level'))
        Text(
          'Lv${ship.level}',
          style: TextStyle(
            color: flatMutedColor,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            shadows: shadows,
          ),
        ),
      if (_show('shipSpeed'))
        _Tag(
          text: fleetText(context, speed.label),
          color: speed.foreground,
          background: speed.background,
        ),
      for (final mechanism in mechanisms)
        _Tag(
          key: Key('minimal-mechanism-${ship.id}-${mechanism.kind?.name}'),
          text: fleetText(context, mechanism.effectiveShortLabel),
          color: mechanismToneColor(mechanism.tone),
        ),
      if (repairStatus != null)
        _Tag(
          key: Key('minimal-repair-${ship.id}'),
          text: fleetText(context, repairStatus!.label),
          color: const Color(0xffffc861),
        ),
    ];
    final icons = _show('equipment')
        ? [
            for (final eq in state.equipmentForShip(ship))
              if (eq.master != null && eq.master!.type.length >= 4)
                Padding(
                  padding: const EdgeInsets.only(left: 1),
                  child: EquipmentTypeIconImage(
                    iconId: eq.master!.type[3],
                    width: 12,
                    height: 12,
                  ),
                ),
          ]
        : const <Widget>[];
    // 除舰名外每段都有宽度上限并可缩放，窄面板里只截断舰名而不会溢出。
    return LayoutBuilder(
      builder: (context, box) => Row(
        children: [
          Expanded(
            child: Row(
              children: [
                if (typeLabel != null) ...[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 30),
                    child: Text(
                      typeLabel,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: const Color(0xffa9bac4),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        shadows: shadows,
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                ],
                Flexible(
                  child: Text(
                    name,
                    key: Key('minimal-name-${ship.id}'),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _textColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      shadows: shadows,
                    ),
                  ),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(width: 3),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: box.maxWidth * .36),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < meta.length; i++) ...[
                            if (i > 0) const SizedBox(width: 3),
                            meta[i],
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (icons.isNotEmpty) ...[
            const SizedBox(width: 3),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: box.maxWidth * .32),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(mainAxisSize: MainAxisSize.min, children: icons),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusLine(MasterShip? master, List<Shadow>? shadows) {
    final currentHp = repairStatus == ShipRepairStatus.retreat
        ? 0
        : ship.currentHp;
    final hpRatio = _ratio(currentHp, ship.maxHp);
    final barColor = shipHpBarColor(hpRatio, isZeroHp: currentHp <= 0);
    if (!_show('bars')) {
      return _valueLine(master, shadows, currentHp, hpRatio, barColor);
    }
    final hpBar = ProphetHpBar(
      value: hpRatio,
      color: barColor,
      backgroundColor: const Color(0xff294052),
      height: 4,
    );
    final showSupply = _show('fuel') || _show('ammo');
    return Row(
      children: [
        if (_show('morale')) ...[_moraleChip(), const SizedBox(width: 4)],
        if (_show('hp')) ...[
          Expanded(
            child: repairStatus == ShipRepairStatus.retreat
                ? hpBar
                : DamagePulseGlow(
                    currentHp: currentHp,
                    maxHp: ship.maxHp,
                    filter: damagePulseFilter,
                    normalColor: barColor,
                    borderRadius: BorderRadius.circular(2),
                    child: hpBar,
                  ),
          ),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 40),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '$currentHp/${ship.maxHp}',
                key: Key('minimal-hp-value-${ship.id}'),
                maxLines: 1,
                style: TextStyle(
                  color: shipHpValueColor(hpRatio, isZeroHp: currentHp <= 0),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  shadows: shadows,
                ),
              ),
            ),
          ),
        ] else
          const Spacer(),
        if (showSupply) ...[
          const SizedBox(width: 4),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_show('fuel'))
                _SupplyBar(
                  key: Key('minimal-supply-fuel-${ship.id}'),
                  ratio: _ratio(ship.currentFuel, master?.maxFuel ?? 0),
                ),
              if (_show('fuel') && _show('ammo')) const SizedBox(height: 1),
              if (_show('ammo'))
                _SupplyBar(
                  key: Key('minimal-supply-ammo-${ship.id}'),
                  ratio: _ratio(ship.currentAmmo, master?.maxAmmo ?? 0),
                ),
            ],
          ),
        ],
      ],
    );
  }

  // 与普通档关闭条状一致只剩数值；补给细条也随之换成数值，从左依次排开。
  Widget _valueLine(
    MasterShip? master,
    List<Shadow>? shadows,
    int currentHp,
    double hpRatio,
    Color barColor,
  ) {
    Widget value(String text, Color color, Key key) => Text(
      text,
      key: key,
      maxLines: 1,
      style: TextStyle(
        color: color,
        fontSize: 9,
        fontWeight: FontWeight.w800,
        fontFeatures: const [FontFeature.tabularFigures()],
        shadows: shadows,
      ),
    );
    Widget item(Widget icon, Widget value) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [icon, const SizedBox(width: 2), value],
    );
    Widget supply(String key, String asset, int current, int max) => item(
      Image.asset(asset, width: 10, height: 10),
      value(
        '$current/$max',
        shipSupplyValueColor(_ratio(current, max)),
        Key('minimal-supply-$key-value-${ship.id}'),
      ),
    );
    final hpText = value(
      '$currentHp/${ship.maxHp}',
      shipHpValueColor(hpRatio, isZeroHp: currentHp <= 0),
      Key('minimal-hp-value-${ship.id}'),
    );
    final items = <Widget>[
      if (_show('hp'))
        item(
          Icon(
            Icons.favorite_rounded,
            color: const Color(0xffef5a5a),
            size: 10,
            shadows: shadows,
          ),
          repairStatus == ShipRepairStatus.retreat
              ? hpText
              : DamagePulseGlow(
                  currentHp: currentHp,
                  maxHp: ship.maxHp,
                  filter: damagePulseFilter,
                  normalColor: barColor,
                  child: hpText,
                ),
        ),
      if (_show('fuel'))
        supply(
          'fuel',
          'assets/images/material/01.png',
          ship.currentFuel,
          master?.maxFuel ?? 0,
        ),
      if (_show('ammo'))
        supply(
          'ammo',
          'assets/images/material/02.png',
          ship.currentAmmo,
          master?.maxAmmo ?? 0,
        ),
    ];
    return Row(
      children: [
        if (_show('morale')) ...[_moraleChip(), const SizedBox(width: 4)],
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  items[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
    super.key,
    required this.text,
    required this.color,
    this.background,
  });

  final String text;
  final Color color;
  final Color? background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
    decoration: BoxDecoration(
      color: background ?? color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(
      text,
      maxLines: 1,
      style: TextStyle(
        color: color,
        fontSize: 8,
        height: 1.1,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _SupplyBar extends StatelessWidget {
  const _SupplyBar({super.key, required this.ratio});

  final double ratio;

  @override
  Widget build(BuildContext context) => Container(
    width: 18,
    height: 3,
    alignment: Alignment.centerLeft,
    decoration: BoxDecoration(
      color: const Color(0xff294052),
      borderRadius: BorderRadius.circular(1.5),
    ),
    child: FractionallySizedBox(
      widthFactor: ratio,
      heightFactor: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: shipSupplyBarColor(ratio),
          borderRadius: BorderRadius.circular(1.5),
        ),
      ),
    ),
  );
}
