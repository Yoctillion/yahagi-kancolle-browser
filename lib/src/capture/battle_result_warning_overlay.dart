import '../theme/app_palette.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../account/account_session.dart';
import '../battle/battle_damage_alert.dart';
import '../battle/battle_models.dart';
import '../bridge/captured_api_event.dart';
import '../game_state/game_state.dart';
import '../settings/safety_settings_controller.dart';
import '../settings/safety_settings_store.dart';
import '../fleet/ship_damage_level.dart';
import '../quest/quest_completion_drawer.dart';
import 'game_capture_controller.dart';
import 'advance_warning_details.dart';
import 'sortie_warning_session.dart';

bool shouldShowPostBattleWarning(LiveBattle? battle) {
  if (battle == null || battle.displayStage != BattleDisplayStage.result) {
    return false;
  }
  final context = battle.context;
  final isBossNode =
      (context.bossNode > 0 && context.node == context.bossNode) ||
      context.nodeTypeLabel == 'Boss 战';
  if (isBossNode) {
    return false;
  }
  final isCombinedFleet = context.combinedFleetType != CombinedFleetType.none;
  return battle.friendShips.any((ship) {
    if (ship.isEscaped || !ship.isHeavilyDamaged) {
      return false;
    }
    final isExcludedFlagship =
        ship.position == 0 &&
        (ship.fleetRole == BattleFleetRole.main ||
            (isCombinedFleet && ship.fleetRole == BattleFleetRole.escort));
    return !isExcludedFlagship;
  });
}

bool shouldShowAdvanceWarning(GameState state) => collectAdvanceWarningShips(
  state,
  damageControlStateTrusted: false,
).isNotEmpty;

bool isPostBattleSafetyEvent(CapturedApiEvent event) =>
    event.path == '/kcsapi/api_req_sortie/battleresult' ||
    event.path == '/kcsapi/api_req_combined_battle/battleresult';

class BattleResultWarningOverlay extends StatefulWidget {
  const BattleResultWarningOverlay({
    super.key,
    required this.gameCaptureController,
    required this.loadSafetyState,
    required this.safetySettingsController,
    required this.damageAlertPort,
    required this.child,
    this.accountSession,
    this.damageControlStateTrusted,
    this.warningSession,
    this.safetyEventAccepted,
    this.damageControlNoticeEnabled,
    this.onReloadGame,
    this.onReloadGameFrame,
  });

  final GameCaptureController gameCaptureController;
  final Future<GameState> Function() loadSafetyState;
  final SafetySettingsController safetySettingsController;
  final BattleDamageAlertPort damageAlertPort;
  final Widget child;
  final AccountSession? accountSession;
  final bool Function()? damageControlStateTrusted;
  final SortieWarningSession? warningSession;
  final bool Function(CapturedApiEvent event, GameState state)?
  safetyEventAccepted;
  final bool Function()? damageControlNoticeEnabled;
  final Future<void> Function()? onReloadGame;
  final Future<void> Function()? onReloadGameFrame;

  @override
  State<BattleResultWarningOverlay> createState() =>
      _BattleResultWarningOverlayState();
}

class _BattleResultWarningOverlayState
    extends State<BattleResultWarningOverlay> {
  int _advanceCheckGeneration = 0;
  int? _pendingSortieStartGeneration;
  AdvanceWarningTimingSettings? _pendingSortieTiming;
  int _metadataGeneration = 0;
  Future<void> _safetyCheckQueue = Future<void>.value();
  CapturedApiEvent? _warningEvent;
  GameState? _warningState;
  late AccountSession _accountSession;
  late AccountScope _accountScope;
  late SortieWarningSession _warningSession;
  final Set<(String?, String?, int)> _checkedSequences = {};
  final ValueNotifier<List<AdvanceWarningShip>> _warningShips =
      ValueNotifier<List<AdvanceWarningShip>>(const []);
  final Set<DialogRoute<void>> _warningDialogRoutes = {};
  DialogRoute<void>? _warningDialogRoute;
  VoidCallback? _removeDamageControlNotice;
  bool _damageControlNoticeActive = false;
  int _damageControlNoticeRevision = 0;
  late AdvanceWarningDisplayMode _displayMode;
  bool _postBattlePresentation = false;
  ({
    int generation,
    int continuity,
    String? session,
    String? document,
    int fleet,
    int area,
    int map,
    int node,
    bool terminal,
  })?
  _navigation;

  @override
  void initState() {
    super.initState();
    _accountSession = widget.accountSession ?? AccountSession.shared;
    _accountScope = _accountSession.current;
    _accountSession.addListener(_onAccountChanged);
    _warningSession = widget.warningSession ?? SortieWarningSession();
    _warningSession.addListener(_onWarningSessionChanged);
    _displayMode = widget.safetySettingsController.advanceWarningDisplayMode;
    widget.safetySettingsController.addListener(_onSafetySettingsChanged);
    widget.gameCaptureController.eventActivity.addListener(
      _onGameCaptureUpdate,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final remove = QuestCompletionDrawerHost.damageControlNoticeRemover(
      context,
    );
    final previous = _removeDamageControlNotice;
    _removeDamageControlNotice = remove;
    if (previous != null && previous != remove && _damageControlNoticeActive) {
      final generation = _advanceCheckGeneration;
      final scope = _accountSession.current;
      final captureGeneration =
          widget.gameCaptureController.continuityGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        previous();
        _fallbackDamageControlNotice(generation, scope, captureGeneration);
      });
    }
  }

  void _clearDamageControlNotice() {
    _damageControlNoticeRevision++;
    _damageControlNoticeActive = false;
    _removeDamageControlNotice?.call();
  }

  bool _noticeEnabled() {
    try {
      return widget.damageControlNoticeEnabled?.call() ?? true;
    } catch (_) {
      return false;
    }
  }

  bool _currentSafetyEventAccepted() {
    final event = _warningEvent;
    final state = _warningState;
    if (event == null || state == null) return false;
    try {
      return widget.safetyEventAccepted?.call(event, state) ?? true;
    } catch (_) {
      return false;
    }
  }

  void _fallbackDamageControlNotice(
    int generation,
    AccountScope scope,
    int captureGeneration,
  ) {
    if (!mounted ||
        !_damageControlNoticeActive ||
        generation != _advanceCheckGeneration ||
        captureGeneration !=
            widget.gameCaptureController.continuityGeneration ||
        !_accountSession.isCurrent(scope) ||
        !_currentSafetyEventAccepted() ||
        _warningSession.isMuted ||
        widget.safetySettingsController.battleWarningMode ==
            BattleWarningMode.off) {
      return;
    }
    _clearDamageControlNotice();
    _showWarningDialog();
  }

  void _onSafetySettingsChanged() {
    final mode = widget.safetySettingsController.battleWarningMode;
    final display = widget.safetySettingsController.advanceWarningDisplayMode;
    final upgrade =
        _displayMode != display &&
        display == AdvanceWarningDisplayMode.alwaysConfirm;
    _displayMode = display;
    if (mode == BattleWarningMode.off) {
      _invalidateWarning(preserveMetadata: true);
      _cancelDamageAlert();
    } else if (upgrade &&
        _damageControlNoticeActive &&
        !_warningSession.isMuted) {
      _clearDamageControlNotice();
      _showWarningDialog();
    }
  }

  @override
  void didUpdateWidget(BattleResultWarningOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_damageControlNoticeActive && !_noticeEnabled()) {
      final generation = _advanceCheckGeneration;
      final scope = _accountSession.current;
      final captureGeneration =
          widget.gameCaptureController.continuityGeneration;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) =>
            _fallbackDamageControlNotice(generation, scope, captureGeneration),
      );
    }
    if (oldWidget.safetySettingsController != widget.safetySettingsController) {
      oldWidget.safetySettingsController.removeListener(
        _onSafetySettingsChanged,
      );
      widget.safetySettingsController.addListener(_onSafetySettingsChanged);
      final settings = widget.safetySettingsController;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(widget.safetySettingsController, settings)) {
          _onSafetySettingsChanged();
        }
      });
    }
    if (oldWidget.warningSession != widget.warningSession) {
      _warningSession.removeListener(_onWarningSessionChanged);
      if (oldWidget.warningSession == null) _warningSession.dispose();
      _warningSession = widget.warningSession ?? SortieWarningSession();
      _warningSession.addListener(_onWarningSessionChanged);
      _invalidateWarning();
    }
    final session = widget.accountSession ?? AccountSession.shared;
    if (!identical(_accountSession, session)) {
      _accountSession.removeListener(_onAccountChanged);
      _accountSession = session;
      _accountScope = session.current;
      _accountSession.addListener(_onAccountChanged);
      _warningSession.endSortie();
      _checkedSequences.clear();
      _invalidateWarning();
    }
    if (oldWidget.gameCaptureController != widget.gameCaptureController) {
      _checkedSequences.clear();
      _warningSession.endSortie();
      _invalidateWarning();
      oldWidget.gameCaptureController.eventActivity.removeListener(
        _onGameCaptureUpdate,
      );
      widget.gameCaptureController.eventActivity.addListener(
        _onGameCaptureUpdate,
      );
    }
  }

  @override
  void dispose() {
    widget.safetySettingsController.removeListener(_onSafetySettingsChanged);
    _clearDamageControlNotice();
    _accountSession.removeListener(_onAccountChanged);
    _warningSession.removeListener(_onWarningSessionChanged);
    if (widget.warningSession == null) _warningSession.dispose();
    final routes = _warningDialogRoutes.toList();
    _warningDialogRoute = null;
    if (routes.isEmpty) {
      _warningShips.dispose();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final route in routes) {
          if (route.isActive) route.navigator?.removeRoute(route);
        }
      });
      unawaited(
        Future.wait(
          routes.map((route) => route.completed),
        ).whenComplete(_warningShips.dispose),
      );
    }
    _advanceCheckGeneration += 1;
    widget.gameCaptureController.eventActivity.removeListener(
      _onGameCaptureUpdate,
    );
    super.dispose();
  }

  void _onGameCaptureUpdate() {
    final event = widget.gameCaptureController.latestEvent;
    if (event == null) {
      _checkedSequences.clear();
      _warningSession.endSortie();
      _invalidateWarning();
      return;
    }
    if (event.apiResult != 1) return;
    if (event.sequence > 0 &&
        !_checkedSequences.add((
          event.captureSessionId,
          event.captureDocumentId,
          event.sequence,
        ))) {
      return;
    }
    if (_checkedSequences.length > 512) {
      _checkedSequences.remove(_checkedSequences.first);
    }

    if (event.path == '/kcsapi/api_port/port' ||
        event.path == '/kcsapi/api_start2/getData') {
      if (widget.warningSession == null) {
        _warningSession.endSortie();
        _invalidateWarning();
      }
      return;
    }

    final isAdvance =
        event.path == '/kcsapi/api_req_map/start' ||
        event.path == '/kcsapi/api_req_map/next';
    final isResult = isPostBattleSafetyEvent(event);
    final configuredTiming =
        widget.safetySettingsController.advanceWarningTimings;
    final effectiveTiming =
        _pendingSortieTiming ?? _warningSession.timings ?? configuredTiming;
    if (!isAdvance && (!isResult || !effectiveTiming.postBattle)) {
      return;
    }
    if (event.path == '/kcsapi/api_req_map/start') {
      _invalidateWarning();
      if (widget.warningSession == null) _warningSession.startSortie();
      _pendingSortieTiming = configuredTiming;
    }

    final scope = _accountSession.current;
    if (!scope.isKnown) return;
    if (isResult || effectiveTiming.afterAdvance) {
      _clearDamageControlNotice();
    }
    final generation = ++_advanceCheckGeneration;
    _pendingSortieStartGeneration =
        event.path == '/kcsapi/api_req_map/start' ||
            _pendingSortieTiming != null
        ? generation
        : null;
    final captureGeneration = widget.gameCaptureController.continuityGeneration;
    final metadataGeneration = _metadataGeneration;
    final timing = _pendingSortieTiming ?? configuredTiming;
    Future<void> check() => _checkAdvanceSafety(
      generation,
      scope,
      captureGeneration,
      event,
      timing,
      metadataGeneration,
    );
    if ((_pendingSortieTiming ?? _warningSession.timings ?? timing)
        .postBattle) {
      _safetyCheckQueue = _safetyCheckQueue.then(
        (_) => check(),
        onError: (_) => check(),
      );
    } else {
      unawaited(check());
    }
  }

  void _invalidateWarning({bool preserveMetadata = false}) {
    _advanceCheckGeneration += 1;
    if (preserveMetadata) {
      if (_pendingSortieTiming != null) {
        _pendingSortieStartGeneration = _advanceCheckGeneration;
      }
    } else {
      _metadataGeneration += 1;
      _safetyCheckQueue = Future<void>.value();
      _pendingSortieStartGeneration = null;
      _pendingSortieTiming = null;
      _navigation = null;
    }
    _warningEvent = null;
    _warningState = null;
    _clearDamageControlNotice();
    _dismissWarningDialog();
  }

  void _dismissWarningDialog() {
    final route = _warningDialogRoute;
    _warningDialogRoute = null;
    if (route != null && route.isActive) {
      route.navigator?.removeRoute(route);
    }
  }

  void _onAccountChanged() {
    if (identical(_accountScope, _accountSession.current)) return;
    _accountScope = _accountSession.current;
    _checkedSequences.clear();
    _warningSession.endSortie();
    _invalidateWarning();
  }

  void _onWarningSessionChanged() {
    if (_warningSession.isMuted) {
      _invalidateWarning(preserveMetadata: true);
      _cancelDamageAlert();
    } else {
      if (_pendingSortieStartGeneration == _advanceCheckGeneration) {
        _clearDamageControlNotice();
        _dismissWarningDialog();
      } else {
        _invalidateWarning();
      }
    }
  }

  void _cancelDamageAlert() {
    final port = widget.damageAlertPort;
    if (port is CancellableBattleDamageAlertPort) {
      final cancellable = port as CancellableBattleDamageAlertPort;
      unawaited(
        cancellable.cancel().catchError((Object error) {
          debugPrint('Failed to cancel damage warning vibration: $error');
        }),
      );
    }
  }

  Future<void> _checkAdvanceSafety(
    int generation,
    AccountScope scope,
    int captureGeneration,
    CapturedApiEvent event,
    AdvanceWarningTimingSettings configuredTiming,
    int metadataGeneration,
  ) async {
    if (!mounted ||
        metadataGeneration != _metadataGeneration ||
        captureGeneration !=
            widget.gameCaptureController.continuityGeneration ||
        !_accountSession.isCurrent(scope)) {
      return;
    }
    final warningGeneration = _warningSession.generation;
    final pendingSortieStart = _pendingSortieStartGeneration == generation;
    try {
      final state = await widget.loadSafetyState();
      if (_pendingSortieStartGeneration == generation) {
        _pendingSortieStartGeneration = null;
        _pendingSortieTiming = null;
      }
      if (!mounted ||
          metadataGeneration != _metadataGeneration ||
          captureGeneration !=
              widget.gameCaptureController.continuityGeneration ||
          !_accountSession.isCurrent(scope) ||
          state.memberId != scope.memberId ||
          (pendingSortieStart &&
              warningGeneration != _warningSession.generation &&
              !_warningSession.isActive) ||
          widget.safetyEventAccepted?.call(event, state) == false) {
        return;
      }
      if (state.combatState.isActive) _warningSession.ensureSortie();
      final timing = _warningSession.timingsForSortie(configuredTiming);
      final combat = state.combatState;
      if (isPostBattleSafetyEvent(event)) {
        if (!timing.postBattle) return;
        final navigation = _navigation;
        if (navigation != null &&
            navigation.generation == _warningSession.generation &&
            navigation.continuity == captureGeneration &&
            navigation.session == event.captureSessionId &&
            navigation.document == event.captureDocumentId &&
            navigation.fleet == combat.sortieFleetId &&
            navigation.area == combat.mapArea &&
            navigation.map == combat.mapInfo &&
            navigation.node == combat.currentNode &&
            navigation.terminal) {
          return;
        }
      } else {
        final envelope =
            event.decodedEnvelope ?? jsonDecode(event.responseBody);
        final data = envelope is Map ? envelope['api_data'] : null;
        _navigation = (
          generation: _warningSession.generation,
          continuity: captureGeneration,
          session: event.captureSessionId,
          document: event.captureDocumentId,
          fleet: combat.sortieFleetId,
          area: combat.mapArea,
          map: combat.mapInfo,
          node: combat.currentNode,
          terminal:
              data is Map &&
              data['api_next'] == 0 &&
              data['api_maparea_id'] == combat.mapArea &&
              data['api_mapinfo_no'] == combat.mapInfo &&
              data['api_no'] == combat.currentNode,
        );
      }
      if (generation != _advanceCheckGeneration || _warningSession.isMuted) {
        return;
      }
      if (!isPostBattleSafetyEvent(event) && !timing.afterAdvance) return;
      _postBattlePresentation = isPostBattleSafetyEvent(event);
      _warningEvent = event;
      _warningState = state;
      var trusted = false;
      try {
        trusted = widget.damageControlStateTrusted?.call() ?? false;
      } catch (error) {
        debugPrint('Damage-control state could not be verified: $error');
      }
      final ships = collectAdvanceWarningShips(
        state,
        damageControlStateTrusted: trusted,
      );
      if (ships.isNotEmpty) {
        await _showAdvanceWarning(ships, generation, scope, captureGeneration);
      } else {
        _clearDamageControlNotice();
        _dismissWarningDialog();
      }
    } catch (error) {
      if (_pendingSortieStartGeneration == generation) {
        _pendingSortieStartGeneration = null;
      }
      debugPrint('Advance safety check failed: $error');
    }
  }

  Future<void> _showAdvanceWarning(
    List<AdvanceWarningShip> ships,
    int generation,
    AccountScope scope,
    int captureGeneration,
  ) async {
    final mode = widget.safetySettingsController.battleWarningMode;
    if (mode == BattleWarningMode.off || _warningSession.isMuted) {
      return;
    }
    _warningShips.value = ships;
    if (_warningDialogRoute != null) return;
    if (widget.safetySettingsController.advanceWarningDisplayMode ==
            AdvanceWarningDisplayMode.smart &&
        ships.every((ship) => ship.hasConfirmedDamageControl)) {
      final noticeRevision = ++_damageControlNoticeRevision;
      var shown = false;
      try {
        if (_noticeEnabled()) {
          final l10n =
              AppLocalizations.of(context) ??
              lookupAppLocalizations(const Locale('zh'));
          shown = await QuestCompletionDrawerHost.showDamageControlNotice(
            context,
            l10n.advanceWarningDamageControlActive,
            onUnavailable: () => _fallbackDamageControlNotice(
              generation,
              scope,
              captureGeneration,
            ),
            onDismissed: () {
              if (mounted && noticeRevision == _damageControlNoticeRevision) {
                _damageControlNoticeActive = false;
              }
            },
          );
        }
      } catch (error) {
        debugPrint('Damage-control notice unavailable: $error');
      }
      if (!mounted ||
          generation != _advanceCheckGeneration ||
          captureGeneration !=
              widget.gameCaptureController.continuityGeneration ||
          !_accountSession.isCurrent(scope) ||
          !_currentSafetyEventAccepted() ||
          _warningSession.isMuted ||
          widget.safetySettingsController.battleWarningMode ==
              BattleWarningMode.off) {
        return;
      }
      _damageControlNoticeActive =
          shown &&
          _noticeEnabled() &&
          widget.safetySettingsController.advanceWarningDisplayMode ==
              AdvanceWarningDisplayMode.smart;
      if (_damageControlNoticeActive) {
        _alertHeavyDamage();
        return;
      }
    }
    _clearDamageControlNotice();
    _alertHeavyDamage();
    _showWarningDialog();
  }

  void _alertHeavyDamage() {
    if (widget.safetySettingsController.battleStatusEffects.vibrates(
      ShipDamageLevel.heavy,
    )) {
      unawaited(
        widget.damageAlertPort
            .alert(BattleDamageAlertSeverity.heavy)
            .catchError((Object error) {
              debugPrint('战后大破警告震动失败: $error');
            }),
      );
    }
  }

  Future<void> _refreshWarning(
    DialogRoute<void> route,
    AccountScope scope,
    int sortieGeneration,
    Future<void> Function() action,
  ) async {
    if (!mounted ||
        !identical(_warningDialogRoute, route) ||
        !route.isCurrent ||
        !_accountSession.isCurrent(scope) ||
        _warningSession.generation != sortieGeneration) {
      return;
    }
    final generation = _advanceCheckGeneration;
    final captureGeneration = widget.gameCaptureController.continuityGeneration;
    _dismissWarningDialog();
    try {
      await action();
    } catch (error) {
      debugPrint('Manual game refresh failed: $error');
      if (!mounted ||
          generation != _advanceCheckGeneration ||
          captureGeneration !=
              widget.gameCaptureController.continuityGeneration ||
          !_accountSession.isCurrent(scope) ||
          _warningSession.generation != sortieGeneration ||
          _warningSession.isMuted ||
          widget.safetySettingsController.battleWarningMode ==
              BattleWarningMode.off ||
          !_currentSafetyEventAccepted() ||
          _warningDialogRoute != null) {
        return;
      }
      _showWarningDialog(refreshFailed: true);
    }
  }

  void _showWarningDialog({bool refreshFailed = false}) {
    if (_warningDialogRoute != null) return;
    final warningGeneration = _warningSession.generation;
    final warningScope = _accountSession.current;
    late final DialogRoute<void> route;
    route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return ValueListenableBuilder<List<AdvanceWarningShip>>(
          valueListenable: _warningShips,
          builder: (context, ships, child) {
            final l10n =
                AppLocalizations.of(context) ??
                lookupAppLocalizations(const Locale('zh'));
            final allEquipped = ships.every(
              (ship) =>
                  ship.damageControlStatus ==
                  AdvanceDamageControlStatus.equipped,
            );
            final hasMissing = ships.any(
              (ship) =>
                  ship.damageControlStatus ==
                  AdvanceDamageControlStatus.missing,
            );
            final reloadGame = widget.onReloadGame;
            final reloadGameFrame = widget.onReloadGameFrame;
            return AlertDialog(
              scrollable: true,
              backgroundColor: appColor(context, const Color(0xff122431)),
              title: Text(
                l10n.postBattleWarningTitle,
                style: appTextStyle(
                  context,
                  TextStyle(color: appColor(context, Color(0xffd4a85f))),
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    allEquipped
                        ? l10n.advanceWarningEquippedHeadline
                        : hasMissing
                        ? l10n.advanceWarningMissingHeadline
                        : l10n.advanceWarningUnknownHeadline,
                    style: appTextStyle(
                      context,
                      TextStyle(
                        color: appColor(
                          context,
                          allEquipped
                              ? const Color(0xffd4a85f)
                              : Colors.redAccent,
                        ),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final ship in ships)
                    _AdvanceWarningShipRow(ship: ship, l10n: l10n),
                  const SizedBox(height: 8),
                  Text(
                    _postBattlePresentation
                        ? allEquipped
                              ? l10n.postBattleDamageControlEquippedBody
                              : l10n.postBattleDamageControlDangerBody
                        : allEquipped
                        ? l10n.advanceWarningEquippedBody
                        : l10n.postBattleWarningBody,
                    style: appTextStyle(
                      context,
                      TextStyle(color: appColor(context, Colors.white70)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _AdvanceWarningRefreshActions(
                    l10n: l10n,
                    initiallyFailed: refreshFailed,
                    canRefresh: () =>
                        mounted &&
                        identical(_warningDialogRoute, route) &&
                        route.isCurrent &&
                        _accountSession.isCurrent(warningScope) &&
                        _warningSession.generation == warningGeneration,
                    onReloadGame: reloadGame == null
                        ? null
                        : () => _refreshWarning(
                            route,
                            warningScope,
                            warningGeneration,
                            reloadGame,
                          ),
                    onReloadGameFrame: reloadGameFrame == null
                        ? null
                        : () => _refreshWarning(
                            route,
                            warningScope,
                            warningGeneration,
                            reloadGameFrame,
                          ),
                  ),
                ],
              ),
              actions: [
                FilledButton(
                  key: const Key('muteCurrentSortieWarning'),
                  onPressed: () {
                    if (!mounted ||
                        !identical(_warningDialogRoute, route) ||
                        !route.isCurrent ||
                        !_accountSession.isCurrent(warningScope) ||
                        _warningSession.generation != warningGeneration) {
                      return;
                    }
                    _warningSession.muteCurrentSortie();
                  },
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    backgroundColor: appColor(context, const Color(0xffe4c267)),
                    foregroundColor: appColor(context, const Color(0xff302305)),
                  ),
                  child: Text(l10n.advanceWarningMuteSortie),
                ),
                FilledButton(
                  key: const Key('acknowledgeAdvanceWarning'),
                  onPressed: () {
                    if (mounted &&
                        identical(_warningDialogRoute, route) &&
                        route.isCurrent) {
                      Navigator.of(context).pop();
                    }
                  },
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    backgroundColor: appColor(context, const Color(0xffff7f88)),
                    foregroundColor: appColor(context, const Color(0xff330c12)),
                  ),
                  child: Text(l10n.acknowledgeAndRetreat),
                ),
              ],
            );
          },
        );
      },
    );
    _warningDialogRoute = route;
    _warningDialogRoutes.add(route);
    unawaited(
      route.completed.then((_) {
        _warningDialogRoutes.remove(route);
      }),
    );
    unawaited(
      Navigator.of(context, rootNavigator: true).push<void>(route).whenComplete(
        () {
          if (identical(_warningDialogRoute, route)) {
            _warningDialogRoute = null;
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class _AdvanceWarningRefreshActions extends StatefulWidget {
  const _AdvanceWarningRefreshActions({
    required this.l10n,
    required this.canRefresh,
    required this.onReloadGame,
    required this.onReloadGameFrame,
    this.initiallyFailed = false,
  });

  final AppLocalizations l10n;
  final bool Function() canRefresh;
  final Future<void> Function()? onReloadGame;
  final Future<void> Function()? onReloadGameFrame;
  final bool initiallyFailed;

  @override
  State<_AdvanceWarningRefreshActions> createState() =>
      _AdvanceWarningRefreshActionsState();
}

class _AdvanceWarningRefreshActionsState
    extends State<_AdvanceWarningRefreshActions> {
  bool _busy = false;
  late bool _failed = widget.initiallyFailed;

  Future<void> _refresh(Future<void> Function() action) async {
    if (!mounted || _busy || !widget.canRefresh()) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            key: const Key('advanceWarningReloadGame'),
            onPressed: _busy || widget.onReloadGame == null
                ? null
                : () => _refresh(widget.onReloadGame!),
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(widget.l10n.advanceWarningReloadGame),
          ),
          OutlinedButton.icon(
            key: const Key('advanceWarningReloadFrame'),
            onPressed: _busy || widget.onReloadGameFrame == null
                ? null
                : () => _refresh(widget.onReloadGameFrame!),
            icon: const Icon(Icons.web_asset, size: 18),
            label: Text(widget.l10n.advanceWarningReloadFrame),
          ),
        ],
      ),
      if (_failed)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            widget.l10n.advanceWarningRefreshFailed,
            style: appTextStyle(
              context,
              TextStyle(color: appColor(context, Colors.redAccent)),
            ),
          ),
        ),
    ],
  );
}

class _AdvanceWarningShipRow extends StatelessWidget {
  const _AdvanceWarningShipRow({required this.ship, required this.l10n});

  final AdvanceWarningShip ship;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final equipped =
        ship.damageControlStatus == AdvanceDamageControlStatus.equipped;
    final color = appColor(
      context,
      equipped ? const Color(0xffd4a85f) : Colors.redAccent,
    );
    final name = ship.requiresDisambiguation
        ? '${ship.name}（${l10n.advanceWarningShipPosition(ship.fleetId, ship.position)}）'
        : ship.name;
    final status = switch (ship.damageControlStatus) {
      AdvanceDamageControlStatus.missing => l10n.advanceWarningMissing,
      AdvanceDamageControlStatus.unknown => l10n.advanceWarningUnknown,
      AdvanceDamageControlStatus.equipped => l10n.advanceWarningEquipped(
        ship.remainingDamageControls.entries
            .map((entry) {
              final item = entry.key == 42
                  ? l10n.advanceWarningPersonnel
                  : l10n.advanceWarningGoddess;
              return '$item ×${entry.value}';
            })
            .join('、'),
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: appTextStyle(context, TextStyle(color: color))),
          const SizedBox(height: 4),
          Text(
            status,
            style: appTextStyle(context, TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
