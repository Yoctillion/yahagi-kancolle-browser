import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../game_state/game_state.dart';
import '../game_state/game_state_controller.dart';
import '../settings/layout_settings_controller.dart';
import 'ship_subtitle_catalog.dart';
import 'ship_subtitle_catalog_controller.dart';
import 'ship_subtitle_kc3_bundle.dart';
import 'ship_subtitle_language.dart';
import 'ship_subtitle_port.dart';
import 'ship_subtitle_settings.dart';

enum ShipSubtitleRuntimeStatus {
  checking,
  unsupported,
  failed,
  waitingForGameData,
  ready,
}

/// Keeps the optional game-frame renderer in sync without sending its complete
/// translation catalog for every layout, font, or drag change.
final class ShipSubtitleRuntimeController extends ChangeNotifier
    with WidgetsBindingObserver {
  ShipSubtitleRuntimeController({
    required this.settings,
    required this.catalog,
    required this.layout,
    required this.gameState,
    ShipSubtitlePort? port,
  }) : port = port ?? MethodChannelShipSubtitlePort() {
    settings.addListener(_onSettingsChanged);
    catalog.addListener(_onCatalogChanged);
    layout.addListener(_schedule);
    gameState.addListener(_onMasterChanged);
    WidgetsBinding.instance.addObserver(this);
    this.port.onPositionChanged = _onPositionChanged;
  }

  final ShipSubtitleSettingsController settings;
  final ShipSubtitleCatalogController catalog;
  final LayoutSettingsController layout;
  final GameStateController gameState;
  final ShipSubtitlePort port;
  Future<void>? _retryOperation;
  Future<void>? _drain;
  Future<void> _positionTail = Future<void>.value();
  bool _ready = false;
  bool _hasSupportedPort = false;
  bool _initialized = false;
  bool _disposed = false;
  bool _wasEnabled = false;
  bool _foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  int _revision = 0;
  Timer? _updateTimer;
  Map<String, Object?>? _sentConfig;
  ShipSubtitleCatalog? _sentCatalog;
  ShipSubtitleLanguage? _sentCatalogLanguage;
  Map<int, MasterShip>? _sentCatalogShips;
  Map<int, MasterShip>? _sentShips;
  ShipSubtitleLanguage? _sentShipsLanguage;
  ShipSubtitleKc3Bundle? _sentNameBundle;
  Map<int, MasterShip>? _observedShips;
  ShipSubtitleCatalog? _observedCatalog;
  ShipSubtitleKc3Bundle? _observedNameBundle;
  ShipSubtitleLanguage? _requestedLanguage;
  bool _observedLanguageReady = false;
  bool _observedLanguageLoading = false;
  Object? _observedLanguageError;
  Object? lastError;
  ShipSubtitleRuntimeStatus _status = ShipSubtitleRuntimeStatus.checking;
  ShipSubtitleRuntimeStatus get status => _status;

  Future<void> get idle async {
    while (_retryOperation != null || _drain != null) {
      await (_retryOperation ?? _drain!);
    }
  }

  Future<void> get positionIdle => _positionTail;

  Future<void> initialize() {
    if (_disposed) return Future<void>.value();
    if (_initialized) return idle;
    _onSettingsChanged();
    _initialized = true;
    return retry();
  }

  /// Recheck platform support and resubmit current data without losing opt-in.
  /// Serialize retries with an older send so its completion cannot restore stale
  /// sent markers after the new attempt has invalidated them.
  Future<void> retry() {
    if (_disposed) return Future<void>.value();
    return _retryOperation ??= _retry().whenComplete(() {
      _retryOperation = null;
    });
  }

  Future<void> _retry() async {
    _ready = false;
    _revision++;
    _setStatus(ShipSubtitleRuntimeStatus.checking);
    try {
      await _drain;
      if (_disposed) return;
      _sentConfig = null;
      _sentCatalog = null;
      _sentCatalogLanguage = null;
      _sentCatalogShips = null;
      _sentShips = null;
      _sentShipsLanguage = null;
      _sentNameBundle = null;
      if (!_catalogMatchesLanguage) {
        await catalog.selectLanguage(settings.language);
        if (_disposed) return;
      }
      final supported = await port.isSupported().timeout(
        const Duration(seconds: 10),
      );
      if (_disposed) return;
      _ready = supported;
      if (supported) _hasSupportedPort = true;
      lastError = null;
      if (!supported) {
        _setStatus(ShipSubtitleRuntimeStatus.unsupported);
        return;
      }
      _schedule();
      while (_drain != null) {
        await _drain;
      }
    } catch (error) {
      if (_disposed) return;
      _ready = false;
      lastError = error;
      _setStatus(ShipSubtitleRuntimeStatus.failed);
    }
  }

  void _setStatus(ShipSubtitleRuntimeStatus value) {
    if (_disposed || _status == value) return;
    _status = value;
    notifyListeners();
  }

  bool get _needsSupportRetry =>
      !_ready || _status == ShipSubtitleRuntimeStatus.failed;

  void _onSettingsChanged() {
    if (_disposed) return;
    final language = settings.language;
    if (_requestedLanguage != language ||
        catalog.language != language ||
        (settings.enabled &&
            !catalog.isLanguageReady &&
            !catalog.isLoadingLanguage)) {
      _requestedLanguage = language;
      unawaited(
        catalog.selectLanguage(language).catchError((Object error) {
          if (!_disposed) lastError = error;
        }),
      );
    }
    final enabledChanged = settings.enabled != _wasEnabled;
    if (enabledChanged) {
      _wasEnabled = settings.enabled;
      _restartUpdateTimer();
    }
    if (_initialized &&
        enabledChanged &&
        settings.enabled &&
        _foreground &&
        _needsSupportRetry) {
      unawaited(retry());
      return;
    }
    _schedule();
  }

  void _restartUpdateTimer() {
    _updateTimer?.cancel();
    _updateTimer = null;
    if (!_wasEnabled || !_foreground) return;
    _checkIfDue();
    _updateTimer = Timer.periodic(
      const Duration(hours: 24),
      (_) => _checkIfDue(),
    );
  }

  void _checkIfDue() {
    if (_disposed || !_renderingEnabled) return;
    unawaited(
      catalog.checkIfDue().catchError((Object error) {
        if (!_disposed) lastError = error;
      }),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground == foreground) return;
    _foreground = foreground;
    _restartUpdateTimer();
    if (_initialized && foreground && settings.enabled && _needsSupportRetry) {
      unawaited(retry());
      return;
    }
    _schedule();
  }

  void _onCatalogChanged() {
    final ready = _catalogMatchesLanguage;
    final loading = catalog.isLoadingLanguage;
    final error = ready ? null : catalog.lastError;
    if (identical(_observedCatalog, catalog.data) &&
        identical(_observedNameBundle, catalog.kc3Bundle) &&
        ready == _observedLanguageReady &&
        loading == _observedLanguageLoading &&
        identical(error, _observedLanguageError)) {
      return;
    }
    _observedCatalog = catalog.data;
    _observedNameBundle = catalog.kc3Bundle;
    _observedLanguageReady = ready;
    _observedLanguageLoading = loading;
    _observedLanguageError = error;
    _schedule();
    if (ready) _checkIfDue();
  }

  bool get _catalogMatchesLanguage =>
      catalog.isLanguageReady && catalog.dataLanguage == settings.language;

  bool get _renderingEnabled =>
      _foreground && settings.enabled && _catalogMatchesLanguage;

  // A failed support recheck must not prevent stopping an existing renderer.
  // Keep disable delivery serialized with older sends, even while checking.
  bool get _canDisable => _hasSupportedPort && !_renderingEnabled;

  void _onMasterChanged() {
    final ships = gameState.state.masterShips;
    if (identical(_observedShips, ships)) return;
    _observedShips = ships;
    _schedule();
  }

  void _onPositionChanged(double x, double y) {
    if (_disposed ||
        !_renderingEnabled ||
        layout.uiLocked ||
        !x.isFinite ||
        !y.isFinite ||
        x < 0 ||
        x > 1 ||
        y < 0 ||
        y > 1) {
      return;
    }
    _positionTail = _positionTail
        .then((_) async {
          if (_disposed || !_renderingEnabled || layout.uiLocked) return;
          await settings.setPosition(x, y);
        })
        .catchError((Object error) {
          if (!_disposed) lastError = error;
        });
  }

  void _schedule() {
    if (_disposed || (!_ready && !_canDisable)) return;
    _revision++;
    if (_drain != null) return;
    final operation = _synchronize();
    _drain = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_drain, operation)) _drain = null;
      }),
    );
  }

  Future<void> _synchronize() async {
    var processed = -1;
    while (!_disposed && (_ready || _canDisable) && processed != _revision) {
      processed = _revision;
      try {
        if (_ready && _renderingEnabled) {
          final ships = gameState.state.masterShips;
          final language = settings.language;
          final nameBundle = catalog.kc3Bundle;
          if (!identical(_sentShips, ships) ||
              _sentShipsLanguage != language ||
              !identical(_sentNameBundle, nameBundle)) {
            await port.setShips([
              for (final ship in ships.values)
                if (ship.portraitFileName?.isNotEmpty ?? false)
                  {
                    'id': ship.id,
                    'fileName': ship.portraitFileName,
                    'name': catalog.shipName(
                      language,
                      ship.name,
                      shipId: ship.id,
                    ),
                  },
            ]);
            if (_disposed) return;
            if (!_ready) continue;
            _sentShips = ships;
            _sentShipsLanguage = language;
            _sentNameBundle = nameBundle;
          }
          if (processed != _revision) continue;
          final data = catalog.data;
          if (!identical(_sentCatalog, data) ||
              _sentCatalogLanguage != language ||
              (language.usesKc3Quotes &&
                  !identical(_sentCatalogShips, ships))) {
            await port.setCatalog(
              language.usesKc3Quotes
                  ? _withRemodelInheritance(data, ships)
                  : data,
            );
            if (_disposed) return;
            if (!_ready) continue;
            _sentCatalog = data;
            _sentCatalogLanguage = language;
            _sentCatalogShips = ships;
          }
        }
        if (_disposed) return;
        if (!_ready && !_canDisable) return;
        if (processed != _revision) continue;
        final config = <String, Object?>{
          'enabled': _renderingEnabled,
          'fontSize': settings.fontSize.wireName,
          'locked': layout.uiLocked,
          'x': settings.x,
          'y': settings.y,
        };
        if (!mapEquals(config, _sentConfig)) {
          await port.configure(
            enabled: _renderingEnabled,
            fontSize: settings.fontSize,
            locked: layout.uiLocked,
            x: settings.x,
            y: settings.y,
          );
          if (_disposed) return;
          _sentConfig = config;
        }
        if (!_ready) continue;
        if (settings.enabled && !_catalogMatchesLanguage) {
          lastError = catalog.lastError;
          _setStatus(
            catalog.isLoadingLanguage
                ? ShipSubtitleRuntimeStatus.checking
                : ShipSubtitleRuntimeStatus.failed,
          );
          continue;
        }
        lastError = null;
        final hasVoiceFiles = gameState.state.masterShips.values.any(
          (ship) => ship.portraitFileName?.isNotEmpty ?? false,
        );
        _setStatus(
          settings.enabled && !hasVoiceFiles
              ? ShipSubtitleRuntimeStatus.waitingForGameData
              : ShipSubtitleRuntimeStatus.ready,
        );
      } catch (error) {
        if (_disposed || !_ready) return;
        lastError = error;
        _setStatus(ShipSubtitleRuntimeStatus.failed);
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _updateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    settings.removeListener(_onSettingsChanged);
    catalog.removeListener(_onCatalogChanged);
    layout.removeListener(_schedule);
    gameState.removeListener(_onMasterChanged);
    port.dispose();
    super.dispose();
  }
}

/// KC3 stores only changed lines on many remodels. Each ship's own translations
/// override its ancestors; a visited set also supports reversible remodels.
ShipSubtitleCatalog _withRemodelInheritance(
  ShipSubtitleCatalog data,
  Map<int, MasterShip> ships,
) {
  final parents = <int, int>{};
  final ordered = ships.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  for (final ship in ordered) {
    if (ship.afterShipId > 0 && ship.afterShipId != ship.id) {
      parents.putIfAbsent(ship.afterShipId, () => ship.id);
    }
  }
  final quotes = Map<String, Map<String, String>>.of(data.quotes);
  for (final ship in ships.values) {
    final chain = <int>[];
    final visited = <int>{};
    int? id = ship.id;
    while (id != null && visited.add(id)) {
      chain.add(id);
      id = parents[id];
    }
    if (chain.length < 2) continue;
    final inherited = <String, String>{};
    for (final ancestor in chain.reversed) {
      inherited.addAll(data.quotes['$ancestor'] ?? const {});
    }
    if (inherited.isNotEmpty) quotes['${ship.id}'] = inherited;
  }
  return ShipSubtitleCatalog(version: data.version, quotes: quotes);
}
