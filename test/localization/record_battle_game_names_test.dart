import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_detail_strings.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/localization/game_name_catalog.dart';
import 'package:yahagi_kancolle_browser/src/localization/game_name_localizations.dart';
import 'package:yahagi_kancolle_browser/src/logbook/logbook_filter_panel.dart';
import 'package:yahagi_kancolle_browser/src/new_ship/new_ship_reminder_controller.dart';
import 'package:yahagi_kancolle_browser/src/notification/new_ship_notification.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_kc3_bundle.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_language.dart';

import 'package:yahagi_kancolle_browser/src/battle/official_enemy_preview.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_models.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_store.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_catalog.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_center_page.dart';

void main() {
  late ShipSubtitleKc3Bundle bundle;
  setUpAll(() {
    bundle = ShipSubtitleKc3Bundle.fromJsonString(
      File(ShipSubtitleKc3Bundle.bundledAsset).readAsStringSync(),
    );
  });

  for (final locale in const [Locale('en'), Locale('ko')]) {
    testWidgets(
      'battle replay names use ${locale.languageCode} resource scope',
      (tester) async {
        final language = locale.languageCode == 'en'
            ? ShipSubtitleLanguage.english
            : ShipSubtitleLanguage.korean;
        final expected = bundle.shipName(language, '霧島改二');
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            locale: locale,
            supportedLocales: const [Locale('en'), Locale('ko')],
            builder: (context, child) =>
                GameNameLocalizationScope(bundle: bundle, child: child!),
            home: Builder(
              builder: (context) =>
                  Text(BattleDetailStrings.of(context).shipDisplayName('霧島改二')),
            ),
          ),
        );
        expect(find.text(expected), findsOneWidget);
        expect(find.text('霧島改二'), findsNothing);
      },
    );
  }

  for (final code in ['en', 'ko']) {
    testWidgets('$code battle preview translates the label and tooltip', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(code),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) =>
              GameNameLocalizationScope(bundle: bundle, child: child!),
          home: const Scaffold(
            body: OfficialEnemyPreview(
              ships: [
                EnemyPreviewShip(
                  masterId: 1501,
                  name: '駆逐イ級',
                  fleetRole: BattleFleetRole.main,
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('駆逐イ級'), findsNothing);
      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).message,
        isNot(contains('駆逐イ級')),
      );
    });
    testWidgets(
      '$code quest descriptions and rewards translate known entities',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1180, 720);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        GameStateController.disableTimerForTest = true;
        addTearDown(() => GameStateController.disableTimerForTest = false);
        final controller = GameStateController(questStore: _MemoryQuestStore());
        addTearDown(controller.dispose);
        await controller.idle;
        final catalog = QuestCatalog([
          QuestCatalogEntry.fromJson(999999, {
            'code': 'F99999',
            'name': '睦月',
            'desc': '12.7cm連装砲',
            'rewards': '12.7cm連装砲',
          }),
        ]);
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(code),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) =>
                GameNameLocalizationScope(bundle: bundle, child: child!),
            home: QuestCenterPage(
              controller: controller,
              catalog: catalog,
              mode: QuestCenterMode.all,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('睦月'), findsNothing);
        expect(find.text('12.7cm連装砲'), findsNothing);
        expect(
          find.textContaining(code == 'en' ? 'Mutsuki' : '무츠키'),
          findsWidgets,
        );
      },
    );
  }

  testWidgets(
    'locale changes refresh names and dialogs inherit the same scope',
    (tester) async {
      final locale = ValueNotifier(const Locale('en'));
      addTearDown(locale.dispose);
      await tester.pumpWidget(
        ValueListenableBuilder<Locale>(
          valueListenable: locale,
          builder: (context, current, _) => MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            locale: current,
            supportedLocales: const [Locale('en'), Locale('ko'), Locale('zh')],
            builder: (context, child) =>
                GameNameLocalizationScope(bundle: bundle, child: child!),
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    content: Text(
                      gameNames(context).equipmentName('12.7cm連装砲'),
                    ),
                  ),
                ),
                child: Text(gameNames(context).shipName('霧島改二')),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Kirishima Kai Ni'), findsOneWidget);
      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();
      expect(find.text('12.7cm Twin Gun Mount'), findsOneWidget);
      locale.value = const Locale('ko');
      await tester.pumpAndSettle();
      expect(find.text('12.7cm 연장포'), findsOneWidget);
      locale.value = const Locale('zh');
      await tester.pumpAndSettle();
      expect(find.text('霧島改二'), findsOneWidget);
      expect(find.text('12.7cm連装砲'), findsOneWidget);
    },
  );

  testWidgets(
    'record filters display translated names while preserving raw option values',
    (tester) async {
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          locale: const Locale('en'),
          builder: (context, child) =>
              GameNameLocalizationScope(bundle: bundle, child: child!),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final result = await showLogbookFilterPanel(
                  context: context,
                  anchor: const Rect.fromLTWH(0, 0, 100, 30),
                  title: '筛选',
                  fields: const [
                    LogbookFilterField(
                      keyName: 'secretary',
                      label: '秘书舰',
                      options: ['全部秘书舰', '霧島改二'],
                      preserveOptionNames: true,
                    ),
                  ],
                  values: const {'secretary': '霧島改二'},
                  defaults: const {'secretary': '全部秘书舰'},
                );
                selected = result?['secretary'];
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Kirishima Kai Ni'), findsOneWidget);
      expect(find.text('霧島改二'), findsNothing);
      expect(selected, isNull);
    },
  );

  test(
    'new ship alerts translate names without changing original master data',
    () {
      final state = GameState(
        masterShips: const {1: MasterShip(id: 1, name: '睦月', shipTypeId: 2)},
      );
      final alert = NewShipAlert(
        key: 'names',
        masterIds: const [1],
        sources: const [],
        occurredAt: DateTime.utc(2026, 10, 19),
      );
      final notification = buildNewShipNotification(
        alert: alert,
        state: state,
        localeCode: 'en',
        names: GameNameCatalog(bundle: bundle, locale: const Locale('en')),
      );
      expect(notification.body, contains('Mutsuki'));
      expect(notification.body, isNot(contains('睦月')));
      expect(state.masterShips[1]!.name, '睦月');
    },
  );
}

class _MemoryQuestStore implements QuestStore {
  @override
  Future<Map<int, GameQuest>> loadQuests() async => {};
  @override
  Future<void> saveQuests(Map<int, GameQuest> quests) async {}
  @override
  Future<void> clearQuests() async {}
}
