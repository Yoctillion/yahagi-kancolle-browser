import 'dart:math' as math;

import '../theme/app_palette.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'fleet_ui_strings.dart';

import '../../l10n/app_localizations.dart';
import '../game_state/game_state.dart';
import '../layout/display_corners.dart';
import '../layout/flat_collapse_chevron.dart';
import '../settings/header_resource_settings.dart';
import '../settings/layout_settings_controller.dart';
import '../performance/second_tick_scope.dart';
import '../widgets/top_notice.dart';
import 'anchorage_repair_calculator.dart';
import 'header_resource_catalog.dart';

class ResourceGrid extends StatelessWidget {
  const ResourceGrid({super.key, required this.state});

  final GameState state;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 450 ? 2 : 4;

        const spacing = 4.0;
        final available =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        final itemWidth = available.clamp(0.0, double.infinity);
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: <Widget>[
            for (final type in GameResourceType.values)
              SizedBox(
                width: itemWidth,
                child: Tooltip(
                  message: fleetText(context, type.label),
                  child: _ResourceItem(type: type, value: state.resource(type)),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ResourceItem extends StatelessWidget {
  const _ResourceItem({required this.type, required this.value});

  final GameResourceType type;
  final int? value;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('resource-item-${type.apiId}'),
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: appColor(context, Color(0xff142735)),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: appColor(context, Color(0xff315064))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Image.asset(
            _assetPath(type),
            key: Key('resource-icon-${type.apiId}'),
            width: 17,
            height: 17,
            filterQuality: FilterQuality.medium,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value?.toString() ?? '—',
                maxLines: 1,
                softWrap: false,
                style: appTextStyle(
                  context,
                  TextStyle(
                    color: appColor(context, Color(0xffdce6eb)),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _assetPath(GameResourceType type) =>
      'assets/images/material/${type.apiId.toString().padLeft(2, '0')}.png';
}

enum ResourceBarLayout { strip, staticStrip, grid }

/// 借用信息栏模块的折叠列表持久化网格的折叠状态。
const panelResourcesCollapseId = 'panel-resources';

class CompactResourceBar extends StatefulWidget {
  const CompactResourceBar({
    super.key,
    required this.state,
    this.senka,
    this.rank,
    this.anchorageRepairStartedAt,
    this.nosakiSparkleStartedAt,
    this.settingsController,
    this.onSenkaTap,
    this.onAnchorageTimerTap,
    this.onNosakiTimerTap,
    this.onFrameRefreshTap,
    this.layout = ResourceBarLayout.strip,
    this.gridPadding = EdgeInsets.zero,
    this.gridCornerRadii = (left: 0, right: 0),
    this.uiSize,
  });

  final GameState state;
  final double? senka;
  final int? rank;
  final DateTime? anchorageRepairStartedAt;
  final DateTime? nosakiSparkleStartedAt;
  final LayoutSettingsController? settingsController;
  final VoidCallback? onSenkaTap;
  final VoidCallback? onAnchorageTimerTap;
  final VoidCallback? onNosakiTimerTap;
  final VoidCallback? onFrameRefreshTap;

  /// grid 用于游戏页没有顶栏时把资源放进信息栏；strip 是顶栏里的横向滚动条；
  /// staticStrip 是只展示的单行，放不下时整行缩小而不滚动。
  final ResourceBarLayout layout;
  final EdgeInsets gridPadding;

  /// 网格贴着屏幕顶角那侧要避让的圆角半径，不贴角的一侧为 0。
  final ({double left, double right}) gridCornerRadii;

  /// Overrides the settings size, e.g. HD lays minimal out as compact.
  final UiDisplaySize? uiSize;

  @override
  State<CompactResourceBar> createState() => _CompactResourceBarState();
}

class _CompactResourceBarState extends State<CompactResourceBar> {
  static const Map<String, ({int useItemId, int rate})> _furnitureBoxCoinRates =
      <String, ({int useItemId, int rate})>{
        'useitem-10': (useItemId: 10, rate: 200),
        'useitem-11': (useItemId: 11, rate: 400),
        'useitem-12': (useItemId: 12, rate: 700),
      };

  late final ScrollController _scrollController = ScrollController();
  final Set<String> _furnitureBoxCoinModeIds = <String>{};
  bool _showTheoreticalFurnitureCoins = false;
  bool _editing = false;
  DateTime _now = DateTime.now().toUtc();

  @override
  void initState() {
    super.initState();
    widget.settingsController?.addListener(_handleSettingsChanged);
  }

  @override
  void didUpdateWidget(covariant CompactResourceBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settingsController != widget.settingsController) {
      oldWidget.settingsController?.removeListener(_handleSettingsChanged);
      widget.settingsController?.addListener(_handleSettingsChanged);
    }
    if (widget.settingsController?.uiLocked == true) {
      _editing = false;
    }
  }

  @override
  void dispose() {
    widget.settingsController?.removeListener(_handleSettingsChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleSettingsChanged() {
    if (!mounted) return;
    if (widget.settingsController?.uiLocked == true && _editing) {
      setState(() => _editing = false);
    }
  }

  void _toggleFurnitureBoxCoinMode(String id) {
    setState(() {
      if (!_furnitureBoxCoinModeIds.remove(id)) {
        _furnitureBoxCoinModeIds.add(id);
      }
    });
  }

  void _toggleTheoreticalFurnitureCoins() {
    setState(() {
      _showTheoreticalFurnitureCoins = !_showTheoreticalFurnitureCoins;
    });
  }

  int? _headerResourceValue(String id, HeaderResourceSpec spec) {
    final value = spec.value(widget.state);
    if (id == headerFurnitureCoinId && _showTheoreticalFurnitureCoins) {
      if (value == null || !widget.state.hasUseItemData) return null;
      var total = value;
      for (final box in _furnitureBoxCoinRates.values) {
        total += widget.state.useItemCount(box.useItemId)! * box.rate;
      }
      return total;
    }
    final box = _furnitureBoxCoinModeIds.contains(id)
        ? _furnitureBoxCoinRates[id]
        : null;
    return value == null || box == null ? value : value * box.rate;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        event.kind != PointerDeviceKind.mouse ||
        event.scrollDelta.dx != 0 ||
        event.scrollDelta.dy == 0 ||
        !_scrollController.hasClients) {
      return;
    }
    // The child Scrollable keeps priority for native horizontal/Shift scrolling.
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!_scrollController.hasClients) return;
      _scrollController.position.pointerScroll(event.scrollDelta.dy);
    });
  }

  String get _anchorageElapsed {
    if (!AnchorageRepairCalculator.hasReadyFleet(widget.state)) {
      return '--:--:--';
    }
    return formatAnchorageRepairElapsed(widget.anchorageRepairStartedAt, _now);
  }

  String get _nosakiElapsed {
    return formatNosakiSparkleElapsed(widget.nosakiSparkleStartedAt, _now);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.anchorageRepairStartedAt == null &&
        widget.nosakiSparkleStartedAt == null) {
      return _buildWithSettings(context, DateTime.now().toUtc());
    }
    return SecondTickBuilder(
      builder: (context, now, _) => _buildWithSettings(context, now),
    );
  }

  Widget _buildWithSettings(BuildContext context, DateTime now) {
    _now = now;
    final controller = widget.settingsController;
    if (controller != null) {
      return AnimatedBuilder(
        animation: controller,
        builder: (context, _) => _buildBar(controller),
      );
    }
    return _buildBar(null);
  }

  Widget _buildBar(LayoutSettingsController? controller) {
    final uiSize =
        widget.uiSize ?? controller?.uiDisplaySize ?? UiDisplaySize.normal;
    final isCompact = uiSize.isCompactOrSmaller;
    final barHeight = headerCapsuleHeight(uiSize);
    final separatorWidth = isCompact && !uiSize.isMinimal ? 5.0 : 6.0;

    final order = controller?.headerResourceOrder ?? allHeaderResourceIds;
    final visible =
        (controller?.visibleHeaderResourceIds ??
                defaultVisibleHeaderResourceIds)
            .toSet();
    final isEditing = _editing && controller?.uiLocked != true;
    final ids = isEditing
        ? order
        : <String>[
            for (final id in order)
              if (visible.contains(id)) id,
          ];
    final l10n =
        AppLocalizations.of(context) ??
        lookupAppLocalizations(const Locale('zh'));
    if (widget.layout == ResourceBarLayout.grid) {
      return _buildGrid(
        ids,
        controller: controller,
        l10n: l10n,
        uiSize: uiSize,
      );
    }
    if (widget.layout == ResourceBarLayout.staticStrip && !isEditing) {
      return _buildStaticStrip(
        ids,
        controller: controller,
        l10n: l10n,
        uiSize: uiSize,
        separatorWidth: separatorWidth,
      );
    }
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: SizedBox(
        height: barHeight,
        child: isEditing
            ? Row(
                key: const Key('header-resource-edit-mode'),
                children: [
                  _EditButton(
                    key: const Key('header-resource-reset'),
                    icon: Icons.restart_alt_rounded,
                    tooltip: l10n.restoreDefaultOrder,
                    size: barHeight,
                    iconSize: isCompact ? 16 : 18,
                    onPressed: controller?.resetHeaderResources,
                  ),
                  const SizedBox(width: 4),
                  _EditButton(
                    key: const Key('header-resource-edit-done'),
                    icon: Icons.check_rounded,
                    tooltip: l10n.editDone,
                    size: barHeight,
                    iconSize: isCompact ? 16 : 18,
                    onPressed: () => setState(() => _editing = false),
                  ),
                  const SizedBox(width: 4),
                  _EditButton(
                    key: const Key('header-resource-filter'),
                    icon: Icons.filter_alt_rounded,
                    tooltip: l10n.filterVisibleItems,
                    size: barHeight,
                    iconSize: isCompact ? 16 : 18,
                    onPressed: controller == null
                        ? null
                        : () => _showResourceFilter(controller),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: ReorderableListView.builder(
                      scrollController: _scrollController,
                      padding: EdgeInsets.zero,
                      scrollDirection: Axis.horizontal,
                      buildDefaultDragHandles: false,
                      itemCount: ids.length,
                      onReorderItem: (oldIndex, newIndex) {
                        if (controller == null) return;
                        final reordered = List<String>.from(ids);
                        final item = reordered.removeAt(oldIndex);
                        reordered.insert(
                          newIndex.clamp(0, reordered.length),
                          item,
                        );
                        controller.setHeaderResourceOrder(reordered);
                      },
                      itemBuilder: (context, index) {
                        final id = ids[index];
                        return Padding(
                          key: ValueKey('header-resource-edit-$id'),
                          padding: EdgeInsets.only(
                            right: index + 1 < ids.length ? separatorWidth : 0,
                          ),
                          child: ReorderableDelayedDragStartListener(
                            index: index,
                            child: _buildEditableItem(
                              id,
                              visible: visible.contains(id),
                              uiSize: uiSize,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              )
            : ListView.separated(
                controller: _scrollController,
                key: const Key('header-resource-list'),
                padding: EdgeInsets.zero,
                primary: false,
                scrollDirection: Axis.horizontal,
                itemCount: ids.length,
                separatorBuilder: (context, index) =>
                    SizedBox(width: separatorWidth),
                itemBuilder: (context, index) {
                  final id = ids[index];
                  return _buildInteractiveItem(
                    id,
                    controller: controller,
                    l10n: l10n,
                    uiSize: uiSize,
                    width: uiSize.isMinimal
                        ? _stripNaturalWidth(context, id, uiSize: uiSize)
                        : _stripItemWidth(id, isCompact),
                  );
                },
              ),
      ),
    );
  }

  static const double _gridSpacing = 4;
  static const int _gridColumns = 4;
  static const double _gridRunSpacing = 2;
  static const double _gridToggleExtent = 24;
  static const double _gridToggleMaxOverhang = 8;

  // 13dp 图标 + 2dp 间隙 + 40dp 数值位：六位数值缩放仍在 0.9 以上。
  static const double _gridMinReadableCellWidth = 55;

  static bool _isWideGridItem(String id) =>
      id == headerSenkaId ||
      id == headerAnchorageTimerId ||
      id == headerNosakiTimerId ||
      id == headerFrameRefreshId ||
      id == headerShipCapacityId ||
      id == headerEquipmentCapacityId;

  static List<String> _defaultCollapsedGridIds(List<String> ids) =>
      ids.where((id) => !_isWideGridItem(id)).take(_gridColumns).toList();

  /// 折叠后显示的项，按 [ids] 的顺序；用户没选过时取前 4 个普通资源。
  static List<String> _collapsedGridIds(
    List<String> ids,
    LayoutSettingsController? controller,
  ) {
    final chosen = controller?.collapsedPanelResourceIds?.toSet();
    if (chosen == null) return _defaultCollapsedGridIds(ids);
    return [
      for (final id in ids)
        if (chosen.contains(id)) id,
    ];
  }

  bool _localGridCollapsed = false;

  bool _gridCollapsed(LayoutSettingsController? controller) =>
      controller?.dashboardCardCollapsed.contains(panelResourcesCollapseId) ??
      _localGridCollapsed;

  void _toggleGridCollapsed(LayoutSettingsController? controller) {
    if (controller == null) {
      setState(() => _localGridCollapsed = !_localGridCollapsed);
    } else {
      controller.toggleDashboardCardCollapsed(panelResourcesCollapseId);
    }
  }

  static String? _gridPartner(String id) => switch (id) {
    headerAnchorageTimerId => headerNosakiTimerId,
    headerNosakiTimerId => headerAnchorageTimerId,
    headerShipCapacityId => headerEquipmentCapacityId,
    headerEquipmentCapacityId => headerShipCapacityId,
    _ => null,
  };

  // 宽项和普通资源分组成行，换类时另起一行，两类项都保持用户排的顺序。宽项按
  // 自然宽度贪心装行（各行可用宽度因圆角内缩而不同），相邻的泊地与野埼、舰娘与
  // 装备容量作为一个整体装行，免得被行尾截成两半；一整行都放不下这一对时才拆开。
  // 普通资源按列数分行，列能上下对齐。
  static List<List<String>> _gridRows(
    List<String> ids,
    int columns, {
    required double Function(int row) rowWidth,
    required double Function(String id) naturalWidth,
  }) {
    final rows = <List<String>>[];
    var row = <String>[];
    var used = 0.0;
    void flush() {
      if (row.isEmpty) return;
      rows.add(row);
      row = <String>[];
      used = 0;
    }

    void addWide(List<String> unit) {
      final width =
          unit.fold(0.0, (sum, id) => sum + naturalWidth(id)) +
          _gridSpacing * (unit.length - 1);
      if (row.isNotEmpty &&
          (!_isWideGridItem(row.first) ||
              used + _gridSpacing + width > rowWidth(rows.length))) {
        flush();
      }
      if (unit.length > 1 && width > rowWidth(rows.length)) {
        for (final id in unit) {
          addWide([id]);
        }
        return;
      }
      used = (row.isEmpty ? 0 : used + _gridSpacing) + width;
      row.addAll(unit);
    }

    for (var i = 0; i < ids.length; i++) {
      final id = ids[i];
      if (_isWideGridItem(id)) {
        final paired = i + 1 < ids.length && ids[i + 1] == _gridPartner(id);
        addWide(paired ? [id, ids[++i]] : [id]);
        continue;
      }
      if (row.isNotEmpty &&
          (_isWideGridItem(row.first) || row.length == columns)) {
        flush();
      }
      row.add(id);
    }
    flush();
    return rows;
  }

  /// 网格项内容不缩放时需要的宽度。
  double _gridNaturalWidth(
    BuildContext context,
    String id, {
    required HeaderUiSize uiSize,
  }) {
    if (id == headerFrameRefreshId) {
      return _HeaderFrameRefreshPill(uiSize: uiSize).gridNaturalWidth(context);
    }
    final wide = _buildGridWideItem(id);
    assert(wide != null, 'no grid natural width for $id');
    return wide?.naturalWidth(context) ?? 0;
  }

  Widget _buildGrid(
    List<String> ids, {
    required LayoutSettingsController? controller,
    required AppLocalizations l10n,
    required HeaderUiSize uiSize,
  }) {
    final collapsed = _gridCollapsed(controller);
    final padding = widget.gridPadding;
    final radii = widget.gridCornerRadii;
    // 极简游戏页没有顶栏，网格顶边就是屏幕顶边。圆弧在每行图标顶线处的切入量各
    // 不相同：大圆角下首行要让得比 45° 的固定量多，后几行则几乎不必让。
    ({double left, double right}) cornerInsets(int row) {
      final iconTop =
          padding.top +
          row * (_headerGridItemHeight + _gridRunSpacing) +
          (_headerGridItemHeight - _headerGridIconSize) / 2;
      return (
        left: cornerInsetAt(radii.left, iconTop),
        right: cornerInsetAt(radii.right, iconTop),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(0.0, constraints.maxWidth - padding.horizontal);
        double rowWidth(int row) {
          final insets = cornerInsets(row);
          return math.max(0.0, width - insets.left - insets.right);
        }

        final naturalWidths = <String, double>{};
        double naturalWidth(String id) => naturalWidths[id] ??=
            _gridNaturalWidth(context, id, uiSize: uiSize);

        double plainCellWidth(int row, int columns) => math.max(
          0.0,
          (rowWidth(row) - _gridSpacing * (columns - 1)) / columns,
        );

        var columns = _gridColumns;
        final shown = collapsed ? _collapsedGridIds(ids, controller) : ids;
        List<List<String>> packRows() => _gridRows(
          shown,
          columns,
          rowWidth: rowWidth,
          naturalWidth: naturalWidth,
        );
        var rows = packRows();
        if (collapsed) {
          // 折叠后行数少、靠近网格顶边，屏幕圆角切得多；普通资源的首行挤不下
          // 可读的数值就改成两列。
          final plainRow = rows.indexWhere(
            (row) => !_isWideGridItem(row.first),
          );
          if (plainRow >= 0 &&
              rows[plainRow].length > 2 &&
              plainCellWidth(plainRow, columns) < _gridMinReadableCellWidth) {
            columns = 2;
            rows = packRows();
          }
        }
        // 折叠按钮压在末行右端，向右伸进留白（至多 8）以少占末格；点击框必须留
        // 在 Stack 内才能被点到，所以伸出量受末行右侧留白限制。
        final toggleRight =
            padding.right + cornerInsets(math.max(0, rows.length - 1)).right;
        final toggleOverhang = math.min(_gridToggleMaxOverhang, toggleRight);
        final toggleReserve = _gridToggleExtent - toggleOverhang;

        Widget buildRow(int index) {
          final row = rows[index];
          final last = index == rows.length - 1;
          final available = rowWidth(index);
          final List<double> cellWidths;
          if (_isWideGridItem(row.first)) {
            // 余量平分给各格让行仍满宽；宽项行总是满的，是末行时要给按钮让位。
            final natural = [for (final id in row) naturalWidth(id)];
            final used =
                natural.fold(0.0, (sum, w) => sum + w) +
                _gridSpacing * (row.length - 1);
            final extra =
                (available - (last ? toggleReserve : 0) - used) / row.length;
            cellWidths = [for (final w in natural) math.max(0.0, w + extra)];
          } else {
            final cell = plainCellWidth(index, columns);
            // 末行没排满时按钮落在空位里，排满了才让末格让出按钮的位置。
            final reserve = last && row.length == columns ? toggleReserve : 0.0;
            cellWidths = [
              for (var i = 0; i < row.length; i++)
                i == row.length - 1 ? math.max(0.0, cell - reserve) : cell,
            ];
          }
          return Padding(
            padding: EdgeInsets.only(left: cornerInsets(index).left),
            child: Row(
              children: [
                for (var i = 0; i < row.length; i++) ...[
                  if (i > 0) const SizedBox(width: _gridSpacing),
                  _buildInteractiveItem(
                    row[i],
                    controller: controller,
                    l10n: l10n,
                    uiSize: uiSize,
                    width: cellWidths[i],
                  ),
                ],
              ],
            ),
          );
        }

        return Stack(
          key: const Key('information-panel-resources'),
          children: [
            Padding(
              padding: padding,
              child: _HeaderGridScope(
                // 折叠后可能一行都没有（只剩宽项或全部隐藏），仍要留出完整的
                // 按钮高度，否则按钮被 Stack 裁掉就再也展不开。
                child: Container(
                  width: width,
                  constraints: BoxConstraints(
                    minHeight: rows.isEmpty ? _gridToggleExtent : 0,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        if (i > 0) const SizedBox(height: _gridRunSpacing),
                        buildRow(i),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: toggleRight - toggleOverhang,
              bottom: padding.bottom,
              child: _buildGridToggle(
                controller,
                collapsed: collapsed,
                l10n: l10n,
                iconInset: toggleOverhang,
              ),
            ),
          ],
        );
      },
    );
  }

  // 折叠与信息栏模块一样不受界面锁影响：锁只禁止改布局，不禁止收起内容。
  Widget _buildGridToggle(
    LayoutSettingsController? controller, {
    required bool collapsed,
    required AppLocalizations l10n,
    required double iconInset,
  }) {
    // 图标右缘与各行右缘对齐，伸进内边距的只是点击框。
    return FlatCollapseChevron(
      key: const Key('information-panel-resources-toggle'),
      collapsed: collapsed,
      label: collapsed
          ? l10n.panelResourcesExpand
          : l10n.panelResourcesCollapse,
      onTap: () => _toggleGridCollapsed(controller),
      width: _gridToggleExtent,
      // 点击框贴着末行底边，比 20dp 的行高出 4dp；图标对齐末行的中线。
      iconAlignment: const Alignment(1, 4 / 9),
      iconInset: iconInset,
    );
  }

  Widget _buildStaticStrip(
    List<String> ids, {
    required LayoutSettingsController? controller,
    required AppLocalizations l10n,
    required HeaderUiSize uiSize,
    required double separatorWidth,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final barHeight = headerCapsuleHeight(uiSize);
        final height = constraints.hasBoundedHeight
            ? math.min(constraints.maxHeight, barHeight)
            : barHeight;
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            key: const Key('header-resource-line'),
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < ids.length; i++) ...[
                if (i > 0) SizedBox(width: separatorWidth),
                SizedBox(
                  height: height,
                  child: _buildInteractiveItem(
                    ids[i],
                    controller: controller,
                    l10n: l10n,
                    uiSize: uiSize,
                    width: _stripNaturalWidth(context, ids[i], uiSize: uiSize),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// 横条项按实际渲染的横条样式测出的不缩放宽度。
  double _stripNaturalWidth(
    BuildContext context,
    String id, {
    required HeaderUiSize uiSize,
  }) {
    if (_buildDisplayItem(id, uiSize: uiSize) case final _NaturallySized item) {
      return item.naturalWidth(context);
    }
    assert(false, 'no strip natural width for $id');
    return _stripItemWidth(id, uiSize.isCompactOrSmaller);
  }

  double _stripItemWidth(String id, bool isCompact) => switch (id) {
    headerSenkaId => isCompact ? 132 : 142,
    headerAnchorageTimerId => isCompact ? 118 : 128,
    headerNosakiTimerId => isCompact ? 118 : 128,
    headerFrameRefreshId => isCompact ? 88 : 98,
    headerShipCapacityId => isCompact ? 108 : 118,
    headerEquipmentCapacityId => isCompact ? 126 : 138,
    _ => isCompact ? 74 : 82,
  };

  Widget _buildInteractiveItem(
    String id, {
    required LayoutSettingsController? controller,
    required AppLocalizations l10n,
    required HeaderUiSize uiSize,
    required double width,
  }) {
    return GestureDetector(
      key: Key('header-resource-$id'),
      behavior: HitTestBehavior.opaque,
      onTap: id == headerFurnitureCoinId
          ? _toggleTheoreticalFurnitureCoins
          : _furnitureBoxCoinRates.containsKey(id)
          ? () => _toggleFurnitureBoxCoinMode(id)
          : switch (id) {
              headerSenkaId => widget.onSenkaTap,
              headerAnchorageTimerId => widget.onAnchorageTimerTap,
              headerNosakiTimerId => widget.onNosakiTimerTap,
              headerFrameRefreshId => widget.onFrameRefreshTap,
              _ => null,
            },
      onLongPress: () {
        if (controller?.uiLocked == true) {
          TopNotice.show(context, message: l10n.uiLockedToast);
        } else if (widget.layout != ResourceBarLayout.grid) {
          setState(() => _editing = true);
        } else if (controller != null) {
          _showCollapsedItemsPicker(controller);
        }
      },
      child: Tooltip(
        message: switch (id) {
          headerSenkaId => fleetText(context, '战果'),
          headerAnchorageTimerId => fleetText(context, '泊地修理计时'),
          headerNosakiTimerId => fleetText(context, '野埼刷闪计时'),
          headerFrameRefreshId => l10n.frameRefreshShortcutLabel,
          headerShipCapacityId => l10n.shipGirl,
          headerEquipmentCapacityId => l10n.equipment,
          _ => fleetText(context, headerResourceById[id]!.label),
        },
        triggerMode:
            id == headerSenkaId ||
                id == headerAnchorageTimerId ||
                id == headerNosakiTimerId ||
                id == headerFrameRefreshId ||
                id == headerFurnitureCoinId ||
                _furnitureBoxCoinRates.containsKey(id)
            ? TooltipTriggerMode.manual
            : TooltipTriggerMode.tap,
        child: SizedBox(
          width: width,
          child: _buildDisplayItem(id, uiSize: uiSize),
        ),
      ),
    );
  }

  _HeaderGridValue? _buildGridWideItem(String id) {
    const dim = Color(0xff9fb3bf);
    const bright = Color(0xffdce6eb);
    switch (id) {
      case headerSenkaId:
        return _HeaderGridValue(
          key: const Key('header-senka-summary'),
          icon: Icons.emoji_events_rounded,
          label: fleetText(context, '战果'),
          value: '${_formatSenka(widget.senka)}(#${widget.rank ?? '--'})',
          color: const Color(0xffe0b25c),
        );
      case headerAnchorageTimerId:
        final elapsed = _anchorageElapsed;
        return _HeaderGridValue(
          key: const Key('header-anchorage-timer-summary'),
          icon: Icons.anchor,
          label: fleetText(context, '泊地修理计时'),
          value: _gridTimerText(elapsed),
          color: elapsed == '--:--:--' ? dim : bright,
        );
      case headerNosakiTimerId:
        final elapsed = _nosakiElapsed;
        return _HeaderGridValue(
          key: const Key('header-nosaki-timer-summary'),
          icon: Icons.auto_awesome,
          label: fleetText(context, '野埼刷闪计时'),
          value: _gridTimerText(elapsed),
          color: elapsed == '--:--:--' ? dim : bright,
        );
      case headerShipCapacityId || headerEquipmentCapacityId:
        final ships = id == headerShipCapacityId;
        final capacity = _capacity(id);
        return _HeaderGridValue(
          key: Key(
            ships ? 'header-ship-capacity' : 'header-equipment-capacity',
          ),
          icon: ships
              ? Icons.directions_boat_filled_rounded
              : Icons.build_rounded,
          label: capacity.label,
          value: '${capacity.current ?? '—'}/${capacity.maximum ?? '—'}',
          color: bright,
        );
    }
    return null;
  }

  // 空闲时网格只留短横线，省下的宽度让别的宽项能挤进同一行。
  static String _gridTimerText(String elapsed) =>
      elapsed == '--:--:--' ? '--' : elapsed;

  Widget _buildDisplayItem(
    String id, {
    HeaderUiSize uiSize = HeaderUiSize.normal,
  }) {
    if (widget.layout == ResourceBarLayout.grid) {
      final wide = _buildGridWideItem(id);
      if (wide != null) return wide;
    }
    if (id == headerSenkaId) {
      return _HeaderSenkaSummary(
        senka: widget.senka,
        rank: widget.rank,
        uiSize: uiSize,
      );
    }
    if (id == headerAnchorageTimerId) {
      return _HeaderAnchorageTimerSummary(
        elapsed: _anchorageElapsed,
        uiSize: uiSize,
      );
    }
    if (id == headerNosakiTimerId) {
      return _HeaderNosakiTimerSummary(elapsed: _nosakiElapsed, uiSize: uiSize);
    }
    if (id == headerFrameRefreshId) {
      return _HeaderFrameRefreshPill(uiSize: uiSize);
    }
    if (id == headerShipCapacityId || id == headerEquipmentCapacityId) {
      return _buildCapacityPill(id, uiSize: uiSize);
    }
    final spec = headerResourceById[id]!;
    return _HeaderResourceItem(
      spec: spec,
      value: _headerResourceValue(id, spec),
      valuePrefix: id == headerFurnitureCoinId && _showTheoreticalFurnitureCoins
          ? '≈'
          : '',
      showFurnitureCoinSuffix: _furnitureBoxCoinModeIds.contains(id),
      uiSize: uiSize,
    );
  }

  Widget _buildEditableItem(
    String id, {
    required bool visible,
    HeaderUiSize uiSize = HeaderUiSize.normal,
  }) {
    final isCompact = uiSize.isCompactOrSmaller;
    if (id == headerSenkaId) {
      return _EditableHeaderSenkaItem(
        senka: widget.senka,
        rank: widget.rank,
        visible: visible,
        uiSize: uiSize,
      );
    }
    if (id == headerAnchorageTimerId) {
      return _EditableHeaderAnchorageTimerItem(
        elapsed: _anchorageElapsed,
        visible: visible,
        uiSize: uiSize,
      );
    }
    if (id == headerNosakiTimerId) {
      return _EditableHeaderNosakiTimerItem(
        elapsed: _nosakiElapsed,
        visible: visible,
        uiSize: uiSize,
      );
    }
    if (id == headerFrameRefreshId) {
      return _EditableHeaderCapacityItem(
        width: isCompact ? 88 : 98,
        visible: visible,
        child: _HeaderFrameRefreshPill(uiSize: uiSize),
      );
    }
    if (id == headerShipCapacityId || id == headerEquipmentCapacityId) {
      return _EditableHeaderCapacityItem(
        width: id == headerShipCapacityId
            ? (isCompact ? 108 : 118)
            : (isCompact ? 126 : 138),
        visible: visible,
        child: _buildCapacityPill(id, uiSize: uiSize),
      );
    }
    final spec = headerResourceById[id]!;
    return _EditableHeaderResourceItem(
      spec: spec,
      value: _headerResourceValue(id, spec),
      valuePrefix: id == headerFurnitureCoinId && _showTheoreticalFurnitureCoins
          ? '≈'
          : '',
      showFurnitureCoinSuffix: _furnitureBoxCoinModeIds.contains(id),
      visible: visible,
      uiSize: uiSize,
    );
  }

  ({String label, int? current, int? maximum}) _capacity(String id) {
    final l10n =
        AppLocalizations.of(context) ??
        lookupAppLocalizations(const Locale('zh'));
    final ships = id == headerShipCapacityId;
    return (
      label: ships ? l10n.shipGirl : l10n.equipment,
      current: widget.state.hasPortData
          ? (ships
                ? widget.state.ships.length
                : widget.state.equipmentCapacityUsed)
          : null,
      maximum: ships
          ? widget.state.maxShipCount
          : widget.state.maxEquipmentCount,
    );
  }

  Widget _buildCapacityPill(
    String id, {
    HeaderUiSize uiSize = HeaderUiSize.normal,
  }) {
    final capacity = _capacity(id);
    return _HeaderCapacityPill(
      key: Key(
        id == headerShipCapacityId
            ? 'header-ship-capacity'
            : 'header-equipment-capacity',
      ),
      label: capacity.label,
      current: capacity.current,
      maximum: capacity.maximum,
      uiSize: uiSize,
    );
  }

  Future<void> _showResourceFilter(LayoutSettingsController controller) {
    final l10n =
        AppLocalizations.of(context) ??
        lookupAppLocalizations(const Locale('zh'));
    return _showResourceChecklist(
      controller,
      title: l10n.selectHeaderVisibleItems,
      ids: () => controller.headerResourceOrder,
      checked: () => controller.visibleHeaderResourceIds.toSet(),
      onToggle: controller.toggleHeaderResourceVisible,
    );
  }

  Future<void> _showCollapsedItemsPicker(LayoutSettingsController controller) {
    final l10n =
        AppLocalizations.of(context) ??
        lookupAppLocalizations(const Locale('zh'));
    List<String> visibleIds() {
      final visible = controller.visibleHeaderResourceIds.toSet();
      return [
        for (final id in controller.headerResourceOrder)
          if (visible.contains(id)) id,
      ];
    }

    return _showResourceChecklist(
      controller,
      key: const Key('panel-resource-collapsed-dialog'),
      title: l10n.panelResourcesCollapsedItems,
      ids: visibleIds,
      checked: () => _collapsedGridIds(visibleIds(), controller).toSet(),
      onToggle: (id) {
        // 从已存的选择出发而不是从可见项出发，隐藏项上的勾才不会被冲掉。
        final next = {
          ...controller.collapsedPanelResourceIds ??
              _defaultCollapsedGridIds(visibleIds()),
        };
        if (!next.remove(id)) next.add(id);
        controller.setCollapsedPanelResourceIds(next.toList());
      },
      action: IconButton(
        key: const Key('panel-resource-collapsed-reset'),
        tooltip: l10n.panelResourcesCollapsedItemsReset,
        onPressed: () => controller.setCollapsedPanelResourceIds(null),
        icon: Icon(
          Icons.restart_alt_rounded,
          color: appColor(context, const Color(0xffe0b25c)),
        ),
      ),
    );
  }

  Future<void> _showResourceChecklist(
    LayoutSettingsController controller, {
    Key? key,
    required String title,
    required List<String> Function() ids,
    required Set<String> Function() checked,
    required void Function(String id) onToggle,
    Widget? action,
  }) async {
    final l10n =
        AppLocalizations.of(context) ??
        lookupAppLocalizations(const Locale('zh'));
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        key: key,
        backgroundColor: appColor(context, const Color(0xff102532)),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: appColor(context, Color(0xff315064))),
          borderRadius: BorderRadius.circular(14),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390, maxHeight: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 6, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: appColor(context, const Color(0xffe0b25c)),
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    ?action,
                    IconButton(
                      key: const Key('header-resource-filter-done'),
                      tooltip: l10n.editDone,
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: Icon(
                        Icons.check_rounded,
                        color: appColor(context, Color(0xffe0b25c)),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: appColor(context, Color(0xff294052))),
              Flexible(
                child: AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) {
                    if (controller.uiLocked) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                      });
                    }
                    final items = ids();
                    final checkedIds = checked();
                    return ListView.builder(
                      key: const Key('header-resource-filter-list'),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final id = items[index];
                        return _buildChecklistRow(
                          id,
                          l10n: l10n,
                          checked: checkedIds.contains(id),
                          onChanged: controller.uiLocked
                              ? null
                              : () => onToggle(id),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChecklistRow(
    String id, {
    required AppLocalizations l10n,
    required bool checked,
    required VoidCallback? onChanged,
  }) {
    if (id == headerSenkaId) {
      return _HeaderSenkaFilterRow(
        senka: widget.senka,
        rank: widget.rank,
        checked: checked,
        onChanged: onChanged,
      );
    }
    if (id == headerAnchorageTimerId) {
      return _HeaderAnchorageTimerFilterRow(
        elapsed: _anchorageElapsed,
        checked: checked,
        onChanged: onChanged,
      );
    }
    if (id == headerNosakiTimerId) {
      return _HeaderNosakiTimerFilterRow(
        elapsed: _nosakiElapsed,
        checked: checked,
        onChanged: onChanged,
      );
    }
    if (id == headerFrameRefreshId) {
      return _HeaderCapacityFilterRow(
        id: id,
        label: l10n.frameRefreshShortcutLabel,
        value: '',
        icon: Icons.refresh_rounded,
        checked: checked,
        onChanged: onChanged,
      );
    }
    if (id == headerShipCapacityId || id == headerEquipmentCapacityId) {
      final ships = id == headerShipCapacityId;
      return _HeaderCapacityFilterRow(
        id: id,
        label: ships ? l10n.shipGirl : l10n.equipment,
        value:
            '${widget.state.hasPortData ? (ships ? widget.state.ships.length : widget.state.equipmentCapacityUsed) : '—'} / ${ships ? widget.state.maxShipCount ?? '—' : widget.state.maxEquipmentCount ?? '—'}',
        icon: ships
            ? Icons.directions_boat_filled_rounded
            : Icons.build_rounded,
        checked: checked,
        onChanged: onChanged,
      );
    }
    final spec = headerResourceById[id]!;
    return _HeaderResourceFilterRow(
      spec: spec,
      value: spec.value(widget.state),
      checked: checked,
      onChanged: onChanged,
    );
  }
}

// 信息栏网格里的资源项没有胶囊，字号也固定，靠它与顶栏 strip 区分。
class _HeaderGridScope extends InheritedWidget {
  const _HeaderGridScope({required super.child});

  @override
  bool updateShouldNotify(_HeaderGridScope oldWidget) => false;
}

bool _inHeaderGrid(BuildContext context) =>
    context.getInheritedWidgetOfExactType<_HeaderGridScope>() != null;

const double _headerGridFontSize = 11;

double _headerFontSize(BuildContext context, double stripSize) =>
    _inHeaderGrid(context) ? _headerGridFontSize : stripSize;

// 网格没有胶囊边框要包住，行高贴着 11 号字收紧，省下信息栏的纵向空间。
const double _headerGridItemHeight = 20;

const double _headerGridIconSize = 12;

double _headerTextWidth(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

// 向上取整再留 1dp，免得测量与实际排版的小数差让数值在格子边上缩放抖动。
double _headerNaturalWidth(double contentWidth) =>
    contentWidth.ceilToDouble() + 1;

/// 能报出内容不缩放时所需宽度的资源项；网格装行和极简横条按它定格宽。
abstract interface class _NaturallySized {
  double naturalWidth(BuildContext context);
}

double _headerStripItemHeight(bool isCompact) => isCompact ? 26 : 30;

double _headerItemHeight(BuildContext context, bool isCompact) =>
    _inHeaderGrid(context)
    ? _headerGridItemHeight
    : _headerStripItemHeight(isCompact);

// 网格按宽项的实际宽度装行，「战果：」这类文字前缀换成小图标，同一行能多放
// 一项；完整名称由外层 Tooltip 和图标的读屏标签提供。
class _HeaderGridValue extends StatelessWidget implements _NaturallySized {
  const _HeaderGridValue({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  static const double _iconGap = 3;

  TextStyle get _style => TextStyle(
    color: color,
    fontSize: _headerGridFontSize,
    fontWeight: FontWeight.w700,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  @override
  double naturalWidth(BuildContext context) => _headerNaturalWidth(
    _headerGridIconSize + _iconGap + _headerTextWidth(context, value, _style),
  );

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _headerGridItemHeight,
    child: Row(
      children: [
        Icon(
          icon,
          size: _headerGridIconSize,
          color: appColor(context, color),
          semanticLabel: label,
        ),
        const SizedBox(width: _iconGap),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              softWrap: false,
              style: appTextStyle(context, _style),
            ),
          ),
        ),
      ],
    ),
  );
}

// 极简档的顶栏要把空间让给数值，所以不画胶囊底色和边框。
BoxDecoration? _headerPillDecoration(
  BuildContext context,
  HeaderUiSize uiSize, {
  bool grid = false,
}) {
  if (grid || uiSize.isMinimal) return null;
  return BoxDecoration(
    color: appColor(context, const Color(0xff142735)),
    borderRadius: BorderRadius.circular(uiSize.isCompactOrSmaller ? 7 : 8),
    border: Border.all(color: appColor(context, const Color(0xff315064))),
  );
}

class _HeaderFrameRefreshPill extends StatelessWidget
    implements _NaturallySized {
  const _HeaderFrameRefreshPill({this.uiSize = HeaderUiSize.normal});

  final HeaderUiSize uiSize;

  bool get _isCompact => uiSize.isCompactOrSmaller;
  double get _horizontalPadding => _isCompact ? 6 : 8;
  double get _iconSize => _isCompact ? 15 : 17;
  double get _iconGap => _isCompact ? 3 : 4;

  static String _label(BuildContext context) =>
      (AppLocalizations.of(context) ??
              lookupAppLocalizations(const Locale('zh')))
          .frameRefreshShortcutLabel;

  static TextStyle _style(double fontSize) => TextStyle(
    color: const Color(0xffdce6eb),
    fontSize: fontSize,
    fontWeight: FontWeight.w700,
  );

  double _naturalWidthAt(BuildContext context, double fontSize) =>
      _headerNaturalWidth(
        _horizontalPadding * 2 +
            _iconSize +
            _iconGap +
            _headerTextWidth(context, _label(context), _style(fontSize)),
      );

  double gridNaturalWidth(BuildContext context) =>
      _naturalWidthAt(context, _headerGridFontSize);

  @override
  double naturalWidth(BuildContext context) =>
      _naturalWidthAt(context, _stripFontSize);

  double get _stripFontSize => _isCompact ? 11 : 12;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('header-frame-refresh'),
      height: _headerItemHeight(context, _isCompact),
      padding: EdgeInsets.symmetric(horizontal: _horizontalPadding),
      decoration: _headerPillDecoration(
        context,
        uiSize,
        grid: _inHeaderGrid(context),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.refresh_rounded,
            size: _iconSize,
            color: appColor(context, const Color(0xffd4a85f)),
          ),
          SizedBox(width: _iconGap),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _label(context),
                maxLines: 1,
                style: appTextStyle(
                  context,
                  _style(_headerFontSize(context, _stripFontSize)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 横条里只有一行文字的胶囊项；文字和样式在一处，测量与渲染不会走样。
abstract class _HeaderTextPill extends StatelessWidget
    implements _NaturallySized {
  const _HeaderTextPill({super.key, required this.uiSize, this.pillKey});

  final HeaderUiSize uiSize;
  final Key? pillKey;

  String text(BuildContext context);
  Color get color;

  /// 普通、紧凑档的固定宽度；极简档由外层按自然宽度约束。
  double? get width => null;

  bool get _isCompact => uiSize.isCompactOrSmaller;
  double get _horizontalPadding => _isCompact ? 6 : 8;

  TextStyle get _style => TextStyle(
    color: color,
    fontSize: _isCompact ? 11.5 : 12.5,
    fontWeight: FontWeight.w700,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  @override
  double naturalWidth(BuildContext context) => _headerNaturalWidth(
    _horizontalPadding * 2 + _headerTextWidth(context, text(context), _style),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      key: pillKey,
      width: width,
      height: _headerStripItemHeight(_isCompact),
      padding: EdgeInsets.symmetric(horizontal: _horizontalPadding),
      decoration: _headerPillDecoration(context, uiSize),
      alignment: Alignment.centerLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          text(context),
          maxLines: 1,
          softWrap: false,
          style: appTextStyle(context, _style),
        ),
      ),
    );
  }
}

class _HeaderCapacityPill extends _HeaderTextPill {
  const _HeaderCapacityPill({
    super.key,
    required this.label,
    required this.current,
    required this.maximum,
    super.uiSize = HeaderUiSize.normal,
  });

  final String label;
  final int? current;
  final int? maximum;

  @override
  String text(BuildContext context) =>
      '$label: ${current ?? '—'} / ${maximum ?? '—'}';

  @override
  Color get color => const Color(0xffdce6eb);
}

String formatAnchorageRepairElapsed(DateTime? startedAt, DateTime now) {
  if (startedAt == null) return '--:--:--';
  final normalizedStart = startedAt.toUtc();
  final normalizedNow = now.toUtc();
  final elapsed = normalizedNow.isBefore(normalizedStart)
      ? Duration.zero
      : normalizedNow.difference(normalizedStart);
  final hours = elapsed.inHours.toString().padLeft(2, '0');
  final minutes = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

String formatNosakiSparkleElapsed(DateTime? startedAt, DateTime now) {
  if (startedAt == null) return '--:--:--';
  final normalizedStart = startedAt.toUtc();
  final normalizedNow = now.toUtc();
  final elapsed = normalizedNow.isBefore(normalizedStart)
      ? Duration.zero
      : normalizedNow.difference(normalizedStart);
  final hours = elapsed.inHours.toString().padLeft(2, '0');
  final minutes = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

class _HeaderAnchorageTimerSummary extends _HeaderTextPill {
  const _HeaderAnchorageTimerSummary({
    required this.elapsed,
    super.uiSize = HeaderUiSize.normal,
  }) : super(pillKey: const Key('header-anchorage-timer-summary'));

  final String elapsed;

  @override
  String text(BuildContext context) => fleetText(context, '泊地：$elapsed');

  @override
  Color get color =>
      elapsed != '--:--:--' ? const Color(0xffdce6eb) : const Color(0xff9fb3bf);

  @override
  double get width => _isCompact ? 118 : 128;
}

class _HeaderNosakiTimerSummary extends _HeaderTextPill {
  const _HeaderNosakiTimerSummary({
    required this.elapsed,
    super.uiSize = HeaderUiSize.normal,
  }) : super(pillKey: const Key('header-nosaki-timer-summary'));

  final String elapsed;

  @override
  String text(BuildContext context) => fleetText(context, '野埼：$elapsed');

  @override
  Color get color =>
      elapsed != '--:--:--' ? const Color(0xffdce6eb) : const Color(0xff9fb3bf);

  @override
  double get width => _isCompact ? 118 : 128;
}

class _HeaderSenkaSummary extends _HeaderTextPill {
  const _HeaderSenkaSummary({
    required this.senka,
    required this.rank,
    super.uiSize = HeaderUiSize.normal,
  }) : super(pillKey: const Key('header-senka-summary'));

  final double? senka;
  final int? rank;

  @override
  String text(BuildContext context) =>
      fleetText(context, '战果：${_formatSenka(senka)}（#${rank ?? '--'}）');

  @override
  Color get color => const Color(0xffe0b25c);

  @override
  double get width => _isCompact ? 132 : 142;
}

String _formatSenka(double? value) {
  if (value == null) return '--';
  if (value == value.roundToDouble()) return value.round().toString();
  return value.toStringAsFixed(1);
}

class _HeaderResourceItem extends StatelessWidget implements _NaturallySized {
  const _HeaderResourceItem({
    required this.spec,
    required this.value,
    this.valuePrefix = '',
    this.showFurnitureCoinSuffix = false,
    this.uiSize = HeaderUiSize.normal,
  });

  final HeaderResourceSpec spec;
  final int? value;
  final String valuePrefix;
  final bool showFurnitureCoinSuffix;
  final HeaderUiSize uiSize;

  bool get _isCompact => uiSize.isCompactOrSmaller;

  // 网格四列很窄，又没有胶囊要留边，去掉内边距、缩小图标，尽量不缩数值。
  ({double padding, double iconSize, double gap}) _metrics(bool grid) => grid
      ? (padding: 0, iconSize: 13, gap: 2)
      : _isCompact
      ? (padding: 4, iconSize: 15, gap: 3)
      : (padding: 5, iconSize: 17, gap: 4);

  String _text(BuildContext context) {
    if (value == null) return '—';
    final suffix = showFurnitureCoinSuffix
        ? fleetText(context, '家具コイン').replaceFirst('家具', '')
        : '';
    return '$valuePrefix$value$suffix';
  }

  TextStyle _style(BuildContext context) => TextStyle(
    color: const Color(0xffdce6eb),
    fontSize: _headerFontSize(context, _isCompact ? 11.5 : 12.5),
    fontWeight: FontWeight.w700,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  @override
  double naturalWidth(BuildContext context) {
    final metrics = _metrics(_inHeaderGrid(context));
    return _headerNaturalWidth(
      metrics.padding * 2 +
          metrics.iconSize +
          metrics.gap +
          _headerTextWidth(context, _text(context), _style(context)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grid = _inHeaderGrid(context);
    final metrics = _metrics(grid);
    return Container(
      height: _headerItemHeight(context, _isCompact),
      padding: EdgeInsets.symmetric(horizontal: metrics.padding),
      decoration: _headerPillDecoration(context, uiSize, grid: grid),
      child: Row(
        children: [
          Image.asset(
            spec.assetPath,
            width: metrics.iconSize,
            height: metrics.iconSize,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
          SizedBox(width: metrics.gap),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              clipBehavior: Clip.hardEdge,
              child: Text(
                _text(context),
                maxLines: 1,
                style: appTextStyle(context, _style(context)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditableHeaderResourceItem extends StatelessWidget {
  const _EditableHeaderResourceItem({
    required this.spec,
    required this.value,
    required this.valuePrefix,
    required this.showFurnitureCoinSuffix,
    required this.visible,
    this.uiSize = HeaderUiSize.normal,
  });

  final HeaderResourceSpec spec;
  final int? value;
  final String valuePrefix;
  final bool showFurnitureCoinSuffix;
  final bool visible;
  final HeaderUiSize uiSize;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: visible ? 1 : 0.42,
    child: SizedBox(
      width: uiSize.isCompactOrSmaller ? 74 : 82,
      child: _HeaderResourceItem(
        spec: spec,
        value: value,
        valuePrefix: valuePrefix,
        showFurnitureCoinSuffix: showFurnitureCoinSuffix,
        uiSize: uiSize,
      ),
    ),
  );
}

class _EditableHeaderSenkaItem extends StatelessWidget {
  const _EditableHeaderSenkaItem({
    required this.senka,
    required this.rank,
    required this.visible,
    this.uiSize = HeaderUiSize.normal,
  });

  final double? senka;
  final int? rank;
  final bool visible;
  final HeaderUiSize uiSize;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: visible ? 1 : 0.42,
    child: SizedBox(
      width: uiSize.isCompactOrSmaller ? 132 : 142,
      child: _HeaderSenkaSummary(senka: senka, rank: rank, uiSize: uiSize),
    ),
  );
}

class _EditableHeaderAnchorageTimerItem extends StatelessWidget {
  const _EditableHeaderAnchorageTimerItem({
    required this.elapsed,
    required this.visible,
    this.uiSize = HeaderUiSize.normal,
  });

  final String elapsed;
  final bool visible;
  final HeaderUiSize uiSize;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: visible ? 1 : 0.42,
    child: SizedBox(
      width: uiSize.isCompactOrSmaller ? 118 : 128,
      child: _HeaderAnchorageTimerSummary(elapsed: elapsed, uiSize: uiSize),
    ),
  );
}

class _EditableHeaderNosakiTimerItem extends StatelessWidget {
  const _EditableHeaderNosakiTimerItem({
    required this.elapsed,
    required this.visible,
    this.uiSize = HeaderUiSize.normal,
  });

  final String elapsed;
  final bool visible;
  final HeaderUiSize uiSize;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: visible ? 1 : 0.42,
    child: SizedBox(
      width: uiSize.isCompactOrSmaller ? 118 : 128,
      child: _HeaderNosakiTimerSummary(elapsed: elapsed, uiSize: uiSize),
    ),
  );
}

class _EditableHeaderCapacityItem extends StatelessWidget {
  const _EditableHeaderCapacityItem({
    required this.width,
    required this.visible,
    required this.child,
  });

  final double width;
  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: visible ? 1 : 0.42,
    child: SizedBox(width: width, child: child),
  );
}

class _HeaderCapacityFilterRow extends StatelessWidget {
  const _HeaderCapacityFilterRow({
    required this.id,
    required this.label,
    required this.value,
    required this.icon,
    required this.checked,
    required this.onChanged,
  });

  final String id;
  final String label;
  final String value;
  final IconData icon;
  final bool checked;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) => Material(
    key: Key('header-resource-filter-row-$id'),
    color: appColor(context, Colors.transparent),
    child: InkWell(
      onTap: onChanged,
      child: SizedBox(
        height: 42,
        child: Row(
          children: [
            Checkbox(
              key: Key('header-resource-visible-$id'),
              value: checked,
              onChanged: onChanged == null ? null : (_) => onChanged!(),
              visualDensity: VisualDensity.compact,
            ),
            Icon(icon, size: 24, color: appColor(context, Color(0xff9fb3bf))),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: appTextStyle(
                  context,
                  TextStyle(
                    color: appColor(context, Color(0xffdce6eb)),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Text(
              value,
              style: appTextStyle(
                context,
                TextStyle(
                  color: appColor(context, Color(0xffdce6eb)),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    ),
  );
}

class _HeaderSenkaFilterRow extends StatelessWidget {
  const _HeaderSenkaFilterRow({
    required this.senka,
    required this.rank,
    required this.checked,
    required this.onChanged,
  });

  final double? senka;
  final int? rank;
  final bool checked;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('header-resource-filter-row-senka'),
    color: appColor(context, Colors.transparent),
    child: InkWell(
      onTap: onChanged,
      child: SizedBox(
        height: 42,
        child: Row(
          children: [
            Checkbox(
              key: const Key('header-resource-visible-senka'),
              value: checked,
              onChanged: onChanged == null ? null : (_) => onChanged!(),
              visualDensity: VisualDensity.compact,
            ),
            Icon(
              Icons.emoji_events_rounded,
              size: 24,
              color: appColor(context, Color(0xffe0b25c)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                fleetText(context, '战果'),
                style: appTextStyle(
                  context,
                  TextStyle(
                    color: Color(0xffdce6eb),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Text(
              '${_formatSenka(senka)}（#${rank ?? '--'}）',
              style: appTextStyle(
                context,
                TextStyle(
                  color: appColor(context, Color(0xffe0b25c)),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    ),
  );
}

class _HeaderAnchorageTimerFilterRow extends StatelessWidget {
  const _HeaderAnchorageTimerFilterRow({
    required this.elapsed,
    required this.checked,
    required this.onChanged,
  });

  final String elapsed;
  final bool checked;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('header-resource-filter-row-anchorage-timer'),
    color: appColor(context, Colors.transparent),
    child: InkWell(
      onTap: onChanged,
      child: SizedBox(
        height: 42,
        child: Row(
          children: [
            Checkbox(
              key: const Key('header-resource-visible-anchorage-timer'),
              value: checked,
              onChanged: onChanged == null ? null : (_) => onChanged!(),
              visualDensity: VisualDensity.compact,
            ),
            Icon(
              Icons.anchor_rounded,
              size: 24,
              color: appColor(context, Color(0xff9fb3bf)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                fleetText(context, '泊地计时'),
                style: appTextStyle(
                  context,
                  TextStyle(
                    color: Color(0xffdce6eb),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Text(
              elapsed,
              style: appTextStyle(
                context,
                TextStyle(
                  color: appColor(context, Color(0xff9fb3bf)),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    ),
  );
}

class _HeaderNosakiTimerFilterRow extends StatelessWidget {
  const _HeaderNosakiTimerFilterRow({
    required this.elapsed,
    required this.checked,
    required this.onChanged,
  });

  final String elapsed;
  final bool checked;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('header-resource-filter-row-nosaki-timer'),
    color: appColor(context, Colors.transparent),
    child: InkWell(
      onTap: onChanged,
      child: SizedBox(
        height: 42,
        child: Row(
          children: [
            Checkbox(
              key: const Key('header-resource-visible-nosaki-timer'),
              value: checked,
              onChanged: onChanged == null ? null : (_) => onChanged!(),
              visualDensity: VisualDensity.compact,
            ),
            Icon(
              Icons.restaurant_rounded,
              size: 24,
              color: appColor(context, Color(0xff9fb3bf)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                fleetText(context, '野埼计时'),
                style: appTextStyle(
                  context,
                  TextStyle(
                    color: Color(0xffdce6eb),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Text(
              elapsed,
              style: appTextStyle(
                context,
                TextStyle(
                  color: appColor(context, Color(0xff9fb3bf)),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    ),
  );
}

class _HeaderResourceFilterRow extends StatelessWidget {
  const _HeaderResourceFilterRow({
    required this.spec,
    required this.value,
    required this.checked,
    required this.onChanged,
  });

  final HeaderResourceSpec spec;
  final int? value;
  final bool checked;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) => Material(
    key: Key('header-resource-filter-row-${spec.id}'),
    color: appColor(context, Colors.transparent),
    child: InkWell(
      onTap: onChanged,
      child: SizedBox(
        height: 42,
        child: Row(
          children: [
            Checkbox(
              key: Key('header-resource-visible-${spec.id}'),
              value: checked,
              onChanged: onChanged == null ? null : (_) => onChanged!(),
              visualDensity: VisualDensity.compact,
            ),
            Image.asset(
              spec.assetPath,
              width: 24,
              height: 24,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                fleetText(context, spec.label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: appTextStyle(
                  context,
                  TextStyle(
                    color: appColor(context, Color(0xffdce6eb)),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Text(
              value?.toString() ?? '—',
              style: appTextStyle(
                context,
                TextStyle(
                  color: appColor(context, Color(0xff9fb3bf)),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    ),
  );
}

class _EditButton extends StatelessWidget {
  const _EditButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 30,
    this.iconSize = 18,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: IconButton(
      padding: EdgeInsets.zero,
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(
        icon,
        size: iconSize,
        color: appColor(context, Color(0xffe0b25c)),
      ),
    ),
  );
}
