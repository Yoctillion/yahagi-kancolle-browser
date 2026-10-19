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

  test('enemy names render KC3 delimiters as display separators', () {
    final en = GameNameCatalog(bundle: bundle, locale: const Locale('en'));
    final ko = GameNameCatalog(bundle: bundle, locale: const Locale('ko'));
    expect(en.shipName('駆逐イ級後期型'), 'I-Class Destroyer - Late Model');
    expect(ko.shipName('駆逐イ級後期型'), isNot(contains('{')));
    expect(en.shipName('Unknown{ -}? Name'), 'Unknown{ -}? Name');
    final names = ShipSubtitleNameCatalog.fromJson({
      'ships': {'架空': 'A{ -}? B{ /}? C'},
      'affix': {
        'prefixes': <String, String>{},
        'suffixes': {'改': ' Kai'},
      },
    });
    expect(names.shipName('架空'), 'A - B C');
  });

  test('English and Korean resolve ship, equipment and both type IDs', () {
    final en = GameNameCatalog(bundle: bundle, locale: const Locale('en'));
    final ko = GameNameCatalog(bundle: bundle, locale: const Locale('ko'));
    expect(en.shipName('睦月改'), 'Mutsuki Kai');
    expect(ko.shipName('睦月改'), '무츠키 개');
    expect(en.equipmentName('12cm単装砲'), '12cm Single Gun Mount');
    expect(ko.equipmentName('12cm単装砲'), '12cm 단장포');
    expect(en.shipTypeName('駆逐艦', typeId: 2), 'DD');
    expect(ko.shipTypeName('駆逐艦', typeId: 2), '구축함');
    expect(ko.shipTypeName('DD'), '구축함');
    expect(ko.shipTypeName('CL'), '경순');
    expect(en.shipTypeName('驱逐舰'), 'DD');
    expect(en.shipTypeName('陸上施設'), 'Land Installation');
    expect(ko.shipTypeName('陸上施設'), '육상기지');
    expect(en.equipmentTypeName('小口径主砲', typeId: 1), 'Small Cal. Main Gun');
    expect(ko.equipmentTypeName('小口径主砲', typeId: 1), '소구경주포');
  });

  test('Chinese and Japanese UI names stay byte for byte unchanged', () {
    for (final locale in [
      const Locale('zh'),
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      const Locale('ja'),
    ]) {
      final names = GameNameCatalog(bundle: bundle, locale: locale);
      expect(names.shipName('金剛改二甲'), '金剛改二甲');
      expect(names.equipmentName('12cm単装砲'), '12cm単装砲');
      expect(names.shipTypeName('駆逐艦', typeId: 2), '駆逐艦');
      expect(names.equipmentTypeName('小口径主砲', typeId: 1), '小口径主砲');
      expect(names.entityText('睦月改・12cm単装砲'), '睦月改・12cm単装砲');
    }
  });

  test('ID overrides and unknown values keep established fallback rules', () {
    final names = GameNameCatalog(bundle: bundle, locale: const Locale('en'));
    expect(names.shipName('宗谷', shipId: 699), 'Souya (ASU)');
    expect(names.shipName('未知艦改二'), '未知艦改二');
    expect(names.equipmentName('未知装備'), '未知装備');
    expect(names.shipTypeName('未知種', typeId: 99999), '未知種');
    expect(names.equipmentTypeName('未知分類', typeId: 99999), '未知分類');
    final missing = GameNameCatalog(locale: const Locale('en'));
    expect(missing.shipName('睦月'), '睦月');
  });

  test('compound entity fields translate longest names once', () {
    final names = GameNameCatalog(bundle: bundle, locale: const Locale('en'));
    expect(
      names.entityText('睦月改・12cm単装砲'),
      'Mutsuki Kai・12cm Single Gun Mount',
    );
    expect(names.entityText('駆逐艦 / 小口径主砲'), 'DD / Small Cal. Main Gun');
    expect(names.entityText('未知艦改二'), '未知艦改二');
  });

  test('stored Chinese aliases resolve without changing the stored names', () {
    final en = GameNameCatalog(bundle: bundle, locale: const Locale('en'));
    final ko = GameNameCatalog(bundle: bundle, locale: const Locale('ko'));
    expect(en.shipName('雾岛'), 'Kirishima');
    expect(en.shipName('雾岛改二'), 'Kirishima Kai Ni');
    expect(ko.shipName('雾岛改二'), '키리시마 개2');
    expect(en.shipName('夕张'), 'Yuubari');
    expect(en.equipmentName('12cm单装炮'), '12cm Single Gun Mount');
    expect(en.equipmentName('12cm單裝炮'), '12cm Single Gun Mount');
    expect(
      en.entityText('雾岛改二・12cm单装炮'),
      'Kirishima Kai Ni・12cm Single Gun Mount',
    );
  });

  test('cross-language ambiguous aliases keep the complete original field', () {
    final source = jsonDecode(bundle.toJsonString()) as Map<String, dynamic>;
    ((source['names'] as Map)['zh-cn']['ships'] as Map)['睦月'] = '重名船';
    ((source['names'] as Map)['zh-tw']['ships'] as Map)['夕張'] = '重名船';
    final names = GameNameCatalog(
      bundle: ShipSubtitleKc3Bundle.fromJson(source),
      locale: const Locale('en'),
    );
    expect(names.shipName('重名船'), '重名船');
    expect(names.shipName('重名船改二'), '重名船改二');
  });
}
