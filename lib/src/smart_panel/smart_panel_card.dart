import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../fleet/dashboard_card.dart';
import '../layout/flat_style.dart';
import '../layout/flat_text_toggle.dart';
import '../layout/flat_underline_tabs.dart';
import '../layout/panel_style.dart';
import '../settings/module_display_settings.dart';
import '../settings/smart_panel_settings.dart';
import '../theme/app_palette.dart';
import 'smart_panel_controller.dart';

String smartPanelStateLabel(AppLocalizations l10n, SmartPanelState state) =>
    switch (state) {
      SmartPanelState.home => l10n.smartPanelStateHome,
      SmartPanelState.sortieCheck => l10n.smartPanelStateSortieCheck,
      SmartPanelState.battle => l10n.smartPanelStateBattle,
      SmartPanelState.quests => l10n.smartPanelStateQuests,
      SmartPanelState.expeditionCheck => l10n.smartPanelStateExpeditionCheck,
      SmartPanelState.practice => l10n.smartPanelStatePractice,
    };

const smartPanelStateIcons = <SmartPanelState, IconData>{
  SmartPanelState.home: Icons.explore_outlined,
  SmartPanelState.sortieCheck: Icons.flag_outlined,
  SmartPanelState.battle: Icons.gps_fixed,
  SmartPanelState.quests: Icons.assignment_outlined,
  SmartPanelState.expeditionCheck: Icons.fact_check_outlined,
  SmartPanelState.practice: Icons.groups_outlined,
};

/// Detail-area card whose content follows [SmartPanelController.state]. The
/// state body is wrapped in [DashboardCardEmbedScope] so existing cards render
/// without their own shell.
class SmartPanelCard extends StatelessWidget {
  const SmartPanelCard({
    super.key,
    required this.controller,
    required this.collapsed,
    required this.onToggleCollapse,
    required this.stateBody,
    required this.headerStyle,
    this.showLogo = true,
    this.showTitle = true,
    this.onOpenDisplaySettings,
  });

  final SmartPanelController controller;
  final bool collapsed;
  final VoidCallback onToggleCollapse;
  final Widget Function(BuildContext context, SmartPanelState state) stateBody;
  final SmartPanelHeaderStyle headerStyle;
  final bool showLogo;
  final bool showTitle;
  final VoidCallback? onOpenDisplaySettings;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final l10n =
          AppLocalizations.of(context) ??
          lookupAppLocalizations(const Locale('zh'));
      final state = controller.state;
      final label = smartPanelStateLabel(l10n, state);
      final auto = controller.autoSelected ? _AutoMarker(l10n) : null;
      final body = DashboardCardEmbedScope(
        child: KeyedSubtree(
          key: ValueKey(state),
          child: stateBody(context, state),
        ),
      );
      final tabs = headerStyle == SmartPanelHeaderStyle.tabs;
      return DashboardCard(
        title: tabs ? l10n.smartPanelTitle : label,
        icon: Icon(
          tabs
              ? Icons.dashboard_customize_outlined
              : smartPanelStateIcons[state],
        ),
        collapsed: collapsed,
        onToggleCollapse: onToggleCollapse,
        showLogo: showLogo,
        showTitle: showTitle,
        collapsedSummary: collapsed ? label : null,
        headerAction: moduleDisplayGear(
          context,
          'smart',
          onOpenDisplaySettings,
        ),
        titleBadge: switch (headerStyle) {
          SmartPanelHeaderStyle.dropdown => Row(
            mainAxisSize: MainAxisSize.min,
            children: [_menu(context, l10n), ?auto],
          ),
          _ => auto,
        },
        trailing: switch (headerStyle) {
          SmartPanelHeaderStyle.dropdown => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HeaderButton(
                key: const Key('smart-panel-prev'),
                icon: Icons.chevron_left,
                onPressed: () => _step(-1),
              ),
              _HeaderButton(
                key: const Key('smart-panel-next'),
                icon: Icons.chevron_right,
                onPressed: () => _step(1),
              ),
            ],
          ),
          SmartPanelHeaderStyle.icons => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in smartPanelStateIcons.entries)
                _HeaderButton(
                  key: Key('smart-panel-icon-${entry.key.name}'),
                  icon: entry.value,
                  tooltip: smartPanelStateLabel(l10n, entry.key),
                  selected: entry.key == state,
                  onPressed: () => controller.select(entry.key),
                ),
            ],
          ),
          SmartPanelHeaderStyle.tabs => null,
        },
        child: tabs
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FlatUnderlineTabs(
                    options: [
                      for (final option in SmartPanelState.values)
                        FlatTextToggleOption(
                          key: Key('smart-panel-tab-${option.name}'),
                          label: smartPanelStateLabel(l10n, option),
                          selected: option == state,
                          onTap: () => controller.select(option),
                        ),
                    ],
                  ),
                  SizedBox(
                    height: PanelStyleScope.isFlat(context)
                        ? flatSectionGap
                        : 6,
                  ),
                  body,
                ],
              )
            : body,
      );
    },
  );

  void _step(int delta) {
    const states = SmartPanelState.values;
    final next = (states.indexOf(controller.state) + delta) % states.length;
    controller.select(states[next]);
  }

  Widget _menu(BuildContext context, AppLocalizations l10n) =>
      PopupMenuButton<SmartPanelState>(
        key: const Key('smart-panel-menu'),
        padding: EdgeInsets.zero,
        tooltip: l10n.smartPanelTitle,
        onSelected: controller.select,
        itemBuilder: (context) => [
          for (final state in SmartPanelState.values)
            PopupMenuItem(
              value: state,
              child: Text(smartPanelStateLabel(l10n, state)),
            ),
        ],
        child: Icon(
          Icons.arrow_drop_down,
          size: PanelStyleScope.isFlat(context) ? flatActionIconSize : 20,
          color: appColor(context, flatAccentColor),
        ),
      );
}

class _AutoMarker extends StatelessWidget {
  const _AutoMarker(this.l10n);

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('smart-panel-auto'),
    margin: const EdgeInsets.only(left: 4),
    padding: const EdgeInsets.symmetric(horizontal: 4),
    decoration: BoxDecoration(
      border: Border.all(color: appColor(context, const Color(0xff2f5f86))),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      l10n.smartPanelAuto,
      style: TextStyle(
        color: appColor(context, const Color(0xff7fc4ff)),
        fontSize: flatSmallFontSize,
      ),
    ),
  );
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.selected = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final flat = PanelStyleScope.isFlat(context);
    final size = flat ? flatHeaderHeight : 28.0;
    return IconButton(
      tooltip: tooltip,
      constraints: BoxConstraints.tightFor(width: size, height: size),
      style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      padding: EdgeInsets.zero,
      icon: Icon(
        icon,
        size: flat ? flatActionIconSize : 18,
        color: appColor(context, selected ? flatAccentColor : flatMutedColor),
      ),
      onPressed: onPressed,
    );
  }
}
