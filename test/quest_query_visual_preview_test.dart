// Opt-in screenshots of the real Flutter quest UI using public catalog assets
// and synthetic quest snapshots only. Set QUEST_QUERY_PREVIEW_DIR to an output
// directory, then run: flutter test --no-pub test/quest_query_visual_preview_test.dart
// QUEST_QUERY_PREVIEW_FONT may override the bundled CJK font for local previews.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_catalog.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_center_page.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_store.dart';

const _previewBoundary = Key('quest-query-preview-root');
const _previewQuestIds = <int>[201, 442, 280, 284, 626, 1161, 1164];
final _outputDirectory = Platform.environment['QUEST_QUERY_PREVIEW_DIR'];
final _previewManifest = <Map<String, Object>>[];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late QuestCatalog catalog;
  setUpAll(() async {
    if (_outputDirectory == null) return;
    await Directory(_outputDirectory!).create(recursive: true);
    await _loadFont(
      'QuestPreviewCjk',
      Platform.environment['QUEST_QUERY_PREVIEW_FONT'] ??
          'assets/fonts/NotoSansJP-wght.ttf',
    );
    await _loadFont('HarmonyOS_Sans_SC', 'assets/fonts/HarmonyOS_Sans_SC.ttf');
    await _loadFont('HarmonyOS_Sans_TC', 'assets/fonts/HarmonyOS_Sans_TC.ttf');
    await _loadFont('monospace', 'assets/fonts/HarmonyOS_Sans.ttf');
    var directory = File(Platform.resolvedExecutable).parent;
    while (directory.parent.path != directory.path) {
      final font = File(
        '${directory.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      );
      if (font.existsSync()) {
        await _loadFont('MaterialIcons', font.path);
        break;
      }
      directory = directory.parent;
    }
    catalog = await QuestCatalog.loadAsset();
    expect(catalog.entries.length, greaterThan(500));
  });

  tearDownAll(() async {
    if (_outputDirectory == null) return;
    await File('$_outputDirectory/preview-manifest.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object>{
        'data':
            'public assets/data/quests-scn.json with synthetic GameQuest data',
        'rendering': 'Flutter RenderRepaintBoundary.toImage, pixelRatio 1',
        'catalogEntries': catalog.entries.length,
        'screenshots': _previewManifest,
      }),
    );
  });

  for (final size in const <Size>[
    Size(667, 375),
    Size(844, 390),
    Size(673, 841),
  ]) {
    testWidgets(
      'real quest landscape or foldable render $size',
      (tester) async {
        await _pumpPreview(tester, catalog, size, initialQuestId: 1164);
        await _capture(tester, 'japanese-conditions', size);
        await tester.tap(find.byKey(const Key('quest-detail-tab-rewards')));
        await tester.pumpAndSettle();
        await _capture(tester, 'japanese-rewards', size);
        await tester.tap(find.byKey(const Key('quest-search-button')));
        await tester.pumpAndSettle();
        await _capture(tester, 'query-panel', size);
        await _expectLastQueryChoiceReachable(tester);
      },
      skip: _outputDirectory == null,
    );
  }

  testWidgets(
    'real portrait list detail translation relations and keyboard renders',
    (tester) async {
      const size = Size(390, 844);
      await _pumpPreview(tester, catalog, size);
      _expectPortraitPanes(tester);
      expect(find.byKey(const Key('quest-detail-title-201')), findsOneWidget);
      await _capture(tester, 'portrait-japanese-list', size);
      await _selectPortraitQuest(tester, 1164);
      await _capture(tester, 'portrait-japanese-conditions', size);
      await tester.tap(find.byKey(const Key('quest-detail-tab-rewards')));
      await tester.pumpAndSettle();
      await _capture(tester, 'portrait-japanese-rewards', size);
      await tester.tap(find.byKey(const Key('quest-translation-toggle')));
      await tester.pumpAndSettle();
      _expectPortraitPanes(tester);
      await _capture(tester, 'portrait-chinese-list', size);
      await _selectPortraitQuest(tester, 442);
      await tester.tap(find.byKey(const Key('quest-detail-tab-relations')));
      await tester.pumpAndSettle();
      await _capture(tester, 'portrait-chinese-relations', size);
      await tester.tap(find.byKey(const Key('quest-search-button')));
      await tester.pumpAndSettle();
      await _capture(tester, 'portrait-query-panel', size);
      await tester.tap(find.byKey(const Key('quest-search-field')));
      await tester.enterText(find.byKey(const Key('quest-search-field')), '工廠');
      tester.view.viewInsets = const FakeViewPadding(bottom: 290);
      await tester.pumpAndSettle();
      await _capture(tester, 'portrait-query-keyboard-insets', size);
      await _expectLastQueryChoiceReachable(tester);
    },
    skip: _outputDirectory == null,
  );

  testWidgets(
    'real portrait list shrinks for one quest and caps at half for many',
    (tester) async {
      const size = Size(390, 844);
      await _pumpPreview(tester, catalog, size, questIds: const <int>[201]);
      _expectPortraitPanes(tester);
      final shortList = tester.getRect(
        find.byKey(const Key('quest-list-panel')),
      );
      final shortDetail = tester.getRect(
        find.byKey(const Key('quest-detail-panel')),
      );
      expect(shortList.height, lessThan(shortDetail.height));
      final card = tester.getRect(find.byKey(const Key('quest-card-201')));
      expect(shortList.bottom - card.bottom, inInclusiveRange(0, 24));
      expect(
        _portraitListPosition(tester).maxScrollExtent,
        lessThanOrEqualTo(.5),
      );
      await _capture(tester, 'portrait-few-quests', size);

      await _pumpPreview(tester, catalog, size);
      _expectPortraitPanes(tester);
      final longList = tester.getRect(
        find.byKey(const Key('quest-list-panel')),
      );
      final longDetail = tester.getRect(
        find.byKey(const Key('quest-detail-panel')),
      );
      final contentHeight = longDetail.bottom - longList.top;
      expect(longList.height, closeTo(contentHeight * .5, 1));
      expect(_portraitListPosition(tester).maxScrollExtent, greaterThan(0));
      expect(longDetail.height, greaterThan(0));
      await _capture(tester, 'portrait-many-quests', size);
    },
    skip: _outputDirectory == null,
  );

  for (final size in const <Size>[Size(667, 375), Size(673, 841)]) {
    testWidgets('real enlarged text quest render $size', (tester) async {
      await _pumpPreview(
        tester,
        catalog,
        size,
        initialQuestId: 1164,
        textScale: 1.3,
      );
      await _capture(tester, 'large-text-conditions', size, textScale: 1.3);
      await tester.tap(find.byKey(const Key('quest-detail-tab-rewards')));
      await tester.pumpAndSettle();
      await _capture(tester, 'large-text-rewards', size, textScale: 1.3);
      await tester.tap(find.byKey(const Key('quest-search-button')));
      await tester.pumpAndSettle();
      await _capture(tester, 'large-text-query', size, textScale: 1.3);
      await _expectLastQueryChoiceReachable(tester);
    }, skip: _outputDirectory == null);
  }
}

Future<void> _loadFont(String family, String path) async {
  await (FontLoader(family)..addFont(
        Future<ByteData>.value(
          ByteData.sublistView(await File(path).readAsBytes()),
        ),
      ))
      .load();
}

Future<void> _pumpPreview(
  WidgetTester tester,
  QuestCatalog catalog,
  Size size, {
  int? initialQuestId,
  double textScale = 1,
  List<int> questIds = _previewQuestIds,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewInsets);
  final controller = GameStateController(
    questStore: _PublicCatalogPreviewStore(catalog, questIds),
  );
  addTearDown(controller.dispose);
  await controller.idle;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'QuestPreviewCjk',
        fontFamilyFallback: const <String>['HarmonyOS_Sans_SC'],
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xffd4a85f),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff0a1823),
        useMaterial3: true,
      ),
      builder: (context, child) => RepaintBoundary(
        key: _previewBoundary,
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
      home: Scaffold(
        body: QuestCenterPage(
          controller: controller,
          catalog: catalog,
          initialQuestId: initialQuestId,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _capture(
  WidgetTester tester,
  String state,
  Size size, {
  double textScale = 1,
}) async {
  expect(tester.takeException(), isNull, reason: state);
  await tester.runAsync(() async {
    final context = tester.element(find.byKey(_previewBoundary));
    await Future.wait<void>(<Future<void>>[
      for (final image in tester.widgetList<Image>(find.byType(Image)))
        precacheImage(image.image, context),
    ]);
  });
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_previewBoundary),
  );
  final filename = '${size.width.toInt()}x${size.height.toInt()}-$state.png';
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(byteData, isNotNull);
      await File('$_outputDirectory/$filename').writeAsBytes(
        byteData!.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        ),
      );
    } finally {
      image.dispose();
    }
  });
  _previewManifest.add(<String, Object>{
    'file': filename,
    'width': size.width.toInt(),
    'height': size.height.toInt(),
    'textScale': textScale,
    'state': state,
  });
}

Future<void> _expectLastQueryChoiceReachable(WidgetTester tester) async {
  final lastChoice = find.byKey(const Key('quest-filter-status-unknown'));
  await tester.ensureVisible(lastChoice);
  await tester.pumpAndSettle();
  expect(lastChoice.hitTestable(), findsOneWidget);
  final apply = find.byKey(const Key('quest-query-apply'));
  expect(apply.hitTestable(), findsOneWidget);
  expect(
    tester.getRect(lastChoice).bottom,
    lessThan(tester.getRect(apply).top),
  );
  expect(tester.takeException(), isNull);
}

void _expectPortraitPanes(WidgetTester tester) {
  final list = tester.getRect(find.byKey(const Key('quest-list-panel')));
  final detail = tester.getRect(find.byKey(const Key('quest-detail-panel')));
  expect(list.bottom, lessThanOrEqualTo(detail.top));
  expect(list.height, lessThanOrEqualTo((detail.bottom - list.top) * .5 + 1));
  expect(detail.height, greaterThan(0));
  expect(find.byKey(const Key('quest-back-to-list')), findsNothing);
}

ScrollPosition _portraitListPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('quest-list-panel')),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

Future<void> _selectPortraitQuest(WidgetTester tester, int id) async {
  final card = find.byKey(Key('quest-card-$id'));
  await tester.scrollUntilVisible(
    card,
    180,
    scrollable: find.descendant(
      of: find.byKey(const Key('quest-list-panel')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.tap(card);
  await tester.pumpAndSettle();
  _expectPortraitPanes(tester);
  expect(find.byKey(Key('quest-detail-title-$id')), findsOneWidget);
}

class _PublicCatalogPreviewStore extends QuestStore {
  _PublicCatalogPreviewStore(this.catalog, this.questIds);

  final QuestCatalog catalog;
  final List<int> questIds;

  @override
  Future<Map<int, GameQuest>> loadQuests() async => <int, GameQuest>{
    for (final id in questIds)
      if (catalog.byGameId(id) case final entry?)
        id: GameQuest(
          id: id,
          title: entry.name,
          detail: entry.description,
          category: entry.category,
          type: entry.period,
          state: 2,
          progressFlag: id == 201 ? 1 : 0,
          materials: entry.materials,
          progressCurrent: id == 201 ? 1 : null,
          progressRequired: id == 201 ? 2 : null,
        ),
  };

  @override
  Future<void> saveQuests(Map<int, GameQuest> quests) async {}

  @override
  Future<void> clearQuests() async {}
}
