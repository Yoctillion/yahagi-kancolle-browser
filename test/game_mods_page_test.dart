import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_controller.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_page.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_models.dart';

import 'game_mods_controller_test.dart' show FakeGameModsPort;
import 'support/game_mod_portrait_platform_mock.dart';

void main() {
  setUp(mockGameModPortraitPlatform);
  tearDown(clearGameModPortraitPlatformMock);
  for (final resource in const [
    (
      kind: 'ship',
      path: 'kcs2/resources/ship/full/0607_tciiyagxjjpu.png',
      rawLabel: '0607 · full',
      spokenLabel: '0607 · 全身立绘',
    ),
    (
      kind: 'audio',
      path: 'kcs/sound/kcxngurirfszwi/107404.mp3',
      rawLabel: '',
      spokenLabel: '语音 · 107404',
    ),
  ]) {
    testWidgets(
      '${resource.kind} resource accessibility label follows its checked state',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final config = const GameModsConfig(
          master: true,
          order: ['resources'],
          enabledPackages: {'resources'},
          enabledResources: {'resource'},
        );
        final port = FakeGameModsPort()
          ..current = GameModsStatus(
            packages: [
              GameModPackage(
                id: 'resources',
                name: 'Resources',
                resources: [
                  GameModResource(
                    id: 'resource',
                    path: resource.path,
                    kind: resource.kind,
                    label: resource.rawLabel,
                    supported: true,
                  ),
                ],
              ),
            ],
            draft: config,
            applied: config,
            winners: {resource.path: 'resource'},
            activeWinners: {resource.path: 'resource'},
          );
        final controller = GameModsController(port: port);
        try {
          await controller.initialize();
          await tester.pumpWidget(
            MaterialApp(
              locale: const Locale('zh'),
              supportedLocales: const [Locale('zh')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: Scaffold(body: GameModsPage(controller: controller)),
            ),
          );
          final details = find.byKey(const Key('game-mods-details-resources'));
          await tester.ensureVisible(details);
          await tester.pumpAndSettle();
          await tester.tap(details);
          await tester.pumpAndSettle();
          final toggle = find.byKey(const Key('game-mods-resource-resource'));
          expect(tester.widget<Switch>(toggle).value, isTrue);
          expect(
            tester.getSemantics(toggle).label,
            contains('已开启 ${resource.spokenLabel}'),
          );
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          expect(tester.widget<Switch>(toggle).value, isFalse);
          expect(
            tester.getSemantics(toggle).label,
            contains('已关闭 ${resource.spokenLabel}'),
          );
          expect(
            tester.getSemantics(toggle).label,
            isNot(contains('已开启 ${resource.spokenLabel}')),
          );
          expect(port.applyCalls, 0);
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          expect(tester.widget<Switch>(toggle).value, isTrue);
          expect(
            tester.getSemantics(toggle).label,
            contains('已开启 ${resource.spokenLabel}'),
          );
          expect(
            tester.getSemantics(toggle).label,
            isNot(contains('已关闭 ${resource.spokenLabel}')),
          );
          await tester.pumpWidget(const SizedBox());
        } finally {
          controller.dispose();
          semantics.dispose();
        }
      },
    );
  }

  testWidgets('package accessibility label follows its checked state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final port = FakeGameModsPort();
      final controller = GameModsController(port: port);
      await controller.initialize();
      controller.setPackageEnabled('a', false);
      await controller.flushDraft();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(body: GameModsPage(controller: controller)),
        ),
      );
      final toggle = find.byKey(const Key('game-mods-package-a'));
      expect(tester.widget<Switch>(toggle).value, isFalse);
      expect(tester.getSemantics(toggle).label, contains('已关闭 Ocean'));
      expect(tester.getSemantics(toggle).label, isNot(contains('已开启 Ocean')));
      expect(find.bySemanticsLabel('已开启 Ocean'), findsNothing);
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(toggle).value, isTrue);
      expect(tester.getSemantics(toggle).label, contains('已开启 Ocean'));
      expect(tester.getSemantics(toggle).label, isNot(contains('已关闭 Ocean')));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    } finally {
      semantics.dispose();
    }
  });

  for (final language in const [
    (
      locale: Locale('zh'),
      counts: '4 个文件，识别 3 项资源：支持 0 项，不支持 3 项',
      reason: '坐标配置未找到匹配的舰娘图片，无法启用',
      importLabel: '仅导入支持的内容',
      cancel: '取消',
    ),
    (
      locale: Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      counts: '4 個檔案，辨識 3 項資源：支援 0 項，不支援 3 項',
      reason: '座標設定找不到匹配的艦娘圖片，無法啟用',
      importLabel: '僅匯入支援的內容',
      cancel: '取消',
    ),
    (
      locale: Locale('ja'),
      counts: '4 ファイル・素材 3 件：対応 0・非対応 3',
      reason: '座標設定に対応する艦娘画像が見つからないため使用できません',
      importLabel: '対応素材のみインポート',
      cancel: 'キャンセル',
    ),
    (
      locale: Locale('en'),
      counts: '4 files, 3 resources: 0 supported, 3 unsupported',
      reason:
          'No matching ship image was found for this coordinate configuration',
      importLabel: 'Import supported content only',
      cancel: 'Cancel',
    ),
    (
      locale: Locale('ko'),
      counts: '4개 파일, 리소스 3개: 지원 0개, 미지원 3개',
      reason: '이 좌표 설정과 일치하는 함선 이미지를 찾지 못했습니다',
      importLabel: '지원하는 항목만 가져오기',
      cancel: '취소',
    ),
  ]) {
    testWidgets(
      'unmatched coordinate archive explains why and cannot import (${language.locale})',
      (tester) async {
        // Two image sources plus compatible INI/JSON become three logical
        // resources. An unresolved binding must still block this import.
        final port = FakeGameModsPort()
          ..candidate = const GameModsPreflight(
            token: 'coordinate-preflight',
            name: 'Unbound coordinate pack',
            sourceFileCount: 4,
            resourceCount: 3,
            supportedCount: 0,
            unsupportedCount: 3,
            warnings: ['coordinate_unmatched'],
          );
        final controller = GameModsController(port: port);
        await controller.initialize();
        await tester.pumpWidget(
          MaterialApp(
            locale: language.locale,
            supportedLocales: [language.locale],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(body: GameModsPage(controller: controller)),
          ),
        );
        await tester.tap(find.byKey(const Key('game-mods-import')));
        await tester.pumpAndSettle();

        expect(find.text('Unbound coordinate pack'), findsOneWidget);
        expect(find.text(language.counts), findsOneWidget);
        expect(find.text(language.reason), findsOneWidget);
        expect(find.text('coordinate_unmatched'), findsNothing);
        final importButton = find.widgetWithText(
          FilledButton,
          language.importLabel,
        );
        expect(tester.widget<FilledButton>(importButton).onPressed, isNull);
        await tester.tap(importButton);
        await tester.pump();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(port.commitCalls, 0);
        expect(port.applyCalls, 0);

        final cancelButton = find.widgetWithText(TextButton, language.cancel);
        expect(tester.widget<TextButton>(cancelButton).onPressed, isNotNull);
        await tester.tap(cancelButton);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(controller.preflight, isNull);
        expect(port.discarded, ['coordinate-preflight']);
        expect(port.commitCalls, 0);
        expect(port.saved, isEmpty);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }

  testWidgets(
    'legacy coordinate imports remain locked until reimport rather than silently enabling',
    (tester) async {
      final package = GameModPackage.fromMap({
        'id': 'coordinate-pack',
        'name': '伊47',
        'warnings': ['coordinates_unsupported'],
        'resources': [
          for (final type in ['full', 'full_dmg'])
            {
              'id': type,
              'path': 'kcs2/resources/ship/$type/0607_tciiyagxjjpu.png',
              'kind': 'ship',
              'label': '0607 · $type',
              'groupId': 'ship:0607',
              'supported': false,
              'reason': 'coordinate_dependency',
            },
          for (final extension in ['ini', 'json'])
            {
              'id': extension,
              'path': 'tciiyagxjjpu.config.$extension',
              'kind': 'coordinates',
              'supported': false,
              'reason': 'coordinates_unsupported',
            },
        ],
      });
      const config = GameModsConfig(order: ['coordinate-pack']);
      final port = FakeGameModsPort()
        ..current = GameModsStatus(
          packages: [package],
          draft: config,
          applied: config,
        );
      final controller = GameModsController(port: port);
      await controller.initialize();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(body: GameModsPage(controller: controller)),
        ),
      );
      final packageToggle = find.byKey(
        const Key('game-mods-package-coordinate-pack'),
      );
      expect(tester.widget<Switch>(packageToggle).value, isFalse);
      expect(tester.widget<Switch>(packageToggle).onChanged, isNull);
      final details = find.byKey(
        const Key('game-mods-details-coordinate-pack'),
      );
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(find.text('此包由旧版导入，请重新导入以启用坐标支持'), findsWidgets);
      expect(find.text('全部选择'), findsNothing);
      expect(find.text('全部取消'), findsNothing);
      for (final id in ['full', 'full_dmg', 'ini', 'json']) {
        final toggle = find.byKey(Key('game-mods-resource-$id'));
        await tester.scrollUntilVisible(
          toggle,
          120,
          scrollable: find.byType(Scrollable).last,
        );
        final resourceSwitch = tester.widget<Switch>(toggle);
        expect(
          resourceSwitch.value,
          isFalse,
          reason: '$id must not look active',
        );
        expect(resourceSwitch.onChanged, isNull, reason: '$id is unsupported');
      }
      expect(port.saved, isEmpty);
      expect(port.applyCalls, 0);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('failed draft save is shown as unsaved rather than saved', (
    tester,
  ) async {
    final port = FakeGameModsPort()..failSave = true;
    final controller = GameModsController(port: port);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GameModsPage(controller: controller)),
      ),
    );
    await tester.tap(find.byKey(const Key('game-mods-master')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('game-mods-details-a')),
      160,
    );
    expect(find.text('Choices not saved'), findsWidgets);
    expect(find.text('Choices saved'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'large resource groups are traversed linearly when opening details',
    (tester) async {
      final resources = _CountingList(
        List.generate(
          400,
          (i) => GameModResource(
            id: 'r$i',
            path: 'kcs2/resources/ship/full/0001_$i.png',
            kind: 'ship',
            label: '0001 · full',
            supported: true,
            groupId: 'ship:0001',
          ),
        ),
      );
      final config = GameModsConfig(
        master: true,
        order: ['large'],
        enabledPackages: {'large'},
        enabledResources: {for (var i = 0; i < 400; i++) 'r$i'},
      );
      final port = FakeGameModsPort()
        ..current = GameModsStatus(
          packages: [
            GameModPackage(id: 'large', name: 'Large', resources: resources),
          ],
          draft: config,
          applied: config,
        );
      final controller = GameModsController(port: port);
      await controller.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GameModsPage(controller: controller)),
        ),
      );
      await tester.ensureVisible(
        find.byKey(const Key('game-mods-details-large')),
      );
      await tester.pumpAndSettle();
      resources.reads = 0;
      await tester.tap(find.byKey(const Key('game-mods-details-large')));
      await tester.pumpAndSettle();
      expect(resources.reads, lessThan(400 * 100));
      expect(find.byType(ExpansionTile).evaluate().length, lessThan(20));
      resources.reads = 0;
      await tester.tap(find.text('Deselect all'));
      await tester.pumpAndSettle();
      expect(resources.reads, lessThan(400 * 100));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets('choices stay pending until the fixed apply action', (
    tester,
  ) async {
    final port = FakeGameModsPort();
    final controller = GameModsController(port: port);
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: Scaffold(body: GameModsPage(controller: controller)),
      ),
    );
    await tester.pump();
    final switchContext = tester.element(
      find.byKey(const Key('game-mods-master')),
    );
    final theme = Theme.of(switchContext);
    const selected = {WidgetState.selected};
    expect(
      theme.switchTheme.thumbColor?.resolve(selected),
      isNot(
        theme.switchTheme.trackColor?.resolve(selected) ??
            theme.colorScheme.primary,
      ),
    );
    await tester.tap(find.byKey(const Key('game-mods-master')));
    await tester.pump();
    expect(find.text('Changes pending'), findsWidgets);
    expect(port.applyCalls, 0);
    await tester.tap(find.byKey(const Key('game-mods-apply')));
    await tester.pump();
    await tester.pump();
    expect(port.applyCalls, 1);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('resource details explain no hits and lock unsupported entries', (
    tester,
  ) async {
    final controller = GameModsController(port: FakeGameModsPort());
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        home: Scaffold(body: GameModsPage(controller: controller)),
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('game-mods-details-b')),
      180,
    );
    await tester.ensureVisible(find.byKey(const Key('game-mods-details-b')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('game-mods-details-b')));
    await tester.pumpAndSettle();
    expect(find.text('No load recorded yet'), findsWidgets);
    final unsupported = tester.widget<Switch>(
      find.byKey(const Key('game-mods-resource-b2')),
    );
    expect(unsupported.onChanged, isNull);
    expect(find.text('Deselect all'), findsOneWidget);
    await tester.tap(find.byKey(const Key('game-mods-remove-b')));
    await tester.pumpAndSettle();
    expect(find.textContaining('after applying'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('narrow layout and large text keep actions reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = GameModsController(port: FakeGameModsPort());
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: Scaffold(body: GameModsPage(controller: controller)),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('game-mods-apply')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('game-mods-apply'))).height,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester.getSize(find.byKey(const Key('game-mods-import'))).height,
      greaterThanOrEqualTo(44),
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'partial import requires explicit supported-content confirmation',
    (tester) async {
      final port = FakeGameModsPort()
        ..candidate = const GameModsPreflight(
          token: 'zip',
          name: 'cache.zip',
          resourceCount: 3,
          supportedCount: 2,
          unsupportedCount: 1,
          warnings: ['coordinates_unsupported'],
        );
      final controller = GameModsController(port: port);
      await controller.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GameModsPage(controller: controller)),
        ),
      );
      await tester.tap(find.byKey(const Key('game-mods-import')));
      await tester.pumpAndSettle();
      expect(port.commitCalls, 0);
      expect(find.text('Import supported content only'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(port.discarded, ['zip']);
      expect(port.commitCalls, 0);
      await tester.tap(find.byKey(const Key('game-mods-import')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import supported content only'));
      await tester.pumpAndSettle();
      expect(port.commitCalls, 1);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}

class _CountingList<E> extends ListBase<E> {
  _CountingList(this.values);
  final List<E> values;
  int reads = 0;
  @override
  int get length => values.length;
  @override
  set length(int value) => values.length = value;
  @override
  E operator [](int index) {
    reads++;
    return values[index];
  }

  @override
  void operator []=(int index, E value) => values[index] = value;
}
