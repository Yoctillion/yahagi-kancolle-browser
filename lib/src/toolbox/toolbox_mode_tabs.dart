import '../theme/app_palette.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'composition_image_strings.dart';
import 'sortie_map_query/sortie_map_query_strings.dart';
import 'toolbox_mode.dart';
import 'game_mods/game_mods_strings.dart';

class ToolboxModeTabs extends StatefulWidget {
  const ToolboxModeTabs({
    super.key,
    required this.mode,
    required this.onChanged,
    this.compact = false,
  });

  final ToolboxMode mode;
  final ValueChanged<ToolboxMode> onChanged;
  final bool compact;

  @override
  State<ToolboxModeTabs> createState() => _ToolboxModeTabsState();
}

class _ToolboxModeTabsState extends State<ToolboxModeTabs> {
  final _scrollController = ScrollController();
  final _keys = {for (final mode in ToolboxMode.values) mode: GlobalKey()};
  @override
  void initState() {
    super.initState();
    _revealSelection();
  }

  @override
  void didUpdateWidget(ToolboxModeTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode || oldWidget.compact != widget.compact) {
      _revealSelection();
    }
  }

  void _revealSelection() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    final context = _keys[widget.mode]?.currentContext;
    if (context != null) Scrollable.ensureVisible(context, alignment: 0.5);
  });
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact, mode = widget.mode;
    final onChanged = widget.onChanged;
    final l10n = AppLocalizations.of(context)!;
    String label(ToolboxMode value) => switch (value) {
      ToolboxMode.export => l10n.fleetExport,
      ToolboxMode.composition => CompositionImageStrings.of(context).title,
      ToolboxMode.expCalc => l10n.expCalculator,
      ToolboxMode.mapQuery => SortieMapQueryStrings.of(context).title,
      ToolboxMode.mods => GameModsStrings.of(context).tabTitle,
      ToolboxMode.other => l10n.otherTools,
    };
    return Container(
      key: const Key('toolbox-mode-tabs'),
      width: compact ? null : 480,
      height: compact ? 36 : 38,
      padding: EdgeInsets.all(compact ? 1 : 3),
      decoration: BoxDecoration(
        color: appColor(context, const Color(0xff0b202d)),
        border: Border.all(color: appColor(context, const Color(0xff315064))),
        borderRadius: BorderRadius.circular(20),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: constraints.maxWidth.clamp(480, double.infinity),
            child: Row(
              children: [
                for (final value in ToolboxMode.values)
                  Expanded(
                    child: Semantics(
                      key: _keys[value],
                      button: true,
                      selected: mode == value,
                      label: label(value),
                      excludeSemantics: true,
                      onTap: () => onChanged(value),
                      child: Material(
                        key: Key('toolbox-tab-${value.name}'),
                        color: appColor(
                          context,
                          mode == value
                              ? const Color(0xff8a6628)
                              : Colors.transparent,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => onChanged(value),
                          child: Center(
                            child: Text(
                              label(value),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: appTextStyle(
                                context,
                                TextStyle(
                                  color: mode == value
                                      ? const Color(0xffffdc88)
                                      : const Color(0xff9fb3bf),
                                  fontSize: compact ? 10 : 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
