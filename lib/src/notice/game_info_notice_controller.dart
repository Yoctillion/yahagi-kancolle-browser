import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../account/account_session.dart';
import '../bridge/captured_api_event.dart';
import '../game_state/game_api_decoder.dart';
import '../game_state/game_api_event_pipeline.dart';
import '../game_state/game_state.dart';
import '../localization/game_name_catalog.dart';
import '../settings/layout_settings_controller.dart';
import '../practice/practice_exp.dart';
import '../widgets/top_notice.dart';

/// Intercepts game events and dispatches unified top bar notices for:
/// - Equipment development (single & 3-batch with slot-by-slot status)
/// - Equipment improvement (success and failure)
/// - Ship modernization (increases, MAX flags, failure)
/// - Marriage (luck bonus and remaining to cap)
/// - Sortie safety checks (ship/equipment capacity warnings)
/// - Practice assistant (opponent base experience and training cruiser bonus)
class GameInfoNoticeController implements GameApiEventConsumer {
  GameInfoNoticeController({
    required this.stateProvider,
    required this.layoutSettingsController,
    required this.topNoticeController,
    this.accountSession,
    this.namesProvider,
  }) : _noticeScope = accountSession?.current {
    accountSession?.addListener(_onAccountChanged);
  }

  final GameState Function() stateProvider;
  final LayoutSettingsController layoutSettingsController;
  final TopNoticeController topNoticeController;
  final AccountSession? accountSession;
  final GameNameCatalog Function()? namesProvider;
  AccountScope? _noticeScope;
  bool _disposed = false;

  void _onAccountChanged() {
    final current = accountSession?.current;
    if (identical(current, _noticeScope)) return;
    _noticeScope = current;
    topNoticeController.hide();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    accountSession?.removeListener(_onAccountChanged);
  }

  Future<void> _queue = Future<void>.value();

  @override
  Future<void> get idle => _queue;

  @override
  bool supportsPath(String path) {
    return path == '/kcsapi/api_req_kousyou/createitem' ||
        path == '/kcsapi/api_req_kousyou/remodel_slot' ||
        path == '/kcsapi/api_req_kaisou/powerup' ||
        path == '/kcsapi/api_req_kaisou/marriage' ||
        path == '/kcsapi/api_get_member/mapinfo' ||
        path == '/kcsapi/api_req_member/get_practice_enemyinfo';
  }

  @override
  void accept(CapturedApiEvent event) {
    if (_disposed || !layoutSettingsController.topNoticeEnabled) {
      return;
    }

    // Immediately and synchronously capture the current state before any asynchronous
    // processing or pipeline reducers have a chance to update the state.
    final stateBefore = stateProvider();
    final scope = accountSession?.current;

    _queue = _queue.then((_) async {
      if (_disposed || (scope != null && !accountSession!.isCurrent(scope))) {
        return;
      }
      try {
        final rawData = GameApiDecoder.decodeEventData(event);
        if (_disposed || (scope != null && !accountSession!.isCurrent(scope))) {
          return;
        }
        if (rawData is! Map<String, Object?>) return;

        switch (event.path) {
          case '/kcsapi/api_req_kousyou/createitem':
            _handleDevelopment(rawData, stateBefore);
            break;
          case '/kcsapi/api_req_kousyou/remodel_slot':
            _handleEquipmentImprovement(rawData);
            break;
          case '/kcsapi/api_req_kaisou/powerup':
            _handleModernization(rawData, event, stateBefore);
            break;
          case '/kcsapi/api_req_kaisou/marriage':
            _handleMarriage(rawData, event, stateBefore);
            break;
          case '/kcsapi/api_get_member/mapinfo':
            _handleSortieCheck(stateBefore);
            break;
          case '/kcsapi/api_req_member/get_practice_enemyinfo':
            _handlePracticeEnemyInfo(rawData, stateBefore);
            break;
        }
      } catch (e, stack) {
        debugPrint(
          'GameInfoNoticeController error handling ${event.path}: $e\n$stack',
        );
      }
    });
  }

  void postNotice({
    required String message,
    required TopNoticeTone tone,
    IconData? icon,
    Color? color,
    Duration appendWithin = const Duration(milliseconds: 500),
    String? replacementKey,
  }) {
    if (_disposed || !layoutSettingsController.topNoticeEnabled) return;
    topNoticeController.show(
      message: message,
      tone: tone,
      customIcon: icon,
      customColor: color,
      duration: Duration(
        seconds: layoutSettingsController.topNoticeDurationSeconds,
      ),
      appendWithin: appendWithin,
      replacementKey: replacementKey,
    );
  }

  AppLocalizations _getL10n() {
    final code = layoutSettingsController.effectiveLocaleCode;
    if (code == 'zh_Hant') {
      return lookupAppLocalizations(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      );
    } else if (code == 'ja' || code == 'ko' || code == 'en') {
      return lookupAppLocalizations(Locale(code));
    }
    return lookupAppLocalizations(const Locale('zh'));
  }

  static int _asInt(dynamic val, [int fallback = 0]) {
    if (val == null) return fallback;
    if (val is int) return val;
    if (val is num) return val.toInt();
    if (val is String) {
      return int.tryParse(val) ?? fallback;
    }
    return fallback;
  }

  static bool _isModernizationInt(Object? value) =>
      (value is int && value >= 0) ||
      (value is String && (int.tryParse(value) ?? -1) >= 0);

  static List<int> _requestShipIds(Object? value) {
    if (value is String) {
      return value.split(',').map(int.tryParse).whereType<int>().toList();
    }
    if (value is List) {
      return value.map(_asInt).where((id) => id > 0).toList();
    }
    return const <int>[];
  }

  /// Poi's theoretical maximum gain from the ships consumed in this request.
  static List<int?> _modernizationMaxDeltas(
    CapturedApiEvent event,
    GameState state,
  ) {
    final totals = List<int>.filled(4, 0);
    final rawSourceIds = event.requestParams['api_id_items'];
    final sourceIds = _requestShipIds(rawSourceIds);
    final requestedCount = rawSourceIds is String
        ? rawSourceIds.split(',').length
        : rawSourceIds is List
        ? rawSourceIds.length
        : 0;
    final incompleteSourceIds =
        sourceIds.isEmpty || sourceIds.length != requestedCount;
    var unknownPowerUp = incompleteSourceIds;
    var unknownLuck = incompleteSourceIds;
    var luckFifths = 0;
    for (final id in sourceIds) {
      final masterId = state.ships[id]?.masterId;
      if (masterId == null) {
        unknownPowerUp = true;
        unknownLuck = true;
        continue;
      }
      final powerUp = state.masterShips[masterId]?.powerUp ?? const <int>[];
      if (powerUp.length < 4) unknownPowerUp = true;
      for (var i = 0; i < 4 && i < powerUp.length; i++) {
        totals[i] += powerUp[i];
      }
      if (masterId == 163) luckFifths += 6;
      if (masterId == 402) luckFifths += 8;
    }
    return [
      for (final total in totals)
        unknownPowerUp ? null : total + ((total + 1) ~/ 5),
      unknownLuck ? null : (luckFifths / 5 - 0.0001).ceil(),
      0,
      0,
    ];
  }

  void _handleDevelopment(Map<String, Object?> data, GameState state) {
    final l10n = _getL10n();
    final rawGetItems = data['api_get_items'];
    if (rawGetItems is List && rawGetItems.isNotEmpty) {
      // 3-batch development
      final results = <String>[];
      var successCount = 0;
      for (final item in rawGetItems) {
        Map? slotItem;
        if (item is Map) {
          final nestedSlotItem = item['api_slot_item'];
          if (nestedSlotItem is Map && _asInt(item['api_create_flag']) == 1) {
            slotItem = nestedSlotItem;
          } else if (item.containsKey('api_slotitem_id')) {
            slotItem = item;
          }
        }

        final masterId = slotItem == null
            ? 0
            : _asInt(slotItem['api_slotitem_id']);
        if (masterId > 0) {
          successCount++;
          final name =
              state.masterSlotItems[masterId]?.name ??
              l10n.noticeDevDefaultName;
          results.add(namesProvider?.call().equipmentName(name) ?? name);
        } else {
          results.add(l10n.noticeDevSlotFailed);
        }
      }

      if (successCount == 0) {
        postNotice(
          message: l10n.noticeDevFailedPenguin,
          tone: TopNoticeTone.warning,
        );
      } else {
        postNotice(message: results.join(' / '), tone: TopNoticeTone.success);
      }
      return;
    }

    // Single development
    final createFlag = _asInt(data['api_create_flag']);
    if (createFlag == 1) {
      final slotItem = data['api_slot_item'];
      final masterId = slotItem is Map
          ? _asInt(slotItem['api_slotitem_id'])
          : 0;
      final name =
          state.masterSlotItems[masterId]?.name ?? l10n.noticeDevDefaultName;
      postNotice(
        message: l10n.noticeDevSuccess(
          namesProvider?.call().equipmentName(name) ?? name,
        ),
        tone: TopNoticeTone.success,
      );
    } else {
      postNotice(message: l10n.noticeDevFailed, tone: TopNoticeTone.warning);
    }
  }

  void _handleEquipmentImprovement(Map<String, Object?> data) {
    final l10n = _getL10n();
    final succeeded = _asInt(data['api_remodel_flag']) == 1;
    postNotice(
      message: succeeded
          ? l10n.noticeEquipImproveSuccess
          : l10n.noticeEquipImproveFailed,
      tone: succeeded ? TopNoticeTone.success : TopNoticeTone.warning,
      appendWithin: const Duration(milliseconds: 500),
    );
  }

  void _handleModernization(
    Map<String, Object?> data,
    CapturedApiEvent event,
    GameState state,
  ) {
    final l10n = _getL10n();
    final flag = _asInt(data['api_powerup_flag']);
    if (flag == 0) {
      postNotice(message: l10n.noticeModFailed, tone: TopNoticeTone.warning);
      return;
    }

    final rawShip = data['api_ship'];
    if (rawShip is! Map) {
      postNotice(message: l10n.noticeModSuccess, tone: TopNoticeTone.success);
      return;
    }

    final shipId = _asInt(rawShip['api_id']);
    final oldShip = state.ships[shipId];
    if (oldShip == null) {
      postNotice(message: l10n.noticeModSuccess, tone: TopNoticeTone.success);
      return;
    }

    final rawMasterId = _asInt(rawShip['api_ship_id']);
    final masterId = rawMasterId > 0 ? rawMasterId : oldShip.masterId;
    final master = state.masterShips[masterId];
    final oldKyouka = oldShip.modernization;

    final rawKyouka = rawShip['api_kyouka'];
    final kyoukaList =
        rawKyouka is List &&
            rawKyouka.length >= 7 &&
            rawKyouka.take(7).every(_isModernizationInt)
        ? rawKyouka.map(_asInt).toList()
        : null;

    // Poi compares api_kyouka before and after the request. The response's
    // displayed stats include equipment bonuses, so they are not a reliable
    // measure of modernization gains or remaining capacity.
    if (kyoukaList != null && kyoukaList.length >= 7 && oldKyouka.length >= 7) {
      final maxDeltas = _modernizationMaxDeltas(event, state);
      final labels = [
        l10n.statFirepower,
        l10n.statTorpedo,
        l10n.statAntiAir,
        l10n.statArmor,
        l10n.statLuck,
        l10n.statHp,
        l10n.statAsw,
      ];
      final details = <String>[];
      for (var i = 0; i < labels.length; i++) {
        final delta = kyoukaList[i] - oldKyouka[i];
        // Poi has master ranges for the first five stats only. HP and ASW
        // therefore have unknown remaining capacity, even when the displayed
        // ship stat happens to equal its current maximum.
        final remaining = i < 5
            ? master?.remainingModernization(i, kyoukaList[i])
            : null;
        if (delta == 0 &&
            !(remaining != null &&
                remaining > 0 &&
                maxDeltas[i] != null &&
                maxDeltas[i] != 0)) {
          continue;
        }
        final remainingText = remaining == null
            ? '?'
            : remaining <= 0
            ? 'MAX'
            : '+$remaining';
        final arrow =
            remaining == null ||
                remaining <= 0 ||
                (maxDeltas[i] != null && delta >= maxDeltas[i]!)
            ? '▲▲'
            : '▲';
        details.add('${labels[i]} $arrow $delta / $remainingText');
      }
      postNotice(
        message: details.isEmpty
            ? l10n.noticeModSuccess
            : l10n.noticeModSuccessDetail(details.join(' · ')),
        tone: TopNoticeTone.success,
      );
      return;
    }

    postNotice(message: l10n.noticeModSuccess, tone: TopNoticeTone.success);
  }

  void _handleMarriage(
    Map<String, Object?> data,
    CapturedApiEvent event,
    GameState state,
  ) {
    final l10n = _getL10n();
    final rawShip = data.containsKey('api_id')
        ? data
        : (data['api_ship'] ?? data['api_data']);
    if (rawShip is! Map) return;

    final shipId = _asInt(rawShip['api_id']);
    final oldShip = state.ships[shipId];
    if (oldShip == null) return;

    final rawLucky = rawShip['api_lucky'];
    final newLuck = rawLucky is List && rawLucky.isNotEmpty
        ? _asInt(rawLucky[0])
        : oldShip.luck;
    final maxLuck = rawLucky is List && rawLucky.length > 1
        ? _asInt(rawLucky[1])
        : oldShip.luckMax;

    final delta = newLuck - oldShip.luck;
    final remaining = maxLuck - newLuck;
    final arrow = delta > 4 ? '▲▲' : '▲';

    if (remaining <= 0) {
      postNotice(
        message: l10n.noticeMarriageLuckMax(arrow, delta),
        tone: TopNoticeTone.marriage,
      );
    } else {
      postNotice(
        message: l10n.noticeMarriageLuck(arrow, delta, remaining),
        tone: TopNoticeTone.marriage,
      );
    }
  }

  void _handleSortieCheck(GameState state) {
    final l10n = _getL10n();
    final maxShips = state.maxShipCount;
    final remainingShips = (maxShips != null && maxShips > 0)
        ? maxShips - state.ships.length
        : null;

    final maxItems = state.maxEquipmentCount;
    final remainingItems = (maxItems != null && maxItems > 0)
        ? maxItems - state.equipmentCapacityUsed
        : null;

    final shipFull = remainingShips != null && remainingShips <= 0;
    final itemFull = remainingItems != null && remainingItems <= 0;

    // Error priority: Full capacity
    if (shipFull && itemFull) {
      postNotice(
        message: l10n.noticeSortieShipAndItemFull,
        tone: TopNoticeTone.error,
      );
      return;
    }
    if (shipFull) {
      postNotice(message: l10n.noticeSortieShipFull, tone: TopNoticeTone.error);
      return;
    }
    if (itemFull) {
      postNotice(message: l10n.noticeSortieItemFull, tone: TopNoticeTone.error);
      return;
    }

    // 2. Warning: Low capacity (<= 5)
    final shipLow =
        remainingShips != null && remainingShips > 0 && remainingShips <= 5;
    final itemLow =
        remainingItems != null && remainingItems > 0 && remainingItems <= 5;

    if (shipLow && itemLow) {
      postNotice(
        message: l10n.noticeSortieShipAndItemLow(
          remainingShips,
          remainingItems,
        ),
        tone: TopNoticeTone.warning,
      );
      return;
    }
    if (shipLow) {
      postNotice(
        message: l10n.noticeSortieShipLow(remainingShips),
        tone: TopNoticeTone.warning,
      );
      return;
    }
    if (itemLow) {
      postNotice(
        message: l10n.noticeSortieItemLow(remainingItems),
        tone: TopNoticeTone.warning,
      );
      return;
    }
  }

  void _handlePracticeEnemyInfo(Map<String, Object?> data, GameState state) {
    const noticeKey = 'practice-experience';
    final l10n = _getL10n();
    final rawDeck = data['api_deck'];
    if (rawDeck is! Map) {
      topNoticeController.removeByKey(noticeKey);
      return;
    }

    final rawShips = rawDeck['api_ships'];
    if (rawShips is! List || rawShips.isEmpty) {
      topNoticeController.removeByKey(noticeKey);
      return;
    }

    final firstShip = rawShips[0];
    final secondShip = rawShips.length > 1 ? rawShips[1] : null;

    final l1 = firstShip is Map ? _asInt(firstShip['api_level']) : 0;
    final l2 = secondShip is Map ? _asInt(secondShip['api_level']) : 0;

    if (l1 <= 0) {
      topNoticeController.removeByKey(noticeKey);
      return;
    }

    final baseExp = practiceBaseExp(l1, l2);
    if (baseExp <= 0) {
      topNoticeController.removeByKey(noticeKey);
      return;
    }

    final bonus = practiceCtBonus(state);
    final sExp = practiceRankExp(baseExp, PracticeRank.s, bonus);
    final aExp = practiceRankExp(baseExp, PracticeRank.a, bonus);
    if (bonus.modifier != 1) {
      final percent = ((bonus.modifier - 1) * 10000).round() / 100;
      // Asahi as flagship lowers non-submarine exp, so the sign is part of the value.
      final sign = percent > 0 ? '+' : '';
      final bonusStr = percent % 1 == 0
          ? '$sign${percent.toInt()}%'
          : '$sign$percent%';
      postNotice(
        message: l10n.noticePracticeExpCtBonus(sExp, aExp, bonusStr),
        tone: TopNoticeTone.info,
        replacementKey: noticeKey,
      );
    } else {
      postNotice(
        message: l10n.noticePracticeExp(sExp, aExp),
        tone: TopNoticeTone.info,
        replacementKey: noticeKey,
      );
    }
  }
}
