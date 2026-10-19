import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/fleet/anchorage_repair_view.dart';
import 'package:yahagi_kancolle_browser/src/fleet/fleet_ui_strings.dart';

void main() {
  const materials = <String, (String, String, String, String, String)>{
    '給糧艦「間宮」': (
      '给粮舰「间宫」',
      '給糧艦「間宮」',
      '給糧艦「間宮」',
      '급양함 마미야',
      'Food Supply Ship Mamiya',
    ),
    '勲章': ('勋章', '勳章', '勲章', '훈장', 'Medal'),
    '給糧艦「伊良湖」': (
      '给粮舰「伊良湖」',
      '給糧艦「伊良湖」',
      '給糧艦「伊良湖」',
      '급양함 이라코',
      'Food Supply Ship Irako',
    ),
    '甲種勲章': ('甲种勋章', '甲種勳章', '甲種勲章', '갑종훈장', 'First Class Medal'),
    '秋刀魚': ('秋刀鱼', '秋刀魚', '秋刀魚', '꽁치', 'Saury'),
    '熟練搭乗員': ('熟练搭乘员', '熟練搭乘員', '熟練搭乗員', '숙련탑승원', 'Skilled Crew Member'),
    '新型砲熕兵装資材': (
      '新型炮熕兵装资材',
      '新型砲熕兵裝資材',
      '新型砲熕兵装資材',
      '신형포공병장자재',
      'New Model Gun Mount Improvement Material',
    ),
    '新型航空兵装資材': (
      '新型航空兵装资材',
      '新型航空兵裝資材',
      '新型航空兵装資材',
      '신형항공병장자재',
      'New Model Aerial Armament Material',
    ),
    '戦闘詳報': ('战斗详报', '戰鬥詳報', '戦闘詳報', '전투상보', 'Action Report'),
    '新型兵装資材': (
      '新型兵装资材',
      '新型兵裝資材',
      '新型兵装資材',
      '신형병장자재',
      'New Model Armament Material',
    ),
    '潜水艦補給物資': (
      '潜水舰补给物资',
      '潛水艦補給物資',
      '潜水艦補給物資',
      '잠수함 보급물자',
      'Submarine Supply Material',
    ),
    '海外艦最新技術': (
      '海外舰最新技术',
      '海外艦最新技術',
      '海外艦最新技術',
      '해외함 최신기술',
      'New Overseas Warship Technology',
    ),
  };
  for (final (locale, index) in [
    (const Locale('zh'), 0),
    (const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'), 1),
    (const Locale('ja'), 2),
    (const Locale('ko'), 3),
    (const Locale('en'), 4),
  ]) {
    testWidgets(
      'resource material catalog translates all 12 terms in $locale',
      (tester) async {
        late BuildContext ui;
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) {
                ui = context;
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final entry in materials.entries) {
          final expected = switch (index) {
            0 => entry.value.$1,
            1 => entry.value.$2,
            2 => entry.value.$3,
            3 => entry.value.$4,
            _ => entry.value.$5,
          };
          expect(
            fleetText(ui, entry.key),
            expected,
            reason: '$locale: ${entry.key}',
          );
        }
      },
    );
  }

  testWidgets('furniture coin label follows the active locale', (tester) async {
    final locale = ValueNotifier(const Locale('zh'));
    addTearDown(locale.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<Locale>(
        valueListenable: locale,
        builder: (context, value, _) => MaterialApp(
          locale: value,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Text(fleetText(context, '家具コイン')),
          ),
        ),
      ),
    );

    expect(find.text('家具币'), findsOneWidget);
    locale.value = const Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'Hant',
    );
    await tester.pumpAndSettle();
    expect(find.text('家具幣'), findsOneWidget);
    locale.value = const Locale('ja');
    await tester.pumpAndSettle();
    expect(find.text('家具コイン'), findsOneWidget);
  });

  testWidgets('repair tabs update when the active locale changes', (
    tester,
  ) async {
    final locale = ValueNotifier(const Locale('zh'));
    addTearDown(locale.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<Locale>(
        valueListenable: locale,
        builder: (context, value, _) => MaterialApp(
          locale: value,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: RepairModeTabs(
              mode: RepairCenterMode.anchorage,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('野埼刷闪'), findsOneWidget);
    locale.value = const Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'Hant',
    );
    await tester.pumpAndSettle();
    expect(find.text('野埼刷閃'), findsOneWidget);
    expect(find.text('野埼刷闪'), findsNothing);
    locale.value = const Locale('ja');
    await tester.pumpAndSettle();
    expect(find.text('野埼キラ付け'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Japanese dynamic counts, model reasons, resources and mechanism descriptions',
    (tester) async {
      late BuildContext ui;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ja'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              ui = context;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(fleetText(ui, '12 分 (3次)'), '12分（3回）');
      expect(fleetText(ui, '4 艘（修理设施 X 2）'), '4隻（修理施設 × 2）');
      expect(fleetText(ui, '疲劳 49'), 'コンディション 49');
      expect(fleetText(ui, '未改野埼需疲劳≥49'), '未改造の野埼はCond≥49が必要');
      expect(fleetText(ui, '展开舰队'), '舰队を展開');
      expect(fleetText(ui, '喷2 75%'), '噴進改二 75%');
      expect(fleetText(ui, '雪風改二'), '雪風改二');
      expect(fleetText(ui, 'Event'), 'イベント海域');
      expect(fleetText(ui, 'Extra'), '拡張作戦');
      expect(fleetText(ui, '未知远征'), '不明な遠征');
      expect(fleetText(ui, '空闲'), '空き');
      expect(fleetText(ui, '建中'), '建造中');
      expect(fleetText(ui, '戦闘詳報'), '戦闘詳報');
      final description = fleetMechanismDescription(
        ui,
        '一齐射击（长门）\n\n长门改二旗舰的特殊攻击编成。 当前配装预估发动概率约为 75%。当前仅表示编成与耐久等静态条件匹配；实际发动还受阵型、联合舰队状态和本次出击中的使用次数限制。',
      );
      expect(description, contains('一斉射（長門）'));
      expect(description, contains('長門改二を旗艦とする特殊攻撃編成です。'));
      expect(description, contains('推定発動率は約75%です。'));
      expect(description, isNot(contains('当前')));
      expect(description, isNot(contains('实际')));
    },
  );
}
