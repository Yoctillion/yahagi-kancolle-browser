import '../localization/game_name_localizations.dart';
import 'package:flutter/material.dart';

import '../fleet/ship_portrait.dart';
import '../game_state/game_state.dart';
import '../layout/panel_style.dart';
import 'battle_models.dart';

class OfficialEnemyPreview extends StatelessWidget {
  const OfficialEnemyPreview({
    super.key,
    required this.ships,
    this.combined = false,
    this.showPortraits = false,
    this.masterShips = const <int, MasterShip>{},
    this.serverOrigin = '',
  });

  final List<EnemyPreviewShip> ships;
  final bool combined;
  final bool showPortraits;
  final Map<int, MasterShip> masterShips;
  final String serverOrigin;

  @override
  Widget build(BuildContext context) {
    final escortShips = ships
        .where((ship) => ship.fleetRole == BattleFleetRole.escort)
        .toList();
    final mainShips = ships
        .where((ship) => ship.fleetRole == BattleFleetRole.main)
        .toList();
    final flat = PanelStyleScope.of(context) == PanelStyle.flat;
    final divider = Divider(
      height: 1,
      color: flat ? const Color(0xff1b3142) : const Color(0xff203746),
    );
    const cardRowPadding = EdgeInsets.symmetric(horizontal: 9, vertical: 4);
    const flatRowPadding = EdgeInsets.symmetric(vertical: 2);
    return Container(
      key: const Key('official-enemy-preview'),
      decoration: flat
          ? null
          : BoxDecoration(
              color: const Color(0xff10212e),
              borderRadius: BorderRadius.circular(8),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: flat
                ? const EdgeInsets.fromLTRB(0, 2, 0, 2)
                : const EdgeInsets.fromLTRB(9, 7, 9, 5),
            child: const Text(
              '敌方部队（战前预测）',
              key: Key('official-enemy-preview-title'),
              style: TextStyle(
                color: Color(0xffff8c78),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (!combined)
            for (var index = 0; index < ships.length; index++) ...<Widget>[
              if (index > 0) divider,
              _nameCell(
                context,
                ships[index],
                index: index,
                portraitWidth: 52,
                portraitHeight: 24,
                padding: flat ? flatRowPadding : cardRowPadding,
                key: Key('official-enemy-preview-row-$index'),
              ),
            ]
          else
            for (var index = 0; index < 3; index++) ...<Widget>[
              if (index > 0) divider,
              Row(
                key: Key('official-enemy-preview-row-$index'),
                children: <Widget>[
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(
                            color: flat
                                ? const Color(0xff1b3142)
                                : const Color(0xff203746),
                          ),
                        ),
                      ),
                      child: _nameCell(
                        context,
                        _shipAt(escortShips, index),
                        index: index,
                        portraitWidth: 52,
                        portraitHeight: 24,
                        // Without a block edge the column divider is the only
                        // separator, so keep text off it.
                        padding: flat
                            ? flatRowPadding.copyWith(right: 6)
                            : cardRowPadding,
                        key: Key('official-enemy-preview-escort-$index'),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _nameCell(
                      context,
                      _shipAt(mainShips, index),
                      index: index + 3,
                      portraitWidth: 52,
                      portraitHeight: 24,
                      padding: flat
                          ? flatRowPadding.copyWith(left: 6)
                          : cardRowPadding,
                      key: Key('official-enemy-preview-main-$index'),
                    ),
                  ),
                ],
              ),
            ],
        ],
      ),
    );
  }

  EnemyPreviewShip? _shipAt(List<EnemyPreviewShip> fleet, int index) =>
      index < fleet.length ? fleet[index] : null;

  Widget _nameCell(
    BuildContext context,
    EnemyPreviewShip? preview, {
    required int index,
    required double portraitWidth,
    required double portraitHeight,
    required EdgeInsets padding,
    required Key key,
  }) {
    final name = preview == null
        ? ''
        : gameNames(context).shipName(preview.name, shipId: preview.masterId);
    final masterShip = preview == null ? null : masterShips[preview.masterId];
    final resourceType = (masterShip?.id ?? 0) >= 1500
        ? ShipPortraitResourceType.banner
        : ShipPortraitResourceType.remodel;
    final portraitUri = masterShip == null
        ? null
        : ShipPortraitUriBuilder.build(
            ship: masterShip,
            serverOrigin: serverOrigin,
            resourceType: resourceType,
          );
    return Padding(
      key: key,
      padding: padding,
      child: Row(
        children: <Widget>[
          if (showPortraits && portraitUri != null) ...<Widget>[
            ShipPortrait(
              key: Key('official-enemy-preview-portrait-$index'),
              ship: masterShip,
              serverOrigin: serverOrigin,
              width: portraitWidth,
              height: portraitHeight,
              decodeHeight: (portraitHeight * 2).round(),
              resourceType: resourceType,
            ),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Tooltip(
              message: name,
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
