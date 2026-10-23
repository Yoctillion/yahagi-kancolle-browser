import 'package:flutter/material.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';

import '../theme/app_palette.dart';
import 'camera_avoidance_settings.dart';
import 'layout_settings_controller.dart';
import 'settings_ui_helpers.dart';

class CameraAvoidanceSettingsSection extends StatelessWidget
    with SettingsUIHelpers {
  const CameraAvoidanceSettingsSection({super.key, required this.controller});

  final LayoutSettingsController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final l10n =
          AppLocalizations.of(context) ??
          lookupAppLocalizations(const Locale('zh'));
      final distance = controller.cameraAvoidanceDistance;
      final value = '${distance.toStringAsFixed(0)} px';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          buildSwitchTile(
            title: l10n.cameraAvoidanceTitle,
            titleKey: const Key('settings-camera-avoidance-label'),
            switchKey: const Key('settings-camera-avoidance-switch'),
            subtitle: l10n.cameraAvoidanceDesc,
            value: controller.cameraAvoidanceEnabled,
            onChanged: controller.setCameraAvoidanceEnabled,
          ),
          if (controller.cameraAvoidanceEnabled)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingsControlRow(
                    label: Text(
                      l10n.cameraAvoidanceDistance,
                      style: appTextStyle(
                        context,
                        SettingsTileTypography.title,
                      ),
                    ),
                    controlBuilder: (_) => Text(
                      value,
                      style: appTextStyle(
                        context,
                        const TextStyle(color: Color(0xffd4a85f)),
                      ),
                    ),
                  ),
                  Slider(
                    key: const Key('settings-camera-avoidance-distance-slider'),
                    value: distance,
                    min: 0,
                    max: CameraAvoidanceSettings.maxDistance,
                    divisions: 120,
                    label: value,
                    semanticFormatterCallback: (value) =>
                        '${value.toStringAsFixed(0)} px',
                    activeColor: appColor(context, const Color(0xffd4a85f)),
                    onChanged: controller.setCameraAvoidanceDistance,
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}
