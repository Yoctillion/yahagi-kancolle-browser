import 'package:flutter/material.dart';

import '../layout/flat_style.dart';
import '../theme/app_palette.dart';
import 'battle_pills.dart';
import 'battle_models.dart';

/// Flat battle and navigation header: node icon, node letter, enemy fleet
/// name and the sortie map toggle on one row; the expanded map under it; then
/// the detail lines with a small result badge beside them.
class FlatBattleHeader extends StatelessWidget {
  const FlatBattleHeader({
    super.key = const Key('flat-battle-header'),
    required this.nodeIcon,
    required this.nodeLabel,
    this.enemyName,
    this.enemyNameColor,
    this.mapToggle,
    this.mapBody,
    this.details = const <Widget>[],
    this.rank,
  });

  final Widget nodeIcon;
  final String nodeLabel;
  final String? enemyName;
  final Color? enemyNameColor;
  final Widget? mapToggle;
  final Widget? mapBody;
  final List<Widget> details;
  final BattleRank? rank;

  static const double rankBadgeSize = 22;

  @override
  Widget build(BuildContext context) {
    final name = enemyName;
    final titleRow = LayoutBuilder(
      builder: (context, constraints) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(padding: const EdgeInsets.only(top: 1), child: nodeIcon),
          const SizedBox(width: 4),
          // Usually a letter, but an unresolved node reads "Node 12" and some
          // languages run longer; it never takes more than half the row.
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth / 2),
            child: Text(
              nodeLabel,
              key: const Key('flat-battle-header-node'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: appTextStyle(
                context,
                const TextStyle(
                  color: Color(0xffffd65c),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: name == null || name.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    // Centers a shrunken single line on the 12px node letter.
                    padding: const EdgeInsets.only(top: 1),
                    child: FittedEnemyName(
                      name: name,
                      color: appColor(context, enemyNameColor),
                    ),
                  ),
          ),
          ?mapToggle,
        ],
      ),
    );
    final rankValue = rank;
    final hasDetails = details.isNotEmpty || rankValue != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        titleRow,
        ?mapBody,
        if (hasDetails)
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: details,
                ),
              ),
              if (rankValue != null) ...<Widget>[
                const SizedBox(width: 6),
                BattleRankBadge(
                  key: const Key('flat-battle-header-rank'),
                  rank: rankValue,
                  size: rankBadgeSize,
                  fontSize: 10,
                ),
              ],
            ],
          ),
      ],
    );
  }
}

/// An enemy fleet name that shrinks from [maxFontSize] down to [minFontSize]
/// to stay on one line, and wraps only when even the smallest size overflows.
class FittedEnemyName extends StatelessWidget {
  const FittedEnemyName({
    super.key = const Key('flat-battle-header-enemy'),
    required this.name,
    this.color,
    this.maxFontSize = 11,
    this.minFontSize = 9.5,
  });

  final String name;
  final Color? color;
  final double maxFontSize;
  final double minFontSize;

  TextStyle _style(double fontSize) => TextStyle(
    color: color,
    fontSize: fontSize,
    fontWeight: FontWeight.w600,
    height: 1.15,
  );

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    final textScaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);
    final textDirection = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        double widthAt(double fontSize) {
          final painter = TextPainter(
            text: TextSpan(text: name, style: base.merge(_style(fontSize))),
            textDirection: textDirection,
            textScaler: textScaler,
            locale: locale,
            maxLines: 1,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        }

        final available = constraints.maxWidth;
        var fontSize = maxFontSize;
        final natural = widthAt(maxFontSize);
        if (natural > available) {
          // Text width scales close to linearly with font size; round down in
          // tenths and confirm so the chosen size really fits.
          fontSize =
              (maxFontSize * available / natural * 10).floorToDouble() / 10;
          while (fontSize >= minFontSize && widthAt(fontSize) > available) {
            fontSize -= .1;
          }
        }
        final singleLine = fontSize >= minFontSize;
        return Text(
          name,
          maxLines: singleLine ? 1 : 2,
          softWrap: !singleLine,
          overflow: TextOverflow.ellipsis,
          style: appTextStyle(
            context,
            _style(singleLine ? fontSize : minFontSize),
          ),
        );
      },
    );
  }
}

/// Colors of a header enemy name: the confirmed name in the default color (or
/// [combinedColor] for a combined fleet), a remembered guess muted.
Color? flatEnemyNameColor({required bool guessed, required bool combined}) {
  if (guessed) return flatMutedColor;
  return combined ? const Color(0xffff8c78) : null;
}
