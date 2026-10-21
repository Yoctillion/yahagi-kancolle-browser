import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../account/account_session.dart';
import 'senka_state.dart';

abstract interface class SenkaStore {
  Future<SenkaState?> load();
  Future<void> save(SenkaState state);
}

abstract interface class AccountSenkaStore implements SenkaStore {
  Future<SenkaState?> loadForAccount(int memberId);
}

abstract interface class SenkaBackupStore {
  Future<void> get idle;
  Stream<int> get archiveChanges;
  Future<String?> readArchiveForAccount(int memberId);
  Future<void> restoreArchiveForAccount(int memberId, String? raw);
}

void validateSenkaArchiveRaw(String raw, int memberId) {
  final value = jsonDecode(raw);
  if (memberId <= 0 || value is! Map || value['memberId'] != memberId) {
    throw const FormatException('Senka archive belongs to another account');
  }
}

class SharedPreferencesSenkaStore
    implements AccountSenkaStore, SenkaBackupStore {
  SharedPreferencesSenkaStore(
    this.preferences, {
    AccountSession? accountSession,
  }) : accountSession = accountSession ?? AccountSession.shared;

  static const _key = 'senka.archive.v1';
  final SharedPreferences preferences;
  final AccountSession accountSession;
  Future<void> _writes = Future<void>.value();
  bool _cacheNeedsReload = false;
  final _archiveChanges = StreamController<int>.broadcast(sync: true);

  @override
  Stream<int> get archiveChanges => _archiveChanges.stream;

  @override
  Future<void> get idle async {
    while (true) {
      final pending = _writes;
      await pending;
      if (identical(pending, _writes)) return;
    }
  }

  static Future<SharedPreferencesSenkaStore> create({
    AccountSession? accountSession,
  }) async => SharedPreferencesSenkaStore(
    await SharedPreferences.getInstance(),
    accountSession: accountSession,
  );

  @override
  Future<SenkaState?> load() => loadForAccount(accountSession.current.memberId);

  @override
  Future<SenkaState?> loadForAccount(int memberId) async {
    if (memberId <= 0) return null;
    await _reloadIfNeeded();
    final key = AccountScope(memberId: memberId, generation: 0).key(_key);
    final raw = preferences.getString(key) ?? preferences.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final state = SenkaState.fromJson(jsonDecode(raw));
      if (state.memberId != memberId) return null;
      await _serializeWrite(() async {
        // Preserve the exact pre-migration JSON, including fields this version
        // may not understand. This backup is written once and never replaced.
        await _preserveRaw(key, preferences.getString(key) ?? raw);
        if (preferences.containsKey(key)) return;
        // The legacy archive identifies its owner. Keep the original as a
        // backup, and never assign anonymous archives to the first login.
        await _writeString(key, raw);
        _archiveChanges.add(memberId);
      });
      return state;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(SenkaState state) async {
    if (state.memberId <= 0) return;
    final key = AccountScope(memberId: state.memberId, generation: 0).key(_key);
    final raw = jsonEncode(state.toJson());
    await _serializeWrite(() async {
      await _reloadIfNeeded();
      final previous = preferences.getString(key);
      if (previous != null && previous.isNotEmpty) {
        await _preserveRaw(key, previous);
      }
      await _writeString(key, raw);
      _archiveChanges.add(state.memberId);
    });
  }

  @override
  Future<String?> readArchiveForAccount(int memberId) async {
    if (memberId <= 0) return null;
    await idle;
    await _reloadIfNeeded();
    final key = AccountScope(memberId: memberId, generation: 0).key(_key);
    final owned = preferences.getString(key);
    final raw = owned ?? preferences.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('Invalid senka archive');
    // Only an explicitly namespaced old archive can establish this ownership.
    // An anonymous global legacy value remains untouched until identified.
    if (owned != null &&
        (decoded['memberId'] == null || decoded['memberId'] == 0)) {
      return jsonEncode({...decoded, 'memberId': memberId});
    }
    if (owned == null && decoded['memberId'] != memberId) return null;
    validateSenkaArchiveRaw(raw, memberId);
    return raw;
  }

  @override
  Future<void> restoreArchiveForAccount(int memberId, String? raw) async {
    if (memberId <= 0) throw StateError('Game account is not verified');
    if (raw != null) validateSenkaArchiveRaw(raw, memberId);
    final key = AccountScope(memberId: memberId, generation: 0).key(_key);
    await _serializeWrite(() async {
      await _reloadIfNeeded();
      final previous = preferences.getString(key);
      if (previous != null && previous.isNotEmpty) {
        await _preserveRaw(key, previous);
        await _preserveRestoreSnapshot(key, previous);
      }
      if (raw == null) {
        try {
          if (!await preferences.remove(key)) {
            throw StateError('Senka archive removal was rejected');
          }
        } catch (error, stackTrace) {
          _cacheNeedsReload = true;
          try {
            await _reloadIfNeeded();
          } catch (_) {}
          Error.throwWithStackTrace(error, stackTrace);
        }
      } else {
        await _preserveRestoreSnapshot(key, raw);
        await _writeString(key, raw);
      }
      _archiveChanges.add(memberId);
    });
  }

  Future<void> _preserveRestoreSnapshot(String key, String raw) async {
    final snapshotKey = '$key.raw.${sha256.convert(utf8.encode(raw))}';
    final existing = preferences.getString(snapshotKey);
    if (existing != null) {
      if (existing != raw) throw StateError('Senka recovery snapshot mismatch');
      return;
    }
    await _writeString(snapshotKey, raw);
  }

  Future<void> _preserveRaw(String key, String raw) async {
    final backupKey = '$key.raw-backup';
    if (!preferences.containsKey(backupKey)) {
      await _writeString(backupKey, raw);
    }
  }

  Future<void> _writeString(String key, String raw) async {
    try {
      if (await preferences.setString(key, raw)) return;
      throw StateError('Senka preference write was rejected: $key');
    } catch (error, stackTrace) {
      // The legacy preferences API changes its cache before native storage
      // completes. Reload on rejection or exception so a failed write cannot
      // masquerade as an archive, while retaining the original write error.
      _cacheNeedsReload = true;
      try {
        await _reloadIfNeeded();
      } catch (_) {
        // A failed reload must not turn the original write into a success.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _reloadIfNeeded() async {
    if (!_cacheNeedsReload) return;
    await preferences.reload();
    _cacheNeedsReload = false;
  }

  Future<void> _serializeWrite(Future<void> Function() operation) {
    final next = _writes.then((_) => operation());
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }
}
