import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_catalog.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_resource_state.dart';

final firstCheck = DateTime.utc(2026, 10, 18, 9);
final secondCheck = firstCheck.add(const Duration(days: 1));
final thirdCheck = secondCheck.add(const Duration(days: 1));

ShipSubtitleResourceState snapshot({
  String version = '2026101805',
  DateTime? checkedAt,
}) => ShipSubtitleResourceState(
  catalogs: {
    for (final language in kcwikiSubtitleLanguages)
      language: ShipSubtitleCatalog(
        version: version,
        quotes: {
          '1': {'1': '${language.code} $version'},
        },
      ),
  },
  kcwikiLastCheckedAt: checkedAt,
  kcwikiLastAttemptAt: checkedAt,
  kc3LastAttemptAt: checkedAt,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late FileShipSubtitleResourceStateStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('subtitle-state-perf-');
    store = FileShipSubtitleResourceStateStore.inDirectory(directory);
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'unchanged catalogs only write small metadata and survive restart',
    () async {
      final initial = snapshot(checkedAt: firstCheck);
      await store.save(initial);
      final original = await store.file.readAsBytes();
      final sentinel = DateTime.utc(2000);
      await store.file.setLastModified(sentinel);
      final originalModified = (await store.file.stat()).modified;
      await store.save(initial.copyWith(kcwikiLastAttemptAt: secondCheck));
      await store.save(
        initial.copyWith(
          catalogs: Map.of(initial.catalogs),
          kcwikiLastCheckedAt: secondCheck,
          kcwikiLastAttemptAt: secondCheck,
          kc3LastAttemptAt: secondCheck,
        ),
      );
      expect(await store.file.readAsBytes(), original);
      expect((await store.file.stat()).modified, originalModified);
      final metadata = File('${store.file.path}.state');
      expect(await metadata.length(), lessThan(512));
      final restored = await FileShipSubtitleResourceStateStore.inDirectory(
        directory,
      ).load();
      expect(restored.catalogs.keys.toSet(), kcwikiSubtitleLanguages.toSet());
      expect(restored.kcwikiLastCheckedAt, secondCheck);
      expect(restored.kcwikiLastAttemptAt, secondCheck);
      expect(restored.kc3LastAttemptAt, secondCheck);
    },
  );

  test(
    'legacy full state stays readable and the next check avoids a data rewrite',
    () async {
      await store.file.writeAsString(
        jsonEncode(snapshot(checkedAt: firstCheck).toJson()),
      );
      final original = await store.file.readAsBytes();
      final loaded = await store.load();
      await store.save(loaded.copyWith(kcwikiLastCheckedAt: secondCheck));
      expect(await store.file.readAsBytes(), original);
      final restored = await FileShipSubtitleResourceStateStore.inDirectory(
        directory,
      ).load();
      expect(restored.kcwikiLastCheckedAt, secondCheck);
      expect(restored.catalogs.values.first.version, '2026101805');
    },
  );

  test(
    'attempts without any downloaded group only need a metadata file',
    () async {
      await store.save(
        ShipSubtitleResourceState(
          kcwikiLastAttemptAt: firstCheck,
          kc3LastAttemptAt: firstCheck,
        ),
      );
      expect(await store.file.exists(), isFalse);
      final restored = await FileShipSubtitleResourceStateStore.inDirectory(
        directory,
      ).load();
      expect(restored.catalogs, isEmpty);
      expect(restored.kcwikiLastAttemptAt, firstCheck);
      expect(restored.kc3LastAttemptAt, firstCheck);
    },
  );

  test(
    'damaged or mismatched metadata cannot replace the group baseline',
    () async {
      await store.save(snapshot(checkedAt: firstCheck));
      final metadata = File('${store.file.path}.state');
      for (final body in [
        '{broken',
        jsonEncode({
          'schema': 1,
          'groupVersion': '2026101905',
          'kcwikiLastCheckedAt': thirdCheck.toIso8601String(),
          'kcwikiLastAttemptAt': thirdCheck.toIso8601String(),
        }),
      ]) {
        await metadata.writeAsString(body);
        final restored = await FileShipSubtitleResourceStateStore.inDirectory(
          directory,
        ).load();
        expect(restored.kcwikiLastCheckedAt, firstCheck);
        expect(restored.kcwikiLastAttemptAt, firstCheck);
      }
    },
  );

  test(
    'a newer group commits together and stale metadata never moves checks backwards',
    () async {
      await store.save(snapshot(checkedAt: firstCheck));
      final loaded = await store.load();
      await store.save(loaded.copyWith(kcwikiLastCheckedAt: secondCheck));
      await store.save(snapshot(version: '2026101905', checkedAt: thirdCheck));
      final restored = await FileShipSubtitleResourceStateStore.inDirectory(
        directory,
      ).load();
      expect(restored.catalogs.values.map((value) => value.version).toSet(), {
        '2026101905',
      });
      expect(restored.kcwikiLastCheckedAt, thirdCheck);
      await File('${store.file.path}.state').writeAsString(
        jsonEncode({
          'schema': 1,
          'groupVersion': '2026101905',
          'kcwikiLastCheckedAt': firstCheck.toIso8601String(),
          'kcwikiLastAttemptAt': firstCheck.toIso8601String(),
        }),
      );
      final withOldMetadata =
          await FileShipSubtitleResourceStateStore.inDirectory(
            directory,
          ).load();
      expect(withOldMetadata.kcwikiLastCheckedAt, thirdCheck);
      expect(withOldMetadata.kcwikiLastAttemptAt, thirdCheck);
    },
  );

  test(
    'failed metadata staging keeps the last complete data and check time',
    () async {
      final initial = snapshot(checkedAt: firstCheck);
      await store.save(initial);
      await Directory('${store.file.path}.state.tmp').create();
      await expectLater(
        store.save(initial.copyWith(kcwikiLastCheckedAt: secondCheck)),
        throwsA(isA<FileSystemException>()),
      );
      final restored = await FileShipSubtitleResourceStateStore.inDirectory(
        directory,
      ).load();
      expect(restored.kcwikiLastCheckedAt, firstCheck);
      expect(restored.catalogs.values.first.version, '2026101805');
    },
  );

  test(
    'failed full group staging preserves the previous snapshot and metadata',
    () async {
      final initial = snapshot(checkedAt: firstCheck);
      await store.save(initial);
      await store.save(initial.copyWith(kcwikiLastCheckedAt: secondCheck));
      await Directory('${store.file.path}.tmp').create();
      await expectLater(
        store.save(snapshot(version: '2026101905', checkedAt: thirdCheck)),
        throwsA(isA<FileSystemException>()),
      );
      final restored = await FileShipSubtitleResourceStateStore.inDirectory(
        directory,
      ).load();
      expect(restored.kcwikiLastCheckedAt, secondCheck);
      expect(restored.catalogs.values.first.version, '2026101805');
    },
  );

  for (final damagedPrimary in [false, true]) {
    test(
      '${damagedPrimary ? 'damaged' : 'missing'} primary recovers its complete backup before metadata-only checks',
      () async {
        final initial = snapshot(checkedAt: firstCheck);
        final backup = File('${store.file.path}.bak');
        await backup.writeAsString(jsonEncode(initial.toJson()));
        if (damagedPrimary) await store.file.writeAsString('{broken');
        final loaded = await store.load();
        final recovered = ShipSubtitleResourceState.fromJson(
          jsonDecode(await store.file.readAsString()) as Map<String, dynamic>,
        );
        expect(recovered.catalogs.values.first.version, '2026101805');
        expect(await backup.exists(), isFalse);
        final original = await store.file.readAsBytes();
        await store.save(loaded.copyWith(kcwikiLastCheckedAt: secondCheck));
        expect(await store.file.readAsBytes(), original);
        final restarted = await FileShipSubtitleResourceStateStore.inDirectory(
          directory,
        ).load();
        expect(restarted.kcwikiLastCheckedAt, secondCheck);
        expect(restarted.catalogs.values.first.version, '2026101805');
      },
    );
  }

  test(
    'failed backup recovery never discards the only valid group on a later update',
    () async {
      final backup = File('${store.file.path}.bak');
      final baseline = jsonEncode(snapshot(checkedAt: firstCheck).toJson());
      await backup.writeAsString(baseline);
      // A directory occupying the target deterministically prevents restoration.
      await Directory(store.file.path).create();
      final loaded = await store.load();
      expect(loaded.catalogs.values.first.version, '2026101805');
      await store.save(loaded.copyWith(kcwikiLastCheckedAt: secondCheck));
      await expectLater(
        store.save(snapshot(version: '2026101905', checkedAt: thirdCheck)),
        throwsA(isA<FileSystemException>()),
      );
      expect(await backup.readAsString(), baseline);
      final restarted = await FileShipSubtitleResourceStateStore.inDirectory(
        directory,
      ).load();
      expect(restarted.kcwikiLastCheckedAt, secondCheck);
      expect(restarted.catalogs.values.first.version, '2026101805');
    },
  );
}
