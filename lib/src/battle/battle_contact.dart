import 'package:flutter/material.dart';

import '../fleet/equipment_type_icon.dart';
import '../game_state/game_state.dart';
import '../layout/flat_style.dart';
import '../localization/game_name_localizations.dart';
import '../theme/app_palette.dart';
import 'battle_detail_strings.dart';
import 'battle_tap_tip.dart';

/// Day contact multiplies only the aerial strike, by the plane's accuracy
/// (KC3Kai `Ship.js` applyPostcapModifiers).
int dayContactPercent(int accuracy) => accuracy >= 3
    ? 120
    : accuracy == 2
    ? 117
    : 112;

/// Night recon contact adds flat night power by accuracy
/// (KC3Kai `Gear.js` isNightContactAircraft).
int nightContactPowerBonus(int accuracy) => accuracy >= 3
    ? 9
    : accuracy == 2
    ? 7
    : 5;

/// Contact planes of both sides as type icon + effect; tap for the plane
/// names and what the effect applies to.
class ContactPlaneMarks extends StatelessWidget {
  const ContactPlaneMarks({
    super.key = const Key('contact-plane-marks'),
    required this.friendPlaneId,
    required this.enemyPlaneId,
    required this.slotItems,
    required this.night,
  });

  /// Zero or negative when that side made no contact.
  final int friendPlaneId;
  final int enemyPlaneId;
  final Map<int, MasterSlotItem> slotItems;
  final bool night;

  static const double fontSize = 9.5;
  static const double iconSize = 12;

  String _effect(int accuracy) => night
      ? '+${nightContactPowerBonus(accuracy)}'
      : '${dayContactPercent(accuracy)}%';

  Widget _side(BuildContext context, int id, {required bool friend}) {
    final item = slotItems[id];
    return Row(
      key: Key(friend ? 'contact-plane-friend' : 'contact-plane-enemy'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        EquipmentTypeIconImage(
          iconId: item != null && item.type.length > 3 ? item.type[3] : -1,
          width: iconSize,
          height: iconSize,
        ),
        const SizedBox(width: 1),
        Text(
          _effect(item?.accuracy ?? 0),
          style: appTextStyle(
            context,
            TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: friend ? flatFriendSideColor : flatEnemySideColor,
            ),
          ),
        ),
      ],
    );
  }

  String _detail(BuildContext context, int id, {required bool friend}) {
    final s = BattleDetailStrings.of(context);
    final item = slotItems[id];
    final name = item == null
        ? 'ID: $id'
        : gameNames(context).equipmentName(item.name);
    final accuracy = item?.accuracy ?? 0;
    final effect = night
        ? '${s.nightPower} +${nightContactPowerBonus(accuracy)}'
        : '${s.airStrikeDamage} ×${(dayContactPercent(accuracy) / 100).toStringAsFixed(2)}';
    final side = friend ? s.contactFriend : s.contactEnemy;
    return '$side $name（${s.accuracy} $accuracy）$effect';
  }

  @override
  Widget build(BuildContext context) {
    final friend = friendPlaneId > 0;
    final enemy = enemyPlaneId > 0;
    if (!friend && !enemy) return const SizedBox.shrink();
    final lines = <String>[
      if (friend) _detail(context, friendPlaneId, friend: true),
      if (enemy) _detail(context, enemyPlaneId, friend: false),
    ];
    return BattleTapTip(
      message: lines.join('\n'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (friend) _side(context, friendPlaneId, friend: true),
          if (friend && enemy) const SizedBox(width: 6),
          if (enemy) _side(context, enemyPlaneId, friend: false),
        ],
      ),
    );
  }
}
