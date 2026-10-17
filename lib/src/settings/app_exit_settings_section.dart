import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'app_exit_settings.dart';
import 'settings_ui_helpers.dart';

class AppExitSettingsSection extends StatelessWidget with SettingsUIHelpers {
  const AppExitSettingsSection({super.key, required this.controller});

  final AppExitSettingsController controller;

  @override
  Widget build(BuildContext context) {
    final l10n =
        AppLocalizations.of(context) ??
        lookupAppLocalizations(const Locale('zh'));
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Column(
        children: [
          buildSwitchTile(
            switchKey: const Key('settings-confirm-before-exit'),
            title: l10n.confirmBeforeExitTitle,
            subtitle: l10n.confirmBeforeExitDescription,
            value: controller.enabled,
            onChanged: controller.saving ? null : controller.setEnabled,
          ),
          if (controller.saveFailed)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.confirmBeforeExitSaveFailed),
            ),
        ],
      ),
    );
  }
}
