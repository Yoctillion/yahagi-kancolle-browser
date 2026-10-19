import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/new_ship/new_ship_reminder_controller.dart';
import 'package:yahagi_kancolle_browser/src/notification/new_ship_notification.dart';
import 'package:yahagi_kancolle_browser/src/notification/notification_models.dart';

void main() {
  test(
    'system new ship alert follows effective language without changing identity',
    () {
      final at = DateTime.utc(2026, 9, 30);
      final alert = NewShipAlert(
        key: 'drop-1',
        masterIds: [1, 2],
        sources: [],
        occurredAt: at,
      );
      const state = GameState(
        masterShips: {1: MasterShip(id: 1, name: '雪風', shipTypeId: 2)},
      );
      for (final code in [
        'ja',
        'zh_Hant',
        'ko',
        'en',
        'zh',
        'unexpected',
        'ja',
      ]) {
        final locale = switch (code) {
          'ja' => const Locale('ja'),
          'ko' => const Locale('ko'),
          'en' => const Locale('en'),
          'zh_Hant' => const Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hant',
          ),
          _ => const Locale('zh'),
        };
        final l10n = lookupAppLocalizations(locale);
        final result = buildNewShipNotification(
          alert: alert,
          state: state,
          localeCode: code,
        );
        expect(result.title, l10n.newShipAlertTitle, reason: code);
        expect(
          result.body,
          l10n.newShipAlertBody(
            '雪風${code == 'en' ? ', ' : '、'}${l10n.newShipFallbackName(2)}',
          ),
          reason: code,
        );
        expect(result.key, 'new-ship:drop-1');
        expect(result.type, GameNotificationType.newShip);
        expect(result.occurredAt, at);
      }
    },
  );
}
