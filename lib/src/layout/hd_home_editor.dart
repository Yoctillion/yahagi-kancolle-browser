import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import 'flat_style.dart';
import 'panel_style.dart';

/// Shared by the ordinary dashboard, HD sidebar and HD bottom row.
class DashboardEditItem extends StatelessWidget {
  const DashboardEditItem({
    super.key,
    required this.id,
    required this.hidden,
    required this.onToggle,
    required this.child,
    this.action,
  });
  final String id;
  final bool hidden;
  final VoidCallback onToggle;
  final Widget child;
  final Widget? action;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final content = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (PanelStyleScope.isFlat(context))
            _FlatVisibilityToggle(id: id, visible: !hidden, onToggle: onToggle)
          else
            Checkbox(
              value: !hidden,
              activeColor: const Color(0xffd4a85f),
              checkColor: Colors.black,
              side: const BorderSide(color: Color(0xff8fa8b6), width: 2),
              onChanged: (_) => onToggle(),
            ),
          Expanded(child: child),
        ],
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: LongPressDraggable<String>(
              key: Key('dashboard-drag-region-$id'),
              data: id,
              maxSimultaneousDrags: 1,
              feedback: Material(
                color: Colors.transparent,
                elevation: 6,
                child: SizedBox(
                  width: constraints.maxWidth,
                  child: IgnorePointer(child: content),
                ),
              ),
              childWhenDragging: Opacity(opacity: .25, child: content),
              child: Opacity(opacity: hidden ? .5 : 1, child: content),
            ),
          ),
          if (action != null)
            Align(alignment: Alignment.centerRight, child: action!),
        ],
      );
    },
  );
}

/// Material 的 Checkbox 固定占 48，和 24 高的扁平标题行对不齐。
class _FlatVisibilityToggle extends StatelessWidget {
  const _FlatVisibilityToggle({
    required this.id,
    required this.visible,
    required this.onToggle,
  });
  final String id;
  final bool visible;
  final VoidCallback onToggle;
  @override
  Widget build(BuildContext context) => Semantics(
    checked: visible,
    child: SizedBox.square(
      key: Key('dashboard-visibility-$id'),
      dimension: flatHeaderHeight,
      child: InkResponse(
        radius: flatHeaderHeight / 2,
        onTap: onToggle,
        child: Icon(
          visible
              ? Icons.check_box_rounded
              : Icons.check_box_outline_blank_rounded,
          size: flatActionIconSize,
          color: visible ? flatAccentColor : flatMutedColor,
        ),
      ),
    ),
  );
}

class DashboardDropTarget extends StatefulWidget {
  const DashboardDropTarget({
    super.key,
    this.id,
    this.horizontal = false,
    this.accepts,
    required this.onMove,
    required this.child,
  });
  final String? id;
  final bool horizontal;
  final bool Function(String)? accepts;
  final void Function(String, bool) onMove;
  final Widget child;
  @override
  State<DashboardDropTarget> createState() => _DashboardDropTargetState();
}

class _DashboardDropTargetState extends State<DashboardDropTarget> {
  bool after = false;
  bool locate(Offset offset) {
    final box = context.findRenderObject() as RenderBox;
    final point = box.globalToLocal(offset);
    return widget.horizontal
        ? point.dx > box.size.width / 2
        : point.dy > box.size.height / 2;
  }

  @override
  Widget build(BuildContext context) => DragTarget<String>(
    onWillAcceptWithDetails: (d) =>
        d.data != widget.id && (widget.accepts?.call(d.data) ?? true),
    onMove: (d) {
      final next = locate(d.offset);
      if (next != after) setState(() => after = next);
      final scroll = Scrollable.maybeOf(context);
      if (!widget.horizontal && scroll != null) {
        final box = scroll.context.findRenderObject();
        if (box is RenderBox && scroll.position.hasContentDimensions) {
          final y = box.globalToLocal(d.offset).dy;
          final delta = y < 36
              ? -14.0
              : y > box.size.height - 36
              ? 14.0
              : 0.0;
          if (delta != 0) {
            scroll.position.jumpTo(
              (scroll.position.pixels + delta).clamp(
                scroll.position.minScrollExtent,
                scroll.position.maxScrollExtent,
              ),
            );
          }
        }
      }
    },
    onAcceptWithDetails: (d) => widget.onMove(d.data, locate(d.offset)),
    builder: (context, candidates, rejected) => Stack(
      children: [
        widget.child,
        if (candidates.isNotEmpty)
          Positioned(
            left: widget.horizontal && after ? null : 0,
            right: widget.horizontal && !after ? null : 0,
            top: !widget.horizontal && after ? null : 0,
            bottom: !widget.horizontal && !after ? null : 0,
            width: widget.horizontal ? 3 : null,
            height: widget.horizontal ? null : 3,
            child: const ColoredBox(color: Color(0xffd4a85f)),
          ),
      ],
    ),
  );
}

class DashboardEditor extends StatelessWidget {
  const DashboardEditor({
    super.key,
    required this.modules,
    required this.hidden,
    required this.cardBuilder,
    required this.onToggle,
    required this.onMove,
    required this.onReset,
    required this.onDone,
  });
  final List<String> modules;
  final Set<String> hidden;
  final Widget Function(String) cardBuilder;
  final ValueChanged<String> onToggle;
  final void Function(String, String?, bool) onMove;
  final VoidCallback onReset, onDone;
  @override
  Widget build(BuildContext context) {
    final flat = PanelStyleScope.isFlat(context);
    return Column(
      children: [
        if (flat) _flatBar(context) else _cardBar(context),
        Expanded(
          child: ListView(
            primary: false,
            padding: flat
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final id in modules)
                DashboardDropTarget(
                  key: Key('dashboard-target-$id'),
                  id: id,
                  onMove: (data, after) => onMove(data, id, after),
                  child: DashboardEditItem(
                    id: id,
                    hidden: hidden.contains(id),
                    onToggle: () => onToggle(id),
                    child: cardBuilder(id),
                  ),
                ),
              DashboardDropTarget(
                key: const Key('dashboard-target-end'),
                onMove: (id, _) => onMove(id, null, false),
                child: const SizedBox(height: 64, width: double.infinity),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cardBar(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      IconButton(
        key: const Key('dashboard-edit-reset'),
        tooltip: AppLocalizations.of(context)!.restoreDefaultOrder,
        onPressed: onReset,
        icon: const Icon(Icons.settings_backup_restore_rounded),
        color: const Color(0xff8197a5),
      ),
      IconButton(
        key: const Key('dashboard-edit-done'),
        tooltip: AppLocalizations.of(context)!.editDone,
        onPressed: onDone,
        icon: const Icon(Icons.check_rounded),
        color: const Color(0xffd4a85f),
      ),
    ],
  );

  // 放不下时先省略「还原」：「完成」是退出编辑的唯一入口，最多占满整行。
  Widget _flatBar(BuildContext context) => SizedBox(
    key: const Key('dashboard-edit-bar'),
    height: flatHeaderHeight,
    child: LayoutBuilder(
      builder: (context, constraints) => Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: _FlatTextButton(
              key: const Key('dashboard-edit-reset'),
              label: AppLocalizations.of(context)!.restoreDefaultOrder,
              color: flatMutedColor,
              onTap: onReset,
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth),
            child: _FlatTextButton(
              key: const Key('dashboard-edit-done'),
              label: AppLocalizations.of(context)!.editDone,
              color: flatAccentColor,
              bold: true,
              onTap: onDone,
            ),
          ),
        ],
      ),
    ),
  );
}

class _FlatTextButton extends StatelessWidget {
  const _FlatTextButton({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
    this.bold = false,
  });
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool bold;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Center(
          widthFactor: 1,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: flatRowFontSize,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    ),
  );
}
