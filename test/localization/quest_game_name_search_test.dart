import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/localization/game_name_catalog.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_catalog.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_kc3_bundle.dart';

void main() {
  late ShipSubtitleKc3Bundle bundle;
  setUpAll(() {
    bundle = ShipSubtitleKc3Bundle.fromJsonString(
      File(ShipSubtitleKc3Bundle.bundledAsset).readAsStringSync(),
    );
  });

  const source = 'Bofors 40mm四連装機関砲';
  const translatedWords = {'en': 'quadruple', 'ko': '보포스'};
  const fields = [
    'name',
    'description',
    'translatedName',
    'translatedDescription',
    'rewards',
    'memo',
    'liveTitle',
    'liveDetail',
  ];
  for (final language in translatedWords.entries) {
    for (final field in fields) {
      test('${language.key} translated $field is searchable independently', () {
        final names = GameNameCatalog(
          locale: Locale(language.key),
          bundle: bundle,
        );
        final item = _itemWithField(field, source);
        final word = language.value;
        expect(names.equipmentName(source).toLowerCase(), contains(word));
        expect(item.matchesSearch([word]), isFalse);
        expect(
          item.matchesSearch([word], displayText: names.entityText),
          isTrue,
        );
        expect(
          item.matchesSearch([
            'no-match-query',
            word,
          ], displayText: names.entityText),
          isTrue,
          reason: 'Each keyword keeps the existing any-match semantics.',
        );
        expect(
          item.matchesSearch([
            'no-match-query',
            'bofors',
          ], displayText: names.entityText),
          isTrue,
          reason: 'The original source remains searchable.',
        );
        expect(
          item.matchesSearch(['no-match-query'], displayText: names.entityText),
          isFalse,
        );
      });
    }
  }

  test(
    'search conversion receives original case and leaves stored data intact',
    () {
      final item = _itemWithField('rewards', source);
      final names = GameNameCatalog(locale: const Locale('en'), bundle: bundle);
      String? converted;
      expect(
        item.matchesSearch(
          ['quadruple'],
          displayText: (text) {
            converted = text;
            return names.entityText(text);
          },
        ),
        isTrue,
      );
      expect(converted, contains(source));
      expect(item.entry.rewards, source);
      expect(item.matchesSearch(['f999999']), isTrue);
      expect(item.matchesSearch(['999999']), isTrue);
      expect(item.matchesSearch([]), isTrue);
    },
  );
}

QuestCatalogItem _itemWithField(String field, String source) =>
    QuestCatalogItem(
      entry: QuestCatalogEntry(
        gameId: 999999,
        code: 'F999999',
        name: field == 'name' ? source : 'Catalog title',
        description: field == 'description' ? source : 'Catalog detail',
        translatedName: field == 'translatedName' ? source : null,
        translatedDescription: field == 'translatedDescription' ? source : null,
        rewards: field == 'rewards' ? source : '',
        memo: field == 'memo' ? source : '',
      ),
      liveQuest: GameQuest(
        id: 999999,
        title: field == 'liveTitle' ? source : 'Live title',
        detail: field == 'liveDetail' ? source : 'Live detail',
        category: 6,
        type: 4,
        state: 2,
        progressFlag: 0,
      ),
      unlockState: QuestUnlockState.unlocked,
      inferredCompleted: false,
    );
