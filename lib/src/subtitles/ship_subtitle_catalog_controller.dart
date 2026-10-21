// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ship_subtitle_catalog.dart';
import 'ship_subtitle_catalog_store.dart';
import 'ship_subtitle_language.dart';
import 'ship_subtitle_kc3_bundle.dart';
import 'ship_subtitle_kc3_store.dart';
import 'ship_subtitle_kc3_update_service.dart';
import 'ship_subtitle_resource_state.dart';
import 'ship_subtitle_update_service.dart';

typedef ShipSubtitleCatalogSourceLoader =
    Future<ShipSubtitleCatalogSource> Function(ShipSubtitleLanguage language);

/// One language's independent offline data, update client and persisted state.
final class ShipSubtitleCatalogSource {
  const ShipSubtitleCatalogSource({
    required this.data,
    required this.updater,
    this.store,
    this.lastCheckedAt,
  });

  final ShipSubtitleCatalog data;
  final ShipSubtitleUpdateClient updater;
  final ShipSubtitleCatalogStore? store;
  final DateTime? lastCheckedAt;
}

final class ShipSubtitleKc3Source {
  const ShipSubtitleKc3Source({
    required this.bundle,
    required this.updater,
    this.store,
    this.lastCheckedAt,
  });
  final ShipSubtitleKc3Bundle bundle;
  final ShipSubtitleKc3UpdateClient updater;
  final ShipSubtitleKc3Store? store;
  final DateTime? lastCheckedAt;
}

final class ShipSubtitleCatalogController extends ChangeNotifier {
  ShipSubtitleCatalogController({
    required ShipSubtitleCatalog data,
    required ShipSubtitleUpdateClient updater,
    ShipSubtitleCatalogStore? store,
    DateTime Function()? now,
    DateTime? lastCheckedAt,
    ShipSubtitleLanguage language = ShipSubtitleLanguage.simplifiedChinese,
    ShipSubtitleCatalogSourceLoader? languageLoader,
    bool updateAllLanguages = false,
    ShipSubtitleKc3Source? kc3Source,
    ShipSubtitleResourceStateStore? resourceStore,
    ShipSubtitleResourceState resourceState = const ShipSubtitleResourceState(),
  }) : _language = language,
       _dataLanguage = language,
       _lastData = data,
       _languageLoader = languageLoader,
       _updateAllLanguages = updateAllLanguages || kc3Source != null,
       _kc3Updater = kc3Source?.updater,
       _kc3Store = kc3Source?.store,
       _kc3Bundle = kc3Source?.bundle,
       _kc3LastCheckedAt = kc3Source?.lastCheckedAt,
       _resourceStore = resourceStore,
       _resourceState = resourceState,
       _now = now ?? DateTime.now {
    _states[language] = _CatalogState(
      ShipSubtitleCatalogSource(
        data: data,
        updater: updater,
        store: store,
        lastCheckedAt: lastCheckedAt,
      ),
    );
  }

  static Future<ShipSubtitleCatalogController> load({
    ShipSubtitleCatalogStore? store,
    ShipSubtitleUpdateClient? updater,
    DateTime Function()? now,
    ShipSubtitleLanguage language = ShipSubtitleLanguage.simplifiedChinese,
    ShipSubtitleCatalogSourceLoader? languageLoader,
    bool? updateAllLanguages,
    ShipSubtitleKc3Source? kc3Source,
    ShipSubtitleResourceStateStore? resourceStore,
  }) async {
    final production =
        store == null &&
        updater == null &&
        languageLoader == null &&
        kc3Source == null;
    if (production ||
        languageLoader != null ||
        kc3Source != null ||
        updateAllLanguages == true) {
      final client = production ? http.Client() : null;
      try {
        final actualResourceStore =
            resourceStore ??
            (production
                ? await FileShipSubtitleResourceStateStore.create()
                : null);
        var resourceState =
            await actualResourceStore?.load() ??
            const ShipSubtitleResourceState();
        final ShipSubtitleKc3Source? actualKc3;
        if (kc3Source != null) {
          actualKc3 = kc3Source;
        } else if (production) {
          final kc3Store = await FileShipSubtitleKc3Store.create();
          actualKc3 = ShipSubtitleKc3Source(
            bundle: await kc3Store.loadBestAvailable(),
            updater: ShipSubtitleKc3UpdateService(
              client: client!,
              store: kc3Store,
            ),
            store: kc3Store,
            lastCheckedAt: await kc3Store.loadLastCheckedAt(),
          );
        } else {
          actualKc3 = null;
        }
        final readLanguage = _offlineSourceLoader(
          production: production,
          initialLanguage: language,
          languageLoader: languageLoader,
          store: store,
          updater: updater,
          client: client,
        );

        final offlineSources =
            <ShipSubtitleLanguage, ShipSubtitleCatalogSource>{};
        Future<ShipSubtitleCatalogSource> loadLanguage(
          ShipSubtitleLanguage target,
        ) async => offlineSources[target] ??= await readLanguage(target);

        // An APK can contain a newer complete group than a previous download.
        // Compare all three languages together so an offline upgrade cannot
        // retain an older cache or mix versions from separate snapshots.
        if (resourceState.catalogs.isNotEmpty) {
          final available = await Future.wait(
            kcwikiSubtitleLanguages.map(loadLanguage),
          );
          resourceState = resourceState.withBestOfflineCatalogs({
            for (var i = 0; i < available.length; i++)
              kcwikiSubtitleLanguages[i]: available[i].data,
          });
        }
        final selectedKc3 = actualKc3?.bundle.catalogFor(language);
        final source = selectedKc3 == null
            ? await loadLanguage(language)
            : ShipSubtitleCatalogSource(
                data: selectedKc3,
                updater: const _BundleOnlySubtitleUpdater(),
              );
        final controller = ShipSubtitleCatalogController(
          data: resourceState.catalogs[language] ?? source.data,
          updater: source.updater,
          store: source.store,
          lastCheckedAt: source.lastCheckedAt,
          language: language,
          languageLoader: readLanguage,
          now: now,
          updateAllLanguages: updateAllLanguages ?? true,
          kc3Source: actualKc3,
          resourceStore: actualResourceStore,
          resourceState: resourceState,
        );
        controller._ownedClient = client;
        // Only the winning catalogs stay owned by the controller. Keeping the
        // temporary loader's memoized sources would retain discarded bundled
        // data, and later retain the startup data after an online update.
        for (final entry in offlineSources.entries) {
          controller._states.putIfAbsent(entry.key, () {
            final state = _CatalogState(entry.value);
            state.data = resourceState.catalogs[entry.key] ?? state.data;
            return state;
          });
        }
        // The first metadata row stays available with either KC3 quote language.
        if (language.usesKc3Quotes) {
          await controller._stateFor(ShipSubtitleLanguage.simplifiedChinese);
        }
        return controller;
      } on Object {
        client?.close();
        rethrow;
      }
    }
    http.Client? client;
    final ShipSubtitleCatalogSource source;
    if (languageLoader != null && store == null && updater == null) {
      source = await languageLoader(language);
    } else {
      final actualStore =
          store ??
          await FileShipSubtitleCatalogStore.create(language: language);
      final data = await actualStore.loadBestAvailable();
      final checked = await actualStore.loadLastCheckedAt();
      client = updater == null ? http.Client() : null;
      source = ShipSubtitleCatalogSource(
        data: data,
        updater:
            updater ??
            ShipSubtitleUpdateService(
              client: client!,
              store: actualStore,
              language: language,
            ),
        store: actualStore,
        lastCheckedAt: checked,
      );
    }
    return ShipSubtitleCatalogController(
      data: source.data,
      updater: source.updater,
      store: source.store,
      lastCheckedAt: source.lastCheckedAt,
      language: language,
      languageLoader: languageLoader,
      now: now,
    ).._ownedClient = client;
  }

  final _states = <ShipSubtitleLanguage, _CatalogState>{};
  final _pendingLoads = <ShipSubtitleLanguage, Future<_CatalogState>>{};
  final ShipSubtitleCatalogSourceLoader? _languageLoader;
  final bool _updateAllLanguages;
  final ShipSubtitleKc3UpdateClient? _kc3Updater;
  final ShipSubtitleKc3Store? _kc3Store;
  ShipSubtitleKc3Bundle? _kc3Bundle;
  DateTime? _kc3LastCheckedAt;
  final ShipSubtitleResourceStateStore? _resourceStore;
  ShipSubtitleResourceState _resourceState;
  Future<ShipSubtitleUpdateResult>? _activeResourceCheck;
  Object? _resourceError;
  ShipSubtitleUpdateResult? _resourceResult;
  final DateTime Function() _now;
  ShipSubtitleLanguage _language;
  ShipSubtitleLanguage _dataLanguage;
  ShipSubtitleCatalog _lastData;
  bool _isLoadingLanguage = false;
  Object? _loadError;
  int _selection = 0;
  bool _disposed = false;
  http.Client? _ownedClient;

  /// The requested language; dataLanguage identifies the data actually loaded.
  ShipSubtitleLanguage get language => _language;
  ShipSubtitleLanguage get dataLanguage => _dataLanguage;
  bool get isLoadingLanguage => _isLoadingLanguage;
  bool get isLanguageReady => !_isLoadingLanguage && _dataLanguage == _language;
  _CatalogState? get _selectedState =>
      isLanguageReady ? _states[_language] : null;
  ShipSubtitleCatalog get data => isLanguageReady
      ? _kc3Bundle?.catalogFor(_language) ?? _selectedState?.data ?? _lastData
      : _lastData;
  ShipSubtitleKc3Bundle? get kc3Bundle => _kc3Bundle;
  String shipName(
    ShipSubtitleLanguage language,
    String rawName, {
    int? shipId,
  }) => _kc3Bundle?.shipName(language, rawName, shipId: shipId) ?? rawName;
  String get kcwikiVersion {
    final catalogs = _resourceState.catalogs.isNotEmpty
        ? _resourceState.catalogs.values
        : _states.entries
              .where((entry) => !entry.key.usesKc3Quotes)
              .map((entry) => entry.value.data);
    final versions = catalogs.map((catalog) => catalog.version).toList()
      ..sort();
    return versions.isEmpty ? '' : versions.first;
  }

  DateTime? get kcwikiLastCheckedAt => _updateAllLanguages
      ? _resourceState.kcwikiLastCheckedAt
      : _states.entries
            .where((entry) => !entry.key.usesKc3Quotes)
            .map((entry) => entry.value.lastCheckedAt)
            .whereType<DateTime>()
            .firstOrNull;
  String get kc3Version =>
      _kc3Bundle?.version ??
      _states[ShipSubtitleLanguage.english]?.data.version ??
      _states[ShipSubtitleLanguage.korean]?.data.version ??
      '';
  DateTime? get kc3LastCheckedAt =>
      _kc3LastCheckedAt ??
      _states[ShipSubtitleLanguage.english]?.lastCheckedAt ??
      _states[ShipSubtitleLanguage.korean]?.lastCheckedAt;
  DateTime? get lastCheckedAt => _updateAllLanguages
      ? (_language.usesKc3Quotes ? kc3LastCheckedAt : kcwikiLastCheckedAt)
      : _selectedState?.lastCheckedAt;
  bool get isChecking => _updateAllLanguages
      ? _activeResourceCheck != null
      : _selectedState?.activeCheck != null;
  Object? get lastError =>
      _loadError ??
      (_updateAllLanguages ? _resourceError : _selectedState?.lastError);
  ShipSubtitleUpdateResult? get lastResult =>
      _updateAllLanguages ? _resourceResult : _selectedState?.lastResult;

  Future<void> selectLanguage(ShipSubtitleLanguage language) async {
    if (_disposed || (language == _language && isLanguageReady)) return;
    final selection = ++_selection;
    _language = language;
    _loadError = null;
    _isLoadingLanguage = true;
    notifyListeners();
    try {
      final state = await _stateFor(language);
      if (_disposed || selection != _selection) return;
      _dataLanguage = language;
      _lastData = state.data;
    } on Object catch (error) {
      if (!_disposed && selection == _selection) _loadError = error;
    } finally {
      if (!_disposed && selection == _selection) {
        _isLoadingLanguage = false;
        notifyListeners();
      }
    }
  }

  Future<_CatalogState> _stateFor(ShipSubtitleLanguage language) {
    final state = _states[language];
    if (state != null) return Future.value(state);
    // Schedule after registration so even a synchronously throwing loader is
    // removed from the pending map and can be retried.
    return _pendingLoads[language] ??= Future<_CatalogState>.microtask(
      () => _loadState(language),
    );
  }

  Future<_CatalogState> _loadState(ShipSubtitleLanguage language) async {
    try {
      final loader = _languageLoader;
      final ShipSubtitleCatalogSource source;
      final bundled = _kc3Bundle?.catalogFor(language);
      if (bundled != null) {
        source = ShipSubtitleCatalogSource(
          data: bundled,
          updater: const _BundleOnlySubtitleUpdater(),
        );
      } else if (loader != null) {
        source = await loader(language);
      } else {
        final store = await FileShipSubtitleCatalogStore.create(
          language: language,
        );
        final data = await store.loadBestAvailable();
        final checked = await store.loadLastCheckedAt();
        if (_disposed) throw StateError('Subtitle controller is disposed.');
        source = ShipSubtitleCatalogSource(
          data: data,
          updater: ShipSubtitleUpdateService(
            client: _ownedClient ??= http.Client(),
            store: store,
            language: language,
          ),
          store: store,
          lastCheckedAt: checked,
        );
      }
      final state = _CatalogState(source);
      state.data = _resourceState.catalogs[language] ?? state.data;
      return _states[language] = state;
    } finally {
      _pendingLoads.remove(language);
    }
  }

  /// The caller invokes this only when subtitles are enabled and data is ready.
  Future<void> checkIfDue() async {
    if (_updateAllLanguages) {
      if (!_disposed) await checkForUpdates(force: false);
      return;
    }
    if (!isLanguageReady || _disposed) return;
    final checked = lastCheckedAt;
    if (checked != null &&
        _now().toUtc().difference(checked) < const Duration(hours: 24)) {
      return;
    }
    await checkForUpdates(force: false);
  }

  /// Manual checks intentionally bypass this language's daily check limit.
  Future<ShipSubtitleUpdateResult> checkForUpdates({bool force = true}) {
    if (_updateAllLanguages && !_disposed) {
      final active = _activeResourceCheck;
      if (active != null) return active;
      final operation = Future<ShipSubtitleUpdateResult>.microtask(
        () => _performResourceCheck(force: force),
      );
      _activeResourceCheck = operation;
      notifyListeners();
      return operation;
    }
    final state = _selectedState;
    if (state == null || _disposed) {
      return Future.value(
        ShipSubtitleUpdateFailed(
          ShipSubtitleUpdateFailure.storage,
          _loadError ?? StateError('Subtitle language is not ready.'),
          sourceHost: '',
        ),
      );
    }
    final active = state.activeCheck;
    if (active != null) return active;
    final checked = state.lastCheckedAt;
    if (!force &&
        checked != null &&
        _now().toUtc().difference(checked) < const Duration(hours: 24)) {
      return Future.value(ShipSubtitleUpToDate(state.data, sourceHost: ''));
    }
    final operation = _performCheck(state);
    state.activeCheck = operation;
    notifyListeners();
    return operation;
  }

  bool _due(DateTime? attempt) =>
      attempt == null ||
      _now().toUtc().difference(attempt) >= const Duration(hours: 24);

  Future<ShipSubtitleUpdateResult> _performResourceCheck({
    required bool force,
  }) async {
    try {
      final checkKcwiki = force || _due(_resourceState.kcwikiLastAttemptAt);
      final checkKc3 =
          _kc3Updater != null &&
          (force || _due(_resourceState.kc3LastAttemptAt));
      if (!checkKcwiki && !checkKc3) {
        return _resourceResult ?? ShipSubtitleUpToDate(data, sourceHost: '');
      }
      final time = _now().toUtc();
      final attempted = _resourceState.copyWith(
        kcwikiLastAttemptAt: checkKcwiki ? time : null,
        kc3LastAttemptAt: checkKc3 ? time : null,
      );
      try {
        await _resourceStore?.save(attempted);
        _resourceState = attempted;
      } on Object catch (error) {
        final result = ShipSubtitleUpdateFailed(
          ShipSubtitleUpdateFailure.storage,
          error,
          sourceHost: '',
        );
        _resourceError = error;
        return _resourceResult = result;
      }
      final previousKc3Bundle = _kc3Bundle;
      final results = await Future.wait([
        if (checkKcwiki) _checkKcwikiGroup(time),
        if (checkKc3) _checkKc3Group(time),
      ]);
      final failures = results.whereType<ShipSubtitleUpdateFailed>().toList();
      if (failures.isNotEmpty) {
        _resourceError = ShipSubtitleResourceUpdateError(
          failures.map((failure) => failure.error).toList(),
          hasSuccessfulGroup:
              results.any((result) => result is! ShipSubtitleUpdateFailed) ||
              !identical(previousKc3Bundle, _kc3Bundle),
        );
        return _resourceResult = ShipSubtitleUpdateFailed(
          failures.first.kind,
          _resourceError!,
          sourceHost: failures.first.sourceHost,
        );
      }
      _resourceError = null;
      return _resourceResult =
          results.any((result) => result is ShipSubtitleUpdated)
          ? ShipSubtitleUpdated(data, sourceHost: '')
          : ShipSubtitleUpToDate(data, sourceHost: '');
    } finally {
      _activeResourceCheck = null;
      if (!_disposed) notifyListeners();
    }
  }

  Future<ShipSubtitleUpdateResult> _checkKcwikiGroup(DateTime checkedAt) async {
    try {
      final states = await Future.wait(kcwikiSubtitleLanguages.map(_stateFor));
      // A CDN can return individually valid files from different snapshots.
      // Retry the entire source so independent language fallback cannot leave
      // the group stuck with incompatible candidates or persist a partial set.
      final sourceHosts =
          states.every((state) => state.updater is ShipSubtitleUpdateService)
          ? ShipSubtitleUpdateService.sourceHosts
          : const <String?>[null];
      var results = <ShipSubtitleUpdateResult>[];
      var catalogs = <ShipSubtitleLanguage, ShipSubtitleCatalog>{};
      ShipSubtitleUpdateFailed? failed;
      for (final host in sourceHosts) {
        results = await Future.wait(
          states.map((state) async {
            try {
              return host == null
                  ? await state.updater.checkAndUpdate(current: state.data)
                  : await (state.updater as ShipSubtitleUpdateService)
                        .checkKcwikiSource(
                          current: state.data,
                          sourceHost: host,
                        );
            } on Object catch (error) {
              return ShipSubtitleUpdateFailed(
                ShipSubtitleUpdateFailure.network,
                error,
                sourceHost: host ?? '',
              );
            }
          }),
        );
        failed = results.whereType<ShipSubtitleUpdateFailed>().firstOrNull;
        if (failed != null) continue;
        catalogs = {
          for (var i = 0; i < states.length; i++)
            kcwikiSubtitleLanguages[i]: switch (results[i]) {
              ShipSubtitleUpdated(:final catalog) => catalog,
              ShipSubtitleUpToDate(:final catalog) => catalog,
              ShipSubtitleUpdateFailed() => throw StateError(
                'Unreachable failed subtitle update.',
              ),
            },
        };
        if (catalogs.values.map((catalog) => catalog.version).toSet().length !=
            1) {
          failed = ShipSubtitleUpdateFailed(
            ShipSubtitleUpdateFailure.validation,
            const FormatException(
              'The kcwiki subtitle files have different versions.',
            ),
            sourceHost: host ?? '',
          );
          continue;
        }
        break;
      }
      if (failed != null) return failed;
      final snapshot = _resourceState.copyWith(
        catalogs: Map.unmodifiable(catalogs),
        kcwikiLastCheckedAt: checkedAt,
      );
      try {
        if (_resourceStore != null) {
          await _resourceStore.save(snapshot);
        } else {
          for (var i = 0; i < states.length; i++) {
            if (results[i] is ShipSubtitleUpdated) {
              await states[i].store?.save(
                catalogs[kcwikiSubtitleLanguages[i]]!,
              );
            }
          }
          for (final state in states) {
            await state.store?.saveLastCheckedAt(checkedAt);
          }
        }
      } on Object catch (error) {
        return ShipSubtitleUpdateFailed(
          ShipSubtitleUpdateFailure.storage,
          error,
          sourceHost: '',
        );
      }
      _resourceState = snapshot;
      for (var i = 0; i < states.length; i++) {
        states[i].data = catalogs[kcwikiSubtitleLanguages[i]]!;
        states[i].lastCheckedAt = checkedAt;
      }
      if (isLanguageReady) _lastData = data;
      if (!_disposed) notifyListeners();
      return results.any((result) => result is ShipSubtitleUpdated)
          ? ShipSubtitleUpdated(data, sourceHost: '')
          : ShipSubtitleUpToDate(data, sourceHost: '');
    } on Object catch (error) {
      return ShipSubtitleUpdateFailed(
        ShipSubtitleUpdateFailure.storage,
        error,
        sourceHost: '',
      );
    }
  }

  Future<ShipSubtitleUpdateResult> _checkKc3Group(DateTime checkedAt) async {
    try {
      final result = await _kc3Updater!.checkAndUpdate(current: _kc3Bundle!);
      if (result is ShipSubtitleKc3UpdateFailed) {
        return ShipSubtitleUpdateFailed(
          result.kind,
          result.error,
          sourceHost: result.sourceHost,
        );
      }
      final bundle = switch (result) {
        ShipSubtitleKc3Updated(:final bundle) => bundle,
        ShipSubtitleKc3UpToDate(:final bundle) => bundle,
        ShipSubtitleKc3UpdateFailed() => throw StateError(
          'Unreachable failed KC3 update.',
        ),
      };
      // The updater has already saved the validated bundle. Publish it even
      // when the independent check timestamp cannot be written.
      _kc3Bundle = bundle;
      for (final entry in _states.entries) {
        final bundled = bundle.catalogFor(entry.key);
        if (bundled != null) entry.value.data = bundled;
      }
      if (isLanguageReady) _lastData = data;
      if (!_disposed) notifyListeners();
      try {
        await _kc3Store?.saveLastCheckedAt(checkedAt);
      } on Object catch (error) {
        return ShipSubtitleUpdateFailed(
          ShipSubtitleUpdateFailure.storage,
          error,
          sourceHost: result.sourceHost,
        );
      }
      _kc3LastCheckedAt = checkedAt;
      if (!_disposed) notifyListeners();
      return result is ShipSubtitleKc3Updated
          ? ShipSubtitleUpdated(data, sourceHost: result.sourceHost)
          : ShipSubtitleUpToDate(data, sourceHost: result.sourceHost);
    } on Object catch (error) {
      return ShipSubtitleUpdateFailed(
        ShipSubtitleUpdateFailure.network,
        error,
        sourceHost: '',
      );
    }
  }

  Future<ShipSubtitleUpdateResult> _performCheck(_CatalogState state) async {
    try {
      ShipSubtitleUpdateResult result;
      try {
        result = await state.updater.checkAndUpdate(current: state.data);
      } on Object catch (error) {
        result = ShipSubtitleUpdateFailed(
          ShipSubtitleUpdateFailure.network,
          error,
          sourceHost: '',
        );
      }
      state.lastResult = result;
      state.lastCheckedAt = _now().toUtc();
      state.lastError = result is ShipSubtitleUpdateFailed
          ? result.error
          : null;
      if (result is ShipSubtitleUpdated &&
          result.catalog.version.compareTo(state.data.version) > 0) {
        state.data = result.catalog;
      }
      try {
        await state.store?.saveLastCheckedAt(state.lastCheckedAt!);
      } on Object catch (error) {
        state.lastError ??= error;
      }
      return result;
    } finally {
      state.activeCheck = null;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ownedClient?.close();
    super.dispose();
  }
}

final class _CatalogState {
  _CatalogState(ShipSubtitleCatalogSource source)
    : data = source.data,
      updater = source.updater,
      store = source.store,
      lastCheckedAt = source.lastCheckedAt;

  ShipSubtitleCatalog data;
  final ShipSubtitleUpdateClient updater;
  final ShipSubtitleCatalogStore? store;
  DateTime? lastCheckedAt;
  Future<ShipSubtitleUpdateResult>? activeCheck;
  ShipSubtitleUpdateResult? lastResult;
  Object? lastError;
}

// Build the persistent loader in its own scope: it must not capture startup
// bundles, the temporary source cache, or catalogs discarded during comparison.
ShipSubtitleCatalogSourceLoader _offlineSourceLoader({
  required bool production,
  required ShipSubtitleLanguage initialLanguage,
  required ShipSubtitleCatalogSourceLoader? languageLoader,
  required ShipSubtitleCatalogStore? store,
  required ShipSubtitleUpdateClient? updater,
  required http.Client? client,
}) => (target) async {
  if (languageLoader != null) return languageLoader(target);
  if (!production &&
      target == initialLanguage &&
      store != null &&
      updater != null) {
    return ShipSubtitleCatalogSource(
      data: await store.loadBestAvailable(),
      updater: updater,
      store: store,
      lastCheckedAt: await store.loadLastCheckedAt(),
    );
  }
  if (!production) {
    throw StateError(
      'A source loader is required for every subtitle language.',
    );
  }
  final actualStore = await FileShipSubtitleCatalogStore.create(
    language: target,
  );
  final data = await compute(
    ShipSubtitleCatalog.fromJsonString,
    await actualStore.bundledReader(),
  );
  return ShipSubtitleCatalogSource(
    data: data,
    updater: ShipSubtitleUpdateService(
      client: client!,
      store: _StagingSubtitleCatalogStore(actualStore),
      language: target,
    ),
    store: actualStore,
  );
};

final class ShipSubtitleResourceUpdateError {
  const ShipSubtitleResourceUpdateError(
    this.errors, {
    this.hasSuccessfulGroup = false,
  });
  final List<Object> errors;
  final bool hasSuccessfulGroup;
  @override
  String toString() =>
      'Some subtitle resources could not be updated: ${errors.join('; ')}';
}

final class _BundleOnlySubtitleUpdater implements ShipSubtitleUpdateClient {
  const _BundleOnlySubtitleUpdater();
  @override
  Future<ShipSubtitleUpdateResult> checkAndUpdate({
    required ShipSubtitleCatalog current,
  }) => throw StateError(
    'KC3 quote languages are updated with the complete KC3 bundle.',
  );
}

/// The existing HTTP validator can download each language, while publication
/// belongs to the controller's single kcwiki group transaction.
final class _StagingSubtitleCatalogStore implements ShipSubtitleCatalogStore {
  const _StagingSubtitleCatalogStore(this.delegate);
  final ShipSubtitleCatalogStore delegate;
  @override
  Future<ShipSubtitleCatalog> loadBestAvailable() =>
      delegate.loadBestAvailable();
  @override
  Future<DateTime?> loadLastCheckedAt() => delegate.loadLastCheckedAt();
  @override
  Future<void> save(ShipSubtitleCatalog catalog) async {}
  @override
  Future<void> saveLastCheckedAt(DateTime value) async {}
}
