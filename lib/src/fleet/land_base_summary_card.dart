import '../widgets/app_segmented_style.dart';
import '../theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';

import '../game_state/game_state.dart';
import '../game_state/game_state_controller.dart';
import '../layout/flat_portrait_backdrop.dart';
import '../layout/flat_style.dart';
import '../settings/battle_status_effect_settings.dart';
import 'dashboard_card.dart';
import 'fleet_ui_strings.dart';
import '../layout/flat_empty_text.dart';
import '../layout/flat_list_row.dart';
import '../layout/flat_text_toggle.dart';
import '../layout/hd_dashboard_content.dart';
import '../layout/module_summaries.dart';
import '../layout/panel_style.dart';
import '../settings/module_display_settings.dart';
import 'equipment_type_icon.dart';
import 'fleet_ship_status_capsule.dart';
import 'land_base_air_power.dart';
import 'land_base_status_visuals.dart';
import 'ship_status_style.dart';
import 'ship_status_visuals.dart';
import 'slot_item_portrait.dart';
import 'status_density.dart';

class LandBaseSummaryCard extends StatefulWidget {
  const LandBaseSummaryCard({
    super.key,
    required this.controller,
    required this.collapsed,
    required this.onToggleCollapse,
    this.damagePulseMode = DamagePulseFilter.all,
    this.visible = const {'portrait', 'bars', 'airPower', 'range'},
    this.showLogo = true,
    this.showTitle = true,
    this.onOpenDisplaySettings,
  });

  final Set<String> visible;
  final bool showLogo;
  final bool showTitle;
  final VoidCallback? onOpenDisplaySettings;
  final GameStateController controller;
  final bool collapsed;
  final VoidCallback onToggleCollapse;
  final DamagePulseFilter damagePulseMode;

  @override
  State<LandBaseSummaryCard> createState() => _LandBaseSummaryCardState();
}

class _LandBaseSummaryCardState extends State<LandBaseSummaryCard> {
  int? _selectedAreaId;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final l10n =
          AppLocalizations.of(context) ??
          lookupAppLocalizations(const Locale('zh'));
      final state = widget.controller.state;
      final areaIds =
          state.landBases.map((base) => base.areaId).toSet().toList()..sort();
      if (!areaIds.contains(_selectedAreaId)) {
        _selectedAreaId = areaIds.firstOrNull;
      }
      final areaId = _selectedAreaId;
      final bases = areaId == null
          ? <LandBaseState>[]
          : state.landBases.where((base) => base.areaId == areaId).toList();
      bases.sort((left, right) => left.baseId.compareTo(right.baseId));

      return DashboardCard(
        collapsedSummary: widget.collapsed
            ? landBaseSummary(l10n, bases)
            : null,
        headerAction: moduleDisplayGear(
          context,
          'land_base',
          widget.onOpenDisplaySettings,
        ),
        title: l10n.landBaseBrief,
        icon: const Icon(Icons.flight_rounded),
        collapsed: widget.collapsed,
        onToggleCollapse: widget.onToggleCollapse,
        showLogo: widget.showLogo,
        showTitle: widget.showTitle,
        collapseButtonKey: const Key('land-base-collapse-button'),
        trailing: _LandBaseAreaSwitcher(
          areaIds: areaIds,
          selectedAreaId: areaId,
          onSelected: (selected) => setState(() => _selectedAreaId = selected),
        ),
        child: bases.isEmpty
            ? PanelStyleScope.isFlat(context)
                  ? FlatEmptyText(l10n.landBaseNoData)
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: Text(
                          l10n.landBaseNoData,
                          style: TextStyle(
                            color: appColor(context, const Color(0xff8197a5)),
                          ),
                        ),
                      ),
                    )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const gap = 4.0;
                      final columnCount =
                          context
                              .dependOnInheritedWidgetOfExactType<
                                HdModuleColumns
                              >()
                              ?.columns ??
                          (constraints.maxWidth >= 680 ? 2 : 1);
                      final rowWidth =
                          (constraints.maxWidth - gap * (columnCount - 1)) /
                          columnCount;
                      return Wrap(
                        spacing: gap,
                        runSpacing: PanelStyleScope.isFlat(context)
                            ? flatRowSpacing
                            : gap,
                        children: <Widget>[
                          for (final base in bases)
                            SizedBox(
                              width: rowWidth,
                              child: LandBaseAirGroupRow(
                                state: state,
                                base: base,
                                visible: widget.visible,
                                damagePulseMode: widget.damagePulseMode,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
      );
    },
  );
}

class _LandBaseAreaSwitcher extends StatelessWidget {
  const _LandBaseAreaSwitcher({
    required this.areaIds,
    required this.selectedAreaId,
    required this.onSelected,
  });

  final List<int> areaIds;
  final int? selectedAreaId;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    if (PanelStyleScope.isFlat(context)) {
      return FlatTextToggle(
        key: const Key('land-base-area-switcher'),
        options: [
          for (final areaId in areaIds)
            FlatTextToggleOption(
              key: Key('land-base-area-selector-$areaId'),
              label: '$areaId',
              selected: areaId == selectedAreaId,
              onTap: () => onSelected(areaId),
            ),
        ],
      );
    }
    return Container(
      key: const Key('land-base-area-switcher'),
      constraints: const BoxConstraints(minWidth: 42, maxWidth: 150),
      height: AppSegmentedStyle.compactHeight,
      padding: AppSegmentedStyle.padding(compact: true),
      decoration: AppSegmentedStyle.decoration(context, compact: true),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final areaId in areaIds)
            Material(
              key: Key('land-base-area-selector-$areaId'),
              color: AppSegmentedStyle.selection(
                context,
                areaId == selectedAreaId,
              ),
              borderRadius: AppSegmentedStyle.itemRadius(compact: true),
              child: InkWell(
                onTap: () => onSelected(areaId),
                borderRadius: AppSegmentedStyle.itemRadius(compact: true),
                child: SizedBox(
                  width: 32,
                  child: Center(
                    child: Text(
                      '$areaId',
                      style: AppSegmentedStyle.textStyle(
                        context,
                        selected: areaId == selectedAreaId,
                        compact: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class LandBaseAirGroupRow extends StatelessWidget {
  const LandBaseAirGroupRow({
    super.key,
    required this.state,
    required this.base,
    this.damagePulseMode = DamagePulseFilter.all,
    this.visible = const {'portrait', 'bars', 'airPower', 'range'},
  });

  final Set<String> visible;
  final GameState state;
  final LandBaseState base;
  final DamagePulseFilter damagePulseMode;

  String get _keySuffix => '${base.areaId}-${base.baseId}';

  @override
  Widget build(BuildContext context) {
    if (PanelStyleScope.isFlat(context)) {
      return _FlatLandBaseRow(
        key: Key('land-base-row-$_keySuffix'),
        state: state,
        base: base,
        visible: visible,
        damagePulseMode: damagePulseMode,
        keySuffix: _keySuffix,
      );
    }
    final maximumHp = base.maxHp ?? 200;
    final currentHp = base.currentHp ?? maximumHp;
    final hpRatio = maximumHp <= 0
        ? 0.0
        : (currentHp / maximumHp).clamp(0.0, 1.0);
    final fatigue = landBaseFatigueLevel(
      base.squadrons.map((squadron) => squadron.condition),
    );
    final airPower = LandBaseAirPower.calculate(state: state, base: base);
    final portraitMaster = _portraitMaster(state, base);

    return Container(
      key: Key('land-base-row-$_keySuffix'),
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
      decoration: BoxDecoration(
        color: appColor(context, Color(0xff1c3547)),
        border: Border.all(
          color: appColor(context, Color(0xff4c6b84)),
          width: 1.2,
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: appColor(context, Colors.black45),
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 460;
          final portraitSize = fleetStatusPortraitSize(constraints.maxWidth);
          final portraitWidth = visible.contains('portrait')
              ? portraitSize.width
              : 0.0;
          final portraitHeight = portraitSize.height;
          final hpTrackHeight =
              fleetStatusMeterHeight(constraints.maxWidth) * 0.45;
          final fatigueFaceSize = (portraitHeight * 0.34)
              .clamp(14.0, 20.0)
              .toDouble();
          final sectionGap = narrow ? 5.0 : 7.0;
          final statusWidth = narrow ? 68.0 : 80.0;
          final maximumSlotWidth = visible.contains('portrait')
              ? (narrow ? 38.0 : 44.0)
              : double.infinity;
          final slotWidth =
              ((constraints.maxWidth -
                          portraitWidth -
                          statusWidth -
                          sectionGap * (visible.contains('portrait') ? 2 : 1) -
                          6) /
                      4)
                  .clamp(0.0, maximumSlotWidth)
                  .toDouble();
          final l10n =
              AppLocalizations.of(context) ??
              lookupAppLocalizations(const Locale('zh'));
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                height: 20,
                child: Row(
                  key: Key('land-base-identity-line-$_keySuffix'),
                  children: <Widget>[
                    Flexible(
                      fit: FlexFit.loose,
                      child: _LandBaseNameChip(
                        key: Key('land-base-name-$_keySuffix'),
                        label: base.name,
                      ),
                    ),
                    if (!visible.contains('portrait') &&
                        fatigue != LandBaseFatigueLevel.none) ...[
                      const SizedBox(width: 4),
                      FatigueFace(
                        level: fatigue == LandBaseFatigueLevel.red
                            ? FatigueFaceLevel.red
                            : FatigueFaceLevel.yellow,
                        size: 14,
                        faceKey: Key('land-base-fatigue-face-$_keySuffix'),
                      ),
                    ],
                    const SizedBox(width: 4),
                    _LandBaseActionChip(
                      key: Key('land-base-action-chip-$_keySuffix'),
                      label: _actionLabel(base.actionKind, l10n),
                      color: appColor(context, _actionColor(base.actionKind)),
                    ),
                    if (visible.contains('airPower')) ...[
                      const SizedBox(width: 3),
                      _LandBaseInfoChip(
                        key: Key('land-base-air-power-chip-$_keySuffix'),
                        label: '${l10n.airPower} ${airPower.displayValue}',
                        color: appColor(context, Color(0xffd4a74e)),
                      ),
                    ],
                    if (visible.contains('range')) ...[
                      const SizedBox(width: 3),
                      _LandBaseInfoChip(
                        key: Key('land-base-range-chip-$_keySuffix'),
                        label:
                            '${l10n.landBaseRange} ${base.effectiveDistance}',
                        color: appColor(context, Color(0xff70b8d8)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: <Widget>[
                  if (visible.contains('portrait')) ...[
                    SizedBox(
                      key: Key('land-base-portrait-$_keySuffix'),
                      width: portraitWidth,
                      height: portraitHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        clipBehavior: Clip.none,
                        children: <Widget>[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: SlotItemPortrait(
                              item: portraitMaster,
                              serverOrigin: state.serverOrigin,
                              width: portraitWidth,
                              height: portraitHeight,
                            ),
                          ),
                          ShipHpFrame(
                            key: Key('land-base-portrait-hp-frame-$_keySuffix'),
                            shipId: base.areaId * 10 + base.baseId,
                            currentHp: currentHp,
                            maxHp: maximumHp,
                            color: appColor(
                              context,
                              shipHpBarColor(hpRatio, isZeroHp: currentHp <= 0),
                            ),
                            filter: damagePulseMode,
                            strokeWidth: 2,
                          ),
                          if (fatigue != LandBaseFatigueLevel.none)
                            Positioned(
                              right: 4,
                              top: 0,
                              child: FatigueFace(
                                level: fatigue == LandBaseFatigueLevel.red
                                    ? FatigueFaceLevel.red
                                    : FatigueFaceLevel.yellow,
                                size: fatigueFaceSize,
                                faceKey: Key(
                                  'land-base-fatigue-face-$_keySuffix',
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(width: sectionGap),
                  ],
                  if (narrow)
                    SizedBox(
                      width: statusWidth,
                      child: _LandBaseStatusColumn(
                        showTrack: visible.contains('bars'),
                        keySuffix: _keySuffix,
                        currentHp: currentHp,
                        maximumHp: maximumHp,
                        hpRatio: hpRatio,
                        height: portraitHeight > 34 ? portraitHeight : 34,
                        trackHeight: hpTrackHeight,
                      ),
                    )
                  else
                    Expanded(
                      child: _LandBaseStatusColumn(
                        showTrack: visible.contains('bars'),
                        keySuffix: _keySuffix,
                        currentHp: currentHp,
                        maximumHp: maximumHp,
                        hpRatio: hpRatio,
                        height: portraitHeight > 34 ? portraitHeight : 34,
                        trackHeight: hpTrackHeight,
                      ),
                    ),
                  SizedBox(width: sectionGap),
                  Row(
                    key: Key('land-base-squadron-strip-$_keySuffix'),
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (
                        var squadronId = 1;
                        squadronId <= 4;
                        squadronId++
                      ) ...[
                        if (squadronId > 1) const SizedBox(width: 2),
                        SizedBox(
                          width: slotWidth,
                          child: _LandBaseSquadronSlot(
                            state: state,
                            squadron: _squadron(base, squadronId),
                            areaId: base.areaId,
                            baseId: base.baseId,
                            squadronId: squadronId,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LandBaseStatusColumn extends StatelessWidget {
  const _LandBaseStatusColumn({
    required this.keySuffix,
    this.showTrack = true,
    required this.currentHp,
    required this.maximumHp,
    required this.hpRatio,
    required this.height,
    required this.trackHeight,
  });

  final String keySuffix;
  final bool showTrack;
  final int currentHp;
  final int maximumHp;
  final double hpRatio;
  final double height;
  final double trackHeight;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: Key('land-base-status-column-$keySuffix'),
    height: height,
    child: _LandBaseStackedHpMeter(
      showTrack: showTrack,
      currentHp: currentHp,
      maximumHp: maximumHp,
      hpRatio: hpRatio,
      trackHeight: trackHeight,
      iconKey: Key('land-base-hp-icon-$keySuffix'),
      valueKey: Key('land-base-hp-value-$keySuffix'),
      trackKey: Key('land-base-hp-meter-$keySuffix'),
    ),
  );
}

class _LandBaseInfoChip extends StatelessWidget {
  const _LandBaseInfoChip({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(
      color: appColor(context, color.withValues(alpha: 0.14)),
      border: Border.all(
        color: appColor(context, color.withValues(alpha: 0.42)),
      ),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      maxLines: 1,
      style: appTextStyle(
        context,
        TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

class _LandBaseNameChip extends StatelessWidget {
  const _LandBaseNameChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(
      color: appColor(context, Color(0xff102331)),
      border: Border.all(color: appColor(context, Color(0xff4c6b84))),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: appTextStyle(
        context,
        TextStyle(
          color: appColor(context, Color(0xffe8f1f5)),
          fontSize: 8,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _LandBaseActionChip extends StatelessWidget {
  const _LandBaseActionChip({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(
      color: appColor(context, color.withValues(alpha: 0.16)),
      border: Border.all(
        color: appColor(context, color.withValues(alpha: 0.42)),
      ),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: appTextStyle(
        context,
        TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

class _LandBaseStackedHpMeter extends StatelessWidget {
  const _LandBaseStackedHpMeter({
    this.showTrack = true,
    required this.currentHp,
    required this.maximumHp,
    required this.hpRatio,
    required this.trackHeight,
    required this.iconKey,
    required this.valueKey,
    required this.trackKey,
  });

  final bool showTrack;
  final int currentHp;
  final int maximumHp;
  final double hpRatio;
  final double trackHeight;
  final Key iconKey;
  final Key valueKey;
  final Key trackKey;

  @override
  Widget build(BuildContext context) {
    final hpColor = shipHpBarColor(hpRatio, isZeroHp: currentHp <= 0);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          key: valueKey,
          children: <Widget>[
            Icon(
              Icons.favorite_rounded,
              key: iconKey,
              color: appColor(context, Color(0xffef5a5a)),
              size: 10,
            ),
            const SizedBox(width: 3),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '$currentHp/$maximumHp',
                  style: appTextStyle(
                    context,
                    TextStyle(
                      color: shipHpValueColor(
                        hpRatio,
                        isZeroHp: currentHp <= 0,
                      ),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (showTrack) const SizedBox(height: 3),
        if (showTrack)
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              key: trackKey,
              height: trackHeight,
              color: appColor(context, Color(0xff294052)),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: hpRatio,
                heightFactor: 1,
                child: ColoredBox(color: appColor(context, hpColor)),
              ),
            ),
          ),
      ],
    );
  }
}

class _LandBaseSquadronSlot extends StatelessWidget {
  const _LandBaseSquadronSlot({
    required this.state,
    required this.squadron,
    required this.areaId,
    required this.baseId,
    required this.squadronId,
  });

  final GameState state;
  final LandBaseSquadronState? squadron;
  final int areaId;
  final int baseId;
  final int squadronId;

  @override
  Widget build(BuildContext context) {
    final owned = squadron == null
        ? null
        : state.slotItems[squadron!.slotItemId];
    final master = owned == null
        ? null
        : state.masterSlotItems[owned.masterSlotItemId];
    final iconId = master != null && master.type.length > 3
        ? master.type[3]
        : -1;
    final fatigue = landBaseFatigueLevel(<int>[
      if (squadron != null) squadron!.condition,
    ]);
    final fatigueColor = landBaseFatigueColor(fatigue);
    final relocating = squadron?.state == 2;
    final missing =
        squadron != null &&
        squadron!.maxCount > 0 &&
        squadron!.currentCount < squadron!.maxCount;
    final countFontSize = isNearSquareLargeDisplay(context) ? 10.0 : 8.0;
    final suffix = '$areaId-$baseId-$squadronId';
    final content = Container(
      key: Key('land-base-slot-$suffix'),
      height: 34,
      decoration: BoxDecoration(
        color: appColor(context, Color(0xff102331)),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: appColor(
            context,
            missing
                ? const Color(0xffef775f)
                : fatigueColor?.withValues(alpha: 0.9) ??
                      const Color(0xff294052),
          ),
        ),
        boxShadow: fatigueColor == null
            ? null
            : <BoxShadow>[
                BoxShadow(
                  color: appColor(
                    context,
                    fatigueColor.withValues(alpha: 0.42),
                  ),
                  blurRadius: fatigue == LandBaseFatigueLevel.red ? 7 : 4,
                ),
              ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final iconSize = (constraints.maxWidth - 8).clamp(20.0, 26.0);
          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              EquipmentTypeIconImage(
                key: Key('land-base-slot-icon-$suffix'),
                iconId: iconId,
                width: iconSize,
                height: iconSize,
              ),
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  key: Key('land-base-slot-count-$suffix'),
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: appColor(context, Color(0xcc102331)),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    squadron == null ? '—' : '${squadron!.currentCount}',
                    style: appTextStyle(
                      context,
                      TextStyle(
                        color: missing
                            ? const Color(0xffff8b78)
                            : const Color(0xffe8f1f5),
                        fontSize: countFontSize,
                        height: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    return relocating
        ? Opacity(
            key: Key('land-base-slot-relocating-$suffix'),
            opacity: 0.38,
            child: content,
          )
        : content;
  }
}

class _FlatLandBaseRow extends StatelessWidget {
  const _FlatLandBaseRow({
    super.key,
    required this.state,
    required this.base,
    required this.visible,
    required this.damagePulseMode,
    required this.keySuffix,
  });

  final GameState state;
  final LandBaseState base;
  final Set<String> visible;
  final DamagePulseFilter damagePulseMode;
  final String keySuffix;

  @override
  Widget build(BuildContext context) {
    final l10n =
        AppLocalizations.of(context) ??
        lookupAppLocalizations(const Locale('zh'));
    final portraitMaster = visible.contains('portrait')
        ? _portraitMaster(state, base)
        : null;
    final shadows = portraitMaster != null ? flatOnImageShadows(context) : null;
    final maximumHp = base.maxHp ?? 200;
    final currentHp = base.currentHp;
    // 基地 HP 只在空袭后才有数据，平时恒为满血；只在已知且受损时占位。
    final damagedHp = currentHp != null && currentHp < maximumHp
        ? currentHp
        : null;
    final meter = damagedHp != null && visible.contains('bars');
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _header(
          context,
          l10n,
          damagedHp,
          maximumHp,
          shadows,
          pulseValue: !meter,
        ),
        // 血条与行间距同高、互相替换，受损前后整行高度不变。
        if (meter)
          _damagePulse(
            context,
            damagedHp,
            maximumHp,
            _hpMeter(context, damagedHp, maximumHp),
          )
        else
          const SizedBox(height: flatRowSpacing),
        Row(
          key: Key('land-base-squadron-strip-$keySuffix'),
          children: <Widget>[
            for (var squadronId = 1; squadronId <= 4; squadronId++) ...[
              if (squadronId > 1) const SizedBox(width: 4),
              Expanded(
                child: _FlatSquadronCell(
                  state: state,
                  squadron: _squadron(base, squadronId),
                  keySuffix: '$keySuffix-$squadronId',
                  shadows: shadows,
                ),
              ),
            ],
          ],
        ),
      ],
    );
    if (portraitMaster == null) return content;
    return FlatPortraitBackdrop(
      imageKey: Key('land-base-portrait-$keySuffix'),
      image: (width, height) => SlotItemPortrait(
        item: portraitMaster,
        serverOrigin: state.serverOrigin,
        width: width,
        height: height,
      ),
      child: content,
    );
  }

  Widget _header(
    BuildContext context,
    AppLocalizations l10n,
    int? damagedHp,
    int maximumHp,
    List<Shadow>? shadows, {
    required bool pulseValue,
  }) {
    final airPower = LandBaseAirPower.calculate(state: state, base: base);
    final airPowerLabel = '${l10n.airPower} ${airPower.displayValue}';
    final rangeLabel =
        '${fleetText(context, FleetUiKeys.landBaseRadiusShort)} ${base.effectiveDistance}';
    var lineHeight = 10.0;
    double textWidth(String value, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(
          text: value,
          style: DefaultTextStyle.of(context).style.merge(style),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        maxLines: 1,
      )..layout();
      final width = painter.width;
      if (painter.height > lineHeight) lineHeight = painter.height;
      painter.dispose();
      return width;
    }

    final widths = <double>[
      // 预留最大 HP 的宽度，受损提示出现或消失时名称位置保持稳定。
      if (damagedHp != null ||
          visible.contains('airPower') ||
          visible.contains('range'))
        11 +
            textWidth(
              '$maximumHp',
              const TextStyle(
                fontSize: flatRowFontSize,
                fontWeight: FontWeight.w800,
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
      if (visible.contains('airPower'))
        11 + textWidth(airPowerLabel, flatRowTextStyle(context)),
      if (visible.contains('range'))
        11 + textWidth(rangeLabel, flatRowTextStyle(context)),
    ];
    final naturalWidth =
        widths.fold(0.0, (total, width) => total + width) +
        (widths.isEmpty ? 0 : widths.length - 1);
    final actionLabel = _actionLabel(base.actionKind, l10n);
    final actionWidth = textWidth(actionLabel, flatRowTextStyle(context));
    final nameWidth = textWidth(base.name, flatRowTextStyle(context));
    final trailing = flatRowTrailing(
      _trailing(
        context,
        l10n,
        damagedHp,
        maximumHp,
        shadows,
        airPowerLabel: airPowerLabel,
        rangeLabel: rangeLabel,
        pulseValue: pulseValue,
      ),
    );
    return LayoutBuilder(
      builder: (context, box) {
        // 单行内先给名称留可辨识的空间，再让指标使用其余宽度。
        // 只压缩本行间距；其它模块仍沿用 FlatListRow 原来的排版。
        final tagWidth = actionWidth.clamp(0.0, box.maxWidth * .2);
        final minimumNameWidth = nameWidth.clamp(
          0.0,
          (box.maxWidth * .2).clamp(0.0, 24.0),
        );
        final available = (box.maxWidth - tagWidth - minimumNameWidth - 2)
            .clamp(0.0, box.maxWidth);
        final metricsWidth = naturalWidth.clamp(0.0, available);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: flatRowSpacing / 2),
          child: SizedBox(
            height: lineHeight,
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: tagWidth,
                  child: flatRowText(
                    context,
                    actionLabel,
                    key: Key('land-base-action-chip-$keySuffix'),
                    color: _actionColor(base.actionKind),
                    shadows: shadows,
                  ),
                ),
                const SizedBox(width: 1),
                Expanded(
                  child: flatRowText(
                    context,
                    base.name,
                    key: Key('land-base-name-$keySuffix'),
                    shadows: shadows,
                  ),
                ),
                if (widths.isNotEmpty) ...<Widget>[
                  const SizedBox(width: 1),
                  SizedBox(
                    width: metricsWidth,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: trailing,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _trailing(
    BuildContext context,
    AppLocalizations l10n,
    int? damagedHp,
    int maximumHp,
    List<Shadow>? shadows, {
    required String airPowerLabel,
    required String rangeLabel,
    required bool pulseValue,
  }) {
    final items = <Widget>[
      if (damagedHp != null)
        _iconValue(
          key: Key('land-base-hp-value-$keySuffix'),
          icon: Icon(
            Icons.favorite_rounded,
            key: Key('land-base-hp-icon-$keySuffix'),
            color: appColor(context, const Color(0xffef5a5a)),
            size: 10,
            shadows: shadows,
          ),
          value: _hpValue(
            context,
            damagedHp,
            maximumHp,
            shadows,
            pulse: pulseValue,
          ),
        ),
      if (visible.contains('airPower'))
        _iconValue(
          key: Key('land-base-air-power-chip-$keySuffix'),
          icon: Icon(
            Icons.flight_rounded,
            color: appColor(context, const Color(0xffd4a74e)),
            size: 10,
            semanticLabel: l10n.airPower,
            shadows: shadows,
          ),
          value: Text(
            airPowerLabel,
            style: flatRowTextStyle(
              context,
              color: const Color(0xffd4a74e),
              shadows: shadows,
            ),
          ),
        ),
      if (visible.contains('range'))
        _iconValue(
          key: Key('land-base-range-chip-$keySuffix'),
          icon: Icon(
            Icons.radar,
            color: appColor(context, const Color(0xff70b8d8)),
            size: 10,
            semanticLabel: l10n.landBaseRange,
            shadows: shadows,
          ),
          value: Text(
            rangeLabel,
            style: flatRowTextStyle(
              context,
              color: const Color(0xff70b8d8),
              shadows: shadows,
            ),
          ),
        ),
    ];
    return Row(
      key: Key('land-base-identity-line-$keySuffix'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var index = 0; index < items.length; index++) ...[
          if (index > 0) const SizedBox(width: 1),
          items[index],
        ],
      ],
    );
  }

  Widget _iconValue({
    required Key key,
    required Widget icon,
    required Widget value,
  }) => Row(
    key: key,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[icon, const SizedBox(width: 1), value],
  );

  Widget _hpValue(
    BuildContext context,
    int currentHp,
    int maximumHp,
    List<Shadow>? shadows, {
    required bool pulse,
  }) {
    final text = Text(
      '$currentHp',
      style: TextStyle(
        color: appColor(
          context,
          shipHpValueColor(
            _hpRatio(currentHp, maximumHp),
            isZeroHp: currentHp <= 0,
          ),
        ),
        fontSize: flatRowFontSize,
        fontWeight: FontWeight.w800,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        shadows: shadows,
      ),
    );
    return pulse ? _damagePulse(context, currentHp, maximumHp, text) : text;
  }

  Widget _hpMeter(BuildContext context, int currentHp, int maximumHp) {
    final hpRatio = _hpRatio(currentHp, maximumHp);
    return Container(
      key: Key('land-base-hp-meter-$keySuffix'),
      height: flatRowSpacing,
      color: appColor(context, const Color(0xff294052)),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: hpRatio,
        heightFactor: 1,
        child: ColoredBox(
          color: appColor(
            context,
            shipHpBarColor(hpRatio, isZeroHp: currentHp <= 0),
          ),
        ),
      ),
    );
  }

  static double _hpRatio(int currentHp, int maximumHp) =>
      maximumHp <= 0 ? 0.0 : (currentHp / maximumHp).clamp(0.0, 1.0);

  Widget _damagePulse(
    BuildContext context,
    int currentHp,
    int maximumHp,
    Widget child,
  ) => DamagePulseGlow(
    currentHp: currentHp,
    maxHp: maximumHp,
    filter: damagePulseMode,
    normalColor: appColor(
      context,
      shipHpBarColor(_hpRatio(currentHp, maximumHp), isZeroHp: currentHp <= 0),
    ),
    child: child,
  );
}

class _FlatSquadronCell extends StatelessWidget {
  const _FlatSquadronCell({
    required this.state,
    required this.squadron,
    required this.keySuffix,
    required this.shadows,
  });

  final GameState state;
  final LandBaseSquadronState? squadron;
  final String keySuffix;
  final List<Shadow>? shadows;

  @override
  Widget build(BuildContext context) {
    final squadron = this.squadron;
    final owned = squadron == null
        ? null
        : state.slotItems[squadron.slotItemId];
    final master = owned == null
        ? null
        : state.masterSlotItems[owned.masterSlotItemId];
    final iconId = master != null && master.type.length > 3
        ? master.type[3]
        : -1;
    final proficiency = owned?.proficiency ?? 0;
    final fatigueColor = squadron == null
        ? null
        : landBaseFatigueColor(landBaseFatigueLevel(<int>[squadron.condition]));
    final missing =
        squadron != null &&
        squadron.maxCount > 0 &&
        squadron.currentCount < squadron.maxCount;
    final cell = Container(
      key: Key('land-base-slot-$keySuffix'),
      height: 18,
      // 用前景装饰画下划线：border 会挤占内边距，使疲劳格内容与正常格错位。
      foregroundDecoration: fatigueColor == null
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: appColor(context, fatigueColor),
                  width: 2,
                ),
              ),
            ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            EquipmentTypeIconImage(
              key: Key('land-base-slot-icon-$keySuffix'),
              iconId: iconId,
              width: 18,
              height: 18,
            ),
            if (proficiency > 0)
              Image.asset(
                'assets/images/airplane/alv${proficiency.clamp(1, 7)}.png',
                key: Key('land-base-slot-proficiency-$keySuffix'),
                width: 8,
                height: 10,
              ),
            const SizedBox(width: 2),
            Text(
              squadron == null ? '—' : '${squadron.currentCount}',
              key: Key('land-base-slot-count-$keySuffix'),
              style: TextStyle(
                color: appColor(
                  context,
                  missing ? const Color(0xffff8b78) : const Color(0xffe8f1f5),
                ),
                fontSize: flatRowFontSize,
                height: 1,
                fontWeight: FontWeight.w900,
                shadows: shadows,
              ),
            ),
          ],
        ),
      ),
    );
    return squadron?.state == 2
        ? Opacity(
            key: Key('land-base-slot-relocating-$keySuffix'),
            opacity: 0.38,
            child: cell,
          )
        : cell;
  }
}

MasterSlotItem? _portraitMaster(GameState state, LandBaseState base) {
  for (final squadron in base.squadrons) {
    final owned = state.slotItems[squadron.slotItemId];
    final master = owned == null
        ? null
        : state.masterSlotItems[owned.masterSlotItemId];
    if (master != null) return master;
  }
  return null;
}

LandBaseSquadronState? _squadron(LandBaseState base, int id) {
  for (final squadron in base.squadrons) {
    if (squadron.squadronId == id) return squadron;
  }
  return null;
}

String _actionLabel(int actionKind, AppLocalizations l10n) =>
    switch (actionKind) {
      1 => l10n.landBaseActionSortie,
      2 => l10n.landBaseActionAirDefense,
      3 => l10n.landBaseActionRetreat,
      4 => l10n.landBaseActionRest,
      _ => l10n.standby,
    };

Color _actionColor(int actionKind) => switch (actionKind) {
  1 => const Color(0xffef7777),
  2 => const Color(0xff69aee8),
  3 => const Color(0xff9ca8b2),
  4 => const Color(0xff70c697),
  _ => const Color(0xffb7c4cc),
};
