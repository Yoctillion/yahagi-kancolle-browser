import '../localization/game_name_localizations.dart';
import 'package:flutter/material.dart';

import 'battle_detail_strings.dart';
import 'battle_ui_text.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import '../layout/module_summaries.dart';

import 'battle_controller.dart';
import 'battle_models.dart';
import 'battle_pills.dart';
import 'battle_prediction_sections.dart';
import 'battle_ship_details_popover.dart';
import '../fleet/dashboard_card.dart';
import '../fleet/ship_status_style.dart';
import '../fleet/ship_status_visuals.dart';
import '../fleet/status_density.dart';
import '../layout/flat_list_row.dart';
import '../layout/flat_text_toggle.dart';
import '../layout/panel_style.dart';
import '../game_state/game_state.dart';
import '../settings/battle_prediction_settings.dart';
import '../settings/battle_status_effect_settings.dart';
import '../settings/module_display_settings.dart';
import 'detailed_battle_panel.dart';
import 'land_base_raid_panel.dart';
import 'official_enemy_preview.dart';
import 'prophet_hp_bar.dart';
import 'sortie_map_section.dart';

enum BattlePanelMode { compact, detailed }

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

class _LiveBattleCardState extends State<LiveBattleCard> {
  BattlePanelMode _mode = BattlePanelMode.detailed;
  bool _modeRestored = false;
  bool _mapExpanded = true;
  bool _mapExpansionRestored = false;
  SortieMapSection? _cachedMapSection;

  static const _mapExpansionStorageId = 'prophet-sortie-map-expanded';

  @override
  void didUpdateWidget(covariant LiveBattleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _cachedMapSection = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_mapExpansionRestored) {
      final storedExpansion = PageStorage.maybeOf(
        context,
      )?.readState(context, identifier: _mapExpansionStorageId);
      if (storedExpansion is bool) _mapExpanded = storedExpansion;
      _mapExpansionRestored = true;
    }
    if (_modeRestored) return;
    final storedMode = PageStorage.maybeOf(context)?.readState(context);
    if (storedMode is String) {
      _mode = BattlePanelMode.values.firstWhere(
        (mode) => mode.name == storedMode,
        orElse: () => _mode,
      );
    }
    _modeRestored = true;
  }

  void _setMode(BattlePanelMode mode) {
    setState(() => _mode = mode);
    PageStorage.maybeOf(context)?.writeState(context, mode.name);
  }

  void _toggleMapExpanded() {
    setState(() => _mapExpanded = !_mapExpanded);
    PageStorage.maybeOf(
      context,
    )?.writeState(context, _mapExpanded, identifier: _mapExpansionStorageId);
  }

  SortieMapSection? _buildMapSection(
    LiveBattle? battle, {
    required bool showCurrentNode,
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
    final currentNodeLabel =
        battle != null &&
            battle.context.mapAreaId == progress.mapAreaId &&
            battle.context.mapInfoNo == progress.mapInfoNo &&
            battle.context.node == progress.currentRouteId
        ? battle.context.nodeDisplayLabel
        : null;
    final cached = _cachedMapSection;
    if (cached != null &&
        identical(cached.progress, progress) &&
        identical(cached.geometry, geometry) &&
        cached.currentNodeLabel == currentNodeLabel &&
        cached.showCurrentNode == showCurrentNode &&
        cached.expanded == _mapExpanded) {
      return cached;
    }
    // Reuse only the immutable widget, so its elements still receive inherited
    // locale, text scale, theme and layout updates normally.
    return _cachedMapSection = SortieMapSection(
      progress: progress,
      geometry: geometry,
      expanded: _mapExpanded,
      onToggleExpanded: _toggleMapExpanded,
      currentNodeLabel: currentNodeLabel,
      showCurrentNode: showCurrentNode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final flat = PanelStyleScope.of(context) == PanelStyle.flat;
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final battle = widget.controller.current;
        final idle = battle == null || battle.friendShips.isEmpty;
        // Flat battle and navigation headers already name the current node.
        final mapSection = _buildMapSection(
          battle,
          showCurrentNode: !flat || idle,
        );
        return DashboardCard(
          key: const Key('live-battle-card'),
          collapsedSummary: widget.collapsed
              ? battleSummary(
                  AppLocalizations.of(context) ??
                      lookupAppLocalizations(const Locale('zh')),
                  battle,
                )
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
          titleBadge: idle ? const _IdleBadge() : _StatusBadge(battle: battle),
          trailing: _ModeSwitch(mode: _mode, onChanged: _setMode),
          child: Column(
            key: widget.collapsed
                ? const Key('live-battle-collapsed')
                : const Key('live-battle-expanded'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!idle && !widget.controller.isPredictionConfirmed)
                Padding(
                  key: const Key('battle-unconfirmed-warning'),
                  padding: EdgeInsets.only(bottom: flat ? 4 : 8),
                  child: Text(
                    (AppLocalizations.of(context) ??
                            lookupAppLocalizations(const Locale('zh')))
                        .battlePredictionUnconfirmed,
                    style: TextStyle(
                      color: const Color(0xffffc95c),
                      fontSize: flat ? flatRowFontSize : 12,
                    ),
                  ),
                ),
              if (idle) ...[
                if (mapSection != null) ...[
                  mapSection,
                  SizedBox(height: flat ? 4 : 9),
                ],
                const _IdleBattleContent(),
              ] else if (_mode == BattlePanelMode.detailed)
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
    final flat = PanelStyleScope.of(context) == PanelStyle.flat;
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
      height: 26,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xff10212e),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xff294052)),
      ),
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
      color: selected ? const Color(0xff5b4829) : Colors.transparent,
      borderRadius: BorderRadius.circular(5),
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: BattleUiText(
            label,
            style: TextStyle(
              color: selected
                  ? const Color(0xffffcf67)
                  : const Color(0xff8197a5),
              fontSize: 10,
              fontWeight: FontWeight.w700,
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
    final flat = PanelStyleScope.of(context) == PanelStyle.flat;
    final navigation = battle.displayStage == BattleDisplayStage.navigation;
    if (navigation) {
      final navigationHeader = Container(
        key: const Key('battle-navigation-header'),
        padding: flat
            ? const EdgeInsets.symmetric(vertical: 2)
            : const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        decoration: flat
            ? null
            : BoxDecoration(
                color: const Color(0xff10212e),
                borderRadius: BorderRadius.circular(7),
              ),
        child: flat
            ? FlatNavigationHeader(
                battle: battle,
                showLastFormationHint: showLastFormationHint,
              )
            : Row(
                children: [
                  const Icon(
                    Icons.explore_outlined,
                    size: 18,
                    color: Color(0xff70c7bc),
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
                      children: <Widget>[
                        if (showLastFormationHint &&
                            battle.lastFormation != null)
                          LastFormationPill(formation: battle.lastFormation!),
                        if (battle.context.combinedFleetType !=
                            CombinedFleetType.none)
                          MetaChip(
                            label: battle.context.combinedFleetType.label,
                            color: const Color(0xff70c7bc),
                          ),
                        if (battle.resourceChanges.isNotEmpty)
                          ResourceChangesPill(changes: battle.resourceChanges),
                        if (battle.rewardItems.isNotEmpty)
                          RewardItemsPill(items: battle.rewardItems),
                        if (battle.resourceChanges.isEmpty &&
                            battle.rewardItems.isEmpty)
                          for (final label in battle.context.nodeTypeLabels)
                            NodeTypePill(label: label),
                      ],
                    ),
                  ),
                ],
              ),
      );
      final raid = battle.landBaseRaid;
      final previewShips =
          battle.enemyPreviewShips ?? const <EnemyPreviewShip>[];
      final enemyPreview = OfficialEnemyPreview(
        ships: previewShips,
        combined: battle.enemyPreviewCombined,
      );
      final friendlyFleets = NavigationFriendlyFleets(
        battle: battle,
        damagePulseMode: damagePulseMode,
      );
      return Column(
        key: const Key('compact-battle-panel'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          navigationHeader,
          SizedBox(height: flat ? 4 : 7),
          BattlePredictionSections(
            order: sectionOrder,
            legacyEnemyPreviewPosition: enemyPreviewPosition,
            sortieMap: mapSection,
            enemyPreview: previewShips.isNotEmpty ? enemyPreview : null,
            predictionResult: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (raid != null) ...[
                  LandBaseRaidPanel(result: raid, compact: true),
                  SizedBox(height: flat ? 4 : 9),
                ],
                friendlyFleets,
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
    final dropEntries = <String>[
      if (dropShipNames.isNotEmpty) l10n.dropLabel(dropShipNames.join('、')),
    ];
    final rawEnemyName = battle.enemyFleetName.isNotEmpty
        ? battle.enemyFleetName
        : '敌方舰队';
    final enemyName = rawEnemyName;
    final enemyCombined =
        battle.enemyEscort.isNotEmpty || rawEnemyName.contains('联合舰队');
    final metaChips = _compactMetaChips(battle);
    final statusPills = <Widget>[
      for (final label in battle.context.nodeTypeLabels)
        NodeTypePill(label: label),
      if (battle.airSuperiority != null)
        AirSuperiorityPill(label: battle.airSuperiority!),
      for (final chip in metaChips) MetaChip(label: chip.$1, color: chip.$2),
      for (final entry in dropEntries) DropPill(text: entry),
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
                    _RankBadge(rank: battle.rank, phone: phone, flat: flat),
                    SizedBox(width: flat ? 8 : 11),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AdaptiveBattleHeader(
                          nodeLabel: battle.context.forecastNodeLabel,
                          nodeFontSize: flat ? 12 : 16,
                          enemyName: enemyName,
                          enemyNameIsFallback: battle.enemyFleetName.isEmpty,
                          enemyStyle: TextStyle(
                            fontSize: flat ? 11 : (phone ? 13 : 14),
                            fontWeight: FontWeight.w600,
                            color: enemyCombined
                                ? const Color(0xffff8c78)
                                : null,
                          ),
                        ),
                        if (flat) ...<Widget>[
                          const SizedBox(height: 2),
                          BattleTagLine(
                            battle: battle,
                            nodeLabel: battle.context.forecastNodeLabel,
                            metaChips: metaChips,
                            dropEntries: dropEntries,
                          ),
                        ] else if (statusPills.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 5),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: statusPills,
                          ),
                        ],
                        if (!flat && battle.rewardItems.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 4),
                          RewardItemsPill(items: battle.rewardItems),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: flat ? 4 : 8),
              _CompactFleetGrid(
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

class _CompactFleetGrid extends StatelessWidget {
  const _CompactFleetGrid({
    required this.battle,
    required this.damagePulseMode,
  });

  final LiveBattle battle;
  final DamagePulseFilter damagePulseMode;

  @override
  Widget build(BuildContext context) {
    final flat = PanelStyleScope.of(context) == PanelStyle.flat;
    final friendCombined = battle.friendEscort.isNotEmpty;
    final enemyCombined = battle.enemyEscort.isNotEmpty;
    final mvpPositions = battle.mvpPositions;
    final friendFormation = battle.friendFormation > 0
        ? '（${formationLabel(battle.friendFormation)}）'
        : '';
    final enemyFormation = battle.enemyFormation > 0
        ? '（${formationLabel(battle.enemyFormation)}）'
        : '';
    final friendColumns = <Widget>[];
    final enemyColumns = <Widget>[];
    if (friendCombined) {
      friendColumns.add(
        _CompactFleetColumn(
          keyName: 'friend-main',
          ships: battle.friendMain,
          mvpPositions: mvpPositions,
          damagePulseMode: damagePulseMode,
        ),
      );
      friendColumns.add(
        _CompactFleetColumn(
          keyName: 'friend-escort',
          ships: battle.friendEscort,
          mvpPositions: mvpPositions,
          positionOffset: 6,
          damagePulseMode: damagePulseMode,
        ),
      );
    } else {
      friendColumns.add(
        _CompactFleetColumn(
          keyName: 'friend',
          ships: battle.friendMain,
          mvpPositions: mvpPositions,
          damagePulseMode: damagePulseMode,
        ),
      );
    }
    if (enemyCombined) {
      enemyColumns.add(
        _CompactFleetColumn(
          keyName: 'enemy-escort',
          ships: battle.enemyEscort,
          mvpPositions: const <int>[],
          positionOffset: 6,
          damagePulseMode: damagePulseMode,
        ),
      );
      enemyColumns.add(
        _CompactFleetColumn(
          keyName: 'enemy-main',
          ships: battle.enemyMain,
          mvpPositions: const <int>[],
          damagePulseMode: damagePulseMode,
        ),
      );
    } else {
      enemyColumns.add(
        _CompactFleetColumn(
          keyName: 'enemy',
          ships: battle.enemyMain,
          mvpPositions: const <int>[],
          damagePulseMode: damagePulseMode,
        ),
      );
    }
    return Row(
      key: const Key('compact-fleet-grid'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          flex: friendColumns.length,
          child: Container(
            padding: flat
                ? EdgeInsets.zero
                : const EdgeInsets.fromLTRB(8, 6, 8, 6),
            decoration: flat
                ? null
                : BoxDecoration(
                    color: const Color(0xff10212e),
                    borderRadius: BorderRadius.circular(8),
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _CompactFleetSideTitle(
                  keyName: 'friend',
                  title: '我方舰队$friendFormation',
                  color: const Color(0xff70c7bc),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (
                      var index = 0;
                      index < friendColumns.length;
                      index++
                    ) ...<Widget>[
                      if (index > 0) const SizedBox(width: 7),
                      Expanded(child: friendColumns[index]),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        SizedBox(width: flat ? 6 : 7),
        Expanded(
          flex: enemyColumns.length,
          child: Container(
            padding: flat
                ? EdgeInsets.zero
                : const EdgeInsets.fromLTRB(8, 6, 8, 6),
            decoration: flat
                ? null
                : BoxDecoration(
                    color: const Color(0xff10212e),
                    borderRadius: BorderRadius.circular(8),
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _CompactFleetSideTitle(
                  keyName: 'enemy',
                  title: '敌方舰队$enemyFormation',
                  color: const Color(0xffff8c78),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (
                      var index = 0;
                      index < enemyColumns.length;
                      index++
                    ) ...<Widget>[
                      if (index > 0) const SizedBox(width: 7),
                      Expanded(child: enemyColumns[index]),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CompactFleetSideTitle extends StatelessWidget {
  const _CompactFleetSideTitle({
    required this.keyName,
    required this.title,
    required this.color,
  });

  final String keyName;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: Key('compact-fleet-side-title-$keyName'),
      height: 14,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: BattleUiText(
          title,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _CompactFleetColumn extends StatelessWidget {
  const _CompactFleetColumn({
    required this.keyName,
    required this.ships,
    required this.mvpPositions,
    required this.damagePulseMode,
    this.positionOffset = 0,
  });

  final String keyName;
  final List<BattleShipSnapshot> ships;
  final List<int> mvpPositions;
  final DamagePulseFilter damagePulseMode;
  final int positionOffset;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: Key('compact-fleet-col-$keyName'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < ships.length; index++)
          BattleShipDetailsTap(
            ship: ships[index],
            child: _CompactBarRow(
              ship: ships[index],
              keyName: keyName,
              index: index,
              isMvp: mvpPositions.contains(index + positionOffset),
              damagePulseMode: damagePulseMode,
            ),
          ),
      ],
    );
  }
}

class _CompactBarRow extends StatelessWidget {
  const _CompactBarRow({
    required this.ship,
    required this.keyName,
    required this.index,
    required this.isMvp,
    required this.damagePulseMode,
  });

  final BattleShipSnapshot ship;
  final String keyName;
  final int index;
  final bool isMvp;
  final DamagePulseFilter damagePulseMode;

  @override
  Widget build(BuildContext context) {
    final flat = PanelStyleScope.of(context) == PanelStyle.flat;
    final isEscaped = ship.isEscaped;
    final ratio = ship.maxHp <= 0
        ? 0.0
        : (ship.currentHp / ship.maxHp).clamp(0.0, 1.0);
    final isZeroHp = ship.currentHp <= 0;
    final hpValueColor = isEscaped
        ? yahagiStatusZeroHp
        : shipHpValueColor(ratio, isZeroHp: isZeroHp);
    final hpBarColor = isEscaped
        ? yahagiStatusZeroHp
        : shipHpBarColor(ratio, isZeroHp: isZeroHp);
    final hpText = isEscaped
        ? '${ship.currentHp} / ${ship.maxHp} (退避)'
        : (ship.damageReceived > 0
              ? '${ship.currentHp} / ${ship.maxHp} (-${ship.damageReceived})'
              : '${ship.currentHp} / ${ship.maxHp}');

    Widget hpContent({double opacity = 1, bool pulsing = false}) {
      if (isEscaped) {
        return const Align(
          alignment: Alignment.centerLeft,
          child: BattleUiText(
            '退避',
            style: TextStyle(
              color: Color(0xff8197a5),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      }
      final hpNumber = Opacity(
        key: pulsing ? Key('compact-damage-hp-number-$keyName-$index') : null,
        opacity: opacity,
        child: Text(
          hpText,
          style: TextStyle(
            color: hpValueColor,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      final hpBar = Opacity(
        key: pulsing ? Key('compact-damage-hp-bar-$keyName-$index') : null,
        opacity: opacity,
        child: ProphetHpBar(
          value: ratio,
          color: hpBarColor,
          backgroundColor: const Color(0xff263e4d),
          height: flat ? 4 : 6,
        ),
      );
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                hpNumber,
                if (isMvp) ...<Widget>[
                  const SizedBox(width: 2),
                  Icon(
                    Icons.emoji_events_rounded,
                    key: Key('compact-mvp-$keyName-$index'),
                    size: 9,
                    color: const Color(0xffffd65c),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 2),
          hpBar,
        ],
      );
      return pulsing
          ? KeyedSubtree(
              key: Key('compact-damage-hp-pulse-$keyName-$index'),
              child: content,
            )
          : content;
    }

    final shouldPulse =
        !isEscaped &&
        ship.currentHp > 0 &&
        ship.maxHp > 0 &&
        ship.currentHp * 4 <= ship.maxHp * 3;
    return Padding(
      key: Key('compact-bar-$keyName-$index'),
      padding: flat
          ? const EdgeInsets.symmetric(vertical: 1)
          : const EdgeInsets.fromLTRB(6, 3, 6, 3),
      child: shouldPulse
          ? DamagePulseBuilder(
              currentHp: ship.currentHp,
              maxHp: ship.maxHp,
              filter: damagePulseMode,
              normalColor: hpBarColor,
              builder: (context, spec, phase) => hpContent(
                opacity:
                    spec.minFrameOpacity + phase * (1 - spec.minFrameOpacity),
                pulsing: true,
              ),
            )
          : hpContent(),
    );
  }
}

List<(String, Color)> _compactMetaChips(LiveBattle battle) {
  return <(String, Color)>[
    if (battle.context.combinedFleetType != CombinedFleetType.none)
      (battle.context.combinedFleetType.label, const Color(0xff70c7bc)),
    if (!battle.context.nodeTypeLabels.contains(battle.phaseLabel))
      (battle.phaseLabel, battlePhaseChipColor(battle.phaseLabel)),
    if (battle.engagement > 0)
      (
        engagementLabel(battle.engagement),
        engagementChipColor(battle.engagement),
      ),
  ];
}

class _IdleBadge extends StatelessWidget {
  const _IdleBadge();

  @override
  Widget build(BuildContext context) {
    final flat = PanelStyleScope.of(context) == PanelStyle.flat;
    final label = Text(
      AppLocalizations.of(context)?.standby ?? '待机',
      style: TextStyle(
        color: const Color(0xff9db2bf),
        fontSize: flat ? 10.5 : 11,
        fontWeight: FontWeight.w700,
      ),
    );
    if (flat) return label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xff203443),
        borderRadius: BorderRadius.circular(8),
      ),
      child: label,
    );
  }
}

class _IdleBattleContent extends StatelessWidget {
  const _IdleBattleContent();

  @override
  Widget build(BuildContext context) {
    final flat = PanelStyleScope.of(context) == PanelStyle.flat;
    final text = AppLocalizations.of(context)?.waitingForSortieData ?? '等待出击数据';
    if (flat) {
      return Padding(
        key: const Key('battle-idle-content'),
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            const Icon(
              Icons.explore_outlined,
              size: 13,
              color: Color(0xff70c7bc),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: flatIdleColor,
                  fontSize: flatRowFontSize,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      key: const Key('battle-idle-content'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xff10212e),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.explore_outlined,
            size: 18,
            color: Color(0xff70c7bc),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xff9db2bf),
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
    final flat = PanelStyleScope.of(context) == PanelStyle.flat;
    final text = BattleUiText(
      label,
      style: TextStyle(
        color: foreground,
        fontSize: flat ? 10.5 : 11,
        fontWeight: FontWeight.w700,
      ),
    );
    if (flat) return text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: text,
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({
    required this.rank,
    required this.phone,
    required this.flat,
  });

  final BattleRank rank;
  final bool phone;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    return BattleRankBadge(
      rank: rank,
      size: flat ? 28 : (phone ? 50 : 48),
      fontSize: flat ? 12 : (phone ? 21 : 20),
    );
  }
}
