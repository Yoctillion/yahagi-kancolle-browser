enum GameLoadPhase {
  navigationStarted,
  documentFinished,
  loginVisible,
  gameDetected,
  bodyWaiting,
  visible,
  timedOut,
  failed,
  retry,
}

enum GamePageCategory { login, gameEntry, gameServer, ooi, other }

/// Fixed, privacy-safe lifecycle fields. No address or error description is kept.
final class GameLoadEvent {
  const GameLoadEvent({
    required this.phase,
    required this.navigationEpoch,
    required this.durationMs,
    required this.pageCategory,
    this.errorCode,
    this.isMainFrame,
  });

  final GameLoadPhase phase;
  final int navigationEpoch;
  final int durationMs;
  final GamePageCategory pageCategory;
  final int? errorCode;
  final bool? isMainFrame;

  Map<String, Object> toMap() => <String, Object>{
    'phase': phase.name,
    'navigationEpoch': navigationEpoch,
    'durationMs': durationMs,
    'pageCategory': pageCategory.name,
    'errorCode': ?errorCode,
    'isMainFrame': ?isMainFrame,
  };
}

GamePageCategory classifyGamePage(Uri? uri) {
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return GamePageCategory.other;
  }
  final host = uri.host.toLowerCase();
  final path = uri.path.toLowerCase();
  if (host == 'accounts.dmm.com' ||
      ((host == 'www.dmm.com' || host == 'www.dmm.co.jp') &&
          (path.contains('/login') || path.contains('/auth')))) {
    return GamePageCategory.login;
  }
  if (host == 'ooi.moe') return GamePageCategory.ooi;
  if (host == 'kancolle-server.com' || host.endsWith('.kancolle-server.com')) {
    return GamePageCategory.gameServer;
  }
  if ((host == 'play.games.dmm.com' && path.startsWith('/game/kancolle')) ||
      (host == 'www.dmm.com' &&
          path.startsWith('/netgame/social/-/gadgets/=/app_id=854854'))) {
    return GamePageCategory.gameEntry;
  }
  return GamePageCategory.other;
}
