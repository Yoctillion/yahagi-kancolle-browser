import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../game_state/game_state.dart';
import '../new_ship/new_ship_reminder_controller.dart';
import 'notification_models.dart';

ImmediateNotificationItem buildNewShipNotification({
  required NewShipAlert alert,
  required GameState state,
  required String localeCode,
}) {
  final locale = switch (localeCode) {
    'ja' => const Locale('ja'),
    'zh_Hant' => const Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'Hant',
    ),
    _ => const Locale('zh'),
  };
  final l10n = lookupAppLocalizations(locale);
  final names = alert.masterIds
      .map((id) => state.masterShips[id]?.name ?? l10n.newShipFallbackName(id))
      .join('、');
  return ImmediateNotificationItem(
    key: 'new-ship:${alert.key}',
    type: GameNotificationType.newShip,
    occurredAt: alert.occurredAt,
    title: l10n.newShipAlertTitle,
    body: l10n.newShipAlertBody(names),
  );
}
