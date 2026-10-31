import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../game_state/game_state_controller.dart';
import '../layout/flat_empty_text.dart';
import '../layout/flat_style.dart';
import '../layout/panel_style.dart';
import '../settings/item_panel_settings.dart';
import '../theme/app_palette.dart';
import 'item_panel_projection.dart';
import 'use_item_catalog.dart';

const _cellMinWidth = 48.0;
const _cellHeight = 44.0;
const _cellIconSize = 32.0;
const _cellSpacing = 3.0;
const _rowHeight = 24.0;
const _rowIconSize = 20.0;
const _columnGap = 8.0;
const _zeroOpacity = 0.3;
const _grayscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
]);

/// Shared by the standalone card and the smart panel so both stay identical.
class ItemPanelView extends StatelessWidget {
  const ItemPanelView({
    super.key,
    required this.controller,
    required this.mode,
  });

  final GameStateController controller;
  final ItemPanelMode mode;

  @override
  Widget build(BuildContext context) {
    final l10n =
        AppLocalizations.of(context) ??
        lookupAppLocalizations(const Locale('zh'));
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final groups = projectItemPanel(controller.state);
        if (groups == null) return _Waiting(l10n.waitingForData);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final group in groups)
              _GroupSection(
                key: Key('item-group-${group.group.name}'),
                title: _groupTitle(l10n, group.group),
                entries: group.entries,
                mode: mode,
              ),
          ],
        );
      },
    );
  }
}

String _groupTitle(AppLocalizations l10n, ItemGroup group) => switch (group) {
  ItemGroup.reward => l10n.itemGroupReward,
  ItemGroup.improvement => l10n.itemGroupImprovement,
  ItemGroup.seasonal => l10n.itemGroupSeasonal,
  ItemGroup.consumable => l10n.itemGroupConsumable,
  ItemGroup.other => l10n.itemGroupOther,
};

class _Waiting extends StatelessWidget {
  const _Waiting(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    if (PanelStyleScope.isFlat(context)) return FlatEmptyText(text);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        text,
        style: TextStyle(color: appColor(context, flatMutedColor)),
      ),
    );
  }
}

class _GroupSection extends StatelessWidget {
  const _GroupSection({
    super.key,
    required this.title,
    required this.entries,
    required this.mode,
  });

  final String title;
  final List<ItemPanelEntry> entries;
  final ItemPanelMode mode;

  @override
  Widget build(BuildContext context) {
    final flat = PanelStyleScope.isFlat(context);
    return Padding(
      padding: EdgeInsets.only(bottom: flat ? flatSectionGap : 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              title,
              style: TextStyle(
                color: appColor(context, flatMutedColor),
                fontSize: flat ? flatSmallFontSize : 11,
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return switch (mode) {
                ItemPanelMode.compact => _CellGrid(
                  entries: entries,
                  width: width,
                ),
                ItemPanelMode.detailed => _RowGrid(
                  entries: entries,
                  width: width,
                ),
              };
            },
          ),
        ],
      ),
    );
  }
}

class _CellGrid extends StatelessWidget {
  const _CellGrid({required this.entries, required this.width});

  final List<ItemPanelEntry> entries;
  final double width;

  @override
  Widget build(BuildContext context) {
    final columns = (width / _cellMinWidth).floor().clamp(3, 12);
    final cellWidth = (width - _cellSpacing * (columns - 1)) / columns;
    return Wrap(
      spacing: _cellSpacing,
      runSpacing: _cellSpacing,
      children: [
        for (final entry in entries)
          SizedBox(
            width: cellWidth,
            height: _cellHeight,
            child: _ItemCell(entry),
          ),
      ],
    );
  }
}

class _ItemCell extends StatelessWidget {
  const _ItemCell(this.entry);

  final ItemPanelEntry entry;

  @override
  Widget build(BuildContext context) {
    final flat = PanelStyleScope.isFlat(context);
    return _ItemTooltip(
      entry: entry,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: flat ? null : appColor(context, const Color(0xff142735)),
          borderRadius: BorderRadius.circular(6),
          border: flat
              ? null
              : Border.all(color: appColor(context, const Color(0xff243f50))),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            _ItemIcon(entry: entry, size: _cellIconSize),
            Positioned(
              left: 2,
              right: 2,
              bottom: 0,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: _ItemCount(entry: entry, overlaid: true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowGrid extends StatelessWidget {
  const _RowGrid({required this.entries, required this.width});

  final List<ItemPanelEntry> entries;
  final double width;

  @override
  Widget build(BuildContext context) {
    final rowWidth = (width - _columnGap) / 2;
    return Wrap(
      spacing: _columnGap,
      children: [
        for (final entry in entries)
          SizedBox(width: rowWidth, height: _rowHeight, child: _ItemRow(entry)),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow(this.entry);

  final ItemPanelEntry entry;

  @override
  Widget build(BuildContext context) {
    final name = useItemName(Localizations.maybeLocaleOf(context), entry.id);
    return _ItemTooltip(
      entry: entry,
      child: Row(
        children: [
          _ItemIcon(entry: entry, size: _rowIconSize),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                color: appColor(
                  context,
                  entry.count == 0 ? flatMutedColor : const Color(0xffdce6eb),
                ),
                fontSize: PanelStyleScope.isFlat(context)
                    ? flatRowFontSize
                    : 12,
              ),
            ),
          ),
          const SizedBox(width: 4),
          _ItemCount(entry: entry, overlaid: false),
        ],
      ),
    );
  }
}

/// Long press is taken by dashboard editing, so names open on tap instead.
class _ItemTooltip extends StatelessWidget {
  const _ItemTooltip({required this.entry, required this.child});

  final ItemPanelEntry entry;
  final Widget child;

  @override
  Widget build(BuildContext context) => Tooltip(
    key: Key('item-cell-${entry.id}'),
    triggerMode: TooltipTriggerMode.tap,
    message: useItemName(Localizations.maybeLocaleOf(context), entry.id),
    child: child,
  );
}

class _ItemIcon extends StatelessWidget {
  const _ItemIcon({required this.entry, required this.size});

  final ItemPanelEntry entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = Image.asset(
      entry.assetPath,
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) =>
          Image.asset(useItemFallbackAsset, width: size, height: size),
    );
    if (entry.count > 0) return icon;
    return Opacity(
      opacity: _zeroOpacity,
      child: ColorFiltered(colorFilter: _grayscale, child: icon),
    );
  }
}

class _ItemCount extends StatelessWidget {
  const _ItemCount({required this.entry, required this.overlaid});

  final ItemPanelEntry entry;
  final bool overlaid;

  @override
  Widget build(BuildContext context) => Text(
    '${entry.count}',
    maxLines: 1,
    softWrap: false,
    style: TextStyle(
      color: appColor(
        context,
        entry.count == 0 ? flatMutedColor : const Color(0xffdce6eb),
      ),
      fontSize: overlaid
          ? 11
          : PanelStyleScope.isFlat(context)
          ? flatRowFontSize
          : 12,
      fontWeight: FontWeight.w700,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      // The count sits on the icon artwork, so it needs its own edge.
      shadows: overlaid && entry.count > 0
          ? const <Shadow>[Shadow(blurRadius: 2)]
          : null,
    ),
  );
}
