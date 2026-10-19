import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/expedition/expedition_models.dart';
import 'package:yahagi_kancolle_browser/src/expedition/expedition_strings.dart';
import 'package:yahagi_kancolle_browser/src/fleet/fleet_ui_strings.dart';
import 'package:yahagi_kancolle_browser/src/localization/record_backup_strings.dart';
import 'package:yahagi_kancolle_browser/src/localization/runtime_message_text.dart';
import 'package:yahagi_kancolle_browser/src/localization/ui_text.dart';

void main() {
  const ko = Locale('ko');

  test('Korean legacy filters translate labels and preserve game names', () {
    expect(uiTextForLocale(ko, '搜索装备'), '장비 검색');
    expect(uiTextForLocale(ko, '筛选出击记录'), '출격 기록 필터');
    expect(uiTextForLocale(ko, '共 23 条'), '총 23건');
    expect(uiTextForLocale(ko, '路线 A → B'), '경로 A → B');
    expect(uiTextForLocale(ko, '家具箱(大)'), '가구 상자(대)');
    expect(uiTextForLocale(ko, '道具 999'), '아이템 999');
    expect(uiTextForLocale(ko, '缺少 2 艘'), '2척 부족');
    expect(uiTextForLocale(ko, '改修消耗（每次）'), '개수 소모(매회)');
    for (final name in ['瑞雲改二(六三四空)', '長門改二', '東京急行', '自分の艦隊']) {
      expect(uiTextForLocale(ko, name), name);
    }
  });

  test('Korean runtime framing retains raw native details and error codes', () {
    const detail = 'SocketException: 系统错误 https://例子.test/未知页面';
    expect(runtimeMessageForLocale(ko, detail), detail);
    expect(
      runtimeMessageForLocale(ko, '游戏页面启动失败：$detail'),
      '게임 페이지 시작 실패: $detail',
    );
    expect(
      runtimeMessageForLocale(ko, '网络设置应用失败 [proxy_apply_timeout]: 代理设置超时'),
      '네트워크 설정 적용 실패 [proxy_apply_timeout]: 프록시 설정 시간이 초과되었습니다',
    );
    expect(
      runtimeMessageForLocale(ko, '网络设置应用失败 [unknown_error]: $detail'),
      '네트워크 설정 적용 실패 [unknown_error]: $detail',
    );
    expect(
      runtimeMessageForLocale(
        ko,
        '游戏页面加载失败 [ERR_CONNECTION_RESET]，请重新加载或检查网络。',
      ),
      '게임 페이지 로드 실패 [ERR_CONNECTION_RESET]. 새로고침하거나 네트워크를 확인하세요.',
    );
  });

  test('Korean backup descriptions retain counts, time and raw errors', () {
    const strings = RecordBackupStrings(ko);
    expect(strings.section, '기록 백업 및 복원');
    expect(strings.restoreDescription(12, 3), contains('12건'));
    expect(strings.restoreDescription(12, 3), contains('3건'));
    expect(strings.clearLogbookDescription(7, false), contains('동기화하지 않습니다'));
    expect(
      strings.clearCompositionDescription(7, true),
      contains('삭제 전에 동기화합니다'),
    );
    expect(strings.syncFailed('原始错误'), '동기화 실패: 原始错误');
    expect(
      strings.lastSync(DateTime(2026, 10, 18, 12, 34, 56)),
      '마지막 동기화: 2026-10-18 12:34:56',
    );
  });

  testWidgets('Korean fleet controls and templates preserve game data', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      _scope(
        ko,
        Builder(
          builder: (value) {
            context = value;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(fleetText(context, '编队简报显示内容'), '편성 요약 표시 항목');
    expect(fleetText(context, '任务进度'), '임무 진행도');
    for (final label in <String, String>{
      '野埼功能简称': '노사키',
      '野崎刷闪中': '노사키 반짝이 작업 중',
      '野埼刷闪': '노사키 반짝이 작업',
      '野埼刷闪计时': '노사키 반짝이 작업 타이머',
      '野埼计时': '노사키 타이머',
      '未改野埼需疲劳≥49': '미개장 노사키는 Cond≥49 필요',
      '野埼自身疲劳过低（需Cond≥30）': '노사키 컨디션 부족(Cond≥30 필요)',
      '未配置野埼（需在第1或第2位）': '노사키 미배치(1번함 또는 2번함에 배치 필요)',
      '未配置野埼': '노사키 미배치',
      '野埼正在入渠修理中': '노사키가 입거 수리 중입니다',
      '野埼未满补给（需满油弹）': '노사키 보급 부족(연료·탄약 완전 보급 필요)',
      '野埼有破损（需完全无伤）': '노사키 손상(손상이 없어야 함)',
    }.entries) {
      expect(fleetText(context, label.key), label.value, reason: label.key);
    }
    expect(
      fleetText(context, '当前配装预估发动概率约为 75%。'),
      '현재 장비 구성의 예상 발동 확률은 약 75%입니다.',
    );
    for (final template in <String, String>{
      '展开편성': '편성 펼치기',
      '折叠편성': '편성 접기',
      '疲劳 49': '컨디션 49',
      '4 艘（修理设施 X 2）': '4척(수리 시설 × 2)',
      '4 艘（2 ': '4척(2 ',
      '/次）': '/회)',
      '0 艘': '0척',
      '12 分 (3次)': '12분(3회)',
      '3号舰': '3번함',
      '3号位': '3번 위치',
      '泊地：12:34': '정박지: 12:34',
      '野埼：12:34': '노사키: 12:34',
      '战果：12.34': '전과: 12.34',
      '刷闪中 (★49)': '반짝이 작업 중 (★49)',
      '已刷闪 (★54)': '반짝이 작업 완료 (★54)',
      '给粮舰 (★54)': '급양함 (★54)',
    }.entries) {
      expect(
        fleetText(context, template.key),
        template.value,
        reason: template.key,
      );
    }
    expect(fleetText(context, '先反 75%'), '선제 대잠 75%');
    expect(
      fleetText(
        context,
        '搭载夜间飞机（夜战/夜攻）及夜间作战航空要员或自带夜战起飞能力，可在夜战中发动空母夜间航空攻击（夜袭 CI）。',
      ),
      contains('夜間作戦航空要員'),
    );
    expect(fleetText(context, '給糧艦「間宮」'), '급양함 마미야');
    for (final name in ['長門改二', '瑞雲改二(六三四空)', '東京急行', '野埼', '野埼改', '自定义舰队野埼']) {
      expect(fleetText(context, name), name);
    }
  });

  testWidgets(
    'Korean expedition conditions translate UI and preserve composition codes',
    (tester) async {
      late ExpeditionStrings strings;
      await tester.pumpWidget(
        _scope(
          ko,
          Builder(
            builder: (context) {
              strings = ExpeditionStrings.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(strings.title, '원정 점검');
      expect(strings.compact, '간단히');
      expect(strings.expeditionAreaName(999), '해역 999');
      for (final area in <int, String>{
        1: '鎮守府海域',
        2: '南西諸島海域',
        3: '北方海域',
        4: '西方海域',
        5: '南方海域',
        7: '南西海域',
      }.entries) {
        expect(strings.expeditionAreaName(area.key), area.value);
      }
      const flagship = ExpeditionConditionResult(
        kind: ExpeditionConditionKind.flagshipType,
        label: '旗舰舰种为轻空母（CVL）',
        actual: '未满足',
        passed: false,
      );
      expect(strings.conditionLabel(flagship), '기함 함종: 경항모(CVL)');
      const composition = ExpeditionConditionResult(
        kind: ExpeditionConditionKind.composition,
        label: '舰队构成：DD 2 + CL 1',
        actual: '未满足',
        passed: false,
      );
      expect(strings.conditionLabel(composition), '함대 구성: DD 2 + CL 1');
      const shortage = ExpeditionConditionResult(
        kind: ExpeditionConditionKind.resupply,
        label: '舰队完成补给',
        actual: '缺少 2 艘',
        passed: false,
      );
      expect(strings.conditionActual(shortage), '2척 부족');
      expect(strings.conditionActual(flagship), '미충족');
      final requirements = <ExpeditionConditionKind, String>{
        ExpeditionConditionKind.flagshipLevel: '기함 레벨 ≥ 30',
        ExpeditionConditionKind.shipCount: '함선 수 ≥ 30',
        ExpeditionConditionKind.levelSum: '함대 레벨 합계 ≥ 30',
        ExpeditionConditionKind.resupply: '함대 보급 완료',
        ExpeditionConditionKind.morale: '전원 컨디션 ≥ 30',
        ExpeditionConditionKind.drumCount: '드럼통 수 ≥ 30',
        ExpeditionConditionKind.drumCarrierCount: '드럼통 탑재함 수 ≥ 30',
        ExpeditionConditionKind.firepower: '총 화력 ≥ 30',
        ExpeditionConditionKind.antiAir: '총 대공 ≥ 30',
        ExpeditionConditionKind.antiSub: '총 대잠 ≥ 30',
        ExpeditionConditionKind.lineOfSight: '총 색적 ≥ 30',
        ExpeditionConditionKind.greatSuccessRate: '현재 대성공 확률 ≥ 30%',
        ExpeditionConditionKind.allSparkled: '모든 함선이 반짝이 상태',
        ExpeditionConditionKind.daihatsuFill: '가능한 한 大発動艇 또는 特大発動艇을 많이 탑재',
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
        'CL': '경순양함',
        'CA': '중순양함',
        'CVL': '경항모',
        'AV': '수상기모함',
        'AS': '잠수모함',
        'CT': '연습순양함',
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
          '기함 함종: ${shipType.value}(${shipType.key})',
        );
      }
    },
  );

  testWidgets('Hong Kong and Macao use Traditional expedition labels', (
    tester,
  ) async {
    for (final region in ['HK', 'MO']) {
      late ExpeditionStrings strings;
      await tester.pumpWidget(
        _scope(
          Locale('zh', region),
          Builder(
            builder: (context) {
              strings = ExpeditionStrings.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(strings.title, '遠征檢查');
    }
  });

  testWidgets('Cond metrics consistently identify morale in all four locales', (
    tester,
  ) async {
    for (final scenario in <(Locale, List<String>)>[
      (const Locale('zh'), ['士气值', '最低士气', '当前士气', '士气 49', '未改野埼需士气≥49']),
      (
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        ['士氣值', '最低士氣', '目前士氣', '士氣 49', '未改野埼需士氣≥49'],
      ),
      (
        const Locale('ja'),
        [
          'コンディション',
          '最低コンディション',
          '現在のコンディション',
          'コンディション 49',
          '未改造の野埼はCond≥49が必要',
        ],
      ),
      (ko, ['컨디션', '최저 컨디션', '현재 컨디션', '컨디션 49', '미개장 노사키는 Cond≥49 필요']),
    ]) {
      late BuildContext context;
      await tester.pumpWidget(
        _scope(
          scenario.$1,
          Builder(
            builder: (value) {
              context = value;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      const keys = ['疲劳值', '最低疲劳', '当前疲劳', '疲劳 49', '未改野埼需疲劳≥49'];
      for (var i = 0; i < keys.length; i++) {
        expect(
          fleetText(context, keys[i]),
          scenario.$2[i],
          reason: '${scenario.$1}: ${keys[i]}',
        );
      }
    }
  });
}

Widget _scope(Locale locale, Widget child) => Localizations(
  locale: locale,
  delegates: const [DefaultWidgetsLocalizations.delegate],
  child: Directionality(textDirection: TextDirection.ltr, child: child),
);
