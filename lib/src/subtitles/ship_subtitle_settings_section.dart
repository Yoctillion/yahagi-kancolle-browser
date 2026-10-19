import 'package:flutter/material.dart';

import '../settings/settings_ui_helpers.dart';
import 'ship_subtitle_language.dart';
import 'ship_subtitle_settings.dart';
import 'ship_subtitle_strings.dart';

class ShipSubtitleSettingsSection extends StatelessWidget
    with SettingsUIHelpers {
  const ShipSubtitleSettingsSection({super.key, required this.controller});

  final ShipSubtitleSettingsController controller;

  @override
  Widget build(BuildContext context) {
    final strings = ShipSubtitleStrings.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildSwitchTile(
            switchKey: const Key('settings-ship-subtitles'),
            title: strings.title,
            subtitle: strings.description,
            value: controller.enabled,
            onChanged: controller.saving ? null : controller.setEnabled,
          ),
          if (controller.enabled) ...[
            const Divider(color: Color(0xff294052), height: 1),
            _choiceRow(
              strings.fontSize,
              DropdownButton<ShipSubtitleFontSize>(
                key: const Key('settings-ship-subtitle-font-size'),
                value: controller.fontSize,
                underline: const SizedBox(),
                alignment: AlignmentDirectional.centerEnd,
                items: [
                  for (final size in ShipSubtitleFontSize.values)
                    DropdownMenuItem(
                      value: size,
                      child: Text(strings.sizeLabel(size)),
                    ),
                ],
                onChanged: controller.saving
                    ? null
                    : (value) {
                        if (value != null) controller.setFontSize(value);
                      },
              ),
            ),
            const Divider(color: Color(0xff294052), height: 1),
            _choiceRow(
              strings.language,
              DropdownButton<ShipSubtitleLanguage>(
                key: const Key('settings-ship-subtitle-language'),
                value: controller.language,
                underline: const SizedBox(),
                alignment: AlignmentDirectional.centerEnd,
                items: [
                  for (final language in ShipSubtitleLanguage.values)
                    DropdownMenuItem(
                      value: language,
                      child: Text(language.label),
                    ),
                ],
                onChanged: controller.saving
                    ? null
                    : (value) {
                        if (value != null) controller.setLanguage(value);
                      },
              ),
            ),
          ],
          if (controller.saveFailed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                strings.saveFailed,
                style: SettingsTileTypography.description.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _choiceRow(String title, Widget dropdown) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(title, style: SettingsTileTypography.title)),
        const SizedBox(width: 12),
        dropdown,
      ],
    ),
  );
}
