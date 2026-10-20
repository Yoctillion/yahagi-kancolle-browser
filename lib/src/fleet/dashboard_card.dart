import 'package:flutter/material.dart';
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
    final flat = PanelStyleScope.of(context) == PanelStyle.flat;
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
                border: Border(bottom: BorderSide(color: Color(0xff1b3142))),
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
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(width: 220, child: header),
                    );
                  }
                  return header;
                }
                final row = FittedBox(
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
                              size: flat ? 13 : 16,
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
                                      style: _titleStyle(flat),
                                    ),
                                  ),
                                ),
                                if (!collapsed && titleBadge != null) ...[
                                  const SizedBox(width: 8),
                                  titleBadge!,
                                ],
                                if (_showSummary(flat)) ...[
                                  const SizedBox(width: 8),
                                  Expanded(child: _summary()),
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
                        _collapseButton(context, flat),
                      ],
                    ),
                  ),
                );
                return flat
                    ? SizedBox(
                        key: const Key('dashboard-card-header'),
                        height: 24,
                        child: row,
                      )
                    : row;
              },
            ),
            if (!collapsed) ...[const SizedBox(height: 0), child],
          ],
        ),
      ),
    );
  }

  TextStyle _titleStyle(bool flat) => TextStyle(
    color: const Color(0xffd4a85f),
    fontWeight: FontWeight.w700,
    fontSize: flat ? 11 : 14,
  );

  bool _showSummary(bool flat) =>
      flat && collapsed && (collapsedSummary?.isNotEmpty ?? false);

  Widget _summary() => Text(
    collapsedSummary!,
    key: const Key('dashboard-card-summary'),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(color: Color(0xff8197a5), fontSize: 10.5),
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
