import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_kc3_bundle.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_language.dart';

Map<String, dynamic> kc3Fixture({
  String version = '20261017023118',
  String commit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
}) => {
  'schema': 3,
  'version': version,
  'commit': commit,
  'english': {
    'version': version,
    '1': {'1': 'Hello!'},
  },
  'korean': {
    'version': version,
    '1': {'1': '안녕하세요!'},
  },
  'entityNames': {
    for (final language in ['zh-cn', 'zh-tw', 'en-us', 'ko-kr'])
      language: {
        'items': {'12cm単装砲': '12cm Single Gun Mount'},
        'stype': List.filled(23, 'Ship type'),
        'equiptype': List.generate(5, (_) => ['', 'Equipment type']),
      },
  },
  'names': {
    for (final language in ['zh-cn', 'zh-tw', 'en-us', 'ko-kr'])
      language: {
        'ships': <String, dynamic>{
          '睦月': 'Mutsuki',
          '睦月改二': 'Exact remodel',
          '金剛': 'Kongou',
          'Верный': 'Verniy',
          '丹陽': 'Tan Yang',
          '宗谷': 'Souya',
          '😀': 'Smile',
        },
        'affix': {
          'prefixes': {
            '夏': 'Summer ',
            '特別': r' Special$',
            '前': 'Outer ',
            '内': 'Inner ',
          },
          'suffixes': {
            '甲': ' A',
            '改': ' Kai',
            '改二': ' Kai Ni',
            '特殊': '^Special ',
            '(特務艦)': ' (ASU)',
          },
          'byId': {
            '699': 'Souya (ASU)',
            '0': 'Invalid zero ID',
            '-1': 'Invalid negative ID',
          },
        },
      },
  },
};

void main() {
  group('KC3 name catalog', () {
    late ShipSubtitleKc3Bundle bundle;
    setUp(() => bundle = ShipSubtitleKc3Bundle.fromJson(kc3Fixture()));

    test('exact names take precedence over remodel affixes', () {
      expect(bundle.shipName(ShipSubtitleLanguage.english, '睦月'), 'Mutsuki');
      expect(
        bundle.shipName(ShipSubtitleLanguage.english, '睦月改二'),
        'Exact remodel',
      );
      expect(bundle.shipName(ShipSubtitleLanguage.english, '丹陽'), 'Tan Yang');
      expect(bundle.shipName(ShipSubtitleLanguage.english, 'Верный'), 'Verniy');
    });

    test(
      'master ID names precede exact names and absent IDs use raw fallback',
      () {
        final catalog = bundle.names[ShipSubtitleLanguage.english]!;
        expect(catalog.shipName('宗谷', shipId: 699), 'Souya (ASU)');
        expect(catalog.shipName('宗谷'), 'Souya');
        expect(catalog.shipName('睦月改', shipId: 1), 'Mutsuki Kai');
        for (final id in [1, 0, -1]) {
          expect(catalog.shipName('未知改', shipId: id), '未知改');
        }
        expect(
          bundle.shipName(ShipSubtitleLanguage.japanese, '宗谷', shipId: 699),
          '宗谷',
        );
      },
    );

    test('combines suffixes in source order with their upstream spacing', () {
      expect(
        bundle.shipName(ShipSubtitleLanguage.english, '睦月改'),
        'Mutsuki Kai',
      );
      expect(
        bundle.shipName(ShipSubtitleLanguage.english, '金剛改二甲'),
        'Kongou Kai Ni A',
      );
      expect(
        bundle.shipName(ShipSubtitleLanguage.english, '宗谷(特務艦)'),
        'Souya (ASU)',
      );
    });

    test('preserves KC3 prefix stack and marker relocation semantics', () {
      expect(
        bundle.shipName(ShipSubtitleLanguage.english, '前内金剛改'),
        'Inner Outer Kongou Kai',
      );
      expect(
        bundle.shipName(ShipSubtitleLanguage.english, '特別金剛特殊'),
        'Special Kongou Special',
      );
    });

    test('keeps unknown roots, repeated affixes and Japanese unchanged', () {
      for (final name in ['未知改二甲', '夏未知改', '金剛改改', '', 'かい', '金剛 改']) {
        expect(bundle.shipName(ShipSubtitleLanguage.english, name), name);
      }
      expect(bundle.shipName(ShipSubtitleLanguage.japanese, '睦月改'), '睦月改');
      expect(bundle.shipName(ShipSubtitleLanguage.english, '😀改'), 'Smile Kai');
    });

    test('all maps are immutable and preserve JSON round trips', () {
      final restored = ShipSubtitleKc3Bundle.fromJsonString(
        bundle.toJsonString(),
      );
      expect(restored.commit, bundle.commit);
      expect(restored.english.quotes, bundle.english.quotes);
      expect(restored.korean.quotes, bundle.korean.quotes);
      expect(
        restored.shipName(ShipSubtitleLanguage.english, '金剛改二甲'),
        'Kongou Kai Ni A',
      );
      expect(() => bundle.names.clear(), throwsUnsupportedError);
      expect(
        () => bundle.names[ShipSubtitleLanguage.english]!.ships.clear(),
        throwsUnsupportedError,
      );
    });
  });

  group('KC3 bundle validation', () {
    test(
      'requires all four equipment dictionaries and five category groups',
      () {
        final missing = kc3Fixture();
        (missing['entityNames'] as Map).remove('ko-kr');
        final emptyItems = kc3Fixture();
        (emptyItems['entityNames'] as Map)['en-us']['items'] =
            <String, String>{};
        final badShipTypes = kc3Fixture();
        (badShipTypes['entityNames'] as Map)['en-us']['stype'] = ['DD'];
        final badTypeGroups = kc3Fixture();
        (badTypeGroups['entityNames'] as Map)['ko-kr']['equiptype'] = [
          ['Type'],
        ];
        final badTypeEntry = kc3Fixture();
        (badTypeEntry['entityNames'] as Map)['zh-tw']['equiptype'] = [
          ...List.generate(4, (_) => ['', 'Type']),
          ['', 42],
        ];
        final oldSchema = kc3Fixture()..['schema'] = 2;
        for (final source in [
          missing,
          emptyItems,
          badShipTypes,
          badTypeGroups,
          badTypeEntry,
          oldSchema,
        ]) {
          expect(
            () => ShipSubtitleKc3Bundle.fromJson(source),
            throwsFormatException,
          );
        }
      },
    );

    test(
      'returns the requested KC3 catalog without cross-language fallback',
      () {
        final bundle = ShipSubtitleKc3Bundle.fromJson(kc3Fixture());
        expect(
          bundle.catalogFor(ShipSubtitleLanguage.english),
          same(bundle.english),
        );
        expect(
          bundle.catalogFor(ShipSubtitleLanguage.korean),
          same(bundle.korean),
        );
        expect(bundle.korean.quotes['1']!['1'], '안녕하세요!');
        expect(
          bundle.catalogFor(ShipSubtitleLanguage.simplifiedChinese),
          isNull,
        );
        expect(
          bundle.catalogFor(ShipSubtitleLanguage.traditionalChinese),
          isNull,
        );
        expect(bundle.catalogFor(ShipSubtitleLanguage.japanese), isNull);
      },
    );

    test(
      'rejects previous schema and incomplete or mismatched Korean data',
      () {
        final old = kc3Fixture()..['schema'] = 1;
        final missing = kc3Fixture()..remove('korean');
        final mismatched = kc3Fixture();
        (mismatched['korean'] as Map)['version'] = '20261016000000';
        final missingNames = kc3Fixture();
        (missingNames['names'] as Map).remove('ko-kr');
        for (final data in [old, missing, mismatched, missingNames]) {
          expect(
            () => ShipSubtitleKc3Bundle.fromJson(data),
            throwsFormatException,
          );
        }
      },
    );

    test('rejects incomplete groups and mismatched English versions', () {
      final incomplete = kc3Fixture();
      (incomplete['names'] as Map).remove('zh-tw');
      final mismatched = kc3Fixture();
      (mismatched['english'] as Map)['version'] = '20261016000000';
      final invalidName = kc3Fixture();
      ((invalidName['names'] as Map)['en-us']['ships'] as Map)['test'] = 4;
      final emptyAffix = kc3Fixture();
      ((emptyAffix['names'] as Map)['en-us']['affix']['suffixes'] as Map)[''] =
          'Bad';
      for (final data in [
        incomplete,
        mismatched,
        invalidName,
        emptyAffix,
        kc3Fixture(commit: '../master'),
        kc3Fixture(version: '20260230023118'),
        kc3Fixture(version: '2026101702'),
      ]) {
        expect(
          () => ShipSubtitleKc3Bundle.fromJson(data),
          throwsFormatException,
        );
      }
    });

    test(
      'requires every pinned source file and converts only supported quotes',
      () {
        final files = <String, dynamic>{
          'data/en/quotes.json': {
            '1': {
              'Intro': {'200,100': 'Second', '0,100': 'First<br>line'},
              'Poke(1)@summer': 'Excluded',
            },
          },
          'data/kr/quotes.json': {
            '1': {'Intro': '안녕하세요!', 'Poke(1)@summer': '제외'},
          },
          for (final language in ['scn', 'tcn', 'en', 'kr']) ...{
            'data/$language/items.json': {'12cm単装砲': '12cm Single Gun Mount'},
            'data/$language/stype.json': List.filled(23, 'Ship type'),
            'data/$language/equiptype.json': List.generate(
              5,
              (_) => ['', 'Type'],
            ),
            'data/$language/ships.json': {'睦月': 'Mutsuki'},
            'data/$language/ship_affix.json': {
              'prefixes': <String, String>{},
              'suffixes': {'改': ' Kai'},
            },
          },
        };
        final bundle = ShipSubtitleKc3Bundle.fromKc3Files(
          version: '20261017023118',
          commit: 'a' * 40,
          files: files,
        );
        expect(bundle.english.quotes['1'], {'1': 'First\nline\nSecond'});
        expect(bundle.korean.quotes['1'], {'1': '안녕하세요!'});
        files.remove('data/tcn/ships.json');
        expect(
          () => ShipSubtitleKc3Bundle.fromKc3Files(
            version: '20261017023118',
            commit: 'a' * 40,
            files: files,
          ),
          throwsFormatException,
        );
      },
    );

    test(
      'real bundled names cover four translations and Japanese passthrough',
      () async {
        final bundle = ShipSubtitleKc3Bundle.fromJsonString(
          await File('assets/data/subtitles/kc3-bundle.json').readAsString(),
        );
        expect(bundle.version, '20261017023118');
        expect(bundle.commit, '6fed2aac44a1ca95f2892bb1af93a6bc0e60b667');
        expect(bundle.english.quoteCount, greaterThan(16000));
        expect(bundle.korean.quoteCount, greaterThan(17000));
        expect(ShipSubtitleKc3Bundle.sourcePaths, hasLength(22));
        expect(bundle.entityNames, hasLength(4));
        for (final names in bundle.entityNames.values) {
          expect(names.items.length, greaterThan(700));
          expect(names.shipTypes.length, greaterThan(60));
          expect(names.equipmentTypes, hasLength(5));
          expect(() => names.items.clear(), throwsUnsupportedError);
          expect(() => names.shipTypes.clear(), throwsUnsupportedError);
          expect(() => names.equipmentTypes[2].clear(), throwsUnsupportedError);
        }
        for (final language in ShipSubtitleLanguage.values) {
          final names = ['睦月', '睦月改', '金剛改二甲', '丹陽', 'Верный', '宗谷(南極観測船)'];
          final expected = switch (language) {
            ShipSubtitleLanguage.simplifiedChinese => [
              '睦月',
              '睦月改',
              '金刚改二甲',
              '丹阳',
              '信赖',
              '宗谷-南极观测',
            ],
            ShipSubtitleLanguage.traditionalChinese => [
              '睦月',
              '睦月改',
              '金剛改二甲',
              '丹陽',
              '信賴',
              '宗谷 (南極觀測)',
            ],
            ShipSubtitleLanguage.japanese => names,
            ShipSubtitleLanguage.english => [
              'Mutsuki',
              'Mutsuki Kai',
              'Kongou Kai Ni A',
              'Tan Yang',
              'Verniy',
              'Souya (AGB)',
            ],
            ShipSubtitleLanguage.korean => [
              '무츠키',
              '무츠키 개',
              '콩고 개2 갑',
              '단양',
              '베르니',
              '소야 (남극 관측선)',
            ],
          };
          expect(
            names.map((name) => bundle.shipName(language, name)).toList(),
            expected,
          );
        }
        expect(jsonDecode(bundle.toJsonString())['schema'], 3);
      },
    );

    test(
      'real byId dictionaries distinguish Souya and Glorious forms',
      () async {
        final bundle = ShipSubtitleKc3Bundle.fromJsonString(
          await File('assets/data/subtitles/kc3-bundle.json').readAsString(),
        );
        const ids = [699, 645, 650, 1022, 1027, 740, 741];
        const rawNames = [
          '宗谷',
          '宗谷',
          '宗谷',
          'Glorious',
          'Glorious',
          'Glorious改',
          'Glorious改',
        ];
        for (final language in ShipSubtitleLanguage.values) {
          final expected = switch (language) {
            ShipSubtitleLanguage.simplifiedChinese => [
              '宗谷-特务舰',
              '宗谷-灯塔补给',
              '宗谷-南极观测',
              '光荣-巡洋战舰',
              '光荣-航空母舰',
              '光荣改-巡洋战舰',
              '光荣改-航空母舰',
            ],
            ShipSubtitleLanguage.traditionalChinese => [
              '宗谷 (特殊用途)',
              '宗谷 (照明補給)',
              '宗谷 (南極觀測)',
              '光榮 (戰巡)',
              '光榮 (航母)',
              '光榮改 (戰巡)',
              '光榮改 (航母)',
            ],
            ShipSubtitleLanguage.english => [
              'Souya (ASU)',
              'Souya (AGL)',
              'Souya (AGB)',
              'Glorious (BC)',
              'Glorious (CV)',
              'Glorious Kai (BC)',
              'Glorious Kai (CV)',
            ],
            ShipSubtitleLanguage.japanese => rawNames,
            ShipSubtitleLanguage.korean => [
              '소야 (특무함)',
              '소야 (등대 보급선)',
              '소야 (남극 관측선)',
              '글로리어스 (순양전함)',
              '글로리어스 (항공모함)',
              '글로리어스 개 (순양전함)',
              '글로리어스 개 (항공모함)',
            ],
          };
          expect([
            for (var index = 0; index < ids.length; index++)
              bundle.shipName(language, rawNames[index], shipId: ids[index]),
          ], expected);
          expect(bundle.shipName(language, '未知改', shipId: 999999), '未知改');
        }
        expect(bundle.shipName(ShipSubtitleLanguage.english, '宗谷'), 'Souya');
        expect(
          bundle.shipName(ShipSubtitleLanguage.english, 'Glorious改'),
          'Glorious Kai',
        );
      },
    );
  });
}
