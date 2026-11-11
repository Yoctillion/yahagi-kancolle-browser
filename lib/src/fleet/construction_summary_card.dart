import '../theme/app_palette.dart';
import 'package:flutter/material.dart';
import '../localization/game_name_localizations.dart';
import '../game_state/game_state_controller.dart';
import '../game_state/game_state.dart';
import '../layout/flat_list_row.dart';
import '../layout/flat_portrait_backdrop.dart';
import '../layout/flat_style.dart';
import '../layout/module_summaries.dart';
import '../layout/panel_style.dart';
import '../performance/second_tick_scope.dart';
import 'dashboard_card.dart';
import '../settings/module_display_settings.dart';
import 'fleet_ui_strings.dart';
import 'operation_progress.dart';
import 'ship_portrait.dart';

import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';

class ConstructionSummaryCard extends StatelessWidget {
  const ConstructionSummaryCard({
    super.key,
    required this.controller,
    required this.collapsed,
    required this.onToggleCollapse,
    required this.onOpenConstruction,
    this.visible = const {'portrait', 'empty'},
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
  final VoidCallback onOpenConstruction;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        final docks = state.constructionDocks;
        // 折叠标题已不展示摘要；展开槽位保留各自的完成计时。
        return SecondTickBuilder(
          enabled: false,
          builder: (context, now, _) => DashboardCard(
            collapsedSummary: collapsed
                ? constructionSummary(
                    AppLocalizations.of(context) ??
                        lookupAppLocalizations(const Locale('zh')),
                    state,
                    now,
                  )
                : null,
            headerAction: moduleDisplayGear(
              context,
              'construction',
              onOpenDisplaySettings,
            ),
            title: AppLocalizations.of(context)?.constructionBrief ?? '建造简报',
            icon: const Icon(Icons.handyman_outlined),
            collapsed: collapsed,
            onToggleCollapse: onToggleCollapse,
            showLogo: showLogo,
            showTitle: showTitle,
            child: ModuleSlotGrid(
              runSpacing: PanelStyleScope.isFlat(context) ? 0 : 8,
              emptyLabel: '暂无建造',
              children: [
                for (var i = 0; i < 4; i++)
                  if (visible.contains('empty') ||
                      (docks.length > i && docks[i].isBuilding))
                    _buildConstructionSlot(
                      docks.length > i ? docks[i] : null,
                      state,
                      i + 1,
                    ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildConstructionSlot(
    ConstructionDock? dock,
    GameState state,
    int position,
  ) {
    return SecondTickBuilder(
      enabled:
          dock != null &&
          dock.isBuilding &&
          dock.state != 3 &&
          dock.completionTime != null,
      stopAt: dock?.completionTime,
      builder: (context, now, _) =>
          _buildConstructionSlotAt(context, dock, state, position, now),
    );
  }

  Widget _buildConstructionSlotAt(
    BuildContext context,
    ConstructionDock? dock,
    GameState state,
    int position,
    DateTime now,
  ) {
    String name = '未知';
    bool active = false;
    bool disabled = true;
    MasterShip? master;

    if (dock != null) {
      if (dock.isLocked) {
        name = '未知';
        disabled = true;
      } else if (!dock.isBuilding) {
        name = '空闲';
        disabled = false;
      } else {
        master = state.masterShips[dock.createdShipMasterId];
        name =
            (master == null
                ? null
                : gameNames(
                    context,
                  ).shipName(master.name, shipId: master.id)) ??
            '建中';
        disabled = false;
        active = true;
      }
    }

    if (PanelStyleScope.isFlat(context)) {
      final completed = active && dock != null && dock.isCompletedAt(now);
      final hasPortrait = visible.contains('portrait') && master != null;
      final shadows = hasPortrait ? flatOnImageShadows(context) : null;
      final slotKey = Key('construction-summary-slot-$position');
      final row = FlatListRow(
        key: hasPortrait ? null : slotKey,
        onTap: onOpenConstruction,
        name: flatRowText(
          context,
          active ? name : '',
          color: disabled ? const Color(0xff4a5c68) : Colors.white,
          shadows: shadows,
        ),
        trailing: active && dock != null
            ? flatRowTrailing(
                completed
                    ? Text(
                        fleetText(context, '已完成'),
                        style: flatRowTextStyle(
                          context,
                          color: flatDoneColor,
                          shadows: shadows,
                        ),
                      )
                    : OperationCountdownText(
                        completionTime: dock.completionTime,
                        completedText: fleetText(context, '已完成'),
                        completedColor: flatDoneColor,
                        countingColor: flatAccentColor,
                        style: flatRowTextStyle(context, shadows: shadows),
                      ),
              )
            : Text(
                fleetText(context, disabled ? '锁' : '闲置'),
                maxLines: 1,
                style: flatRowTextStyle(
                  context,
                  color: disabled ? const Color(0xff4a5c68) : flatMutedColor,
                ),
              ),
      );
      if (!hasPortrait) return row;
      return FlatPortraitBackdrop(
        key: slotKey,
        image: (width, height) => ShipPortrait(
          ship: master,
          serverOrigin: state.serverOrigin,
          width: width,
          height: height,
        ),
        child: row,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final inline =
            !visible.contains('portrait') && constraints.maxWidth >= 180;
        // HD slots can be narrower than a portrait plus one name/status line.
        // Stack those slots so the fixed portrait cannot consume the text width.
        final stackedPortrait =
            visible.contains('portrait') && constraints.maxWidth < 92;
        final available = constraints.maxWidth - 18;
        final portraitWidth = stackedPortrait
            ? (constraints.maxWidth - 12).clamp(0.0, 96.0).toDouble()
            : available >= 138
            ? 96.0
            : (available - 42).clamp(32.0, 96.0).toDouble();
        final iconWidth = portraitWidth < 32 ? portraitWidth : 32.0;
        final completed = active && dock != null && dock.isCompletedAt(now);
        final statusDotColor = completed
            ? const Color(0xff4caf50)
            : const Color(0xffffc940);
        return Material(
          color: appColor(context, Colors.transparent),
          child: InkWell(
            onTap: onOpenConstruction,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(
                color: appColor(context, Color(0xff0d1a26)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Flex(
                direction: stackedPortrait ? Axis.vertical : Axis.horizontal,
                children: [
                  if (visible.contains('portrait')) ...[
                    if (master != null) ...[
                      ShipPortrait(
                        ship: master,
                        serverOrigin: state.serverOrigin,
                        width: portraitWidth,
                        height: 32,
                      ),
                      SizedBox(
                        width: stackedPortrait ? 0 : 6,
                        height: stackedPortrait ? 6 : 0,
                      ),
                    ] else ...[
                      Container(
                        width: iconWidth,
                        height: 32,
                        decoration: BoxDecoration(
                          color: appColor(context, Color(0xff142735)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.handyman_rounded,
                            size: 16,
                            color: appColor(
                              context,
                              disabled
                                  ? const Color(0xff4a5c68)
                                  : const Color(0xff8197a5),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: stackedPortrait ? 0 : 6,
                        height: stackedPortrait ? 6 : 0,
                      ),
                    ],
                  ],
                  _constructionTextPart(
                    stackedPortrait,
                    Flex(
                      direction: inline ? Axis.horizontal : Axis.vertical,
                      crossAxisAlignment: inline
                          ? CrossAxisAlignment.center
                          : CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _constructionTextPart(
                          !inline,
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${visible.contains('empty') ? '' : '$position · '}${master == null ? fleetText(context, name) : name}',
                                  style: appTextStyle(
                                    context,
                                    TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: disabled
                                          ? const Color(0xff4a5c68)
                                          : Colors.white,
                                    ),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (active)
                                Container(
                                  width: 6,
                                  height: 6,
                                  margin: const EdgeInsets.only(left: 4),
                                  decoration: BoxDecoration(
                                    color: appColor(context, statusDotColor),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (inline) const SizedBox(width: 6),
                        if (active && dock != null)
                          _constructionTextPart(
                            !inline,
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: completed
                                  ? Text(
                                      fleetText(context, '已完成'),
                                      style: appTextStyle(
                                        context,
                                        operationSummaryTimeStyle.copyWith(
                                          color: const Color(0xff4caf50),
                                        ),
                                      ),
                                    )
                                  : OperationCountdownText(
                                      completionTime: dock.completionTime,
                                      completedText: fleetText(context, '已完成'),
                                      completedColor: const Color(0xff4caf50),
                                      countingColor: const Color(0xffd4a85f),
                                      style: operationSummaryTimeStyle,
                                    ),
                            ),
                          )
                        else ...[
                          const SizedBox(height: 2),
                          Text(
                            fleetText(context, disabled ? '锁' : '闲置'),
                            style: appTextStyle(
                              context,
                              TextStyle(
                                fontSize: 11,
                                color: disabled
                                    ? const Color(0xff4a5c68)
                                    : const Color(0xff8197a5),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

Widget _constructionTextPart(bool portrait, Widget child) =>
    portrait ? child : Expanded(child: child);
