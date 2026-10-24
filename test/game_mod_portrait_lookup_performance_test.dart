import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/fleet/game_mod_portraits.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_portrait.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';

const _ship = MasterShip(
  id: 607,
  name: 'I-47',
  shipTypeId: 13,
  portraitFileName: 'tciiyagxjjpu',
);

String _path(String type, {MasterShip ship = _ship}) {
  final id = ship.id.toString().padLeft(4, '0');
  final cipher = ShipPortraitUriBuilder.createCipher(ship.id, 'ship_$type');
  final suffix = type == 'full' ? '_${ship.portraitFileName}' : '';
  return 'kcs2/resources/ship/$type/${id}_$cipher$suffix.png';
}

GameModPortraitSnapshot _snapshot(String token, List<Object?> resources) =>
    GameModPortraitSnapshot.fromMap({'token': token, 'resources': resources});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('snapshot freezes input and keeps its resource list unmodifiable', () {
    final entry = <String, Object?>{
      'id': 'original',
      'path': '/${_path('banner')}',
    };
    final source = <Object?>[
      entry,
      null,
      'not a map',
      {'id': 1, 'path': _path('banner')},
      {'id': 'invalid path', 'path': 1},
    ];
    final snapshot = _snapshot('frozen', source);
    entry['id'] = 'changed';
    entry['path'] = _path('full');
    source.clear();

    expect(snapshot.token, 'frozen');
    expect(snapshot.resources, hasLength(1));
    expect(snapshot.resources.single.path, _path('banner'));
    expect(GameModPortraitResolver.select(_ship, snapshot)?.id, 'original');
    expect(
      () => snapshot.resources.add(
        const GameModPortraitResource(id: 'extra', path: 'extra.png'),
      ),
      throwsUnsupportedError,
    );
    expect(snapshot.resources.single.id, 'original');
  });

  test(
    'duplicate normalized paths keep the first resource and its identity',
    () {
      final path = _path('banner');
      final snapshot = _snapshot('duplicates', [
        {'id': 'first', 'path': '///$path'},
        {'id': 'second', 'path': path},
        {'id': 'third', 'path': '/$path'},
      ]);

      for (var attempt = 0; attempt < 3; attempt++) {
        final selected = GameModPortraitResolver.select(_ship, snapshot);
        expect(selected?.id, 'first');
        expect(identical(selected, snapshot.resources.first), isTrue);
      }
    },
  );

  test(
    'type priority survives reverse input order and unrelated resources',
    () {
      const priorities = ['remodel', 'banner', 'character_full', 'full'];
      for (var first = 0; first < priorities.length; first++) {
        final available = priorities.skip(first).toList();
        final snapshot = _snapshot('priority-$first', [
          {'id': 'unrelated', 'path': 'kcs2/resources/ship/unrelated.png'},
          for (final type in available.reversed)
            {'id': type, 'path': _path(type)},
        ]);
        final selected = GameModPortraitResolver.select(_ship, snapshot);
        expect(selected?.id, priorities[first]);
        expect(selected?.layout, GameModPortraitLayout.values[first]);
      }
    },
  );

  test('lookup uses exact normal paths and the exact full filename', () {
    final full = _path('full');
    final snapshot = _snapshot('exact', [
      {'id': 'damage', 'path': full.replaceFirst('/full/', '/full_dmg/')},
      {
        'id': 'wrong filename',
        'path': full.replaceFirst('tciiyagxjjpu', 'other'),
      },
      {'id': 'extra prefix', 'path': 'another/$full'},
      {'id': 'wrong case', 'path': full.toUpperCase()},
      {'id': 'trailing suffix', 'path': '$full.extra'},
      {'id': 'exact', 'path': full},
    ]);

    expect(GameModPortraitResolver.select(_ship, snapshot)?.id, 'exact');
    final withoutExact = _snapshot('no-exact', [
      for (final resource in snapshot.resources.take(5))
        {'id': resource.id, 'path': resource.path},
    ]);
    expect(GameModPortraitResolver.select(_ship, withoutExact), isNull);
  });

  test(
    'invalid full filenames cannot match while banner fallback stays valid',
    () {
      for (final filename in [
        '',
        'UpperCase',
        '../escape',
        'file-name',
        '立绘',
      ]) {
        final invalidShip = _ship.copyWith(portraitFileName: filename);
        final fullOnly = _snapshot('invalid-$filename', [
          {'id': 'invalid-full', 'path': _path('full', ship: invalidShip)},
        ]);
        expect(GameModPortraitResolver.select(invalidShip, fullOnly), isNull);
        final withBanner = _snapshot('fallback-$filename', [
          {'id': 'invalid-full', 'path': _path('full', ship: invalidShip)},
          {'id': 'banner', 'path': _path('banner')},
        ]);
        expect(
          GameModPortraitResolver.select(invalidShip, withBanner)?.id,
          'banner',
        );
      }
      const unnamedShip = MasterShip(id: 607, name: 'I-47', shipTypeId: 13);
      expect(
        GameModPortraitResolver.select(
          unnamedShip,
          _snapshot('missing-name', [
            {'id': 'null-full', 'path': _path('full', ship: unnamedShip)},
          ]),
        ),
        isNull,
      );
    },
  );

  test(
    'token changes and rollback replace the index while same token stays cached',
    () async {
      final port = _Port(
        _snapshot('one', [
          {'id': 'one-first', 'path': _path('banner')},
          {'id': 'one-second', 'path': _path('banner')},
        ]),
      );
      final controller = GameModPortraitController(port: port, store: _Store());
      await controller.initialize();
      try {
        await controller.resolve(_ship);
        await controller.resolve(_ship);
        expect(port.reads, [('one', 'one-first')]);

        port.current = _snapshot('one', [
          {'id': 'ignored-same-token', 'path': _path('banner')},
        ]);
        await controller.refresh();
        await controller.resolve(_ship);
        expect(port.reads, [('one', 'one-first')]);

        port.current = _snapshot('two', [
          {'id': 'two-first', 'path': _path('banner')},
          {'id': 'two-second', 'path': _path('banner')},
        ]);
        await controller.refresh();
        await controller.resolve(_ship);
        expect(port.reads.last, ('two', 'two-first'));

        port.current = _snapshot('one', [
          {'id': 'rollback-first', 'path': _path('banner')},
        ]);
        await controller.refresh();
        await controller.resolve(_ship);
        expect(port.reads, [
          ('one', 'one-first'),
          ('two', 'two-first'),
          ('one', 'rollback-first'),
        ]);
      } finally {
        controller.dispose();
      }
    },
  );

  test(
    'large snapshot lookup benchmark reports tail and miss without time limits',
    () {
      const resourceCount = 5000;
      const iterations = 1000;
      const warmup = 50;
      final construction = Stopwatch()..start();
      final snapshot = _snapshot('large', [
        for (var index = 0; index < resourceCount; index++)
          {
            'id': 'other-$index',
            'path': 'kcs2/resources/ship/banner/unrelated-$index.png',
          },
        {'id': 'tail-full', 'path': _path('full')},
      ]);
      construction.stop();
      const missing = MasterShip(
        id: 9999,
        name: 'missing',
        shipTypeId: 2,
        portraitFileName: 'missing',
      );
      for (var index = 0; index < warmup; index++) {
        GameModPortraitResolver.select(_ship, snapshot);
        GameModPortraitResolver.select(missing, snapshot);
      }

      var hits = 0;
      final tail = Stopwatch()..start();
      for (var index = 0; index < iterations; index++) {
        if (GameModPortraitResolver.select(_ship, snapshot)?.id ==
            'tail-full') {
          hits++;
        }
      }
      tail.stop();
      var misses = 0;
      final miss = Stopwatch()..start();
      for (var index = 0; index < iterations; index++) {
        if (GameModPortraitResolver.select(missing, snapshot) == null) misses++;
      }
      miss.stop();
      expect(hits, iterations);
      expect(misses, iterations);
      // Report observations only: CPU scheduling must never make this test fail.
      debugPrint(
        'portrait lookup benchmark: resources=${snapshot.resources.length} '
        'iterations=$iterations warmup=$warmup '
        'constructMicros=${construction.elapsedMicroseconds} '
        'tailMicros=${tail.elapsedMicroseconds} '
        'missMicros=${miss.elapsedMicroseconds}',
      );
    },
  );
}

class _Port implements GameModPortraitPort {
  _Port(this.current);
  GameModPortraitSnapshot current;
  final reads = <(String, String)>[];

  @override
  Future<GameModPortraitSnapshot> snapshot() async => current;

  @override
  Future<Uint8List?> read({
    required String token,
    required String resourceId,
  }) async {
    reads.add((token, resourceId));
    return null;
  }

  @override
  void setChangedHandler(void Function()? handler) {}
}

class _Store implements GameModPortraitStore {
  @override
  Future<bool?> readEnabled() async => true;

  @override
  Future<void> writeEnabled(bool enabled) async {}
}
