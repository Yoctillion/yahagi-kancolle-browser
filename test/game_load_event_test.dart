import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_load_event.dart';

void main() {
  test(
    'page categories discard query credentials and private path details',
    () {
      expect(
        classifyGamePage(
          Uri.parse(
            'https://accounts.dmm.com/service/login/password?token=secret',
          ),
        ),
        GamePageCategory.login,
      );
      expect(
        classifyGamePage(
          Uri.parse('https://play.games.dmm.com/game/kancolle?token=secret'),
        ),
        GamePageCategory.gameEntry,
      );
      expect(
        classifyGamePage(
          Uri.parse(
            'https://w01p.kancolle-server.com/kcs2/index.html?token=secret',
          ),
        ),
        GamePageCategory.gameServer,
      );
      expect(
        classifyGamePage(Uri.parse('https://ooi.moe/?password=secret')),
        GamePageCategory.ooi,
      );
      expect(
        classifyGamePage(
          Uri.parse('https://dmm.com.evil.example/game/kancolle'),
        ),
        GamePageCategory.other,
      );
    },
  );

  test('load events serialize only fixed diagnostic fields', () {
    const event = GameLoadEvent(
      phase: GameLoadPhase.failed,
      navigationEpoch: 5,
      durationMs: 2400,
      pageCategory: GamePageCategory.gameEntry,
      errorCode: -2,
    );
    expect(event.toMap(), <String, Object>{
      'phase': 'failed',
      'navigationEpoch': 5,
      'durationMs': 2400,
      'pageCategory': 'gameEntry',
      'errorCode': -2,
    });
  });

  test('main frame attribution is included only when supplied', () {
    const event = GameLoadEvent(
      phase: GameLoadPhase.failed,
      navigationEpoch: 5,
      durationMs: 2400,
      pageCategory: GamePageCategory.gameEntry,
      errorCode: -2,
      isMainFrame: false,
    );
    expect(event.toMap()['isMainFrame'], false);
  });
}
