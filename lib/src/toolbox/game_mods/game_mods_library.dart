/// Public, user-owned storage is independent of the validated runtime copy.
class GameModLibraryStatus {
  const GameModLibraryStatus({
    this.configured = false,
    this.available = false,
    this.displayName = '',
    this.uri,
    this.error,
    this.packageCount = 0,
    this.lastScan,
  });
  final bool configured, available;
  final String displayName;
  final String? uri, error;
  final int packageCount;
  final Object? lastScan;

  factory GameModLibraryStatus.fromMap(Map<String, dynamic> map) =>
      GameModLibraryStatus(
        configured: map['configured'] == true,
        available: map['available'] == true,
        displayName: map['displayName'] as String? ?? '',
        uri: map['uri'] as String?,
        error: map['error'] as String?,
        packageCount: (map['packageCount'] as num?)?.toInt() ?? 0,
        lastScan: map['lastScan'],
      );

  Map<String, dynamic> toMap() => {
    'configured': configured,
    'available': available,
    'displayName': displayName,
    'uri': uri,
    'error': error,
    'packageCount': packageCount,
    'lastScan': lastScan,
  };
}

enum GameModLibraryEntryKind {
  added,
  updated,
  unchanged,
  duplicate,
  missing,
  invalid,
}

class GameModLibraryEntry {
  const GameModLibraryEntry({
    required this.id,
    required this.name,
    required this.kind,
    this.reason,
    this.detail,
    this.resourceCount = 0,
    this.supportedCount = 0,
    this.unsupportedCount = 0,
  });
  final String id, name;
  final GameModLibraryEntryKind kind;
  final String? reason, detail;
  final int resourceCount, supportedCount, unsupportedCount;

  bool get importable =>
      kind == GameModLibraryEntryKind.added ||
      kind == GameModLibraryEntryKind.updated;

  factory GameModLibraryEntry.fromMap(Map<String, dynamic> map) =>
      GameModLibraryEntry(
        id: map['id'] as String? ?? '',
        name: map['name'] as String? ?? '',
        kind: map['kind'] == 'new'
            ? GameModLibraryEntryKind.added
            : GameModLibraryEntryKind.values.firstWhere(
                (kind) => kind.name == map['kind'],
                orElse: () => GameModLibraryEntryKind.invalid,
              ),
        reason: map['reason'] as String?,
        detail: map['detail'] as String?,
        resourceCount: (map['resourceCount'] as num?)?.toInt() ?? 0,
        supportedCount: (map['supportedCount'] as num?)?.toInt() ?? 0,
        unsupportedCount: (map['unsupportedCount'] as num?)?.toInt() ?? 0,
      );
}

class GameModLibraryScan {
  const GameModLibraryScan({
    required this.token,
    this.entries = const [],
    this.restoreAvailable = false,
    this.cleanupCount = 0,
  });
  final String token;
  final List<GameModLibraryEntry> entries;
  final bool restoreAvailable;
  final int cleanupCount;
  bool get hasChanges =>
      restoreAvailable || cleanupCount > 0 || entries.any((e) => e.importable);
  int count(GameModLibraryEntryKind kind) =>
      entries.where((e) => e.kind == kind).length;

  factory GameModLibraryScan.fromMap(Map<String, dynamic> map) =>
      GameModLibraryScan(
        token: map['token'] as String? ?? '',
        entries: (map['entries'] as List? ?? [])
            .whereType<Map>()
            .map(
              (entry) => GameModLibraryEntry.fromMap(
                entry.map((key, value) => MapEntry(key.toString(), value)),
              ),
            )
            .toList(growable: false),
        restoreAvailable: map['restoreAvailable'] == true,
        cleanupCount: (map['cleanupCount'] as num?)?.toInt() ?? 0,
      );
}
