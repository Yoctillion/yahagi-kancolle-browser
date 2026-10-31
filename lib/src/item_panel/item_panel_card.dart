import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../fleet/dashboard_card.dart';
import '../game_state/game_state_controller.dart';
import '../settings/item_panel_settings.dart';
import '../settings/module_display_settings.dart';
import 'item_panel_view.dart';

class ItemPanelCard extends StatelessWidget {
  const ItemPanelCard({
    super.key,
    required this.controller,
    required this.mode,
    required this.collapsed,
    required this.onToggleCollapse,
    this.showLogo = true,
    this.showTitle = true,
    this.onOpenDisplaySettings,
  });

  final GameStateController controller;
  final ItemPanelMode mode;
  final bool collapsed;
  final VoidCallback onToggleCollapse;
  final bool showLogo;
  final bool showTitle;
  final VoidCallback? onOpenDisplaySettings;

  @override
  Widget build(BuildContext context) {
    final l10n =
        AppLocalizations.of(context) ??
        lookupAppLocalizations(const Locale('zh'));
    return DashboardCard(
      title: l10n.itemPanelTitle,
      icon: const Icon(Icons.inventory_2_outlined),
      collapsed: collapsed,
      onToggleCollapse: onToggleCollapse,
      showLogo: showLogo,
      showTitle: showTitle,
      headerAction: moduleDisplayGear(context, 'items', onOpenDisplaySettings),
      child: ItemPanelView(controller: controller, mode: mode),
    );
  }
}
