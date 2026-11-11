import '../widgets/app_segmented_style.dart';
import '../theme/app_palette.dart';
import '../localization/game_name_localizations.dart';
import 'package:flutter/material.dart';

import 'battle_detail_strings.dart';
import 'battle_ui_text.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import '../layout/flat_list_row.dart';
import '../layout/flat_style.dart';
import '../layout/module_summaries.dart';

import 'battle_controller.dart';
import 'battle_fleet_grid.dart';
import 'battle_models.dart';
import 'battle_node_icon.dart';
import 'battle_pills.dart';
import 'battle_prediction_sections.dart';
import 'battle_ship_details_popover.dart';
import '../fleet/dashboard_card.dart';
import '../fleet/status_density.dart';
import '../layout/flat_text_toggle.dart';
import '../layout/panel_style.dart';
import '../game_state/game_state.dart';
import '../settings/battle_prediction_settings.dart';
import '../settings/battle_status_effect_settings.dart';
import '../settings/module_display_settings.dart';
import '../settings/panel_view_preferences.dart';
import 'detailed_battle_panel.dart';
import 'land_base_raid_panel.dart';
import 'official_enemy_preview.dart';
import 'flat_air_battle_section.dart';
import 'flat_battle_header.dart';
import 'sortie_map_progress.dart';
import 'sortie_map_section.dart';

class LiveBattleCard extends StatefulWidget {
  const LiveBattleCard({
    super.key,
    required this.controller,
    required this.collapsed,
    required this.onToggleCollapse,
    this.damagePulseMode = DamagePulseFilter.all,
    this.showEnemyPortraits = true,
    this.showLastFormationHint = true,
    this.enemyPreviewPosition = EnemyPreviewPosition.above,
    this.sectionOrder,
    this.showLogo = true,
    this.showTitle = true,
    this.onOpenDisplaySettings,
  });

  final BattleController controller;
  final bool collapsed;
  final VoidCallback onToggleCollapse;
  final DamagePulseFilter damagePulseMode;
  final bool showEnemyPortraits;
  final bool showLastFormationHint;
  final EnemyPreviewPosition enemyPreviewPosition;
  final List<BattlePredictionSection>? sectionOrder;
  final bool showLogo;
  final bool showTitle;
  final VoidCallback? onOpenDisplaySettings;

  @override
  State<LiveBattleCard> createState() => _LiveBattleCardState();
}

class _LiveBattleCardState extends State<LiveBattleCard>
    with PanelViewPreferencesHost {
  SortieMapSection? _cachedMapSection;
  SortieMapBody? _cachedMapBody;

  @override
  void didUpdateWidget(covariant LiveBattleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _cachedMapSection = null;
    }
  }

  void _setMode(BattlePanelMode mode) => panelViewPreferences.battleMode = mode;

  void _toggleMapExpanded() {
    final preferences = panelViewPreferences;
    preferences.battleMapExpanded = !preferences.battleMapExpanded;
  }

  String? _currentNodeLabel(LiveBattle? battle, SortieMapProgress progress) =>
      battle != null &&
          battle.context.mapAreaId == progress.mapAreaId &&
          battle.context.mapInfoNo == progress.mapInfoNo &&
          battle.context.node == progress.currentRouteId
      ? battle.context.nodeDisplayLabel
      : null;

  /// The map split for a flat header that already names the node: its toggle
  /// and, while expanded, the map to show under that header.
  ({Widget toggle, Widget? body})? _buildHeaderMap(
    LiveBattle battle, {
    required bool expanded,
  }) {
    final progress = widget.controller.sortieMapProgress;
    if (widget.collapsed || battle.context.practice || progress == null) {
      _cachedMapBody = null;
      return null;
    }
    final toggle = SortieMapToggle(
      progress: progress,
      expanded: expanded,
      onToggleExpanded: _toggleMapExpanded,
    );
    if (!expanded) return (toggle: toggle, body: null);
    final geometry = widget.controller.sortieMapGeometry;
    final currentNodeLabel = _currentNodeLabel(battle, progress);
    final cached = _cachedMapBody;
    if (cached != null &&
        identical(cached.progress, progress) &&
        identical(cached.geometry, geometry) &&
        cached.currentNodeLabel == currentNodeLabel) {
      return (toggle: toggle, body: cached);
    }
    return (
      toggle: toggle,
      body: _cachedMapBody = SortieMapBody(
        progress: progress,
        geometry: geometry,
        currentNodeLabel: currentNodeLabel,
      ),
    );
  }

  SortieMapSection? _buildMapSection(
    LiveBattle? battle, {
    required bool showCurrentNode,
    required bool expanded,
  }) {
    // DashboardCard does not mount its child while collapsed. Avoid even the
    // first lazy geometry parse until the map can be shown.
    if (widget.collapsed || battle?.context.practice == true) {
      _cachedMapSection = null;
      return null;
    }
    final progress = widget.controller.sortieMapProgress;
    if (progress == null) {
      _cachedMapSection = null;
      return null;
    }
    final geometry = widget.controller.sortieMapGeometry;
    final currentNodeLabel = _currentNodeLabel(battle, progress);
    final cached = _cachedMapSection;
    if (cached != null &&
        identical(cached.progress, progress) &&
        identical(cached.geometry, geometry) &&
        cached.currentNodeLabel == currentNodeLabel &&
        cached.showCurrentNode == showCurrentNode &&
        cached.expanded == expanded) {
      return cached;
    }
    // Reuse only the immutable widget, so its elements still receive inherited
    // locale, text scale, theme and layout updates normally.
    return _cachedMapSection = SortieMapSection(
      progress: progress,
      geometry: geometry,
      expanded: expanded,
      onToggleExpanded: _toggleMapExpanded,
      currentNodeLabel: currentNodeLabel,
      showCurrentNode: showCurrentNode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final flat = PanelStyleScope.isFlat(context);
    final preferences = panelViewPreferences;
    final mode = preferences.battleMode;
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final battle = widget.controller.current;
        final idle = battle == null || battle.friendShips.isEmpty;
        // The flat header carries the map toggle on its own row.
        final headerMap = flat && !idle
            ? _buildHeaderMap(battle, expanded: preferences.battleMapExpanded)
            : null;
        // Flat battle and navigation headers already name the current node.
        final mapSection = headerMap != null
            ? null
            : _buildMapSection(
                battle,
                showCurrentNode: !flat || idle,
                expanded: preferences.battleMapExpanded,
              );
        return DashboardCard(
          key: const Key('live-battle-card'),
          collapsedSummary: widget.collapsed
              ? battleSummary(BattleDetailStrings.of(context), battle)
              : null,
          title: AppLocalizations.of(context)?.forecast ?? '未卜先知',
          icon: const Icon(Icons.remove_red_eye_outlined),
          collapsed: widget.collapsed,
          onToggleCollapse: widget.onToggleCollapse,
          showLogo: widget.showLogo,
          showTitle: widget.showTitle,
          headerAction: moduleDisplayGear(
            context,
            'battle',
            widget.onOpenDisplaySettings,
          ),
          titleBadge: idle
              ? (flat ? null : const _IdleBadge())
              : _StatusBadge(battle: battle),
          trailing: _ModeSwitch(mode: mode, onChanged: _setMode),
          child: Column(
            key: widget.collapsed
                ? const Key('live-battle-collapsed')
                : const Key('live-battle-expanded'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.controller.isPredictionConfirmed)
                Padding(
                  key: const Key('battle-unconfirmed-warning'),
                  padding: EdgeInsets.only(bottom: flat ? flatSectionGap : 8),
                  child: Text(
                    (AppLocalizations.of(context) ??
                            lookupAppLocalizations(const Locale('zh')))
                        .battlePredictionUnconfirmed,
                    style: TextStyle(
                      color: appColor(context, const Color(0xffffc95c)),
                      fontSize: flat ? flatRowFontSize : 12,
                    ),
                  ),
                ),
              if (idle) ...[
                if (mapSection != null) ...[
                  mapSection,
                  SizedBox(height: flat ? flatSectionGap : 9),
                ],
                const _IdleBattleContent(),
              ] else if (flat)
                BattleShipDetailsHost(
                  battle: battle,
                  latestGameState: () => widget.controller.gameStateSnapshot,
                  child: _FlatBattlePanel(
                    battle: battle,
                    gameState: widget.controller.gameStateSnapshot,
                    damagePulseMode: widget.damagePulseMode,
                    showLastFormationHint: widget.showLastFormationHint,
                    detailed: mode == BattlePanelMode.detailed,
                    mapSection: mapSection,
                    mapToggle: headerMap?.toggle,
                    mapBody: headerMap?.body,
                  ),
                )
              else if (mode == BattlePanelMode.detailed)
                DetailedBattlePanel(
                  battle: battle,
                  gameState: widget.controller.gameStateSnapshot,
                  latestGameState: () => widget.controller.gameStateSnapshot,
                  damagePulseMode: widget.damagePulseMode,
                  showEnemyPortraits: widget.showEnemyPortraits,
                  showLastFormationHint: widget.showLastFormationHint,
                  enemyPreviewPosition: widget.enemyPreviewPosition,
                  sectionOrder: widget.sectionOrder,
                  mapSection: mapSection,
                )
              else
                BattleShipDetailsHost(
                  battle: battle,
                  latestGameState: () => widget.controller.gameStateSnapshot,
                  child: _CompactBattlePanel(
                    battle: battle,
                    gameState: widget.controller.gameStateSnapshot,
                    damagePulseMode: widget.damagePulseMode,
                    showLastFormationHint: widget.showLastFormationHint,
                    enemyPreviewPosition: widget.enemyPreviewPosition,
                    sectionOrder: widget.sectionOrder,
                    mapSection: mapSection,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.mode, required this.onChanged});

  final BattlePanelMode mode;
  final ValueChanged<BattlePanelMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final flat = PanelStyleScope.isFlat(context);
    if (flat) {
      // BattleUiText 在显示时按语言本地化标签，共享组件只渲染 Text，所以这里先转换。
      final strings = BattleDetailStrings.of(context);
      return FlatTextToggle(
        options: [
          FlatTextToggleOption(
            key: const Key('battle-mode-compact'),
            label: strings.localize(
              AppLocalizations.of(context)?.compact ?? '紧凑',
            ),
            selected: mode == BattlePanelMode.compact,
            onTap: () => onChanged(BattlePanelMode.compact),
          ),
          FlatTextToggleOption(
            key: const Key('battle-mode-detailed'),
            label: strings.localize(
              AppLocalizations.of(context)?.detailed ?? '完整',
            ),
            selected: mode == BattlePanelMode.detailed,
            onTap: () => onChanged(BattlePanelMode.detailed),
          ),
        ],
      );
    }
    return Container(
      height: AppSegmentedStyle.compactHeight,
      padding: AppSegmentedStyle.padding(compact: true),
      decoration: AppSegmentedStyle.decoration(context, compact: true),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeButton(
            key: const Key('battle-mode-compact'),
            label: AppLocalizations.of(context)?.compact ?? '紧凑',
            selected: mode == BattlePanelMode.compact,
            onTap: () => onChanged(BattlePanelMode.compact),
          ),
          _ModeButton(
            key: const Key('battle-mode-detailed'),
            label: AppLocalizations.of(context)?.detailed ?? '完整',
            selected: mode == BattlePanelMode.detailed,
            onTap: () => onChanged(BattlePanelMode.detailed),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppSegmentedStyle.selection(context, selected),
      borderRadius: AppSegmentedStyle.itemRadius(compact: true),
      child: InkWell(
        borderRadius: AppSegmentedStyle.itemRadius(compact: true),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: BattleUiText(
            label,
            style: AppSegmentedStyle.textStyle(
              context,
              selected: selected,
              compact: true,
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactBattlePanel extends StatelessWidget {
  const _CompactBattlePanel({
    required this.battle,
    required this.gameState,
    required this.damagePulseMode,
    required this.showLastFormationHint,
    required this.enemyPreviewPosition,
    this.sectionOrder,
    this.mapSection,
  });

  final LiveBattle battle;
  final GameState gameState;
  final DamagePulseFilter damagePulseMode;
  final bool showLastFormationHint;
  final EnemyPreviewPosition enemyPreviewPosition;
  final List<BattlePredictionSection>? sectionOrder;
  final Widget? mapSection;

  @override
  Widget build(BuildContext context) {
    final phone = isPhoneDensity(context);
    final navigation = battle.displayStage == BattleDisplayStage.navigation;
    if (navigation) {
      final raid = battle.landBaseRaid;
      final previewShips =
          battle.enemyPreviewShips ?? const <EnemyPreviewShip>[];
      return Column(
        key: const Key('compact-battle-panel'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const Key('battle-navigation-header'),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
            decoration: BoxDecoration(
              color: appColor(context, const Color(0xff10212e)),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.explore_outlined,
                  size: 18,
                  color: appColor(context, const Color(0xff70c7bc)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: BattleUiText(
                    battle.context.forecastNodeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    alignment: WrapAlignment.end,
                    children: navigationHeaderPills(
                      battle,
                      showLastFormationHint: showLastFormationHint,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          BattlePredictionSections(
            order: sectionOrder,
            legacyEnemyPreviewPosition: enemyPreviewPosition,
            sortieMap: mapSection,
            enemyPreview: previewShips.isNotEmpty
                ? OfficialEnemyPreview(
                    ships: previewShips,
                    combined: battle.enemyPreviewCombined,
                  )
                : null,
            predictionResult: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (raid != null) ...[
                  LandBaseRaidPanel(result: raid, compact: true),
                  const SizedBox(height: 9),
                ],
                NavigationFriendlyFleets(
                  battle: battle,
                  damagePulseMode: damagePulseMode,
                ),
              ],
            ),
          ),
        ],
      );
    }
    final l10n =
        AppLocalizations.of(context) ??
        lookupAppLocalizations(const Locale('zh'));
    final dropShipNames = <String>[
      for (final id in battle.effectiveDropShipMasterIds)
        gameNames(
          context,
        ).shipName(gameState.masterShips[id]?.name ?? 'ID: $id', shipId: id),
    ];
    final enemyCombined =
        battle.enemyEscort.isNotEmpty || battle.enemyFleetName.contains('联合舰队');
    final metaChips = _compactMetaChips(battle, includeEngagement: true);
    final statusPills = <Widget>[
      for (final label in battle.context.nodeTypeLabels)
        NodeTypePill(label: label),
      if (battle.airSuperiority != null)
        AirSuperiorityPill(label: battle.airSuperiority!),
      for (final chip in metaChips) MetaChip(label: chip.$1, color: chip.$2),
      if (dropShipNames.isNotEmpty)
        DropPill(text: l10n.dropLabel(dropShipNames.join('、'))),
    ];

    return Column(
      key: const Key('compact-battle-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BattlePredictionSections(
          order: sectionOrder,
          legacyEnemyPreviewPosition: enemyPreviewPosition,
          sortieMap: mapSection,
          predictionResult: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (battle.rank != BattleRank.unknown) ...<Widget>[
                    BattleRankBadge(
                      rank: battle.rank,
                      size: phone ? 50 : 48,
                      fontSize: phone ? 21 : 20,
                    ),
                    const SizedBox(width: 11),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AdaptiveBattleHeader(
                          nodeLabel: battle.context.forecastNodeLabel,
                          enemyName: battle.enemyFleetName.isNotEmpty
                              ? battle.enemyFleetName
                              : '敌方舰队',
                          enemyNameIsFallback: battle.enemyFleetName.isEmpty,
                          enemyStyle: TextStyle(
                            fontSize: phone ? 13 : 14,
                            fontWeight: FontWeight.w600,
                            color: appColor(
                              context,
                              enemyCombined ? const Color(0xffff8c78) : null,
                            ),
                          ),
                        ),
                        if (statusPills.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 5),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: statusPills,
                          ),
                        ],
                        if (battle.rewardItems.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 4),
                          RewardItemsPill(items: battle.rewardItems),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              BattleFleetGrid(
                battle: battle,
                damagePulseMode: damagePulseMode,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Flat layout shared by navigation, battle and both panel modes: one header
/// row with the node, enemy fleet name and map toggle, then the formation line
/// and the friend/enemy grid, so the panel keeps its shape when the battle
/// starts or the mode switches. Detailed mode only adds ship names.
class _FlatBattlePanel extends StatelessWidget {
  const _FlatBattlePanel({
    required this.battle,
    required this.gameState,
    required this.damagePulseMode,
    required this.showLastFormationHint,
    required this.detailed,
    this.mapToggle,
    this.mapBody,
    this.mapSection,
  });

  final LiveBattle battle;
  final GameState gameState;
  final DamagePulseFilter damagePulseMode;
  final bool showLastFormationHint;
  final bool detailed;
  final Widget? mapToggle;
  final Widget? mapBody;

  /// Only when the toggle could not join the header.
  final Widget? mapSection;

  @override
  Widget build(BuildContext context) {
    final navigation = battle.displayStage == BattleDisplayStage.navigation;
    final strings = BattleDetailStrings.of(context);
    final l10n =
        AppLocalizations.of(context) ??
        lookupAppLocalizations(const Locale('zh'));
    final confirmedName = battle.enemyFleetName;
    final guessed =
        confirmedName.isEmpty && battle.enemyFleetNameGuess.isNotEmpty;
    final enemyName = confirmedName.isNotEmpty
        ? confirmedName
        : guessed
        ? battle.enemyFleetNameGuess
        : navigation
        ? null
        : strings.localize('敌方舰队');
    final details = <Widget>[];
    if (navigation) {
      details.add(FlatNavigationTagLine(battle: battle));
    } else {
      final dropShipNames = <String>[
        for (final id in battle.effectiveDropShipMasterIds)
          gameNames(
            context,
          ).shipName(gameState.masterShips[id]?.name ?? 'ID: $id', shipId: id),
      ];
      details
        ..add(
          BattleTagLine(
            battle: battle,
            metaLabels: [
              for (final chip in _compactMetaChips(
                battle,
                includeEngagement: false,
              ))
                chip.$1,
            ],
          ),
        )
        ..add(
          BattleDropLine(
            dropEntries: [
              if (dropShipNames.isNotEmpty)
                l10n.dropLabel(dropShipNames.join('、')),
            ],
            rewardItems: battle.rewardItems,
          ),
        );
    }
    final header = FlatBattleHeader(
      nodeIcon: BattleNodeIcon(nodeContext: battle.context),
      nodeLabel: strings.localize(battle.context.forecastNodeLabel),
      enemyName: enemyName,
      enemyNameColor: flatEnemyNameColor(
        guessed: guessed,
        combined:
            battle.enemyEscort.isNotEmpty ||
            (enemyName?.contains('联合舰队') ?? false),
      ),
      mapToggle: mapToggle,
      mapBody: mapBody,
      details: details,
      rank: !navigation && battle.rank != BattleRank.unknown
          ? battle.rank
          : null,
    );
    final dayAir = detailed && !(battle.dayAir?.isEmpty ?? true)
        ? battle.dayAir
        : null;
    final night = detailed && !(battle.night?.isEmpty ?? true)
        ? battle.night
        : null;
    return Column(
      key: Key(detailed ? 'detailed-battle-panel' : 'compact-battle-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (mapSection case final section?) ...[
          section,
          const SizedBox(height: flatSectionGap),
        ],
        KeyedSubtree(
          key: Key(
            navigation ? 'battle-navigation-header' : 'battle-result-header',
          ),
          child: header,
        ),
        if (navigation && battle.landBaseRaid != null) ...[
          const SizedBox(height: flatSectionGap),
          LandBaseRaidPanel(result: battle.landBaseRaid!, compact: true),
        ],
        const SizedBox(height: flatSectionGap),
        BattleFleetGrid(
          battle: battle,
          damagePulseMode: damagePulseMode,
          lastFormation: showLastFormationHint ? battle.lastFormation : null,
          showShipNames: detailed,
        ),
        if (dayAir != null) ...[
          const SizedBox(height: flatSectionGap),
          FlatAirBattleSection(
            report: dayAir,
            friendMain: battle.friendMain,
            friendEscort: battle.friendEscort,
            slotItems: gameState.masterSlotItems,
          ),
        ],
        if (night != null) ...[
          const SizedBox(height: flatSectionGap),
          FlatNightBattleSection(
            report: night,
            friendMain: battle.friendMain,
            friendEscort: battle.friendEscort,
            enemyMain: battle.enemyMain,
            enemyEscort: battle.enemyEscort,
            slotItems: gameState.masterSlotItems,
          ),
        ],
      ],
    );
  }
}

List<(String, Color)> _compactMetaChips(
  LiveBattle battle, {
  required bool includeEngagement,
}) {
  return <(String, Color)>[
    if (battle.context.combinedFleetType != CombinedFleetType.none)
      (battle.context.combinedFleetType.label, const Color(0xff70c7bc)),
    if (!battle.context.nodeTypeLabels.contains(battle.phaseLabel))
      (battle.phaseLabel, battlePhaseChipColor(battle.phaseLabel)),
    if (includeEngagement && battle.engagement > 0)
      (
        engagementLabel(battle.engagement),
        engagementChipColor(battle.engagement),
      ),
  ];
}

/// 标题行右侧的状态徽章：卡片档是胶囊，扁平档只留文字。
class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({
    required this.color,
    required this.background,
    required this.label,
  });

  final Color color;
  final Color background;
  final Widget Function(TextStyle style) label;

  @override
  Widget build(BuildContext context) {
    final flat = PanelStyleScope.isFlat(context);
    final text = label(
      TextStyle(
        color: appColor(context, color),
        fontSize: flat ? flatSmallFontSize : 11,
        fontWeight: FontWeight.w700,
      ),
    );
    if (flat) return text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: appColor(context, background),
        borderRadius: BorderRadius.circular(8),
      ),
      child: text,
    );
  }
}

class _IdleBadge extends StatelessWidget {
  const _IdleBadge();

  @override
  Widget build(BuildContext context) => _HeaderBadge(
    color: const Color(0xff9db2bf),
    background: const Color(0xff203443),
    label: (style) =>
        Text(AppLocalizations.of(context)?.standby ?? '待机', style: style),
  );
}

class _IdleBattleContent extends StatelessWidget {
  const _IdleBattleContent();

  @override
  Widget build(BuildContext context) {
    final flat = PanelStyleScope.isFlat(context);
    final text = AppLocalizations.of(context)?.waitingForSortieData ?? '等待出击数据';
    if (flat) {
      return Padding(
        key: const Key('battle-idle-content'),
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: FlatIconLine(
          icon: Icons.explore_outlined,
          color: const Color(0xff70c7bc),
          child: Text(
            text,
            style: TextStyle(
              color: appColor(context, flatMutedColor),
              fontSize: flatRowFontSize,
            ),
          ),
        ),
      );
    }
    return Container(
      key: const Key('battle-idle-content'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: appColor(context, Color(0xff10212e)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          Icon(
            Icons.explore_outlined,
            size: 18,
            color: appColor(context, Color(0xff70c7bc)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: appColor(context, const Color(0xff9db2bf)),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.battle});

  final LiveBattle battle;

  @override
  Widget build(BuildContext context) {
    final navigation = battle.displayStage == BattleDisplayStage.navigation;
    final forecast = battle.status == LiveBattleStatus.forecast;
    final label = navigation
        ? '航向'
        : forecast
        ? '预判'
        : '已确认';
    final foreground = navigation
        ? const Color(0xff70c7bc)
        : forecast
        ? const Color(0xffffc95c)
        : const Color(0xff83d5c8);
    final background = navigation
        ? const Color(0xff18343c)
        : forecast
        ? const Color(0xff4a3b21)
        : const Color(0xff183e38);
    return _HeaderBadge(
      color: foreground,
      background: background,
      label: (style) => BattleUiText(label, style: style),
    );
  }
}
