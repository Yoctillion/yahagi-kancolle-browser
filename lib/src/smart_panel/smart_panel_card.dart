import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../fleet/dashboard_card.dart';
import '../layout/dashboard_editing_scope.dart';
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => _build(context, constraints.maxWidth),
  );

  Widget _build(BuildContext context, double cardWidth) => AnimatedBuilder(
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
      // The editing list names modules, so it must not follow the state.
      final editing = DashboardEditingScope.isEditing(context);
      final tabs = headerStyle == SmartPanelHeaderStyle.tabs || editing;
      final dropdown = headerStyle == SmartPanelHeaderStyle.dropdown;
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
        // The highlighted icon already names the state, and the strip needs
        // the title's width to keep its buttons tappable.
        showTitle:
            showTitle &&
            (editing || headerStyle != SmartPanelHeaderStyle.icons),
        onTitleTap: dropdown ? (anchor) => _openMenu(anchor, l10n) : null,
        collapsedSummary: collapsed ? label : null,
        headerAction: moduleDisplayGear(
          context,
          'smart',
          onOpenDisplaySettings,
        ),
        titleBadge: dropdown
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [_dropdownMarker(context, l10n), ?auto],
              )
            : auto,
        trailing: switch (headerStyle) {
          SmartPanelHeaderStyle.dropdown => null,
          // The card header row gives trailing unbounded width and is never
          // narrower than 220; the flat header caps trailing itself.
          SmartPanelHeaderStyle.icons => ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.max(cardWidth - 24, 220) - 60,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
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
            ),
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

  Future<void> _openMenu(BuildContext anchor, AppLocalizations l10n) async {
    final box = anchor.findRenderObject()! as RenderBox;
    final overlay = Overlay.of(anchor).context.findRenderObject()! as RenderBox;
    final selected = await showMenu<SmartPanelState>(
      context: anchor,
      position: RelativeRect.fromRect(
        Rect.fromPoints(
          box.localToGlobal(
            box.size.bottomLeft(Offset.zero),
            ancestor: overlay,
          ),
          box.localToGlobal(
            box.size.bottomRight(Offset.zero),
            ancestor: overlay,
          ),
        ),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final state in SmartPanelState.values)
          PopupMenuItem(
            value: state,
            child: Text(smartPanelStateLabel(l10n, state)),
          ),
      ],
    );
    if (selected != null) controller.select(selected);
  }

  Widget _dropdownMarker(BuildContext context, AppLocalizations l10n) =>
      Semantics(
        button: true,
        label: l10n.smartPanelTitle,
        child: Icon(
          Icons.arrow_drop_down,
          key: const Key('smart-panel-menu'),
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
    // The flat header fits trailing into 22 dp, so a taller button would shrink.
    final height = flat ? 22.0 : 28.0;
    return IconButton(
      tooltip: tooltip,
      constraints: BoxConstraints.tightFor(width: 26, height: height),
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
