import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../game_state/game_state_controller.dart';
import '../layout/flat_empty_text.dart';
import '../layout/flat_style.dart';
import '../layout/panel_style.dart';
import '../localization/game_name_localizations.dart';
import '../theme/app_palette.dart';
import 'practice_exp.dart';
import 'practice_opponent_controller.dart';

String practiceRankName(AppLocalizations l10n, int rankId) => switch (rankId) {
  1 => l10n.practiceRank1,
  2 => l10n.practiceRank2,
  3 => l10n.practiceRank3,
  4 => l10n.practiceRank4,
  5 => l10n.practiceRank5,
  6 => l10n.practiceRank6,
  7 => l10n.practiceRank7,
  8 => l10n.practiceRank8,
  9 => l10n.practiceRank9,
  10 => l10n.practiceRank10,
  _ => '',
};

const _resultLetters = ['', 'E', 'D', 'C', 'B', 'A', 'S'];

/// Opponent list from the exercise screen, or the opened opponent's fleet with
/// the exp we would earn (layout follows KC3's PvP activity box).
class PracticeOpponentPanel extends StatelessWidget {
  const PracticeOpponentPanel({
    super.key,
    required this.controller,
    required this.gameStateController,
  });

  final PracticeOpponentController controller;
  final GameStateController gameStateController;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([controller, gameStateController]),
    builder: (context, _) {
      final l10n =
          AppLocalizations.of(context) ??
          lookupAppLocalizations(const Locale('zh'));
      final selected = controller.selected;
      if (controller.view == PracticeView.detail && selected != null) {
        return _detail(context, l10n, selected);
      }
      if (controller.opponents.isEmpty) {
        return PanelStyleScope.isFlat(context)
            ? FlatEmptyText(l10n.practicePanelEmpty)
            : Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: _text(context, l10n.practicePanelEmpty, muted: true),
              );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final opponent in controller.opponents)
            _row(
              context,
              key: Key('practice-opponent-${opponent.memberId}'),
              name: opponent.name,
              details: [
                'Lv.${opponent.level}',
                practiceRankName(l10n, opponent.rankId),
              ],
              trailing: opponent.result > 0 && opponent.result < 7
                  ? _resultLetters[opponent.result]
                  : l10n.practiceNotFought,
              trailingMuted: opponent.result <= 0,
            ),
        ],
      );
    },
  );

  Widget _detail(
    BuildContext context,
    AppLocalizations l10n,
    PracticeOpponentFleet fleet,
  ) {
    final state = gameStateController.state;
    final names = gameNames(context);
    final ships = fleet.ships;
    final baseExp = ships.isEmpty
        ? 0
        : practiceBaseExp(
            ships[0].level,
            ships.length > 1 ? ships[1].level : 0,
          );
    final bonus = practiceCtBonus(state);
    int rankExp(PracticeRank rank) => practiceRankExp(baseExp, rank, bonus);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row(
          context,
          name: fleet.name,
          details: ['Lv.${fleet.level}', practiceRankName(l10n, fleet.rankId)],
          trailing: fleet.deckName,
          trailingMuted: true,
          emphasized: true,
        ),
        for (var i = 0; i < ships.length; i++)
          _row(
            context,
            key: Key('practice-ship-$i'),
            name: switch (state.masterShips[ships[i].masterId]) {
              final master? => names.shipName(
                master.name,
                shipId: ships[i].masterId,
              ),
              null => '#${ships[i].masterId}',
            },
            details: const [],
            trailing: 'Lv.${ships[i].level}',
          ),
        if (baseExp > 0)
          Padding(
            padding: EdgeInsets.only(
              top: PanelStyleScope.isFlat(context) ? flatSectionGap : 6,
            ),
            child: Tooltip(
              triggerMode: TooltipTriggerMode.tap,
              message:
                  'A/B ${rankExp(PracticeRank.a)} · C ${rankExp(PracticeRank.c)}'
                  ' · D ${rankExp(PracticeRank.d)} · E ${rankExp(PracticeRank.e)}',
              child: _text(
                context,
                l10n.practiceBaseExpS(rankExp(PracticeRank.s)),
                key: const Key('practice-exp-s'),
                accent: true,
              ),
            ),
          ),
      ],
    );
  }

  Widget _row(
    BuildContext context, {
    Key? key,
    required String name,
    required List<String> details,
    required String trailing,
    bool trailingMuted = false,
    bool emphasized = false,
  }) {
    final flat = PanelStyleScope.isFlat(context);
    return Padding(
      key: key,
      padding: EdgeInsets.symmetric(vertical: flat ? flatRowSpacing / 2 : 2),
      child: Row(
        children: [
          Expanded(child: _text(context, name, bold: emphasized)),
          for (final detail in details)
            if (detail.isNotEmpty) ...[
              const SizedBox(width: 6),
              _text(context, detail, muted: true),
            ],
          if (trailing.isNotEmpty) ...[
            const SizedBox(width: 6),
            _text(context, trailing, muted: trailingMuted),
          ],
        ],
      ),
    );
  }

  Widget _text(
    BuildContext context,
    String text, {
    Key? key,
    bool muted = false,
    bool accent = false,
    bool bold = false,
  }) {
    final flat = PanelStyleScope.isFlat(context);
    final color = accent
        ? flatAccentColor
        : muted
        ? flatMutedColor
        : Colors.white;
    return Text(
      text,
      key: key,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: appColor(context, color),
        fontSize: flat ? flatRowFontSize : 12.5,
        fontWeight: bold || accent ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }
}
