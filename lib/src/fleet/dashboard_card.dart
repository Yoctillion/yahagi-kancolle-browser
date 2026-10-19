import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Container(
        padding:
            padding ??
            EdgeInsets.fromLTRB(14, collapsed ? 8 : 10, 10, collapsed ? 8 : 10),
        decoration: BoxDecoration(
          color: const Color(0xff142735),
          borderRadius: BorderRadius.circular(10),
          border: borderColor != null ? Border.all(color: borderColor!) : null,
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
                  final header = _englishHeader(context);
                  if (constraints.maxWidth < 220) {
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(width: 220, child: header),
                    );
                  }
                  return header;
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
                            data: const IconThemeData(
                              size: 16,
                              color: Color(0xffd4a85f),
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
                                      style: const TextStyle(
                                        color: Color(0xffd4a85f),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
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
                        _collapseButton(context),
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

  Widget _englishHeader(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          if (showLogo) ...[
            IconTheme(
              data: const IconThemeData(size: 16, color: Color(0xffd4a85f)),
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
                if (showTitle)
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xffd4a85f),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                if (!collapsed && titleBadge != null) titleBadge!,
              ],
            ),
          ),
          ?headerAction,
          _collapseButton(context),
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

  Widget _collapseButton(BuildContext context) => Semantics(
    label: collapsed
        ? fleetText(context, '展开$title')
        : fleetText(context, '折叠$title'),
    child: IconButton(
      key: collapseButtonKey,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 30),
      padding: EdgeInsets.zero,
      alignment: Alignment.centerRight,
      onPressed: onToggleCollapse,
      icon: Icon(
        collapsed
            ? Icons.keyboard_arrow_down_rounded
            : Icons.keyboard_arrow_up_rounded,
        size: 20,
        color: const Color(0xff8fa8b6),
      ),
    ),
  );
}
