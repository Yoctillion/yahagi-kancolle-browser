import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/account/account_session.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';

CapturedApiEvent _identityEvent({
  String path = '/kcsapi/api_port/port',
  int memberId = 1001,
  String? nickname = 'Admiral',
  String origin = 'https://game.example',
}) {
  final basic = <String, Object?>{
    'api_member_id': memberId,
    'api_nickname': ?nickname,
  };
  return CapturedApiEvent(
    path: path,
    responseBody: '',
    decodedEnvelope: {
      'api_result': 1,
      'api_data': path == '/kcsapi/api_port/port'
          ? <String, Object?>{'api_basic': basic}
          : basic,
    },
    source: CaptureSource.manual,
    sourceOrigin: origin,
    capturedAt: DateTime.utc(2026, 10, 17),
  );
}

void main() {
  test('identical port responses notify account listeners only once', () {
    final session = AccountSession();
    addTearDown(session.dispose);
    var notifications = 0;
    session.addListener(() => notifications++);

    session.accept(_identityEvent());
    final scope = session.current;
    for (var index = 0; index < 100; index++) {
      session.accept(_identityEvent(nickname: ' Admiral '));
    }

    expect(notifications, 1);
    expect(session.current, same(scope));
    expect(session.admiralName, 'Admiral');
    expect(session.serverName, 'game.example');
  });

  test(
    'basic and port responses share the same notification deduplication',
    () {
      final session = AccountSession();
      addTearDown(session.dispose);
      session.accept(_identityEvent());
      final scope = session.current;
      var notifications = 0;
      session.addListener(() => notifications++);

      session.accept(_identityEvent(path: '/kcsapi/api_get_member/basic'));
      session.accept(_identityEvent(nickname: null, origin: ''));
      session.accept(_identityEvent(nickname: '  ', origin: ''));

      expect(notifications, 0);
      expect(session.current, same(scope));
      expect(session.admiralName, 'Admiral');
      expect(session.serverName, 'game.example');
    },
  );

  test('nickname changes notify without replacing the account scope', () {
    final session = AccountSession();
    addTearDown(session.dispose);
    session.accept(_identityEvent());
    final scope = session.current;
    final publishedNames = <String>[];
    session.addListener(() => publishedNames.add(session.admiralName));

    session.accept(_identityEvent(nickname: 'New Admiral'));
    session.accept(_identityEvent(nickname: 'New Admiral'));

    expect(publishedNames, ['New Admiral']);
    expect(session.current, same(scope));
  });

  test('server changes notify without replacing the account scope', () {
    final session = AccountSession();
    addTearDown(session.dispose);
    session.accept(_identityEvent());
    final scope = session.current;
    final publishedServers = <String>[];
    session.addListener(() => publishedServers.add(session.serverName));

    session.accept(_identityEvent(origin: 'https://other.example'));
    session.accept(_identityEvent(origin: 'https://other.example/path'));

    expect(publishedServers, ['other.example']);
    expect(session.current, same(scope));
  });

  test(
    'account switch publishes the new identity and metadata together once',
    () {
      final session = AccountSession();
      addTearDown(session.dispose);
      session.accept(_identityEvent());
      final previous = session.current;
      final published = <(int, int, String, String)>[];
      session.addListener(() {
        published.add((
          session.current.memberId,
          session.current.generation,
          session.admiralName,
          session.serverName,
        ));
      });

      session.accept(
        _identityEvent(
          memberId: 2002,
          nickname: 'Second Admiral',
          origin: 'https://other.example',
        ),
      );

      expect(published, [
        (2002, previous.generation + 1, 'Second Admiral', 'other.example'),
      ]);
      expect(session.isCurrent(previous), isFalse);
    },
  );

  test('getData resets notify and invalidate scopes even while unknown', () {
    final session = AccountSession();
    addTearDown(session.dispose);
    session.accept(_identityEvent());
    final previous = session.current;
    final published = <(int, int, String, String)>[];
    session.addListener(() {
      published.add((
        session.current.memberId,
        session.current.generation,
        session.admiralName,
        session.serverName,
      ));
    });

    session.accept(_identityEvent(path: '/kcsapi/api_start2/getData'));
    final firstReset = session.current;
    session.accept(_identityEvent(path: '/kcsapi/api_start2/getData'));
    final secondReset = session.current;
    session.accept(_identityEvent());

    expect(published, [
      (0, previous.generation + 1, '', ''),
      (0, previous.generation + 2, '', ''),
      (1001, previous.generation + 3, 'Admiral', 'game.example'),
    ]);
    expect(session.isCurrent(previous), isFalse);
    expect(session.isCurrent(firstReset), isFalse);
    expect(session.isCurrent(secondReset), isFalse);
  });
}
