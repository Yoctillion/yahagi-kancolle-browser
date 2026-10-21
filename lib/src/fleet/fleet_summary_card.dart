import '../settings/fleet_display_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../game_state/fleet_metrics.dart';
import '../game_state/game_state_controller.dart';
import '../game_state/game_state.dart';
import 'dashboard_card.dart';
import 'separated_wrap.dart';
import '../layout/flat_empty_text.dart';
import '../layout/flat_style.dart';
import '../layout/hd_dashboard_content.dart';
import 'combat_mechanism.dart';
import 'fleet_ship_minimal_row.dart';
import 'ship_repair_status.dart';
import 'fleet_ui_strings.dart';

import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';

import 'fleet_ship_status_capsule.dart';
import 'fleet_line_of_sight_details.dart';
import '../performance/second_tick_scope.dart';
import '../layout/module_summaries.dart';
import '../layout/panel_style.dart';
import '../settings/battle_status_effect_settings.dart';
import '../settings/module_display_settings.dart';
import 'fleet_air_power_details.dart';
import 'morale_recovery_display.dart';
import 'morale_recovery_timer_controller.dart';

class FleetSummaryCard extends StatefulWidget {
  const FleetSummaryCard({
    super.key,
    required this.controller,
    required this.collapsed,
    required this.onToggleCollapse,
    required this.onOpenFleet,
    this.damagePulseFilter = DamagePulseFilter.all,
    this.moraleSparkleMode = MoraleSparkleMode.blinking,
    this.moraleRecoveryTimerController,
    this.clock,
    this.visible = defaultFields,
    this.twoColumnVisible,
    this.shipTypeLabelMode = FleetShipTypeLabelMode.localizedName,
    this.showLogo = true,
    this.showTitle = true,
    this.onOpenDisplaySettings,
  });

  final GameStateController controller;
  final bool collapsed;
  final VoidCallback onToggleCollapse;
  final ValueChanged<int> onOpenFleet;
  final DamagePulseFilter damagePulseFilter;
  final MoraleSparkleMode moraleSparkleMode;
  final MoraleRecoveryTimerController? moraleRecoveryTimerController;
  final DateTime Function()? clock;
  final Set<String> visible;
  final Set<String>? twoColumnVisible;
  final FleetShipTypeLabelMode shipTypeLabelMode;
  final bool showLogo;
  final bool showTitle;
  final VoidCallback? onOpenDisplaySettings;

  @override
  State<FleetSummaryCard> createState() => _FleetSummaryCardState();
}

class _FleetSummaryCardState extends State<FleetSummaryCard> {
  int _selectedFleetId = 1;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        if (widget.moraleRecoveryTimerController != null)
          widget.moraleRecoveryTimerController!,
      ]),
      builder: (context, _) {
        final state = widget.controller.state;
        final summaryVisible = HdModuleColumns.of(context) == 2
            ? widget.twoColumnVisible ??
                  {...widget.visible, 'firepower', 'anti-sub'}
            : widget.visible;
        final fleetIndex = state.fleets.indexWhere(
          (fleet) => fleet.id == _selectedFleetId,
        );
        final selectedFleet = fleetIndex < 0 ? null : state.fleets[fleetIndex];
        final ships = state.shipsForFleet(_selectedFleetId);
        final metrics = selectedFleet == null
            ? null
            : FleetMetrics.fromState(state, selectedFleet);
        final specialAttack = selectedFleet == null
            ? null
            : detectFleetSpecialAttack(state, selectedFleet);
        final twoColumns = HdModuleColumns.of(context) > 1;
        final flat = PanelStyleScope.isFlat(context);
        void selectFleet(int id) => setState(() => _selectedFleetId = id);
        final fleetSwitcher = flat
            ? _FleetUnderlineSwitcher(
                fleets: state.fleets,
                selectedFleetId: _selectedFleetId,
                onSelected: selectFleet,
              )
            : _FleetSegmentedSwitcher(
                fleets: state.fleets,
                selectedFleetId: _selectedFleetId,
                onSelected: selectFleet,
              );
        // Keep the ship subtree until captured data, preferences, locale, or
        // repair badges change. Only morale/countdown metrics need every tick.
        Localizations.localeOf(context);
        Widget? cachedShips;
        Map<int, ShipRepairStatus>? cachedRepairStatuses;
        // Fleet metrics depend on captured state, not the ticking clock.
        return SecondTickBuilder(
          now: widget.clock,
          enabled: !widget.collapsed,
          builder: (context, now, _) {
            final repairStatuses = widget.collapsed
                ? const <int, ShipRepairStatus>{}
                : shipRepairStatusesFor(
                    state: state,
                    anchorageRepairStartedAt:
                        widget.controller.anchorageRepairStartedAt,
                    nosakiSparkleStartedAt:
                        widget.controller.nosakiSparkleStartedAt,
                    now: now,
                  );
            if (!mapEquals(cachedRepairStatuses, repairStatuses)) {
              cachedShips = null;
              cachedRepairStatuses = repairStatuses;
            }
            return DashboardCard(
              title: AppLocalizations.of(context)?.fleetBrief ?? '编队简报',
              collapsedSummary: widget.collapsed
                  ? fleetSummary(
                      AppLocalizations.of(context) ??
                          lookupAppLocalizations(const Locale('zh')),
                      state,
                      _selectedFleetId,
                    )
                  : null,
              icon: const Icon(Icons.directions_boat_filled_outlined),
              collapsed: widget.collapsed,
              onToggleCollapse: widget.onToggleCollapse,
              showLogo: widget.showLogo,
              showTitle: widget.showTitle,
              headerAction: widget.onOpenDisplaySettings == null
                  ? null
                  : displaySettingsGear(
                      context,
                      key: const Key('fleet-display-settings-button'),
                      tooltip: fleetText(
                        context,
                        FleetUiKeys.fleetSummaryDisplay,
                      ),
                      onPressed: widget.onOpenDisplaySettings!,
                    ),
              trailing: twoColumns
                  ? SizedBox(width: 108, child: fleetSwitcher)
                  : null,
              child: _FleetSummaryBody(
                switcher: twoColumns ? null : fleetSwitcher,
                metrics: summaryVisible.any(summaryFields.contains)
                    ? _FleetSummaryMetrics(
                        visible: summaryVisible,
                        state: state,
                        fleetId: _selectedFleetId,
                        metrics: metrics,
                        now: now,
                        moraleRecoveryTimerController:
                            widget.moraleRecoveryTimerController,
                      )
                    : null,
                ships: cachedShips ??= ships.isEmpty
                    ? flat
                          ? FlatEmptyText(fleetText(context, '无数据'))
                          : Container(
                              padding: const EdgeInsets.all(16),
                              alignment: Alignment.center,
                              child: Text(
                                fleetText(context, '无数据'),
                                style: TextStyle(color: Color(0xff8197a5)),
                              ),
                            )
                    : flat
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < ships.length; i++) ...[
                            if (i > 0)
                              const SizedBox(
                                height: 1,
                                child: ColoredBox(color: Color(0xff1b3142)),
                              ),
                            FleetShipMinimalRow(
                              state: state,
                              ship: ships[i],
                              visible: widget.visible,
                              shipTypeLabelMode: widget.shipTypeLabelMode,
                              damagePulseFilter: widget.damagePulseFilter,
                              moraleSparkleMode: widget.moraleSparkleMode,
                              repairStatus: repairStatuses[ships[i].id],
                              onTap: () => widget.onOpenFleet(_selectedFleetId),
                            ),
                          ],
                        ],
                      )
                    : HdDashboardItems(
                        children: [
                          for (final ship in ships)
                            FleetShipStatusCapsule(
                              state: state,
                              ship: ship,
                              visible: widget.visible,
                              shipTypeLabelMode: widget.shipTypeLabelMode,
                              damagePulseFilter:
                                  widget.visible.contains('portrait')
                                  ? widget.damagePulseFilter
                                  : DamagePulseFilter.off,
                              moraleSparkleMode:
                                  widget.visible.contains('portrait')
                                  ? widget.moraleSparkleMode
                                  : MoraleSparkleMode.off,
                              repairStatus: repairStatuses[ship.id],
                              specialAttack: ship == ships.first
                                  ? specialAttack
                                  : null,
                              onTap: () => widget.onOpenFleet(_selectedFleetId),
                            ),
                        ],
                      ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Wide HD cards keep their summary in a narrow rail beside the ship grid.
class _FleetSummaryBody extends StatelessWidget {
  const _FleetSummaryBody({
    this.switcher,
    required this.metrics,
    required this.ships,
  });
  final Widget? switcher;
  final Widget? metrics;
  final Widget ships;
  @override
  Widget build(BuildContext context) {
    if (HdModuleColumns.of(context) > 1) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 70, child: metrics),
          const SizedBox(width: 6),
          Expanded(child: ships),
        ],
      );
    }
    final flat = PanelStyleScope.isFlat(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?switcher,
        if (metrics != null) ...[
          if (switcher != null) SizedBox(height: flat ? flatRowSpacing : 4),
          metrics!,
          SizedBox(height: flat ? flatRowSpacing : 6),
        ] else if (flat && switcher != null)
          const SizedBox(height: 2),
        ships,
      ],
    );
  }
}

class _FleetSegmentedSwitcher extends StatelessWidget {
  const _FleetSegmentedSwitcher({
    required this.fleets,
    required this.selectedFleetId,
    required this.onSelected,
  });

  final List<Fleet> fleets;
  final int selectedFleetId;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final visibleFleets = fleets.take(4).toList();
    return Container(
      key: const Key('fleet-summary-switcher'),
      height: 28,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xff102331),
        border: Border.all(color: const Color(0xff294052)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: visibleFleets.map((fleet) {
          final isSelected = fleet.id == selectedFleetId;
          return Expanded(
            child: Material(
              key: Key('fleet-summary-selector-${fleet.id}'),
              color: isSelected ? const Color(0xff8a6628) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                onTap: () => onSelected(fleet.id),
                borderRadius: BorderRadius.circular(6),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _fleetSelectorLabel(fleet),
                      style: TextStyle(
                        color: isSelected
                            ? const Color(0xffffdc88)
                            : const Color(0xff9fb3bf),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

String _fleetSelectorLabel(Fleet fleet) =>
    fleetSelectorLabelModeSetting == FleetSelectorLabelMode.number ||
        fleet.name.trim().isEmpty
    ? '${fleet.id}'
    : fleet.name;

class _FleetUnderlineSwitcher extends StatelessWidget {
  const _FleetUnderlineSwitcher({
    required this.fleets,
    required this.selectedFleetId,
    required this.onSelected,
  });

  final List<Fleet> fleets;
  final int selectedFleetId;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const Key('fleet-summary-switcher'),
    height: 22,
    child: Row(
      children: [
        for (final fleet in fleets.take(4))
          Expanded(
            child: InkWell(
              key: Key('fleet-summary-selector-${fleet.id}'),
              onTap: () => onSelected(fleet.id),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 2,
                      color: fleet.id == selectedFleetId
                          ? const Color(0xff8a6628)
                          : Colors.transparent,
                    ),
                  ),
                ),
                child: Center(
                  child: Text(
                    _fleetSelectorLabel(fleet),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fleet.id == selectedFleetId
                          ? const Color(0xffffdc88)
                          : const Color(0xff9fb3bf),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
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

class _FleetSummaryMetrics extends StatelessWidget {
  const _FleetSummaryMetrics({
    required this.state,
    required this.fleetId,
    required this.visible,
    required this.metrics,
    required this.now,
    required this.moraleRecoveryTimerController,
  });

  final GameState state;
  final int fleetId;
  final Set<String> visible;
  final FleetMetrics? metrics;
  final DateTime now;
  final MoraleRecoveryTimerController? moraleRecoveryTimerController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final requiredL10n = l10n ?? lookupAppLocalizations(const Locale('zh'));
    final noValue = l10n?.noValue ?? '—';
    final current = metrics;
    final airPower = current?.airPower;
    final airPowerMaximum = current?.airPowerMaximum;
    final hasAirPowerDetails =
        airPower != null &&
        airPowerMaximum != null &&
        current?.airPowerWithoutProficiency != null;
    final recoveryValue = fleetMoraleRecoveryDisplay(
      state: state,
      fleetId: fleetId,
      targetAt: moraleRecoveryTimerController?.targetForFleet(fleetId),
      now: now,
      recoveredLabel: requiredL10n.moraleRecovered,
      noValueLabel: noValue,
    );
    final twoColumns = HdModuleColumns.of(context) == 2;
    final metricFields = visible;
    final values =
        <(String, String, String)>[
              (
                'speed',
                l10n?.speed ?? '速度',
                fleetText(context, current?.speedLabel ?? noValue),
              ),
              (
                'total-level',
                l10n?.totalLevel ?? '总等级',
                current == null ? noValue : '${current.totalLevel}',
              ),
              (
                'firepower',
                fleetText(context, '火力'),
                current == null ? noValue : '${current.firepower}',
              ),
              (
                'torpedo',
                fleetText(context, '雷装'),
                current == null ? noValue : '${current.torpedo}',
              ),
              (
                'anti-air',
                fleetText(context, '对空'),
                current == null ? noValue : '${current.antiAir}',
              ),
              (
                'anti-sub',
                fleetText(context, '对潜'),
                current == null ? noValue : '${current.antiSub}',
              ),
              (
                'air-power',
                l10n?.airPower ?? '制空',
                airPower == null
                    ? noValue
                    : airPowerMaximum != null && airPowerMaximum > airPower
                    ? '$airPower+'
                    : '$airPower',
              ),
              (
                'line-of-sight',
                l10n?.lineOfSight ?? '索敌',
                current == null || current.formula33.isEmpty
                    ? noValue
                    : current.formula33.first.total.toStringAsFixed(2),
              ),
              (
                'minimum-condition',
                fleetText(context, '最低疲劳'),
                current == null ? noValue : '${current.minimumCondition}',
              ),
              (
                'recovery-countdown',
                fleetText(context, '恢复倒计时'),
                recoveryValue,
              ),
            ]
            .where((value) => metricFields.contains(value.$1))
            .take(twoColumns ? 7 : maximumSummaryFields)
            .toList();
    if (values.isEmpty) return const SizedBox.shrink();
    String? semanticLabelAt(int index) => switch (values[index].$1) {
      'air-power' when hasAirPowerDetails => requiredL10n.showAirPowerDetails,
      _ => null,
    };
    VoidCallback? onTapAt(int index) =>
        values[index].$1 == 'air-power' && hasAirPowerDetails && current != null
        ? () => showFleetAirPowerDetails(context, current)
        : values[index].$1 == 'line-of-sight' &&
              current != null &&
              current.formula33.isNotEmpty
        ? () => showFleetLineOfSightDetails(context, current)
        : null;
    if (PanelStyleScope.isFlat(context)) {
      return SeparatedWrap(
        key: const Key('fleet-summary-metrics'),
        separator: '·',
        style: const TextStyle(color: Color(0xff4f6676), fontSize: 10),
        children: [
          for (var index = 0; index < values.length; index++)
            _FlatSummaryMetric(
              id: values[index].$1,
              label: values[index].$2,
              value: values[index].$3,
              semanticLabel: semanticLabelAt(index),
              onTap: onTapAt(index),
            ),
        ],
      );
    }
    Widget metricAt(int index) => _FleetSummaryMetric(
      id: values[index].$1,
      label: values[index].$2,
      value: values[index].$3,
      semanticLabel: semanticLabelAt(index),
      onTap: onTapAt(index),
    );
    final vertical = HdModuleColumns.of(context) > 1;
    return Flex(
      key: const Key('fleet-summary-metrics'),
      direction: vertical ? Axis.vertical : Axis.horizontal,
      crossAxisAlignment: vertical
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.center,
      children: [
        for (var index = 0; index < values.length; index++) ...[
          if (vertical) metricAt(index) else Expanded(child: metricAt(index)),
          if (index != values.length - 1)
            SizedBox(width: vertical ? 0 : 4, height: vertical ? 3 : 0),
        ],
      ],
    );
  }
}

class _FleetSummaryMetric extends StatelessWidget {
  const _FleetSummaryMetric({
    required this.id,
    required this.label,
    required this.value,
    this.onTap,
    this.semanticLabel,
  });

  final String id;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Material(
    key: Key('fleet-summary-metric-$id'),
    color: const Color(0xff102331),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: const BorderSide(color: Color(0xff294052)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Semantics(
      button: onTap != null,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: HdModuleColumns.of(context) > 1 ? 26 : 28,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Color(0xff8197a5),
                      fontSize: 8,
                      height: 1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    key: Key('fleet-summary-metric-$id-value'),
                    maxLines: 1,
                    style: const TextStyle(
                      color: Color(0xffdce6eb),
                      fontSize: 8,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _FlatSummaryMetric extends StatelessWidget {
  const _FlatSummaryMetric({
    required this.id,
    required this.label,
    required this.value,
    this.onTap,
    this.semanticLabel,
  });

  final String id;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    label: semanticLabel,
    child: InkWell(
      key: Key('fleet-summary-metric-$id'),
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            style: const TextStyle(color: Color(0xff8197a5), fontSize: 10),
          ),
          const SizedBox(width: 3),
          Text(
            value,
            key: Key('fleet-summary-metric-$id-value'),
            maxLines: 1,
            style: const TextStyle(
              color: Color(0xffdce6eb),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    ),
  );
}
