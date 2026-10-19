import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/localization/game_name_catalog.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_kc3_bundle.dart';

void main() {
  late ShipSubtitleKc3Bundle bundle;
  setUpAll(() async {
    bundle = ShipSubtitleKc3Bundle.fromJsonString(
      await File('assets/data/subtitles/kc3-bundle.json').readAsString(),
    );
  });

  test('repeated compound names and fields reuse their resolved results', () {
    final names = GameNameCatalog(bundle: bundle, locale: const Locale('en'));
    final ship = names.shipName('睦月改');
    expect(ship, 'Mutsuki Kai');
    expect(identical(names.shipName('睦月改'), ship), isTrue);
    final field = names.entityText('睦月改・12cm単装砲');
    expect(field, 'Mutsuki Kai・12cm Single Gun Mount');
    expect(identical(names.entityText('睦月改・12cm単装砲'), field), isTrue);
  });

  test(
    'cold unrelated ASCII remains unchanged before translated buckets open',
    () {
      final unrelated = List.filled(16, 'abcdefghijklmnopqrstuvwxyz / ').join();
      for (final language in ['en', 'ko']) {
        final names = GameNameCatalog(bundle: bundle, locale: Locale(language));
        expect(identical(names.entityText(unrelated), unrelated), isTrue);
        final expected = language == 'en'
            ? 'Mutsuki Kai・12cm Single Gun Mount'
            : '무츠키 개・12cm 단장포';
        expect(names.entityText('睦月改・12cm単装砲'), expected);
        expect(
          identical(names.entityText(_fresh(unrelated)), unrelated),
          isTrue,
        );
      }
    },
  );

  test('cached ship variants remain separated by master ID and locale', () {
    final en = GameNameCatalog(bundle: bundle, locale: const Locale('en'));
    final ko = GameNameCatalog(bundle: bundle, locale: const Locale('ko'));
    expect(en.shipName('宗谷', shipId: 699), 'Souya (ASU)');
    expect(en.shipName('宗谷', shipId: 645), 'Souya (AGL)');
    expect(en.shipName('宗谷', shipId: 699), 'Souya (ASU)');
    expect(ko.shipName('睦月改'), '무츠키 개');
    expect(en.shipName('睦月改'), 'Mutsuki Kai');
  });

  test('field cache has an entry limit and preserves unknown fallback', () {
    final names = GameNameCatalog(bundle: bundle, locale: const Locale('en'));
    final first = _fresh('§first§');
    expect(identical(names.entityText(first), first), isTrue);
    expect(identical(names.entityText(_fresh(first)), first), isTrue);
    for (var index = 0; index < 2048; index++) {
      names.entityText('§$index§');
    }
    final afterEviction = names.entityText(_fresh(first));
    expect(afterEviction, first);
    expect(identical(afterEviction, first), isFalse);
  });

  test('field cache bounds characters and bypasses oversized input', () {
    final names = GameNameCatalog(bundle: bundle, locale: const Locale('en'));
    final first = _fresh('§first§');
    names.entityText(first);
    final padding = List.filled(4096, '§').join();
    for (var index = 0; index < 70; index++) {
      names.entityText('$index$padding');
    }
    expect(identical(names.entityText(_fresh(first)), first), isFalse);

    final large = List.filled(9000, '§').join();
    expect(identical(names.entityText(large), large), isTrue);
    expect(identical(names.entityText(_fresh(large)), large), isFalse);
  });

  test('ship cache is bounded and does not change unknown names', () {
    final names = GameNameCatalog(bundle: bundle, locale: const Locale('en'));
    final first = _fresh('§unknown§');
    names.shipName(first);
    expect(identical(names.shipName(_fresh(first)), first), isTrue);
    for (var index = 0; index < 2048; index++) {
      names.shipName('§$index§');
    }
    expect(names.shipName(_fresh(first)), first);
    expect(identical(names.shipName(_fresh(first)), first), isFalse);
  });

  test('complete task corpus remains cached while switching search terms', () {
    final source =
        jsonDecode(File('assets/data/quests-scn.json').readAsStringSync())
            as Map<String, dynamic>;
    final fields = [
      for (final entry in source.entries)
        '${entry.key} ${['code', 'name', 'desc', 'nameZh', 'descZh', 'rewards', 'memo2'].map((key) => (entry.value as Map)[key] ?? '').join(' ')}',
    ];
    for (final language in ['en', 'ko']) {
      final names = GameNameCatalog(bundle: bundle, locale: Locale(language));
      final results = [for (final field in fields) names.entityText(field)];
      for (var index = 0; index < fields.length; index++) {
        expect(
          identical(names.entityText(fields[index]), results[index]),
          isTrue,
        );
      }
    }
  });

  test(
    'initial buckets preserve greedy prefixes, fallback and UTF-16 text',
    () {
      final source = jsonDecode(bundle.toJsonString()) as Map<String, dynamic>;
      (source['names'] as Map)['en-us'] = {
        'ships': {
          'a': 'Alpha',
          'ab': 'Beta',
          'aba': 'Gamma',
          'b': 'Bravo',
          'ba': 'Delta',
        },
        'affix': {
          'prefixes': {'a': 'P-', 'ab': 'Q-', 'b': 'R-'},
          'suffixes': {'a': '-S', 'ba': '-T', 'b': '-U'},
        },
      };
      final names = GameNameCatalog(
        bundle: ShipSubtitleKc3Bundle.fromJson(source),
        locale: const Locale('en'),
      );
      // These expectations were recorded from the original complete matcher.
      expect(names.entityText('baaaba'), 'P-R-Alpha-S-T');
      expect(names.entityText('ababab'), 'ababab');
      expect(names.entityText('aaaaaaaaaa'), 'aaaaaaaaaa');
      expect(names.entityText('bbbbbbbbbbbb'), 'bbbbbbbbbbbb');
      expect(names.entityText('🚢baaaba🚢'), '🚢P-R-Alpha-S-T🚢');
    },
  );
}

String _fresh(String value) => String.fromCharCodes(value.codeUnits);
