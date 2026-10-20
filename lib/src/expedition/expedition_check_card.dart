import 'package:flutter/material.dart';

import '../account/account_session.dart';

import '../localization/ui_text.dart';
import '../localization/game_name_localizations.dart';

import '../game_state/game_state.dart';
import '../game_state/game_state_controller.dart';
import 'expedition_evaluator.dart';
import 'expedition_income_calculator.dart';
import 'expedition_mission_picker.dart';
import 'expedition_rule_catalog.dart';
import 'expedition_selection_store.dart';
import 'expedition_strings.dart';
import '../layout/flat_list_row.dart';
import '../layout/panel_style.dart';

class ExpeditionCheckContent extends StatefulWidget {
  const ExpeditionCheckContent({
    super.key,
    required this.controller,
    required this.onOpenDetails,
    this.selectionStore,
    this.accountSession,
  });

  final GameStateController controller;
  final ValueChanged<int> onOpenDetails;
  final ExpeditionSelectionStore? selectionStore;
  final AccountSession? accountSession;

  @override
  State<ExpeditionCheckContent> createState() => _ExpeditionCheckContentState();
}

class _ExpeditionCheckContentState extends State<ExpeditionCheckContent> {
  bool _detailed = false;
  bool _greatSuccess = false;
  int _target = 100;
  int _fleetId = 2;
  int _missionId = 1;
  int _restoreGeneration = 0;
  late final AccountSession _accountSession;
  late final ExpeditionSelectionStore _selectionStore;

  @override
  void initState() {
    super.initState();
    _accountSession = widget.accountSession ?? AccountSession.shared;
    _selectionStore =
        widget.selectionStore ??
        SharedPreferencesExpeditionSelectionStore(
          accountSession: _accountSession,
        );
    _accountSession.addListener(_onAccountChanged);
    _restoreMissionForFleet(_fleetId);
  }

  Future<void> _restoreMissionForFleet(int fleetId) async {
    final generation = ++_restoreGeneration;
    final scope = _accountSession.current;
    if (!scope.isKnown) return;
    final savedMissionId = await _selectionStore.loadMissionId(fleetId);
    if (!mounted ||
        _fleetId != fleetId ||
        generation != _restoreGeneration ||
        !_accountSession.isCurrent(scope)) {
      return;
    }
    final restoredMissionId =
        savedMissionId != null && expeditionRules.containsKey(savedMissionId)
        ? savedMissionId
        : expeditionRules.keys.first;
    if (_missionId == restoredMissionId) return;
    setState(() => _missionId = restoredMissionId);
  }

  void _selectFleet(int fleetId) {
    setState(() {
      _fleetId = fleetId;
      _missionId = expeditionRules.keys.first;
    });
    _restoreMissionForFleet(fleetId);
  }

  void _selectMission(int missionId) {
    _restoreGeneration++;
    setState(() => _missionId = missionId);
    if (_accountSession.current.isKnown) {
      _selectionStore.saveMissionId(_fleetId, missionId);
    }
  }

  void _onAccountChanged() {
    setState(() {
      _fleetId = 2;
      _missionId = expeditionRules.keys.first;
    });
    _restoreMissionForFleet(_fleetId);
  }

  @override
  void dispose() {
    _accountSession.removeListener(_onAccountChanged);
    super.dispose();
  }

  bool get _flat => PanelStyleScope.of(context) == PanelStyle.flat;

  @override
  Widget build(BuildContext context) {
    final strings = ExpeditionStrings.of(context);
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) =>
          _buildContent(context, widget.controller.state, strings),
    );
  }

  Widget _buildContent(
    BuildContext context,
    GameState state,
    ExpeditionStrings strings,
  ) {
    if (!state.hasPortData || state.fleets.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _controls(strings),
          SizedBox(height: _flat ? 4 : 10),
          _statusBox(
            strings.waiting,
            false,
            neutral: true,
            onTap: () => widget.onOpenDetails(_fleetId),
          ),
        ],
      );
    }
    final fleets = state.fleets
        .where((fleet) => fleet.shipIds.isNotEmpty)
        .toList();
    if (fleets.isEmpty) {
      return _statusBox(
        strings.waiting,
        false,
        neutral: true,
        onTap: () => widget.onOpenDetails(_fleetId),
      );
    }
    final fleet = fleets.cast<Fleet?>().firstWhere(
      (item) => item!.id == _fleetId,
      orElse: () => fleets.first,
    )!;
    final missionId = expeditionRules.containsKey(_missionId)
        ? _missionId
        : expeditionRules.keys.first;
    final evaluation = const ExpeditionEvaluator().evaluate(
      state: state,
      fleet: fleet,
      missionId: missionId,
      greatSuccessTarget: _target,
    );
    final income = ExpeditionIncomeCalculator.forMission(
      mission: state.masterMissions[missionId],
      greatSuccess: _greatSuccess,
      daihatsuBonus: ExpeditionIncomeCalculator.daihatsuBonusForFleet(
        state,
        fleet,
      ),
    );
    final flat = _flat;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _controls(strings),
        SizedBox(height: flat ? 4 : 8),
        _fleetSelector(fleets),
        SizedBox(height: flat ? 2 : 7),
        _missionSelector(state, missionId),
        SizedBox(height: flat ? 4 : 8),
        if (_greatSuccess && flat) ...[
          _statusBox(
            '${strings.normalCheck}：${evaluation.normalPassed ? strings.passed : strings.failed}',
            evaluation.normalPassed,
            onTap: () => widget.onOpenDetails(_fleetId),
          ),
          _statusBox(
            evaluation.greatSuccessPassed
                ? '${strings.greatSuccess}：${strings.passed} (${evaluation.greatSuccessRate.toStringAsFixed(2)}%)'
                : '${strings.greatSuccess}：${strings.failed}',
            evaluation.greatSuccessPassed,
            onTap: () => widget.onOpenDetails(_fleetId),
          ),
        ] else if (_greatSuccess)
          Row(
            children: [
              Expanded(
                child: _statusBox(
                  '${strings.normalCheck}：${evaluation.normalPassed ? strings.passed : strings.failed}',
                  evaluation.normalPassed,
                  onTap: () => widget.onOpenDetails(_fleetId),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _statusBox(
                  evaluation.greatSuccessPassed
                      ? '${strings.greatSuccess}：${strings.passed} (${evaluation.greatSuccessRate.toStringAsFixed(2)}%)'
                      : '${strings.greatSuccess}：${strings.failed}',
                  evaluation.greatSuccessPassed,
                  onTap: () => widget.onOpenDetails(_fleetId),
                ),
              ),
            ],
          )
        else
          _statusBox(
            '${strings.normalCheck}：${evaluation.normalPassed ? strings.passed : strings.failed}',
            evaluation.normalPassed,
            onTap: () => widget.onOpenDetails(_fleetId),
          ),
        if (_detailed) ...[
          SizedBox(height: flat ? 6 : 10),
          _sectionTitle(strings.expectedIncome, flat),
          SizedBox(height: flat ? 2 : 5),
          _resourceGrid(income, flat),
          SizedBox(height: flat ? 6 : 10),
          _sectionTitle(strings.conditions, flat),
          SizedBox(height: flat ? 2 : 5),
          for (final condition in [
            ...evaluation.normalConditions,
            if (_greatSuccess) ...evaluation.greatSuccessConditions,
            evaluation.daihatsuFill,
          ])
            _conditionRow(context, condition, strings, flat),
        ],
      ],
    );
  }

  Widget _controls(ExpeditionStrings strings) => LayoutBuilder(
    builder: (context, constraints) {
      final controlGroups = <Widget>[
        _segmentGroup(
          key: const Key('expedition-mode-segments'),
          children: [
            _segmentButton(
              key: const Key('expedition-mode-compact'),
              label: strings.compact,
              selected: !_detailed,
              onTap: () => setState(() => _detailed = false),
            ),
            _segmentButton(
              key: const Key('expedition-mode-detailed'),
              label: strings.detailed,
              selected: _detailed,
              onTap: () => setState(() => _detailed = true),
            ),
          ],
        ),
        _segmentGroup(
          key: const Key('expedition-success-segments'),
          children: [
            _segmentButton(
              key: const Key('expedition-success-normal'),
              label: strings.success,
              selected: !_greatSuccess,
              onTap: () => setState(() => _greatSuccess = false),
            ),
            _segmentButton(
              key: const Key('expedition-success-great'),
              label: strings.greatSuccess,
              selected: _greatSuccess,
              onTap: () => setState(() => _greatSuccess = true),
            ),
          ],
        ),
        if (_greatSuccess) _targetMenu(),
      ];
      if (constraints.maxWidth >= 440 && !_flat) {
        return Row(
          children: [
            for (var index = 0; index < controlGroups.length; index++) ...[
              if (index > 0) const SizedBox(width: 8),
              controlGroups[index],
            ],
            const Spacer(),
          ],
        );
      }
      return Wrap(
        spacing: _flat ? 10 : 8,
        runSpacing: _flat ? 2 : 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [...controlGroups],
      );
    },
  );

  Widget _segmentGroup({
    Key? key,
    required List<Widget> children,
    bool expandChildren = false,
  }) {
    if (_flat) {
      return Wrap(
        key: key,
        spacing: 8,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      );
    }
    return _cardSegmentGroup(
      key: key,
      children: children,
      expandChildren: expandChildren,
    );
  }

  Widget _cardSegmentGroup({
    Key? key,
    required List<Widget> children,
    required bool expandChildren,
  }) => Container(
    key: key,
    height: 26,
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: const Color(0xff10212e),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: const Color(0xff294052)),
    ),
    child: Row(
      mainAxisSize: expandChildren ? MainAxisSize.max : MainAxisSize.min,
      children: [
        for (final child in children)
          if (expandChildren) Expanded(child: child) else child,
      ],
    ),
  );

  Widget _segmentButton({
    Key? key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool command = false,
  }) {
    if (_flat) {
      return InkWell(
        key: key,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? flatTimeColor : flatIdleColor,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    return _cardSegmentButton(
      key: key,
      label: label,
      selected: selected,
      onTap: onTap,
      command: command,
    );
  }

  Widget _cardSegmentButton({
    Key? key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required bool command,
  }) => Material(
    key: key,
    color: selected ? const Color(0xff8a6628) : Colors.transparent,
    borderRadius: BorderRadius.circular(5),
    child: InkWell(
      borderRadius: BorderRadius.circular(5),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              children: [
                Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xffffdc88)
                        : command
                        ? const Color(0xffd4a85f)
                        : const Color(0xff8197a5),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _targetMenu() => PopupMenuButton<int>(
    initialValue: _target,
    onSelected: (value) => setState(() => _target = value),
    color: const Color(0xff1b263b),
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: Color(0xff415a77)),
      borderRadius: BorderRadius.circular(4),
    ),
    child: _segmentGroup(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: _flat ? 0 : 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$_target%',
                style: TextStyle(
                  fontSize: _flat ? 10.5 : 10,
                  color: _flat ? flatTimeColor : const Color(0xffdce6eb),
                  fontWeight: FontWeight.w700,
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                size: 14,
                color: _flat ? flatTimeColor : const Color(0xffdce6eb),
              ),
            ],
          ),
        ),
      ],
    ),
    itemBuilder: (context) => [
      for (final value in const [80, 85, 90, 95, 100])
        PopupMenuItem(
          value: value,
          height: 32,
          child: Text(
            '$value%',
            style: const TextStyle(fontSize: 13, color: Color(0xffdce6eb)),
          ),
        ),
    ],
  );

  Widget _fleetSelector(List<Fleet> fleets) => _segmentGroup(
    key: const Key('expedition-fleet-segments'),
    expandChildren: true,
    children: [
      for (final fleet in fleets.take(4))
        _segmentButton(
          key: Key('expedition-fleet-${fleet.id}'),
          label: fleet.name,
          selected: _fleetId == fleet.id,
          onTap: () => _selectFleet(fleet.id),
        ),
    ],
  );

  Widget _missionSelector(GameState state, int current) =>
      ExpeditionMissionPicker(
        missions: state.masterMissions,
        missionIds: expeditionRules.keys,
        selectedMissionId: current,
        selectedTextKey: const Key('expedition-mission-name'),
        compact: true,
        onSelected: _selectMission,
      );

  Widget _statusBox(
    String text,
    bool passed, {
    bool neutral = false,
    VoidCallback? onTap,
  }) {
    if (_flat) {
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Text(
            text,
            key: const Key('expedition-status-text'),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: flatRowTextStyle(
              color: neutral
                  ? flatIdleColor
                  : passed
                  ? flatDoneColor
                  : _flatFailColor,
            ),
          ),
        ),
      );
    }
    final color = neutral
        ? const Color(0xff244457)
        : passed
        ? const Color(0xff258a52)
        : const Color(0xffc43f4b);
    return LayoutBuilder(
      builder: (context, constraints) => Material(
        color: color,
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(5),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(
              text,
              key: const Key('expedition-status-text'),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: _expeditionSummaryTextSize(constraints.maxWidth),
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

double _expeditionSummaryTextSize(double availableWidth) =>
    availableWidth < 340 ? 11 : 12;

// 复用条件行里的未通过红，扁平档不新增配色。
const _flatFailColor = Color(0xffff5964);

Widget _sectionTitle(String text, bool flat) => Text(
  text,
  style: TextStyle(
    color: const Color(0xffd4a85f),
    fontSize: flat ? 11 : 13,
    fontWeight: flat ? FontWeight.w700 : FontWeight.w800,
  ),
);

Widget _resourceGrid(ExpeditionIncome income, bool flat) {
  final values = income.values;
  final gap = flat ? 2.0 : 6.0;
  return Column(
    children: [
      _resourceRow(1, values[0], 2, values[1], flat),
      SizedBox(height: gap),
      _resourceRow(3, values[2], 4, values[3], flat),
      if (income.items.isNotEmpty) ...[
        SizedBox(height: gap),
        _itemsRow(income.items, flat),
      ],
    ],
  );
}

Widget _resourceRow(int id1, int val1, int id2, int val2, bool flat) => Row(
  children: [
    Expanded(child: _resourceTile(id1, val1, flat)),
    SizedBox(width: flat ? 8 : 6),
    Expanded(child: _resourceTile(id2, val2, flat)),
  ],
);

Widget _itemsRow(List<ExpeditionRewardItem> items, bool flat) {
  final gap = SizedBox(width: flat ? 8 : 6);
  if (items.length == 1) {
    return Row(
      children: [
        Expanded(child: _itemTile(items[0], flat)),
        gap,
        const Expanded(child: SizedBox()),
      ],
    );
  }
  return Row(
    children: [
      Expanded(child: _itemTile(items[0], flat)),
      gap,
      Expanded(child: _itemTile(items[1], flat)),
    ],
  );
}

Widget _resourceTile(int apiId, int value, bool flat) {
  final assetId = apiId.toString().padLeft(2, '0');
  if (flat) {
    return Row(
      children: [
        Image.asset(
          'assets/images/material/$assetId.png',
          width: 13,
          height: 13,
          filterQuality: FilterQuality.medium,
        ),
        const Spacer(),
        Text('$value', style: flatRowTextStyle()),
      ],
    );
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xff0b1d29),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      children: [
        Image.asset(
          'assets/images/material/$assetId.png',
          width: 17,
          height: 17,
          filterQuality: FilterQuality.medium,
        ),
        const Spacer(),
        Text('$value', style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}

Widget _itemTile(ExpeditionRewardItem item, bool flat) {
  // Map useitem ID to material asset ID for common items
  String assetId;
  String? label;
  switch (item.id) {
    case 1:
      assetId = '06';
      break; // Bucket
    case 2:
      assetId = '05';
      break; // Flamethrower
    case 3:
      assetId = '07';
      break; // Dev mat
    case 4:
      assetId = '08';
      break; // Screw
    case 10:
      assetId = '10';
      label = '家具箱(小)';
      break;
    case 11:
      assetId = '11';
      label = '家具箱(中)';
      break;
    case 12:
      assetId = '12';
      label = '家具箱(大)';
      break;
    case 59:
      assetId = '59';
      label = '礼物箱';
      break;
    default:
      assetId = 'unknown';
      label = '道具 ${item.id}';
      break;
  }

  String kindText = item.kind == ExpeditionRewardKind.greatSuccess
      ? '(大成功获得)'
      : '(有几率获得)';
  if (flat) {
    return Row(
      children: [
        if (['05', '06', '07', '08', '10', '11', '12'].contains(assetId))
          Image.asset(
            'assets/images/material/$assetId.png',
            width: 13,
            height: 13,
            filterQuality: FilterQuality.medium,
          )
        else
          Flexible(
            child: UiText(
              label ?? '道具',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: flatIdleColor, fontSize: 11),
            ),
          ),
        const SizedBox(width: 4),
        Flexible(
          child: UiText(
            kindText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: flatIdleColor, fontSize: 11),
          ),
        ),
        const Spacer(),
        Text('${item.count}', style: flatRowTextStyle()),
      ],
    );
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xff0b1d29),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      children: [
        if (['05', '06', '07', '08', '10', '11', '12'].contains(assetId))
          Image.asset(
            'assets/images/material/$assetId.png',
            width: 17,
            height: 17,
            filterQuality: FilterQuality.medium,
          )
        else
          UiText(
            label ?? '道具',
            style: const TextStyle(color: Color(0xffa8bbc5), fontSize: 12),
          ),
        const SizedBox(width: 4),
        UiText(
          kindText,
          style: const TextStyle(color: Color(0xff7792a3), fontSize: 11),
        ),
        const Spacer(),
        Text(
          '${item.count}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

Widget _conditionRow(
  BuildContext context,
  ExpeditionConditionResult condition,
  ExpeditionStrings strings,
  bool flat,
) {
  final color = condition.passed
      ? const Color(0xff28d978)
      : condition.auxiliary
      ? const Color(0xffffc247)
      : const Color(0xffff5964);
  if (flat) {
    return FlatListRow(
      tags: [
        Text(
          condition.passed
              ? '✓'
              : condition.auxiliary
              ? '!'
              : '×',
          style: flatRowTextStyle(color: color),
        ),
      ],
      name: Text(
        gameNames(context).entityText(strings.conditionLabel(condition)),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: flatRowTextStyle(),
      ),
      trailing: flatRowTrailing(
        Text(
          strings.conditionActual(condition),
          maxLines: 1,
          style: flatRowTextStyle(color: color),
        ),
      ),
    );
  }
  return Container(
    margin: const EdgeInsets.only(bottom: 5),
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
    decoration: BoxDecoration(
      color: condition.auxiliary && !condition.passed
          ? const Color(0xff5a451b)
          : const Color(0xff0b1f2b),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Row(
      children: [
        Text(
          condition.passed
              ? '✓'
              : condition.auxiliary
              ? '!'
              : '×',
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            gameNames(context).entityText(strings.conditionLabel(condition)),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        Text(
          strings.conditionActual(condition),
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}
