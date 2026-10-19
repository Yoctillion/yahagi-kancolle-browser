import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_controller.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_models.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_page.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_strings.dart';

import 'game_mods_controller_test.dart' show FakeGameModsPort;
import 'support/game_mod_portrait_platform_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(mockGameModPortraitPlatform);
  tearDown(clearGameModPortraitPlatformMock);

  test(
    'optional partial telemetry survives mapping, draft edits and fresh runtime merges',
    () {
      expect(GameModsStatus.fromMap({}).partialHits, isEmpty);
      final initial = _voiceStatus(partial: ['voice-0', 'voice-0']);
      expect(initial.partialHits, {'voice-0'});
      expect(initial.toMap()['partialHits'], ['voice-0']);
      final edited = initial.withDraft(initial.draft.copyWith(master: false));
      expect(edited.partialHits, {'voice-0'});
      final fresh = _voiceStatus(
        session: 2,
        full: ['voice-0'],
        partial: ['voice-0', 'voice-1'],
      );
      final merged = edited.withRuntimeFrom(fresh);
      expect(merged.draft.master, isFalse);
      expect(merged.hits, {'voice-0'});
      expect(merged.partialHits, {'voice-0', 'voice-1'});
      expect(merged.partialOnlyHits, {'voice-1'});
      expect(merged.withRuntimeFrom(initial).sessionId, 2);
      expect(merged.withRuntimeFrom(initial).partialOnlyHits, {'voice-1'});
    },
  );

  test(
    'partial telemetry follows a late poll without overwriting newer voice choices',
    () async {
      final port = FakeGameModsPort()..current = _voiceStatus(partial: []);
      final controller = GameModsController(port: port);
      addTearDown(controller.dispose);
      await controller.initialize();
      final response = Completer<GameModsStatus>();
      port.statusGate = response;
      final polling = controller.refresh();
      controller.setResourceEnabled('voice-0', false);
      await controller.flushDraft();
      response.complete(_voiceStatus(partial: ['voice-0']));
      await polling;
      expect(
        controller.status.draft.enabledResources.contains('voice-0'),
        isFalse,
      );
      expect(controller.status.partialHits, {'voice-0'});
    },
  );

  test(
    'older native session snapshots cannot replace current voice telemetry',
    () async {
      final port = FakeGameModsPort()
        ..current = _voiceStatus(session: 3, partial: ['voice-1']);
      final controller = GameModsController(port: port);
      addTearDown(controller.dispose);
      await controller.initialize();
      port.current = _voiceStatus(session: 2, partial: ['voice-0']);
      await controller.refresh();
      expect(controller.status.sessionId, 3);
      expect(controller.status.partialHits, {'voice-1'});
    },
  );

  testWidgets(
    'voice package preflight reports 54 supported files and cleaned copies before importing',
    (tester) async {
      final port = FakeGameModsPort()
        ..candidate = const GameModsPreflight(
          token: 'voice-import',
          name: 'Voice pack',
          resourceCount: 59,
          supportedCount: 54,
          unsupportedCount: 5,
          warnings: [
            'png_trailing_data_removed',
            'unsupported_audio_files',
            'unsupported_files',
          ],
        );
      final controller = GameModsController(port: port);
      await controller.initialize();
      await tester.pumpWidget(_app(controller));
      await tester.tap(find.byKey(const Key('game-mods-import')));
      await tester.pumpAndSettle();
      expect(
        find.text('59 found: 54 supported, 5 unsupported'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Extra trailing data was removed from imported image copies; the source archive is unchanged',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(
                FilledButton,
                'Import supported content only',
              ),
            )
            .onPressed,
        isNotNull,
      );
      expect(port.commitCalls, 0);
      expect(
        find.text('Unable to complete this operation; retry or check the logs'),
        findsNothing,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(port.discarded, ['voice-import']);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  for (final language in const [
    (
      locale: Locale('zh'),
      counts: '发现 59 项：支持 54 项，不支持 5 项',
      warning: '部分音频不符合游戏替换规则，将跳过；支持的 MP3 / WAV 仍可导入',
      failure: '无法完成此操作，请重试或查看日志',
    ),
    (
      locale: Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      counts: '發現 59 項：支援 54 項，不支援 5 項',
      warning: '部分音訊不符合遊戲替換規則，將略過；支援的 MP3 / WAV 仍可匯入',
      failure: '無法完成此操作，請重試或檢視日誌',
    ),
    (
      locale: Locale('ja'),
      counts: '59 件：対応 54・非対応 5',
      warning: '置換条件を満たさない音声はスキップします。対応する MP3 / WAV はインポートできます',
      failure: '操作を完了できません。再試行またはログを確認してください',
    ),
    (
      locale: Locale('en'),
      counts: '59 found: 54 supported, 5 unsupported',
      warning:
          'Unsupported audio files will be skipped; supported MP3 / WAV voices can still be imported',
      failure: 'Unable to complete this operation; retry or check the logs',
    ),
    (
      locale: Locale('ko'),
      counts: '59개 발견: 지원 54개, 미지원 5개',
      warning: '대체 조건에 맞지 않는 오디오는 건너뜁니다. 지원하는 MP3 / WAV 음성은 계속 가져올 수 있습니다',
      failure: '작업을 완료하지 못했습니다. 다시 시도하거나 로그를 확인하세요',
    ),
  ]) {
    testWidgets(
      'unsupported audio warning is nonfatal in a 59/54/5 import (${language.locale})',
      (tester) async {
        final port = FakeGameModsPort()
          ..candidate = const GameModsPreflight(
            token: 'audio-warning',
            name: 'Voice pack',
            resourceCount: 59,
            supportedCount: 54,
            unsupportedCount: 5,
            warnings: [
              'png_trailing_data_removed',
              'unsupported_audio_files',
              'unsupported_files',
            ],
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
        expect(find.text(language.counts), findsOneWidget);
        expect(find.text(language.warning), findsOneWidget);
        expect(find.text(language.failure), findsNothing);
        expect(
          tester
              .widget<FilledButton>(
                find.descendant(
                  of: find.byType(AlertDialog),
                  matching: find.byType(FilledButton),
                ),
              )
              .onPressed,
          isNotNull,
        );
        expect(controller.errorCode, isNull);
        expect(port.commitCalls, 0);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }

  test(
    'a poll from the old game session cannot restore old partial voice records',
    () async {
      final port = FakeGameModsPort()
        ..current = _voiceStatus(partial: ['voice-0']);
      final controller = GameModsController(port: port);
      addTearDown(controller.dispose);
      await controller.initialize();
      final oldResponse = Completer<GameModsStatus>();
      port.statusGate = oldResponse;
      final polling = controller.refresh();
      port.statusGate = null;
      port.current = _voiceStatus(session: 2, full: ['voice-1'], partial: []);
      await controller.apply();
      oldResponse.complete(_voiceStatus(partial: ['voice-0']));
      await polling;
      expect(controller.status.sessionId, 2);
      expect(controller.status.partialHits, isEmpty);
      expect(controller.status.hits, {'voice-1'});
    },
  );

  testWidgets(
    'partial voice bytes are distinct from a full file and from no load record',
    (tester) async {
      final port = FakeGameModsPort()
        ..current = _voiceStatus(partial: ['voice-0']);
      final controller = GameModsController(port: port);
      await controller.initialize();
      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('1 voice resource partially provided'),
        findsWidgets,
      );
      expect(find.text('No load recorded yet'), findsNothing);
      await tester.ensureVisible(
        find.byKey(const Key('game-mods-details-voice-pack')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('game-mods-details-voice-pack')));
      await tester.pumpAndSettle();
      expect(find.text('Voice · 107404'), findsOneWidget);
      expect(find.text('1 voice resource partially provided'), findsWidgets);
      expect(
        find.text('1 complete replacement resource provided'),
        findsNothing,
      );
      port.current = _voiceStatus(full: ['voice-0'], partial: ['voice-0']);
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(find.text('1 voice resource partially provided'), findsNothing);
      expect(
        find.text('1 complete replacement resource provided'),
        findsWidgets,
      );
      expect(find.text('Played'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'real package shape keeps 25 voices independent of 29 images and 5 unsupported entries',
    (tester) async {
      final port = FakeGameModsPort()..current = _voiceStatus();
      final controller = GameModsController(port: port);
      await controller.initialize();
      expect(controller.status.packages.single.resources.length, 59);
      await tester.pumpWidget(_app(controller));
      await tester.ensureVisible(
        find.byKey(const Key('game-mods-details-voice-pack')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('game-mods-details-voice-pack')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('game-mods-resource-voice-0')));
      await tester.pumpAndSettle();
      expect(
        controller.status.draft.enabledResources.contains('voice-0'),
        isFalse,
      );
      expect(
        controller.status.draft.enabledResources.contains('voice-1'),
        isTrue,
      );
      expect(
        controller.status.draft.enabledResources.contains('image-0'),
        isTrue,
      );
      await tester.tap(find.text('Select all').first);
      await tester.pumpAndSettle();
      expect(
        controller.status.draft.enabledResources
            .where((id) => id.startsWith('voice-'))
            .length,
        25,
      );
      await tester.tap(find.text('Deselect all').first);
      await tester.pumpAndSettle();
      expect(
        controller.status.draft.enabledResources.where(
          (id) => id.startsWith('voice-'),
        ),
        isEmpty,
      );
      expect(
        controller.status.draft.enabledResources
            .where((id) => id.startsWith('image-'))
            .length,
        29,
      );
      for (var index = 0; index < 5; index++) {
        final toggle = find.byKey(Key('game-mods-resource-unsupported-$index'));
        await tester.scrollUntilVisible(
          toggle,
          240,
          scrollable: find.byType(Scrollable).last,
        );
        expect(tester.widget<Switch>(toggle).value, isFalse);
        expect(tester.widget<Switch>(toggle).onChanged, isNull);
      }
      expect(port.applyCalls, 0);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  test(
    'numeric voice paths share the same conflict priority resolver as images',
    () async {
      final original = _voiceStatus();
      final duplicate = original.packages.single.resources.first;
      final port = FakeGameModsPort()
        ..current = GameModsStatus.fromMap({
          ...original.toMap(),
          'packages': [
            ...original.packages.map((p) => p.toMap()),
            {
              'id': 'override',
              'name': 'Alternate voice',
              'resources': [
                {...duplicate.toMap(), 'id': 'alternate'},
              ],
            },
          ],
          'draft': {
            ...original.draft.toMap(),
            'order': ['voice-pack', 'override'],
            'enabledPackages': ['voice-pack', 'override'],
            'enabledResources': [
              ...original.draft.enabledResources,
              'alternate',
            ],
          },
        });
      final controller = GameModsController(port: port);
      addTearDown(controller.dispose);
      await controller.initialize();
      controller.movePackage('override', -1);
      expect(controller.status.winners[duplicate.path], 'alternate');
      controller.setResourceEnabled('alternate', false);
      expect(controller.status.winners[duplicate.path], 'voice-0');
      await controller.flushDraft();
      expect(port.applyCalls, 0);
    },
  );

  test(
    'five locales explain voice paths, partial reads and cleaned image copies',
    () {
      final descriptions = <String>{};
      for (final locale in const [
        Locale('zh'),
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        Locale('ja'),
        Locale('en'),
        Locale('ko'),
      ]) {
        final s = GameModsStrings(locale);
        expect(s.importHint, contains('MP3'));
        expect(s.helpBody, contains('MP3'));
        expect(s.partialProvided(1), isNotEmpty);
        for (final code in [
          'audio_filename_unsupported',
          'audio_path_unsupported',
          'audio_format_unsupported',
          'invalid_audio',
          'png_trailing_data_removed',
          'seven_zip_unsupported',
        ]) {
          expect(
            s.reason(code),
            isNot(s.reason('unknown_failure')),
            reason: '$locale $code',
          );
        }
        descriptions.add(s.reason('png_trailing_data_removed'));
      }
      expect(descriptions.length, 5);
      final zh = GameModsStrings(const Locale('zh'));
      expect(
        zh.resourceLabel(_voiceStatus().packages.single.resources.first, 1),
        '语音 · 107404',
      );
      expect(zh.reason('seven_zip_unsupported'), contains('7z'));
      expect(zh.reason('seven_zip_unsupported'), contains('ZIP'));
      expect(zh.reason('invalid_audio'), zh.reason('invalid_mp3'));
    },
  );
  test(
    'unsupported backup audio keeps its readable basename beside the lock reason',
    () {
      final s = GameModsStrings(const Locale('zh'));
      final backup = GameModResource.fromMap({
        'id': 'backup',
        'path': 'backup/结婚.mp3',
        'kind': 'audio',
        'supported': false,
        'reason': 'audio_filename_unsupported',
      });
      final wav = GameModResource.fromMap({
        'id': 'wav',
        'path': 'spares/击沉.WAV',
        'kind': 'audio',
        'supported': false,
        'reason': 'audio_format_unsupported',
      });
      expect(s.resourceLabel(backup, 1), '语音 · 结婚.mp3');
      expect(s.resourceLabel(wav, 2), '语音 · 击沉.WAV');
      expect(backup.supported, isFalse);
      expect(wav.supported, isFalse);
    },
  );

  for (final language in const [
    (
      locale: Locale('zh'),
      numericId: '游戏的数字编号',
      encoding: '编码',
      reimport: '重新导入',
    ),
    (
      locale: Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      numericId: '遊戲的數字編號',
      encoding: '編碼',
      reimport: '重新匯入',
    ),
    (
      locale: Locale('ja'),
      numericId: 'ゲームの数字ID',
      encoding: 'エンコード',
      reimport: '再インポート',
    ),
    (
      locale: Locale('en'),
      numericId: 'numeric game IDs',
      encoding: 'encoding',
      reimport: 'reimport',
    ),
    (
      locale: Locale('ko'),
      numericId: '게임의 숫자 ID',
      encoding: '인코딩',
      reimport: '다시 가져',
    ),
  ]) {
    final s = GameModsStrings(language.locale);
    test(
      'WAV import guidance retains game IDs and supported encodings (${language.locale})',
      () {
        expect(s.importHint, contains('MP3 / WAV'));
        expect(s.helpBody, contains('MP3 / WAV'));
        expect(s.helpBody, contains(language.numericId));
        expect(s.helpBody, contains('PCM'));
        expect(s.helpBody, contains('IEEE'));
        expect(s.helpBody, contains('32'));
      },
    );
    test(
      'audio validation failure does not misidentify WAV as MP3 (${language.locale})',
      () {
        final message = s.reason('invalid_audio');
        expect(message, isNot(s.reason('unknown_failure')));
        expect(message, isNot(contains('MP3')));
        expect(message, contains(language.encoding));
        expect(s.reason('invalid_mp3'), message);
      },
    );
    test(
      'legacy unsupported WAV asks for reimport instead of denying WAV support (${language.locale})',
      () {
        final message = s.reason('audio_format_unsupported');
        expect(message, contains(language.encoding));
        expect(message, contains('WAV'));
        expect(message, contains(language.reimport));
        expect(s.reason('unsupported_audio_type'), message);
        expect(s.reason('unsupported_audio_files'), contains('MP3 / WAV'));
      },
    );
  }

  test(
    'numeric WAV labels match canonical MP3 labels and keep source paths',
    () {
      final s = GameModsStrings(const Locale('zh'));
      final canonical = GameModResource.fromMap({
        'id': 'wav',
        'path': 'kcs/sound/kcxngurirfszwi/107404.mp3',
        'sourcePaths': ['cache/kcs/sound/kcxngurirfszwi/107404.hack.wav'],
        'kind': 'audio',
        'supported': true,
      });
      final direct = GameModResource.fromMap({
        'id': 'wav-direct',
        'path': 'kcs/sound/kcxngurirfszwi/107404.WAV',
        'kind': 'audio',
        'supported': true,
      });
      expect(s.resourceLabel(canonical, 1), '语音 · 107404');
      expect(s.resourceLabel(direct, 2), '语音 · 107404');
      expect(canonical.sources, [
        'cache/kcs/sound/kcxngurirfszwi/107404.hack.wav',
      ]);
      expect(canonical.toMap()['sourcePaths'], canonical.sources);
    },
  );

  testWidgets('visible help explains WAV import without promising playback', (
    tester,
  ) async {
    final port = FakeGameModsPort()..current = _voiceStatus();
    final controller = GameModsController(port: port);
    await controller.initialize();
    await tester.pumpWidget(_app(controller));
    final s = GameModsStrings(const Locale('en'));
    await tester.tap(find.byTooltip(s.help));
    await tester.pumpAndSettle();
    final help = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.textContaining(s.helpBody),
    );
    expect(help, findsOneWidget);
    expect(tester.widget<Text>(help).data, contains('MP3 / WAV'));
    expect(tester.widget<Text>(help).data, contains('PCM'));
    expect(tester.widget<Text>(help).data, contains('IEEE'));
    expect(tester.widget<Text>(help).data, contains('numeric game IDs'));
    expect(tester.widget<Text>(help).data, contains('INI / JSON'));
    expect(
      tester.widget<Text>(help).data,
      contains('Neither proves a resource was drawn or played'),
    );
    expect(tester.widget<Text>(help).data, contains(s.syncPortraitsHelp));
    expect(
      tester.widget<Text>(help).data,
      contains('takes effect immediately'),
    );
    expect(tester.widget<Text>(help).data, contains('currently applied'));
    expect(
      tester.widget<Text>(help).data,
      contains('restores original portraits'),
    );
    expect(
      tester.widget<Text>(help).data,
      contains('without affecting in-game mods'),
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}

Widget _app(GameModsController controller) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: Scaffold(body: GameModsPage(controller: controller)),
);

GameModsStatus _voiceStatus({
  int session = 1,
  List<String> full = const [],
  List<String> partial = const [],
}) {
  final resources = <Map<String, Object?>>[
    for (var i = 0; i < 25; i++)
      {
        'id': 'voice-$i',
        'path': 'kcs/sound/kcxngurirfszwi/${107404 + i}.mp3',
        'kind': 'audio',
        'supported': true,
      },
    for (var i = 0; i < 29; i++)
      {
        'id': 'image-$i',
        'path': 'kcs2/img/port/theme_$i.png',
        'kind': 'image',
        'supported': true,
      },
    for (final (index, path, reason) in [
      (0, 'kcs/sound/kcxngurirfszwi/备份语音.mp3', 'audio_filename_unsupported'),
      (1, 'kcs/sound/kcxngurirfszwi/旧版备份.mp3', 'audio_filename_unsupported'),
      (2, 'kcs/sound/kcxngurirfszwi/107431.wav', 'audio_format_unsupported'),
      (3, 'kcs/sound/kcxngurirfszwi/107432.wav', 'audio_format_unsupported'),
      (4, 'kcs/sound/kcxngurirfszwi/107433.wav', 'audio_format_unsupported'),
    ])
      {
        'id': 'unsupported-$index',
        'path': path,
        'kind': 'audio',
        'supported': false,
        'reason': reason,
      },
  ];
  final config = {
    'master': true,
    'order': ['voice-pack'],
    'enabledPackages': ['voice-pack'],
    'enabledResources': resources
        .where((r) => r['supported'] == true)
        .map((r) => r['id'])
        .toList(),
  };
  final winners = {
    for (final r in resources.where((r) => r['supported'] == true))
      r['path']: r['id'],
  };
  return GameModsStatus.fromMap({
    'packages': [
      {
        'id': 'voice-pack',
        'name': 'Voice and image pack',
        'resources': resources,
      },
    ],
    'draft': config,
    'applied': config,
    'winners': winners,
    'activeWinners': winners,
    'hits': full,
    'partialHits': partial,
    'sessionId': session,
  });
}
