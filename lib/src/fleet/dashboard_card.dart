import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../layout/flat_style.dart';
import '../layout/panel_style.dart';
import 'fleet_ui_strings.dart';

class DashboardCard extends StatelessWidget {
  const DashboardCard({
    super.key,
    required this.title,
    required this.icon,
    required this.collapsed,
    required this.onToggleCollapse,
    required this.child,
    this.showLogo = true,
    this.showTitle = true,
    this.titleBadge,
    this.trailing,
    this.padding,
    this.borderColor,
    this.collapseButtonKey,
    this.headerAction,
    this.collapsedSummary,
  });

  final String title;
  final Widget icon;
  final bool collapsed;
  final VoidCallback onToggleCollapse;
  final Widget child;
  final bool showLogo;
  final bool showTitle;
  final Widget? titleBadge;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;
  final Color? borderColor;
  final Key? collapseButtonKey;
  final Widget? headerAction;

  /// 只在扁平样式且折叠时显示在标题行右侧。
  final String? collapsedSummary;

  @override
  Widget build(BuildContext context) {
    final flat = PanelStyleScope.isFlat(context);
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Container(
        padding: flat
            ? EdgeInsets.fromLTRB(6, 0, 6, collapsed ? 0 : 4)
            : padding ??
                  EdgeInsets.fromLTRB(
                    14,
                    collapsed ? 8 : 10,
                    10,
                    collapsed ? 8 : 10,
                  ),
        decoration: flat
            ? const BoxDecoration(
                border: Border(bottom: BorderSide(color: flatDividerColor)),
              )
            : BoxDecoration(
                color: const Color(0xff142735),
                borderRadius: BorderRadius.circular(10),
                border: borderColor != null
                    ? Border.all(color: borderColor!)
                    : null,
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                if (Localizations.maybeLocaleOf(context)?.languageCode ==
                        'en' &&
                    (constraints.maxWidth < 400 ||
                        MediaQuery.textScalerOf(context).scale(14) > 14)) {
                  final header = _englishHeader(context, flat);
                  if (constraints.maxWidth < 220) {
                    return SingleChildScrollView(
                      // Cards keep their own state in the slot their
                      // PageStorageKey derives; an unkeyed scroll view would
                      // restore that value as its offset and throw.
                      key: const PageStorageKey('dashboard-card-header-scroll'),
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(width: 220, child: header),
                    );
                  }
                  return header;
                }
                if (flat) {
                  return SizedBox(
                    key: const Key('dashboard-card-header'),
                    height: flatHeaderHeight,
                    child: _flatHeader(context),
                  );
                }
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: constraints.maxWidth < 220
                        ? 220
                        : constraints.maxWidth,
                    child: Row(
                      children: [
                        if (showLogo) ...[
                          IconTheme(
                            data: IconThemeData(
                              size: 16,
                              color: const Color(0xffd4a85f),
                            ),
                            child: icon,
                          ),
                          if (showTitle) const SizedBox(width: 6),
                        ],
                        if (showTitle)
                          Expanded(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      title,
                                      style: _titleStyle(false),
                                    ),
                                  ),
                                ),
                                if (!collapsed && titleBadge != null) ...[
                                  const SizedBox(width: 8),
                                  titleBadge!,
                                ],
                              ],
                            ),
                          )
                        else ...[
                          const Spacer(),
                          if (!collapsed && titleBadge != null) ...[
                            titleBadge!,
                            const SizedBox(width: 8),
                          ],
                        ],
                        if (!collapsed && trailing != null) ...[
                          trailing!,
                          const SizedBox(width: 3),
                        ],
                        ?headerAction,
                        _collapseButton(context, false),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (!collapsed) ...[const SizedBox(height: 0), child],
          ],
        ),
      ),
    );
  }

  // Scaling the whole row would shrink the title whenever one child (badge,
  // switcher, gear) is taller than the 24dp header, so only that child scales.
  Widget _flatHeader(BuildContext context) {
    Widget fit(Widget w, double height, AlignmentGeometry alignment) =>
        SizedBox(
          height: height,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: alignment,
            child: w,
          ),
        );
    return Row(
      children: [
        if (showLogo) ...[
          IconTheme(
            data: const IconThemeData(size: 13, color: flatAccentColor),
            child: icon,
          ),
          if (showTitle) const SizedBox(width: 6),
        ],
        if (showTitle)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _titleStyle(true),
                    ),
                  ),
                  if (!collapsed && titleBadge != null) ...[
                    const SizedBox(width: 8),
                    // Rigid so the title shrinks first (a Flexible badge would
                    // cap the title at half too); the cap stops it overflowing
                    // once the title is gone.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: math.max(0, (constraints.maxWidth - 8) / 2),
                      ),
                      child: fit(titleBadge!, 22, Alignment.centerLeft),
                    ),
                  ],
                  if (_showSummary(true)) ...[
                    const SizedBox(width: 8),
                    Expanded(child: _summary()),
                  ],
                ],
              ),
            ),
          )
        else if (!collapsed && titleBadge != null) ...[
          // A Flexible badge next to a Spacer would split the free space and
          // leave a gap after the trailing controls; Align keeps it flush.
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              heightFactor: 1,
              child: fit(titleBadge!, 22, Alignment.centerRight),
            ),
          ),
          const SizedBox(width: 8),
        ] else
          const Spacer(),
        if (!collapsed && trailing != null) ...[
          fit(trailing!, 22, Alignment.centerRight),
          const SizedBox(width: 3),
        ],
        if (headerAction != null) fit(headerAction!, 24, Alignment.center),
        _collapseButton(context, true),
      ],
    );
  }

  TextStyle _titleStyle(bool flat) => TextStyle(
    color: const Color(0xffd4a85f),
    fontWeight: FontWeight.w700,
    fontSize: flat ? flatRowFontSize : 14,
  );

  bool _showSummary(bool flat) =>
      flat && collapsed && (collapsedSummary?.isNotEmpty ?? false);

  Widget _summary() => Text(
    collapsedSummary!,
    key: const Key('dashboard-card-summary'),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(color: flatMutedColor, fontSize: flatSmallFontSize),
  );

  Widget _englishHeader(BuildContext context, bool flat) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          if (showLogo) ...[
            IconTheme(
              data: IconThemeData(
                size: flat ? 13 : 16,
                color: const Color(0xffd4a85f),
              ),
              child: icon,
            ),
            if (showTitle) const SizedBox(width: 6),
          ],
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (showTitle) Text(title, style: _titleStyle(flat)),
                if (!collapsed && titleBadge != null) titleBadge!,
                if (_showSummary(flat))
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: _summary(),
                  ),
              ],
            ),
          ),
          ?headerAction,
          _collapseButton(context, flat),
        ],
      ),
      if (!collapsed && trailing != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: SingleChildScrollView(
            key: const PageStorageKey('dashboard-card-trailing-scroll'),
            scrollDirection: Axis.horizontal,
            child: trailing!,
          ),
        ),
    ],
  );

  Widget _collapseButton(BuildContext context, bool flat) => Semantics(
    label: collapsed
        ? fleetText(context, '展开$title')
        : fleetText(context, '折叠$title'),
    child: IconButton(
      key: collapseButtonKey,
      visualDensity: VisualDensity.compact,
      constraints: flat
          ? const BoxConstraints(minWidth: 24, minHeight: 24)
          : const BoxConstraints(minWidth: 32, minHeight: 30),
      padding: EdgeInsets.zero,
      alignment: Alignment.centerRight,
      onPressed: onToggleCollapse,
      icon: Icon(
        collapsed
            ? Icons.keyboard_arrow_down_rounded
            : Icons.keyboard_arrow_up_rounded,
        size: flat ? 15 : 20,
        color: const Color(0xff8fa8b6),
      ),
    ),
  );
}
