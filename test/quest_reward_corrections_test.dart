import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/quest/quest_catalog.dart';

void main() {
  final raw =
      jsonDecode(File('assets/data/quests-scn.json').readAsStringSync())
          as Map<String, dynamic>;
  final cases = <int, String>{
    131: '開発資材×3',
    315: '給糧艦「間宮」, プレゼント箱',
    602: '開発資材',
    603: '開発資材, 高速建造材',
    1029:
        '二回選択報酬：[開発資材×13、新型砲熕兵装資材×2、改修資材×5]'
        '[25mm三連装機銃★9×2、13号対空電探改(後期型)★8、12.7cm連装砲D型改二★7]',
  };

  for (final item in cases.entries) {
    test('corrects independently verified reward for quest ${item.key}', () {
      final source = Map<String, Object?>.from(raw['${item.key}'] as Map);
      final before = jsonEncode(source);

      final entry = QuestCatalogEntry.fromJson(item.key, source);

      expect(entry.rewards, item.value);
      expect(
        jsonEncode(source),
        before,
        reason: 'preserve upstream provenance',
      );
    });
  }

  test('landing convoy exercise awards 100 steel despite upstream blank', () {
    final source = Map<String, Object?>.from(raw['380'] as Map);
    final before = jsonEncode(source);

    final entry = QuestCatalogEntry.fromJson(380, source);

    expect(entry.materials, <int>[100, 100, 100, 100]);
    expect(entry.rewards, source['rewards']);
    expect(jsonEncode(source), before);
  });

  test('updated upstream rewards take precedence over legacy corrections', () {
    for (final id in <int>[131, 315, 380, 602, 603, 1029]) {
      final source = Map<String, Object?>.from(raw['$id'] as Map)
        ..['rewards'] = '新しい報酬×9';
      expect(QuestCatalogEntry.fromJson(id, source).rewards, '新しい報酬×9');
      if (id == 380) {
        source['resources'] = <List<int>>[
          <int>[100, 100, 300, 100],
          <int>[0, 0, 0, 0],
        ];
        expect(QuestCatalogEntry.fromJson(id, source).materials, <int>[
          100,
          100,
          300,
          100,
        ]);
      }
    }
  });

  test('corrections require matching code and both resource rows', () {
    for (final id in cases.keys) {
      final original = Map<String, Object?>.from(raw['$id'] as Map);
      final differentCode = <String, Object?>{...original, 'code': 'new-code'};
      expect(
        QuestCatalogEntry.fromJson(id, differentCode).rewards,
        original['rewards'],
      );
      for (var row = 0; row < 2; row++) {
        final resources = (original['resources'] as List)
            .map((values) => List<num>.from(values as List))
            .toList();
        resources[row][0] += 1;
        final differentResources = <String, Object?>{
          ...original,
          'resources': resources,
        };
        expect(
          QuestCatalogEntry.fromJson(id, differentResources).rewards,
          original['rewards'],
          reason: '$id changed resource row $row',
        );
      }
    }
  });
}
