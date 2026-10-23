import '../theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';

import 'battle_prediction_settings.dart';
import 'battle_prediction_settings_section.dart';
import 'battle_status_effect_settings.dart';
import 'safety_settings_controller.dart';
import 'safety_settings_store.dart';
import 'settings_ui_helpers.dart';

class BattleSettingsPage extends StatelessWidget with SettingsUIHelpers {
  const BattleSettingsPage({
    super.key,
    this.battlePredictionSettingsController,
    required this.safetySettingsController,
  });

  final BattlePredictionSettingsController? battlePredictionSettingsController;
  final SafetySettingsController safetySettingsController;

  @override
  Widget build(BuildContext context) {
    final l10n =
        AppLocalizations.of(context) ??
        lookupAppLocalizations(const Locale('zh'));

    return Container(
      color: appColor(context, const Color(0xff0d1a26)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            buildSectionTitle(l10n.gameSafety),
            buildCard(
              child: AnimatedBuilder(
                animation: safetySettingsController,
                builder: (context, _) => Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) => Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Text(
                          l10n.blockSortieTitle,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        _fitDropdown(
                          maxWidth: constraints.maxWidth,
                          child: DropdownButton<BattleWarningMode>(
                            value: safetySettingsController.battleWarningMode,
                            underline: const SizedBox(),
                            alignment: AlignmentDirectional.centerEnd,
                            isExpanded: true,
                            itemHeight: null,
                            items: [
                              DropdownMenuItem(
                                value: BattleWarningMode.off,
                                alignment: AlignmentDirectional.centerEnd,
                                child: Text(
                                  l10n.battleWarningOff,
                                  textAlign: TextAlign.end,
                                ),
                              ),
                              DropdownMenuItem(
                                value: BattleWarningMode.confirm,
                                alignment: AlignmentDirectional.centerEnd,
                                child: Text(
                                  l10n.battleWarningConfirm,
                                  textAlign: TextAlign.end,
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                safetySettingsController.setBattleWarningMode(
                                  value,
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            buildSectionTitle(l10n.battleStatusEffectsSection),
            buildCard(
              child: AnimatedBuilder(
                animation: safetySettingsController,
                builder: (context, _) {
                  final settings = safetySettingsController.battleStatusEffects;
                  final childrenEnabled = settings.enabled;
                  return Column(
                    children: <Widget>[
                      buildSwitchTile(
                        title: l10n.battleStatusEffectsEnabled,
                        subtitle: l10n.battleStatusEffectsEnabledDesc,
                        switchKey: const Key('battleStatusEffectsMasterSwitch'),
                        value: settings.enabled,
                        onChanged: safetySettingsController
                            .setBattleStatusEffectsEnabled,
                      ),
                      Divider(
                        height: 1,
                        color: appColor(context, Color(0xff294052)),
                      ),
                      _StatusEffectRow(
                        title: l10n.battleEffectDisplayScope,
                        subtitle: l10n.battleEffectDisplayScopeDesc,
                        enabled: childrenEnabled,
                        trailing: DropdownButton<BattleEffectDisplayScope>(
                          key: const Key('battleEffectScopeDropdown'),
                          value: settings.displayScope,
                          underline: const SizedBox(),
                          alignment: AlignmentDirectional.centerEnd,
                          isExpanded: true,
                          itemHeight: null,
                          items: BattleEffectDisplayScope.values
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: Text(
                                    _scopeLabel(l10n, value),
                                    textAlign: TextAlign.end,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: childrenEnabled
                              ? (value) {
                                  if (value != null) {
                                    safetySettingsController
                                        .setBattleEffectDisplayScope(value);
                                  }
                                }
                              : null,
                        ),
                      ),
                      Divider(
                        height: 1,
                        color: appColor(context, Color(0xff294052)),
                      ),
                      _StatusEffectRow(
                        title: l10n.battleDamagePulse,
                        subtitle: l10n.battleDamagePulseDesc,
                        enabled: childrenEnabled,
                        trailing: DropdownButton<DamagePulseFilter>(
                          key: const Key('damagePulseFilterDropdown'),
                          value: settings.damagePulseFilter,
                          underline: const SizedBox(),
                          alignment: AlignmentDirectional.centerEnd,
                          isExpanded: true,
                          itemHeight: null,
                          items: DamagePulseFilter.values
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: Text(
                                    _pulseFilterLabel(l10n, value),
                                    textAlign: TextAlign.end,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: childrenEnabled
                              ? (value) {
                                  if (value != null) {
                                    safetySettingsController
                                        .setDamagePulseFilter(value);
                                  }
                                }
                              : null,
                        ),
                      ),
                      Divider(
                        height: 1,
                        color: appColor(context, Color(0xff294052)),
                      ),
                      _StatusEffectRow(
                        title: l10n.battleDamageVibrationEffect,
                        subtitle: l10n.battleDamageVibrationEffectDesc,
                        enabled: childrenEnabled,
                        trailing: DropdownButton<DamageVibrationFilter>(
                          key: const Key('damageVibrationFilterDropdown'),
                          value: settings.damageVibrationFilter,
                          underline: const SizedBox(),
                          alignment: AlignmentDirectional.centerEnd,
                          isExpanded: true,
                          itemHeight: null,
                          items: DamageVibrationFilter.values
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: Text(
                                    _vibrationFilterLabel(l10n, value),
                                    textAlign: TextAlign.end,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: childrenEnabled
                              ? (value) {
                                  if (value != null) {
                                    safetySettingsController
                                        .setDamageVibrationFilter(value);
                                  }
                                }
                              : null,
                        ),
                      ),
                      Divider(
                        height: 1,
                        color: appColor(context, Color(0xff294052)),
                      ),
                      _StatusEffectRow(
                        title: l10n.battleMoraleSparkle,
                        subtitle: l10n.battleMoraleSparkleDesc,
                        enabled: childrenEnabled,
                        trailing: DropdownButton<MoraleSparkleMode>(
                          key: const Key('moraleSparkleModeDropdown'),
                          value: settings.moraleSparkleMode,
                          underline: const SizedBox(),
                          alignment: AlignmentDirectional.centerEnd,
                          isExpanded: true,
                          itemHeight: null,
                          items: MoraleSparkleMode.values
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: Text(
                                    _moraleSparkleModeLabel(l10n, value),
                                    textAlign: TextAlign.end,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: childrenEnabled
                              ? (value) {
                                  if (value != null) {
                                    safetySettingsController
                                        .setMoraleSparkleMode(value);
                                  }
                                }
                              : null,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            if (battlePredictionSettingsController != null) ...<Widget>[
              buildSectionTitle(l10n.battlePredictionSection),
              buildCard(
                child: BattlePredictionSettingsSection(
                  controller: battlePredictionSettingsController!,
                ),
              ),
              const SizedBox(height: 24),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

String _pulseFilterLabel(AppLocalizations l10n, DamagePulseFilter filter) =>
    switch (filter) {
      DamagePulseFilter.off => l10n.battleEffectOff,
      DamagePulseFilter.minorOnly => l10n.battleEffectMinorOnly,
      DamagePulseFilter.moderateOnly => l10n.battleEffectModerateOnly,
      DamagePulseFilter.heavyOnly => l10n.battleEffectHeavyOnly,
      DamagePulseFilter.all => l10n.battleEffectAll,
    };

String _moraleSparkleModeLabel(AppLocalizations l10n, MoraleSparkleMode mode) =>
    switch (mode) {
      MoraleSparkleMode.blinking => l10n.battleMoraleSparkleBlinking,
      MoraleSparkleMode.steady => l10n.battleMoraleSparkleSteady,
      MoraleSparkleMode.off => l10n.battleEffectOff,
    };

String _scopeLabel(AppLocalizations l10n, BattleEffectDisplayScope scope) =>
    switch (scope) {
      BattleEffectDisplayScope.predictionOnly =>
        l10n.battleEffectScopePredictionOnly,
      BattleEffectDisplayScope.fleetOnly => l10n.battleEffectScopeFleetOnly,
      BattleEffectDisplayScope.all => l10n.battleEffectScopeAll,
    };

String _vibrationFilterLabel(
  AppLocalizations l10n,
  DamageVibrationFilter filter,
) => switch (filter) {
  DamageVibrationFilter.off => l10n.battleEffectOff,
  DamageVibrationFilter.moderateOnly => l10n.battleEffectModerateOnly,
  DamageVibrationFilter.heavyOnly => l10n.battleEffectHeavyOnly,
  DamageVibrationFilter.all => l10n.battleEffectAll,
};

Widget _fitDropdown({required double maxWidth, required Widget child}) =>
    ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: IntrinsicWidth(child: child),
    );

class _StatusEffectRow extends StatelessWidget {
  const _StatusEffectRow({
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final bool enabled;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          title,
          style: appTextStyle(
            context,
            SettingsTileTypography.title.copyWith(
              color: enabled ? null : const Color(0xff526776),
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: appTextStyle(
            context,
            SettingsTileTypography.description.copyWith(
              color: enabled ? null : const Color(0xff526776),
            ),
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final dropdown = _fitDropdown(
          maxWidth: (constraints.maxWidth - 32) * (compact ? 1 : .5),
          child: trailing,
        );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    text,
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: dropdown),
                  ],
                )
              : Row(
                  children: <Widget>[
                    Expanded(child: text),
                    const SizedBox(width: 12),
                    dropdown,
                  ],
                ),
        );
      },
    );
  }
}
