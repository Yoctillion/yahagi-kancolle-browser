import 'dart:math' as math;

import '../theme/app_palette.dart';
import 'package:flutter/material.dart';

import '../layout/flat_style.dart';
import 'battle_ui_text.dart';
import 'battle_detail_strings.dart';

import '../../l10n/app_localizations.dart';
import '../game_state/game_state.dart';
import 'battle_models.dart';

const double _battlePillHeight = 20;
const EdgeInsets _battlePillPadding = EdgeInsets.symmetric(horizontal: 8);
const TextStyle _battlePillTextStyle = TextStyle(
  fontSize: 10,
  fontWeight: FontWeight.w600,
  height: 1,
);

class AdaptiveBattleHeader extends StatelessWidget {
  const AdaptiveBattleHeader({
    super.key,
    required this.nodeLabel,
    required this.enemyName,
    required this.enemyStyle,
    this.enemyNameIsFallback = false,
    this.nodeFontSize = 16,
    this.nodeIcon,
  });

  final String nodeLabel;
  final String enemyName;
  final TextStyle enemyStyle;
  final bool enemyNameIsFallback;
  final double nodeFontSize;
  final Widget? nodeIcon;

  @override
  Widget build(BuildContext context) {
    final nodeStyle = TextStyle(
      color: appColor(context, Color(0xffffd65c)),
      fontSize: nodeFontSize,
      fontWeight: FontWeight.w800,
    );
    final enemyTitle = enemyNameIsFallback
        ? BattleUiText(enemyName, style: appTextStyle(context, enemyStyle))
        : Text(enemyName, style: appTextStyle(context, enemyStyle));
    final node = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (nodeIcon case final icon?) ...<Widget>[
          icon,
          const SizedBox(width: 4),
        ],
        Flexible(
          child: BattleUiText(
            nodeLabel,
            style: appTextStyle(context, nodeStyle),
          ),
        ),
      ],
    );
    if (Localizations.localeOf(context).languageCode == 'en') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [node, const SizedBox(height: 3), enemyTitle],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        node,
        const SizedBox(width: 6),
        Expanded(child: enemyTitle),
      ],
    );
  }
}

/// Flat-style air state color, from best (green) to worst (red).
Color flatAirStateColor(String state) => switch (state) {
  '确保' => flatDoneColor,
  '优势' => const Color(0xff83d5c8),
  '均衡' => const Color(0xffffc95c),
  '劣势' => const Color(0xffffa05c),
  '丧失' => const Color(0xffff8c78),
  _ => flatMutedColor,
};
const Color _flatGainColor = Color(0xff83d5c8);
const Color _flatLossColor = Color(0xffff8c78);

const TextSpan flatSegmentSeparator = TextSpan(
  text: ' · ',
  style: TextStyle(color: flatMutedColor),
);

/// Flat-style replacement for the status pill row: plain text with only the
/// air state colored. The node icon carries the node type. Drops and rewards
/// live in [BattleDropLine].
class BattleTagLine extends StatelessWidget {
  const BattleTagLine({
    super.key = const Key('battle-tag-line'),
    required this.battle,
    this.metaLabels = const <String>[],
    this.extras = const <String>[],
  });

  final LiveBattle battle;
  final List<String> metaLabels;

  /// Muted trailing segments that wrap whole, such as contact planes, so a
  /// ship or plane name never splits across lines.
  final List<String> extras;

  @override
  Widget build(BuildContext context) {
    final l10n =
        AppLocalizations.of(context) ??
        lookupAppLocalizations(const Locale('zh'));
    final strings = BattleDetailStrings.of(context);
    final segments = <(String, Color)>[
      if (battle.airSuperiority != null)
        (
          l10n.airStateLabel(strings.localize(battle.airSuperiority!)),
          flatAirStateColor(battle.airSuperiority!),
        ),
      for (final label in metaLabels) (strings.localize(label), flatMutedColor),
    ];
    if (segments.isEmpty && extras.isEmpty) return const SizedBox.shrink();
    const style = TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600);
    final extraStyle = TextStyle(
      fontSize: flatAirPhaseFontSize,
      fontWeight: FontWeight.w400,
      color: appColor(context, flatMutedColor),
    );
    return Text.rich(
      appTextSpan(
        context,
        TextSpan(
          style: style,
          children: <InlineSpan>[
            for (
              var index = 0;
              index < segments.length;
              index++
            ) ...<InlineSpan>[
              if (index > 0) flatSegmentSeparator,
              TextSpan(
                text: segments[index].$1,
                style: TextStyle(color: segments[index].$2),
              ),
            ],
            for (var index = 0; index < extras.length; index++) ...<InlineSpan>[
              if (segments.isNotEmpty || index > 0) flatSegmentSeparator,
              TextSpan(text: _unbreakable(extras[index]), style: extraStyle),
            ],
          ],
        ),
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// Word joiners between characters and no-break spaces keep a segment on one
// line; CJK text may otherwise break between any two characters.
String _unbreakable(String text) => String.fromCharCodes(
  text.runes.expand((rune) => <int>[rune == 0x20 ? 0xa0 : rune, 0x2060]),
);

/// Drops and rewards split out of [BattleTagLine] so they wrap instead of
/// being cut off by its ellipsis. Carries its own top gap so an empty line
/// takes no space.
class BattleDropLine extends StatelessWidget {
  const BattleDropLine({
    super.key = const Key('battle-drop-line'),
    required this.dropEntries,
    required this.rewardItems,
  });

  final List<String> dropEntries;
  final List<BattleRewardItem> rewardItems;

  @override
  Widget build(BuildContext context) {
    if (dropEntries.isEmpty && rewardItems.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        <String>[
          ...dropEntries,
          if (rewardItems.isNotEmpty) _rewardItemsText(rewardItems),
        ].join(' · '),
        style: TextStyle(
          color: appColor(context, flatAccentColor),
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String _rewardItemsText(List<BattleRewardItem> items) =>
    items.map((item) => '${item.name} ×${item.count}').join('、');

/// What the navigation header shows after the node name. The pill row and
/// the flat text line both render this list, so they share one set of
/// visibility rules and one order.
sealed class NavigationHeaderSegment {
  const NavigationHeaderSegment();
}

final class LastFormationHeaderSegment extends NavigationHeaderSegment {
  const LastFormationHeaderSegment(this.formation);
  final int formation;
}

final class CombinedFleetHeaderSegment extends NavigationHeaderSegment {
  const CombinedFleetHeaderSegment(this.type);
  final CombinedFleetType type;
}

final class ResourceChangesHeaderSegment extends NavigationHeaderSegment {
  const ResourceChangesHeaderSegment(this.changes);
  final List<BattleResourceChange> changes;
}

final class RewardItemsHeaderSegment extends NavigationHeaderSegment {
  const RewardItemsHeaderSegment(this.items);
  final List<BattleRewardItem> items;
}

final class NodeTypeHeaderSegment extends NavigationHeaderSegment {
  const NodeTypeHeaderSegment(this.label);
  final String label;
}

List<NavigationHeaderSegment> navigationHeaderSegments(
  LiveBattle battle, {
  required bool showLastFormationHint,
}) => <NavigationHeaderSegment>[
  if (showLastFormationHint && battle.lastFormation != null)
    LastFormationHeaderSegment(battle.lastFormation!),
  if (battle.context.combinedFleetType != CombinedFleetType.none)
    CombinedFleetHeaderSegment(battle.context.combinedFleetType),
  if (battle.resourceChanges.isNotEmpty)
    ResourceChangesHeaderSegment(battle.resourceChanges),
  if (battle.rewardItems.isNotEmpty)
    RewardItemsHeaderSegment(battle.rewardItems),
  if (battle.resourceChanges.isEmpty && battle.rewardItems.isEmpty)
    for (final label in battle.context.nodeTypeLabels)
      NodeTypeHeaderSegment(label),
];

/// Pill row contents of the card-style navigation header.
List<Widget> navigationHeaderPills(
  LiveBattle battle, {
  required bool showLastFormationHint,
}) => <Widget>[
  for (final segment in navigationHeaderSegments(
    battle,
    showLastFormationHint: showLastFormationHint,
  ))
    switch (segment) {
      LastFormationHeaderSegment(:final formation) => LastFormationPill(
        formation: formation,
      ),
      CombinedFleetHeaderSegment(:final type) => MetaChip(
        label: type.label,
        color: const Color(0xff70c7bc),
      ),
      ResourceChangesHeaderSegment(:final changes) => ResourceChangesPill(
        changes: changes,
      ),
      RewardItemsHeaderSegment(:final items) => RewardItemsPill(items: items),
      NodeTypeHeaderSegment(:final label) => NodeTypePill(label: label),
    },
];

List<InlineSpan> _navigationSegmentSpans(
  BuildContext context,
  NavigationHeaderSegment segment,
) {
  final l10n =
      AppLocalizations.of(context) ??
      lookupAppLocalizations(const Locale('zh'));
  final strings = BattleDetailStrings.of(context);
  return switch (segment) {
    LastFormationHeaderSegment(:final formation) => [
      TextSpan(
        text: l10n.battleLastFormation(
          strings.localize(formationLabel(formation)),
        ),
        style: const TextStyle(color: flatMutedColor),
      ),
    ],
    CombinedFleetHeaderSegment(:final type) => [
      TextSpan(
        text: strings.localize(type.label),
        style: const TextStyle(color: flatMutedColor),
      ),
    ],
    ResourceChangesHeaderSegment(:final changes) => [
      for (var index = 0; index < changes.length; index++) ...[
        if (index > 0) const TextSpan(text: ' '),
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Image.asset(
            'assets/images/material/${changes[index].type.apiId.toString().padLeft(2, '0')}.png',
            key: Key('battle-resource-icon-${changes[index].type.apiId}'),
            width: 11,
            height: 11,
            fit: BoxFit.contain,
          ),
        ),
        TextSpan(
          text: _signed(changes[index].amount),
          style: TextStyle(
            color: changes[index].amount < 0 ? _flatLossColor : _flatGainColor,
          ),
        ),
      ],
    ],
    RewardItemsHeaderSegment(:final items) => [
      TextSpan(
        text: _rewardItemsText(items),
        style: const TextStyle(color: flatAccentColor),
      ),
    ],
    NodeTypeHeaderSegment(:final label) => [
      TextSpan(
        text: strings.localize(label),
        style: TextStyle(color: nodeTypePillColors(label).foreground),
      ),
    ],
  };
}

bool _isNavigationOutcome(NavigationHeaderSegment segment) =>
    segment is ResourceChangesHeaderSegment ||
    segment is RewardItemsHeaderSegment ||
    segment is NodeTypeHeaderSegment;

/// The navigation header's text after the node, for a header that shows the
/// node itself. The last formation is left to the formation line.
class FlatNavigationTagLine extends StatelessWidget {
  const FlatNavigationTagLine({super.key, required this.battle});

  final LiveBattle battle;

  @override
  Widget build(BuildContext context) {
    final segments = navigationHeaderSegments(
      battle,
      showLastFormationHint: false,
    );
    if (segments.isEmpty) return const SizedBox.shrink();
    final ordered = <NavigationHeaderSegment>[
      ...segments.where(_isNavigationOutcome),
      ...segments.where((segment) => !_isNavigationOutcome(segment)),
    ];
    return Text.rich(
      key: const Key('battle-navigation-tag-line'),
      appTextSpan(
        context,
        TextSpan(
          style: const TextStyle(
            fontSize: flatSmallFontSize,
            fontWeight: FontWeight.w600,
          ),
          children: <InlineSpan>[
            for (var index = 0; index < ordered.length; index++) ...[
              if (index > 0) flatSegmentSeparator,
              ..._navigationSegmentSpans(context, ordered[index]),
            ],
          ],
        ),
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class AirSuperiorityPillColors {
  const AirSuperiorityPillColors({
    required this.background,
    required this.foreground,
    required this.border,
  });

  final Color background;
  final Color foreground;
  final Color border;
}

class NodeTypePillColors {
  const NodeTypePillColors({
    required this.background,
    required this.foreground,
    required this.border,
  });

  final Color background;
  final Color foreground;
  final Color border;
}

NodeTypePillColors nodeTypePillColors(String label) {
  if (label == 'Boss 战') {
    return const NodeTypePillColors(
      background: Color(0xff2b1a17),
      foreground: Color(0xffff8c78),
      border: Color(0xffa0453a),
    );
  }
  if (label == '夜战') {
    return const NodeTypePillColors(
      background: Color(0xff302943),
      foreground: Color(0xffcbbcf6),
      border: Color(0xff6b5b91),
    );
  }
  if (const <String>{'资源获得', '运输点', '护送成功', '航空侦察', '泊地修理'}.contains(label)) {
    return const NodeTypePillColors(
      background: Color(0xff183e38),
      foreground: Color(0xff83d5c8),
      border: Color(0xff2f7469),
    );
  }
  if (const <String>{'资源损失', '起点', '无战斗', '路线选择', '节点事件'}.contains(label)) {
    return const NodeTypePillColors(
      background: Color(0xff26343e),
      foreground: Color(0xff9db2bf),
      border: Color(0xff526875),
    );
  }
  return const NodeTypePillColors(
    background: Color(0xff4a3b21),
    foreground: Color(0xffffc95c),
    border: Color(0xff8b6a2b),
  );
}

Color battlePhaseChipColor(String label) {
  if (label == '夜战') return const Color(0xffcbbcf6);
  if (label == '昼战' || label == '航空战') {
    return const Color(0xffffc95c);
  }
  return const Color(0xff9db2bf);
}

class MetaChipColors {
  const MetaChipColors({
    required this.background,
    required this.foreground,
    required this.border,
  });

  final Color background;
  final Color foreground;
  final Color border;
}

MetaChipColors metaChipColors(Color foreground) {
  if (foreground == const Color(0xffffc95c)) {
    return const MetaChipColors(
      background: Color(0xff4a3b21),
      foreground: Color(0xffffc95c),
      border: Color(0xff8b6a2b),
    );
  }
  if (foreground == const Color(0xffcbbcf6)) {
    return const MetaChipColors(
      background: Color(0xff302943),
      foreground: Color(0xffcbbcf6),
      border: Color(0xff6b5b91),
    );
  }
  if (foreground == const Color(0xff6fd3a9) ||
      foreground == const Color(0xff70c7bc)) {
    return MetaChipColors(
      background: const Color(0xff183e38),
      foreground: foreground,
      border: const Color(0xff2f7469),
    );
  }
  if (foreground == const Color(0xffff6f68)) {
    return const MetaChipColors(
      background: Color(0xff46211e),
      foreground: Color(0xffff6f68),
      border: Color(0xffa0453a),
    );
  }
  return const MetaChipColors(
    background: Color(0xff26343e),
    foreground: Color(0xff9db2bf),
    border: Color(0xff526875),
  );
}

class BattleRankBadgeColors {
  const BattleRankBadgeColors({
    required this.background,
    required this.foreground,
    required this.border,
  });

  final Color background;
  final Color foreground;
  final Color border;
}

BattleRankBadgeColors battleRankBadgeColors(BattleRank rank) {
  switch (rank) {
    case BattleRank.ss:
    case BattleRank.s:
      return const BattleRankBadgeColors(
        background: Color(0xff4a3b21),
        foreground: Color(0xffffd65c),
        border: Color(0xffd4a85f),
      );
    case BattleRank.a:
      return const BattleRankBadgeColors(
        background: Color(0xff2b1a17),
        foreground: Color(0xffff8c78),
        border: Color(0xffa0453a),
      );
    case BattleRank.b:
      return const BattleRankBadgeColors(
        background: Color(0xff183e38),
        foreground: Color(0xff83d5c8),
        border: Color(0xff2f7469),
      );
    case BattleRank.c:
    case BattleRank.d:
    case BattleRank.e:
    case BattleRank.unknown:
      return const BattleRankBadgeColors(
        background: Color(0xff26343e),
        foreground: Color(0xff9db2bf),
        border: Color(0xff526875),
      );
  }
}

/// Air-control state colors: ensure/advantage green, disadvantage/loss red,
/// balance/unknown yellow.
AirSuperiorityPillColors airSuperiorityPillColors(String label) {
  switch (label) {
    case '确保':
    case '优势':
      return const AirSuperiorityPillColors(
        background: Color(0xff183e38),
        foreground: Color(0xff83d5c8),
        border: Color(0xff2f7469),
      );
    case '劣势':
    case '丧失':
      return const AirSuperiorityPillColors(
        background: Color(0xff46211e),
        foreground: Color(0xffff8c78),
        border: Color(0xffa0453a),
      );
    default:
      return const AirSuperiorityPillColors(
        background: Color(0xff4a3b21),
        foreground: Color(0xffffc95c),
        border: Color(0xff8b6a2b),
      );
  }
}

class AirSuperiorityPill extends StatelessWidget {
  const AirSuperiorityPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = airSuperiorityPillColors(label);
    final english = Localizations.localeOf(context).languageCode == 'en';
    return Container(
      key: const Key('air-superiority-pill'),
      height: english ? null : _battlePillHeight,
      constraints: english
          ? const BoxConstraints(minHeight: _battlePillHeight)
          : null,
      padding: english
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
          : _battlePillPadding,
      decoration: BoxDecoration(
        color: appColor(context, colors.background),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: appColor(context, colors.border)),
      ),
      child: Align(
        widthFactor: 1,
        child: Text(
          (AppLocalizations.of(context) ??
                  lookupAppLocalizations(const Locale('zh')))
              .airStateLabel(BattleDetailStrings.of(context).localize(label)),
          textAlign: english ? TextAlign.center : null,
          style: appTextStyle(
            context,
            _battlePillTextStyle.copyWith(color: colors.foreground),
          ),
        ),
      ),
    );
  }
}

class NodeTypePill extends StatelessWidget {
  const NodeTypePill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = nodeTypePillColors(label);
    return Container(
      key: const Key('node-type-pill'),
      height: _battlePillHeight,
      padding: _battlePillPadding,
      decoration: BoxDecoration(
        color: appColor(context, colors.background),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: appColor(context, colors.border)),
      ),
      child: Align(
        widthFactor: 1,
        child: BattleUiText(
          label,
          style: appTextStyle(
            context,
            _battlePillTextStyle.copyWith(color: colors.foreground),
          ),
        ),
      ),
    );
  }
}

class DropPill extends StatelessWidget {
  const DropPill({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('battle-drop-pill'),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 1),
      decoration: BoxDecoration(
        color: appColor(context, const Color(0xff183e38)),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: appColor(context, const Color(0xff2f7469))),
      ),
      child: Text(
        text,
        style: appTextStyle(
          context,
          TextStyle(
            color: appColor(context, Color(0xff83d5c8)),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class ResourceChangesPill extends StatelessWidget {
  const ResourceChangesPill({super.key, required this.changes});

  final List<BattleResourceChange> changes;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('battle-resource-changes-pill'),
      height: _battlePillHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: appColor(context, const Color(0xff183e38)),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: appColor(context, const Color(0xff2f7469))),
      ),
      child: SingleChildScrollView(
        key: const PageStorageKey('battle-resource-changes-scroll'),
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var index = 0; index < changes.length; index++) ...<Widget>[
              if (index > 0)
                Container(
                  width: 1,
                  height: 10,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  color: appColor(context, const Color(0x4d83d5c8)),
                ),
              Image.asset(
                'assets/images/material/${changes[index].type.apiId.toString().padLeft(2, '0')}.png',
                key: Key('battle-resource-icon-${changes[index].type.apiId}'),
                width: 15,
                height: 15,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 2),
              Text(
                _signed(changes[index].amount),
                style: appTextStyle(
                  context,
                  _battlePillTextStyle.copyWith(
                    color: changes[index].amount < 0
                        ? const Color(0xffff8c78)
                        : const Color(0xff83d5c8),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class RewardItemsPill extends StatelessWidget {
  const RewardItemsPill({super.key, required this.items});

  final List<BattleRewardItem> items;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Container(
        key: const Key('battle-reward-items-pill'),
        constraints: const BoxConstraints(minHeight: _battlePillHeight),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: appColor(context, const Color(0xff183e38)),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: appColor(context, Color(0xff2f7469))),
        ),
        child: SingleChildScrollView(
          // Keep the offset separate from LiveBattleCard's saved panel mode.
          key: const PageStorageKey('battle-reward-items-scroll'),
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var index = 0; index < items.length; index++) ...<Widget>[
                if (index > 0)
                  Container(
                    width: 1,
                    height: 10,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    color: appColor(context, Color(0x4d83d5c8)),
                  ),
                Text(
                  '${items[index].name} ×${items[index].count}',
                  style: appTextStyle(
                    context,
                    _battlePillTextStyle.copyWith(
                      color: const Color(0xff83d5c8),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _signed(int value) => value > 0 ? '+$value' : '$value';

class MetaChip extends StatelessWidget {
  const MetaChip({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = metaChipColors(color);
    return Container(
      height: _battlePillHeight,
      padding: _battlePillPadding,
      decoration: BoxDecoration(
        color: appColor(context, colors.background),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: appColor(context, colors.border)),
      ),
      child: Align(
        widthFactor: 1,
        child: BattleUiText(
          label,
          style: appTextStyle(
            context,
            _battlePillTextStyle.copyWith(color: colors.foreground),
          ),
        ),
      ),
    );
  }
}

class LastFormationPill extends StatelessWidget {
  const LastFormationPill({super.key, required this.formation});

  final int formation;

  @override
  Widget build(BuildContext context) {
    final l10n =
        AppLocalizations.of(context) ??
        lookupAppLocalizations(const Locale('zh'));
    return MetaChip(
      key: const Key('battle-last-formation-pill'),
      label: l10n.battleLastFormation(
        BattleDetailStrings.of(context).localize(formationLabel(formation)),
      ),
      color: const Color(0xffffc95c),
    );
  }
}

class BattleRankBadge extends StatelessWidget {
  const BattleRankBadge({
    super.key,
    required this.rank,
    this.size = 50,
    this.fontSize = 21,
  });

  final BattleRank rank;
  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final colors = battleRankBadgeColors(rank);
    return Container(
      key: const Key('battle-rank-badge'),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: appColor(context, colors.background),
        // Full-size badges keep 9; small ones round less so they stay square.
        borderRadius: BorderRadius.circular(math.min(9, size * .3)),
        border: Border.all(color: appColor(context, colors.border)),
      ),
      child: Text(
        rank.label,
        style: appTextStyle(
          context,
          TextStyle(
            color: colors.foreground,
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

String formationLabel(int value) =>
    const <int, String>{
      1: '单纵阵',
      2: '复纵阵',
      3: '轮形阵',
      4: '梯形阵',
      5: '单横阵',
      6: '警戒阵',
      11: '第一警戒',
      12: '第二警戒',
      13: '第三警戒',
      14: '第四警戒',
    }[value] ??
    '阵型 $value';

String engagementLabel(int value) =>
    const <int, String>{1: '同航战', 2: '反航战', 3: 'T 字有利', 4: 'T 字不利'}[value] ??
    '航向 $value';
