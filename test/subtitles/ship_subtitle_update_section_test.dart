import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_catalog.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_catalog_controller.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_language.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_update_section.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_update_service.dart';
import 'package:yahagi_kancolle_browser/src/settings/data_update_metadata.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_kc3_bundle.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_kc3_update_service.dart';

void main() {
  testWidgets(
    'Korean uses the same two source metadata rows and one update button',
    (tester) async {
      final catalog = ShipSubtitleCatalog(
        version: '2026101805',
        quotes: {
          '1': {'1': '睦月'},
        },
      );
      final bundle = await tester.runAsync(
        () async => ShipSubtitleKc3Bundle.fromJsonString(
          await File('assets/data/subtitles/kc3-bundle.json').readAsString(),
        ),
      );
      final controller = ShipSubtitleCatalogController(
        data: catalog,
        updater: _UpToDateUpdater(),
        kc3Source: ShipSubtitleKc3Source(
          bundle: bundle!,
          updater: _Kc3UpToDateUpdater(),
        ),
        languageLoader: (_) async =>
            throw StateError('Korean is available in the loaded KC3 bundle.'),
      );
      addTearDown(controller.dispose);
      await controller.selectLanguage(ShipSubtitleLanguage.korean);
      expect(controller.isLanguageReady, isTrue);
      expect(controller.data, same(bundle.korean));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShipSubtitleUpdateSection(controller: controller),
          ),
        ),
      );
      expect(find.byType(DataUpdateMetadata), findsNWidgets(2));
      expect(find.text('数据版本：2026101805'), findsOneWidget);
      expect(find.text('数据版本：${bundle.version}'), findsOneWidget);
      expect(find.textContaining('字幕语言'), findsNothing);
      expect(find.textContaining('kcwiki'), findsNothing);
      expect(find.textContaining('KC3'), findsNothing);
      expect(find.byIcon(Icons.sync), findsOneWidget);
    },
  );
  testWidgets(
    'a successful source group and a failed group report partial failure',
    (tester) async {
      final catalog = ShipSubtitleCatalog(
        version: '2026101805',
        quotes: {
          '1': {'1': '睦月'},
        },
      );
      final bundle = await tester.runAsync(
        () async => ShipSubtitleKc3Bundle.fromJsonString(
          await File('assets/data/subtitles/kc3-bundle.json').readAsString(),
        ),
      );
      final controller = ShipSubtitleCatalogController(
        data: catalog,
        updater: _FailingUpdater(),
        kc3Source: ShipSubtitleKc3Source(
          bundle: bundle!,
          updater: _Kc3UpToDateUpdater(),
        ),
        languageLoader: (_) async => ShipSubtitleCatalogSource(
          data: catalog,
          updater: _FailingUpdater(),
        ),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShipSubtitleUpdateSection(controller: controller),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('ship-subtitle-check-button')));
      await tester.pumpAndSettle();
      expect(find.text('一部分更新失败，已有资料仍可用。'), findsOneWidget);
      expect(find.textContaining('已是最新版本'), findsNothing);
      expect(controller.kcwikiLastCheckedAt, isNull);
      expect(controller.kc3LastCheckedAt, isNotNull);
    },
  );
  testWidgets(
    'an entirely failed grouped check reports failure without claiming partial success',
    (tester) async {
      final catalog = ShipSubtitleCatalog(
        version: '2026101805',
        quotes: {
          '1': {'1': '睦月'},
        },
      );
      final controller = ShipSubtitleCatalogController(
        data: catalog,
        updater: _FailingUpdater(),
        updateAllLanguages: true,
        languageLoader: (_) async => ShipSubtitleCatalogSource(
          data: catalog,
          updater: _FailingUpdater(),
        ),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShipSubtitleUpdateSection(controller: controller),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('ship-subtitle-check-button')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('一部分更新失败'), findsNothing);
      expect(find.textContaining('翻译资料更新失败，已有资料仍可用'), findsOneWidget);
      expect(find.textContaining('已是最新版本'), findsNothing);
    },
  );
  testWidgets(
    'uses two metadata rows with one sync and no language or source labels',
    (tester) async {
      final controller = ShipSubtitleCatalogController(
        data: ShipSubtitleCatalog(
          version: '2026101805',
          quotes: {
            '1': {'1': '睦月'},
          },
        ),
        updater: _UpToDateUpdater(),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShipSubtitleUpdateSection(controller: controller),
          ),
        ),
      );
      expect(find.byType(DataUpdateMetadata), findsNWidgets(2));
      expect(find.textContaining('字幕语言'), findsNothing);
      expect(find.textContaining('kcwiki'), findsNothing);
      expect(find.textContaining('KC3'), findsNothing);
      expect(find.byIcon(Icons.sync), findsOneWidget);
    },
  );
  testWidgets(
    'an update finishing after a language switch does not show an old dialog',
    (tester) async {
      final pending = _PendingUpdater();
      final controller = ShipSubtitleCatalogController(
        data: ShipSubtitleCatalog(
          version: '2026101805',
          quotes: {
            '1': {'1': '睦月'},
          },
        ),
        updater: pending,
        languageLoader: (_) async => ShipSubtitleCatalogSource(
          data: ShipSubtitleCatalog(
            version: '20260804124356',
            quotes: {
              '1': {'1': 'Mutsuki'},
            },
          ),
          updater: _UpToDateUpdater(),
        ),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShipSubtitleUpdateSection(controller: controller),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('ship-subtitle-check-button')));
      await tester.pump();
      await controller.selectLanguage(ShipSubtitleLanguage.english);
      pending.pending.complete(
        ShipSubtitleUpdated(
          ShipSubtitleCatalog(
            version: '2026101905',
            quotes: {
              '1': {'1': '新简中'},
            },
          ),
          sourceHost: 'test',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('数据版本：20260804124356'), findsOneWidget);
    },
  );

  testWidgets('keeps source group metadata while loading another language', (
    tester,
  ) async {
    final pending = Completer<ShipSubtitleCatalogSource>();
    final controller = ShipSubtitleCatalogController(
      data: ShipSubtitleCatalog(
        version: '2026101805',
        quotes: {
          '1': {'1': '睦月'},
        },
      ),
      updater: _UpToDateUpdater(),
      languageLoader: (_) => pending.future,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ShipSubtitleUpdateSection(controller: controller)),
      ),
    );
    final loading = controller.selectLanguage(ShipSubtitleLanguage.english);
    await tester.pump();
    expect(find.textContaining('字幕语言'), findsNothing);
    expect(find.text('数据版本：2026101805'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('ship-subtitle-check-button')),
          )
          .onPressed,
      isNotNull,
    );
    pending.complete(
      ShipSubtitleCatalogSource(
        data: ShipSubtitleCatalog(
          version: '20260804124356',
          quotes: {
            '1': {'1': 'Mutsuki'},
          },
        ),
        updater: _UpToDateUpdater(),
      ),
    );
    await loading;
    await tester.pump();
    expect(find.text('数据版本：20260804124356'), findsOneWidget);
    expect(find.text('数据版本：2026101805'), findsOneWidget);
  });

  testWidgets(
    'failed language load keeps the independently available source metadata',
    (tester) async {
      final controller = ShipSubtitleCatalogController(
        data: ShipSubtitleCatalog(
          version: '2026101805',
          quotes: {
            '1': {'1': '睦月'},
          },
        ),
        updater: _UpToDateUpdater(),
        languageLoader: (_) async => throw const FormatException('broken data'),
      );
      addTearDown(controller.dispose);
      await controller.selectLanguage(ShipSubtitleLanguage.english);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShipSubtitleUpdateSection(controller: controller),
          ),
        ),
      );
      expect(find.textContaining('字幕语言'), findsNothing);
      expect(find.text('数据版本：2026101805'), findsOneWidget);
      expect(find.byType(DataUpdateMetadata), findsNWidgets(2));
    },
  );

  testWidgets(
    'shows independently versioned subtitle data and a manual check',
    (tester) async {
      final controller = ShipSubtitleCatalogController(
        data: ShipSubtitleCatalog(
          version: '2026101805',
          quotes: {
            '1': {'1': '我是睦月！'},
          },
        ),
        updater: _UpToDateUpdater(),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          home: Scaffold(
            body: ShipSubtitleUpdateSection(controller: controller),
          ),
        ),
      );
      expect(find.text('翻译资料'), findsOneWidget);
      expect(find.text('数据版本：2026101805'), findsOneWidget);
      expect(find.text('上次检查：尚未检查'), findsNWidgets(2));
      expect(tester.getTopLeft(find.text('翻译资料')).dx, 16);
      await tester.tap(find.byKey(const Key('ship-subtitle-check-button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('已是最新版本'), findsOneWidget);
      expect(controller.lastCheckedAt, isNotNull);
    },
  );
}

final class _UpToDateUpdater implements ShipSubtitleUpdateClient {
  @override
  Future<ShipSubtitleUpdateResult> checkAndUpdate({
    required ShipSubtitleCatalog current,
  }) async => ShipSubtitleUpToDate(current, sourceHost: 'test');
}

final class _Kc3UpToDateUpdater implements ShipSubtitleKc3UpdateClient {
  @override
  Future<ShipSubtitleKc3UpdateResult> checkAndUpdate({
    required ShipSubtitleKc3Bundle current,
  }) async => ShipSubtitleKc3UpToDate(current, sourceHost: 'test');
}

final class _FailingUpdater implements ShipSubtitleUpdateClient {
  @override
  Future<ShipSubtitleUpdateResult> checkAndUpdate({
    required ShipSubtitleCatalog current,
  }) async => ShipSubtitleUpdateFailed(
    ShipSubtitleUpdateFailure.network,
    StateError('offline'),
    sourceHost: 'test',
  );
}

final class _PendingUpdater implements ShipSubtitleUpdateClient {
  final pending = Completer<ShipSubtitleUpdateResult>();
  @override
  Future<ShipSubtitleUpdateResult> checkAndUpdate({
    required ShipSubtitleCatalog current,
  }) => pending.future;
}
