import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/expedition/expedition_models.dart';
import 'package:yahagi_kancolle_browser/src/expedition/expedition_strings.dart';
import 'package:yahagi_kancolle_browser/src/fleet/fleet_ui_strings.dart';
import 'package:yahagi_kancolle_browser/src/localization/record_backup_strings.dart';
import 'package:yahagi_kancolle_browser/src/localization/runtime_message_text.dart';
import 'package:yahagi_kancolle_browser/src/localization/ui_text.dart';

void main() {
  const en = Locale('en');

  test('English legacy filters and dynamic labels preserve game names', () {
    expect(uiTextForLocale(en, '搜索装备'), 'Search equipment');
    expect(uiTextForLocale(en, '筛选出击记录'), 'Filter sortie records');
    expect(uiTextForLocale(en, '筛选资源记录'), 'Filter resource records');
    expect(uiTextForLocale(en, '共 23 条'), 'Total: 23');
    expect(uiTextForLocale(en, '路线 A → B'), 'Route A → B');
    expect(uiTextForLocale(en, '家具箱(大)'), 'Furniture box (large)');
    expect(uiTextForLocale(en, '家具箱(中)'), 'Furniture box (medium)');
    expect(uiTextForLocale(en, '家具箱(小)'), 'Furniture box (small)');
    expect(uiTextForLocale(en, '家具箱(未知size)'), 'Furniture box (未知size)');
    expect(uiTextForLocale(en, '演习'), 'Exercise');
    expect(uiTextForLocale(en, '道具 999'), 'Item 999');
    expect(uiTextForLocale(en, '筛选CustomName记录'), 'Filter CustomName records');
    expect(uiTextForLocale(en, '缺少 2 艘'), 'Missing ships: 2');
    expect(uiTextForLocale(en, '改修消耗（每次）'), 'Improvement cost (per attempt)');
    for (final name in ['瑞雲改二(六三四空)', '長門改二', '東京急行', '自分の艦隊']) {
      expect(uiTextForLocale(en, name), name);
    }
  });

  test('English runtime framing preserves raw native details and codes', () {
    const detail = 'SocketException: 系统错误 https://例子.test/未知页面';
    expect(runtimeMessageForLocale(en, detail), detail);
    expect(
      runtimeMessageForLocale(en, '捕获配置失败（$detail）'),
      'Capture configuration failed ($detail)',
    );
    const incompleteWrapper = '捕获配置失败（UnknownType';
    expect(runtimeMessageForLocale(en, incompleteWrapper), incompleteWrapper);
    expect(
      runtimeMessageForLocale(en, '游戏页面启动失败：$detail'),
      'Failed to start the game page: $detail',
    );
    expect(
      runtimeMessageForLocale(en, '网络设置应用失败 [proxy_apply_timeout]: 代理设置超时'),
      'Failed to apply network settings [proxy_apply_timeout]: Proxy setup timed out',
    );
    expect(
      runtimeMessageForLocale(en, '网络设置应用失败 [unknown_error]: $detail'),
      'Failed to apply network settings [unknown_error]: $detail',
    );
    expect(
      runtimeMessageForLocale(
        en,
        '游戏页面加载失败 [ERR_CONNECTION_RESET]，请重新加载或检查网络。',
      ),
      'Failed to load the game page [ERR_CONNECTION_RESET]. Reload or check your network.',
    );
  });

  test(
    'English backup warnings distinguish deletion from backup retention',
    () {
      const strings = RecordBackupStrings(en);
      expect(strings.section, 'Record backup and restore');
      expect(strings.restoreDescription(12, 3), contains('12 logbook records'));
      expect(
        strings.restoreDescription(12, 3),
        contains('3 composition records'),
      );
      expect(
        strings.clearLogbookDescription(7, false),
        contains('will not sync'),
      );
      expect(
        strings.clearCompositionDescription(7, true),
        contains('sync before deleting'),
      );
      expect(
        strings.clearCompositionDescription(7, true),
        contains('Backup files will be kept'),
      );
      expect(strings.syncFailed('原始错误'), 'Sync failed: 原始错误');
      expect(
        strings.lastSync(DateTime(2026, 10, 18, 12, 34, 56)),
        'Last sync: 2026-10-18 12:34:56',
      );
    },
  );

  testWidgets('English fleet controls and templates retain game originals', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      _scope(
        en,
        Builder(
          builder: (value) {
            context = value;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(fleetText(context, '编队简报显示内容'), 'Fleet summary display');
    expect(fleetText(context, '任务进度'), 'Quest progress');
    expect(fleetText(context, '最低疲劳'), 'Minimum morale');
    expect(fleetText(context, '改造'), 'Remodel');
    expect(fleetText(context, '疲劳 49'), 'Morale 49');
    for (final label in <String, String>{
      '野埼功能简称': 'Nosaki',
      '野崎刷闪中': 'Nosaki sparkling',
      '野埼刷闪': 'Nosaki sparkling',
      '野埼刷闪计时': 'Nosaki sparkling timer',
      '野埼计时': 'Nosaki timer',
      '未改野埼需疲劳≥49': 'Unremodeled Nosaki requires Cond≥49',
      '野埼自身疲劳过低（需Cond≥30）': 'Nosaki morale too low (requires Cond≥30)',
      '未配置野埼（需在第1或第2位）': 'Nosaki is not assigned (must be ship 1 or 2)',
      '未配置野埼': 'Nosaki is not assigned',
      '野埼正在入渠修理中': 'Nosaki is in a repair dock',
      '野埼未满补给（需满油弹）':
          'Nosaki is not fully supplied (full fuel and ammo required)',
      '野埼有破损（需完全无伤）': 'Nosaki is damaged (must be undamaged)',
    }.entries) {
      expect(fleetText(context, label.key), label.value, reason: label.key);
    }
    expect(
      fleetText(context, '当前配装预估发动概率约为 75%。'),
      'Estimated activation chance with the current equipment: about 75%.',
    );
    for (final template in <String, String>{
      '展开Summary': 'Expand Summary',
      '折叠Summary': 'Collapse Summary',
      '4 艘（修理设施 X 2）': 'Ships: 4 (repair facilities × 2)',
      '4 艘（2 ': 'Ships: 4 (2 ',
      '/次）': '/cycle)',
      '0 艘': 'Ships: 0',
      '12 分 (3次)': '12 min (3 cycles)',
      '1 分 (1次)': '1 min (1 cycle)',
      '3号舰': 'Ship 3',
      '3号位': 'Position 3',
      '泊地：12:34': 'Anchorage: 12:34',
      '野埼：12:34': 'Nosaki: 12:34',
      '战果：12.34': 'Senka: 12.34',
      '刷闪中 (★49)': 'Sparkling (★49)',
      '已刷闪 (★54)': 'Sparkled (★54)',
      '给粮舰 (★54)': 'Food supply ship (★54)',
    }.entries) {
      expect(
        fleetText(context, template.key),
        template.value,
        reason: template.key,
      );
    }
    expect(fleetText(context, '先反 75%'), 'Opening ASW 75%');
    final mechanism = fleetMechanismDescription(
      context,
      '开幕雷击前先进行一次对潜攻击。当前舰娘的舰种、对潜值和装备组合满足 Yahagi 的先制对潜静态判定。',
    );
    expect(mechanism, contains('opening torpedoes. The ship type'));
    expect(mechanism, isNot(contains('torpedoes.The')));
    expect(
      fleetText(
        context,
        '搭载夜间飞机（夜战/夜攻）及夜间作战航空要员或自带夜战起飞能力，可在夜战中发动空母夜间航空攻击（夜袭 CI）。',
      ),
      contains('夜間作戦航空要員'),
    );
    expect(fleetText(context, '給糧艦「間宮」'), 'Food Supply Ship Mamiya');
    for (final name in ['長門改二', '瑞雲改二(六三四空)', '東京急行', '野埼', '野埼改', '自定义舰队野埼']) {
      expect(fleetText(context, name), name);
    }
  });

  testWidgets(
    'English expedition requirements preserve map names and composition codes',
    (tester) async {
      late ExpeditionStrings strings;
      await tester.pumpWidget(
        _scope(
          en,
          Builder(
            builder: (context) {
              strings = ExpeditionStrings.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(strings.title, 'Expedition check');
      expect(strings.compact, 'Compact');
      expect(strings.expeditionAreaName(1), '鎮守府海域');
      expect(strings.expeditionAreaName(2), '南西諸島海域');
      expect(strings.expeditionAreaName(999), 'Area 999');
      const flagship = ExpeditionConditionResult(
        kind: ExpeditionConditionKind.flagshipType,
        label: '旗舰舰种为轻空母（CVL）',
        actual: '未满足',
        passed: false,
      );
      expect(
        strings.conditionLabel(flagship),
        'Flagship type: Light carrier (CVL)',
      );
      const composition = ExpeditionConditionResult(
        kind: ExpeditionConditionKind.composition,
        label: '舰队构成：DD 2 + CL 1',
        actual: '未满足',
        passed: false,
      );
      expect(
        strings.conditionLabel(composition),
        'Fleet composition: DD 2 + CL 1',
      );
      const shortage = ExpeditionConditionResult(
        kind: ExpeditionConditionKind.resupply,
        label: '舰队完成补给',
        actual: '缺少 2 艘',
        passed: false,
      );
      expect(strings.conditionActual(shortage), 'Missing ships: 2');
      expect(strings.conditionActual(flagship), 'Not met');
      final requirements = <ExpeditionConditionKind, String>{
        ExpeditionConditionKind.flagshipLevel: 'Flagship level ≥ 30',
        ExpeditionConditionKind.shipCount: 'Ship count ≥ 30',
        ExpeditionConditionKind.levelSum: 'Total fleet level ≥ 30',
        ExpeditionConditionKind.resupply: 'Fleet fully supplied',
        ExpeditionConditionKind.morale: 'All ships: morale ≥ 30',
        ExpeditionConditionKind.drumCount: 'Drum count ≥ 30',
        ExpeditionConditionKind.drumCarrierCount: 'Ships carrying drums ≥ 30',
        ExpeditionConditionKind.firepower: 'Total firepower ≥ 30',
        ExpeditionConditionKind.antiAir: 'Total anti-air ≥ 30',
        ExpeditionConditionKind.antiSub: 'Total anti-sub ≥ 30',
        ExpeditionConditionKind.lineOfSight: 'Total LOS ≥ 30',
        ExpeditionConditionKind.greatSuccessRate:
            'Current great success chance ≥ 30%',
        ExpeditionConditionKind.allSparkled: 'All ships sparkled',
        ExpeditionConditionKind.daihatsuFill:
            'Equip as many 大発動艇 or 特大発動艇 as possible',
      };
      for (final requirement in requirements.entries) {
        expect(
          strings.conditionLabel(
            ExpeditionConditionResult(
              kind: requirement.key,
              label: '要求 ≥ 30',
              actual: '已满足',
              passed: true,
            ),
          ),
          requirement.value,
          reason: requirement.key.name,
        );
      }
      for (final shipType in <String, String>{
        'CL': 'Light cruiser',
        'CA': 'Heavy cruiser',
        'CVL': 'Light carrier',
        'AV': 'Seaplane tender',
        'AS': 'Submarine tender',
        'CT': 'Training cruiser',
      }.entries) {
        expect(
          strings.conditionLabel(
            ExpeditionConditionResult(
              kind: ExpeditionConditionKind.flagshipType,
              label: '旗舰舰种为（${shipType.key}）',
              actual: '已满足',
              passed: true,
            ),
          ),
          'Flagship type: ${shipType.value} (${shipType.key})',
        );
      }
      const unknownActual = ExpeditionConditionResult(
        kind: ExpeditionConditionKind.resupply,
        label: '舰队完成补给',
        actual: '原始未知条件 CustomName',
        passed: false,
      );
      expect(strings.conditionActual(unknownActual), unknownActual.actual);
    },
  );
}

Widget _scope(Locale locale, Widget child) => Localizations(
  locale: locale,
  delegates: const [DefaultWidgetsLocalizations.delegate],
  child: Directionality(textDirection: TextDirection.ltr, child: child),
);
