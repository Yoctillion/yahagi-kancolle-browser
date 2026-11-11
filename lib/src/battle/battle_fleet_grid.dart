import '../theme/app_palette.dart';
import '../localization/game_name_localizations.dart';
import 'package:flutter/material.dart';

import 'battle_detail_strings.dart';
import 'battle_ui_text.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';

import 'battle_models.dart';
import 'battle_pills.dart';
import 'battle_ship_details_popover.dart';
import '../fleet/ship_status_style.dart';
import '../fleet/ship_status_visuals.dart';
import '../layout/flat_style.dart';
import '../layout/panel_style.dart';
import '../settings/battle_status_effect_settings.dart';
import 'prophet_hp_bar.dart';

/// Official enemy preview names, one per row at the height of a
/// [_CompactBarRow], so they line up with the friendly HP bars beside them.
class _PreviewNameColumn extends StatelessWidget {
  const _PreviewNameColumn({required this.keyName, required this.ships});

  final String keyName;
  final List<EnemyPreviewShip> ships;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: Key('compact-fleet-col-$keyName'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < ships.length; index++)
          Padding(
            key: Key('compact-preview-$keyName-$index'),
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  gameNames(
                    context,
                  ).shipName(ships[index].name, shipId: ships[index].masterId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: appTextStyle(
                    context,
                    const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                ),
                // The bar row's gap and bar, kept empty.
                const SizedBox(height: 2 + _flatBarHeight),
              ],
            ),
          ),
      ],
    );
  }
}

const double _flatBarHeight = 4;

/// Pre-battle HP as a faint bar behind the current one; null when nothing was
/// lost (a damage-control revive can leave current HP above the pre-battle
/// value) or the ship is escaped.
({double? value, Color? color}) battleHpGhost(BattleShipSnapshot ship) {
  if (ship.isEscaped || ship.maxHp <= 0) return (value: null, color: null);
  final pre = ship.initialHp.clamp(0, ship.maxHp) / ship.maxHp;
  return (value: pre, color: shipHpBarColor(pre, isZeroHp: false));
}

class BattleFleetGrid extends StatelessWidget {
  const BattleFleetGrid({
    super.key,
    required this.battle,
    required this.damagePulseMode,
    this.lastFormation,
    this.showShipNames = false,
  });

  final LiveBattle battle;
  final DamagePulseFilter damagePulseMode;

  /// While navigating, the formation remembered for this node.
  final int? lastFormation;

  /// Puts each ship's name above its bar, in the height the nameless row
  /// already has, so the enemy preview names still line up.
  final bool showShipNames;

  bool get _navigation => battle.displayStage == BattleDisplayStage.navigation;

  List<Widget> _previewColumns() {
    final ships = battle.enemyPreviewShips ?? const <EnemyPreviewShip>[];
    if (ships.isEmpty) return const <Widget>[];
    if (!battle.enemyPreviewCombined) {
      return <Widget>[_PreviewNameColumn(keyName: 'enemy', ships: ships)];
    }
    return <Widget>[
      _PreviewNameColumn(
        keyName: 'enemy-escort',
        ships: [
          for (final ship in ships)
            if (ship.fleetRole == BattleFleetRole.escort) ship,
        ],
      ),
      _PreviewNameColumn(
        keyName: 'enemy-main',
        ships: [
          for (final ship in ships)
            if (ship.fleetRole == BattleFleetRole.main) ship,
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final flat = PanelStyleScope.isFlat(context);
    final friendCombined = battle.friendEscort.isNotEmpty;
    final enemyCombined = battle.enemyEscort.isNotEmpty;
    final mvpPositions = battle.mvpPositions;
    final navigation = _navigation;
    final friendFormation = battle.friendFormation > 0
        ? '（${formationLabel(battle.friendFormation)}）'
        : '';
    final enemyFormation = battle.enemyFormation > 0
        ? '（${formationLabel(battle.enemyFormation)}）'
        : '';
    final friendColumns = <Widget>[];
    final enemyColumns = <Widget>[];
    if (friendCombined) {
      friendColumns.add(
        _CompactFleetColumn(
          keyName: 'friend-main',
          ships: battle.friendMain,
          mvpPositions: mvpPositions,
          damagePulseMode: damagePulseMode,
          showShipNames: showShipNames,
        ),
      );
      friendColumns.add(
        _CompactFleetColumn(
          keyName: 'friend-escort',
          ships: battle.friendEscort,
          mvpPositions: mvpPositions,
          positionOffset: 6,
          damagePulseMode: damagePulseMode,
          showShipNames: showShipNames,
        ),
      );
    } else {
      friendColumns.add(
        _CompactFleetColumn(
          keyName: 'friend',
          ships: battle.friendMain,
          mvpPositions: mvpPositions,
          damagePulseMode: damagePulseMode,
          showShipNames: showShipNames,
        ),
      );
    }
    if (navigation) {
      enemyColumns.addAll(_previewColumns());
    } else if (enemyCombined) {
      enemyColumns.add(
        _CompactFleetColumn(
          keyName: 'enemy-escort',
          ships: battle.enemyEscort,
          mvpPositions: const <int>[],
          positionOffset: 6,
          damagePulseMode: damagePulseMode,
          showShipNames: showShipNames,
        ),
      );
      enemyColumns.add(
        _CompactFleetColumn(
          keyName: 'enemy-main',
          ships: battle.enemyMain,
          mvpPositions: const <int>[],
          damagePulseMode: damagePulseMode,
          showShipNames: showShipNames,
        ),
      );
    } else {
      enemyColumns.add(
        _CompactFleetColumn(
          keyName: 'enemy',
          ships: battle.enemyMain,
          mvpPositions: const <int>[],
          damagePulseMode: damagePulseMode,
          showShipNames: showShipNames,
        ),
      );
    }
    Widget side(
      String keyName,
      String title,
      Color color,
      List<Widget> columns,
    ) => Expanded(
      // An unknown enemy still holds its half, so the grid does not shift
      // when the battle fills it in.
      flex: columns.isEmpty ? 1 : columns.length,
      child: Container(
        padding: flat ? EdgeInsets.zero : const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: flat
            ? null
            : BoxDecoration(
                color: appColor(context, const Color(0xff10212e)),
                borderRadius: BorderRadius.circular(8),
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (!flat) ...<Widget>[
              _CompactFleetSideTitle(
                keyName: keyName,
                title: title,
                color: appColor(context, color),
              ),
              const SizedBox(height: 4),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (
                  var index = 0;
                  index < columns.length;
                  index++
                ) ...<Widget>[
                  if (index > 0) const SizedBox(width: 7),
                  Expanded(child: columns[index]),
                ],
              ],
            ),
          ],
        ),
      ),
    );
    final grid = Row(
      key: const Key('compact-fleet-grid'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        side(
          'friend',
          '我方舰队$friendFormation',
          const Color(0xff70c7bc),
          friendColumns,
        ),
        SizedBox(width: flat ? 6 : 7),
        side(
          'enemy',
          '敌方舰队$enemyFormation',
          const Color(0xffff8c78),
          enemyColumns,
        ),
      ],
    );
    if (!flat) return grid;
    final strings = BattleDetailStrings.of(context);
    final l10n =
        AppLocalizations.of(context) ??
        lookupAppLocalizations(const Locale('zh'));
    final formationLine = navigation
        ? _FlatFormationLine(
            key: const Key('compact-formation-line'),
            friend: lastFormation == null
                ? null
                : l10n.battleLastFormation(
                    strings.localize(formationLabel(lastFormation!)),
                  ),
            engagement: null,
            enemy: enemyColumns.isEmpty ? null : l10n.battleSectionEnemyPreview,
          )
        : _FlatFormationLine(
            key: const Key('compact-formation-line'),
            friend: battle.friendFormation > 0
                ? strings.localize(formationLabel(battle.friendFormation))
                : null,
            engagement: battle.engagement > 0
                ? strings.localize(engagementLabel(battle.engagement))
                : null,
            enemy: battle.enemyFormation > 0
                ? strings.localize(formationLabel(battle.enemyFormation))
                : null,
          );
    if (formationLine.isEmpty) return grid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[formationLine, const SizedBox(height: 2), grid],
    );
  }
}

/// Replaces the two flat side titles: friend formation, engagement and enemy
/// formation in one line, falling back to centered wrapping text rather than
/// truncating any of them.
class _FlatFormationLine extends StatelessWidget {
  const _FlatFormationLine({
    super.key,
    required this.friend,
    required this.engagement,
    required this.enemy,
  });

  final String? friend;
  final String? engagement;
  final String? enemy;

  bool get isEmpty => friend == null && engagement == null && enemy == null;

  static const double _gap = 8;
  static const TextStyle _baseStyle = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle _friendStyle = TextStyle(color: Color(0xff70c7bc));
  static const TextStyle _engagementStyle = TextStyle(color: Color(0xffdfe8ee));
  static const TextStyle _enemyStyle = TextStyle(color: Color(0xffff8c78));

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);
    final textDirection = Directionality.of(context);
    final measureStyle = DefaultTextStyle.of(context).style.merge(_baseStyle);
    double widthOf(String? text) {
      if (text == null) return 0;
      final painter = TextPainter(
        text: TextSpan(text: text, style: measureStyle),
        textDirection: textDirection,
        textScaler: textScaler,
        locale: locale,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    Widget label(String? text, TextStyle style) => text == null
        ? const SizedBox.shrink()
        : Text(text, maxLines: 1, style: _baseStyle.merge(style));

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final friendWidth = widthOf(friend);
        final enemyWidth = widthOf(enemy);
        if (engagement != null) {
          // Equal side slots keep the engagement centered on the line even
          // when one formation is missing or the two differ in width.
          final side = (maxWidth - widthOf(engagement)) / 2 - _gap;
          if (friendWidth <= side && enemyWidth <= side) {
            return Row(
              children: <Widget>[
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: label(friend, _friendStyle),
                  ),
                ),
                const SizedBox(width: _gap),
                label(engagement, _engagementStyle),
                const SizedBox(width: _gap),
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: label(enemy, _enemyStyle),
                  ),
                ),
              ],
            );
          }
        } else if (friendWidth + _gap + enemyWidth <= maxWidth) {
          return Row(
            children: <Widget>[
              label(friend, _friendStyle),
              const Spacer(),
              label(enemy, _enemyStyle),
            ],
          );
        }
        final segments = <(String, TextStyle)>[
          if (friend != null) (friend!, _friendStyle),
          if (engagement != null) (engagement!, _engagementStyle),
          if (enemy != null) (enemy!, _enemyStyle),
        ];
        return Text.rich(
          appTextSpan(
            context,
            TextSpan(
              style: _baseStyle,
              children: <InlineSpan>[
                for (var index = 0; index < segments.length; index++) ...[
                  if (index > 0) flatSegmentSeparator,
                  TextSpan(text: segments[index].$1, style: segments[index].$2),
                ],
              ],
            ),
          ),
          textAlign: TextAlign.center,
        );
      },
    );
  }
}

class _CompactFleetSideTitle extends StatelessWidget {
  const _CompactFleetSideTitle({
    required this.keyName,
    required this.title,
    required this.color,
  });

  final String keyName;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: Key('compact-fleet-side-title-$keyName'),
      height: 14,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: BattleUiText(
          title,
          maxLines: 1,
          softWrap: false,
          style: appTextStyle(
            context,
            TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

class _CompactFleetColumn extends StatelessWidget {
  const _CompactFleetColumn({
    required this.keyName,
    required this.ships,
    required this.mvpPositions,
    required this.damagePulseMode,
    required this.showShipNames,
    this.positionOffset = 0,
  });

  final String keyName;
  final List<BattleShipSnapshot> ships;
  final List<int> mvpPositions;
  final DamagePulseFilter damagePulseMode;
  final bool showShipNames;
  final int positionOffset;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: Key('compact-fleet-col-$keyName'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < ships.length; index++)
          BattleShipDetailsTap(
            ship: ships[index],
            child: _CompactBarRow(
              ship: ships[index],
              keyName: keyName,
              index: index,
              isMvp: mvpPositions.contains(index + positionOffset),
              damagePulseMode: damagePulseMode,
              showShipNames: showShipNames,
            ),
          ),
      ],
    );
  }
}

class _CompactBarRow extends StatelessWidget {
  const _CompactBarRow({
    required this.ship,
    required this.keyName,
    required this.index,
    required this.isMvp,
    required this.damagePulseMode,
    required this.showShipNames,
  });

  final BattleShipSnapshot ship;
  final String keyName;
  final int index;
  final bool isMvp;
  final DamagePulseFilter damagePulseMode;
  final bool showShipNames;

  @override
  Widget build(BuildContext context) {
    final flat = PanelStyleScope.isFlat(context);
    final isEscaped = ship.isEscaped;
    final ratio = ship.maxHp <= 0
        ? 0.0
        : (ship.currentHp / ship.maxHp).clamp(0.0, 1.0);
    final isZeroHp = ship.currentHp <= 0;
    final hpValueColor = isEscaped
        ? yahagiStatusZeroHp
        : shipHpValueColor(ratio, isZeroHp: isZeroHp);
    final hpBarColor = isEscaped
        ? yahagiStatusZeroHp
        : shipHpBarColor(ratio, isZeroHp: isZeroHp);
    final hpText = isEscaped
        ? '${ship.currentHp} / ${ship.maxHp} (退避)'
        : '${ship.currentHp} / ${ship.maxHp}';
    final ghost = battleHpGhost(ship);
    final shipName = gameNames(
      context,
    ).shipName(ship.name, shipId: ship.masterId);
    final mvpIcon = Icon(
      Icons.emoji_events_rounded,
      key: Key('compact-mvp-$keyName-$index'),
      size: 9,
      color: appColor(context, Color(0xffffd65c)),
    );
    Widget nameLine(Widget trailing) => Row(
      key: Key('compact-name-$keyName-$index'),
      children: <Widget>[
        Flexible(
          child: Text(
            shipName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: appTextStyle(
              context,
              TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isEscaped ? const Color(0xff8197a5) : null,
              ),
            ),
          ),
        ),
        if (isMvp) ...<Widget>[const SizedBox(width: 2), mvpIcon],
        const Spacer(),
        const SizedBox(width: 3),
        trailing,
      ],
    );

    Widget hpContent({double opacity = 1, bool pulsing = false}) {
      if (isEscaped && showShipNames) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            nameLine(
              BattleUiText(
                '退避',
                style: appTextStyle(
                  context,
                  const TextStyle(
                    color: Color(0xff8197a5),
                    fontSize: flatNamedHpFontSize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2 + _flatBarHeight),
          ],
        );
      }
      if (isEscaped) {
        return Align(
          alignment: Alignment.centerLeft,
          child: BattleUiText(
            '退避',
            style: appTextStyle(
              context,
              TextStyle(
                color: Color(0xff8197a5),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
      final hpNumber = Opacity(
        key: pulsing ? Key('compact-damage-hp-number-$keyName-$index') : null,
        opacity: opacity,
        child: Text(
          hpText,
          style: appTextStyle(
            context,
            TextStyle(
              color: hpValueColor,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
      final hpBar = Opacity(
        key: pulsing ? Key('compact-damage-hp-bar-$keyName-$index') : null,
        opacity: opacity,
        child: ProphetHpBar(
          value: ratio,
          color: appColor(context, hpBarColor),
          backgroundColor: appColor(context, const Color(0xff263e4d)),
          height: flat ? _flatBarHeight : 6,
          ghostValue: ghost.value,
          ghostColor: ghost.color == null
              ? null
              : appColor(context, ghost.color!),
        ),
      );
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (showShipNames)
            nameLine(
              Opacity(
                key: pulsing
                    ? Key('compact-damage-hp-number-$keyName-$index')
                    : null,
                opacity: opacity,
                child: Text(
                  hpText,
                  style: appTextStyle(
                    context,
                    TextStyle(
                      color: hpValueColor,
                      fontSize: flatNamedHpFontSize,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            )
          else
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  hpNumber,
                  if (isMvp) ...<Widget>[const SizedBox(width: 2), mvpIcon],
                ],
              ),
            ),
          const SizedBox(height: 2),
          hpBar,
        ],
      );
      return pulsing
          ? KeyedSubtree(
              key: Key('compact-damage-hp-pulse-$keyName-$index'),
              child: content,
            )
          : content;
    }

    final shouldPulse =
        !isEscaped &&
        ship.currentHp > 0 &&
        ship.maxHp > 0 &&
        ship.currentHp * 4 <= ship.maxHp * 3;
    return Padding(
      key: Key('compact-bar-$keyName-$index'),
      padding: flat
          ? const EdgeInsets.symmetric(vertical: 1)
          : const EdgeInsets.fromLTRB(6, 3, 6, 3),
      child: shouldPulse
          ? DamagePulseBuilder(
              currentHp: ship.currentHp,
              maxHp: ship.maxHp,
              filter: damagePulseMode,
              normalColor: hpBarColor,
              builder: (context, spec, phase) => hpContent(
                opacity:
                    spec.minFrameOpacity + phase * (1 - spec.minFrameOpacity),
                pulsing: true,
              ),
            )
          : hpContent(),
    );
  }
}
