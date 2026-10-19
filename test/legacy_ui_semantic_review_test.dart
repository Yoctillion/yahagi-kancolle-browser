import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/expedition/expedition_models.dart';
import 'package:yahagi_kancolle_browser/src/expedition/expedition_strings.dart';
import 'package:yahagi_kancolle_browser/src/localization/runtime_message_text.dart';
import 'package:yahagi_kancolle_browser/src/localization/ui_text.dart';

void main() {
  test(
    'Simplified Chinese translates only the three known English fallbacks',
    () {
      const zh = Locale('zh');
      for (final entry in const {
        'Unknown error': '未知错误',
        'No result returned from native platform': '原生平台未返回结果',
        'Platform exception occurred': '原生平台发生异常',
      }.entries) {
        expect(runtimeMessageForLocale(zh, entry.key), entry.value);
        const code = '原始_CODE/ko/Unknown error';
        expect(
          runtimeMessageForLocale(zh, '网络设置应用失败 [$code]: ${entry.key}'),
          '网络设置应用失败 [$code]: ${entry.value}',
        );
      }
      for (final raw in [
        'SocketException: connection reset https://example.test/Unknown error',
        'Unknown error: system detail',
        'PlatformException(原始错误, 시스템 오류)',
        '网络设置应用失败 [raw_code]: Unknown error: system detail',
        '网络设置应用失败 [raw_code]: SocketException: https://example.test/경로',
        'Unknown wrapper [raw_code]: Unknown error',
      ]) {
        expect(runtimeMessageForLocale(zh, raw), raw);
      }
    },
  );

  test(
    'Korean capture wrapper pairs punctuation and preserves raw details',
    () {
      const ko = Locale('ko');
      const detail = 'PlatformException: 原始错误 https://example.test/경로';
      expect(
        runtimeMessageForLocale(ko, '捕获配置失败（$detail）'),
        '캡처 설정 실패($detail)',
      );
      const incomplete = '捕获配置失败（UnknownType';
      expect(runtimeMessageForLocale(ko, incomplete), incomplete);
      expect(runtimeMessageForLocale(ko, detail), detail);
    },
  );

  test('Korean furniture box sizes localize only known size labels', () {
    const ko = Locale('ko');
    for (final entry in const {'小': '소', '中': '중', '大': '대'}.entries) {
      for (final source in ['家具箱(${entry.key})', '家具箱（${entry.key}）']) {
        expect(uiTextForLocale(ko, source), '가구 상자(${entry.value})');
      }
    }
    expect(uiTextForLocale(ko, '家具箱(Custom Size)'), '가구 상자(Custom Size)');
    expect(uiTextForLocale(ko, '家具箱（Custom Size）'), '가구 상자(Custom Size)');
    expect(
      uiTextForLocale(const Locale('en'), '家具箱（大）'),
      'Furniture box (large)',
    );
  });

  test('Korean powerup removal records identify ship modernization', () {
    expect(uiTextForLocale(const Locale('ko'), '改修'), '근대화개수');
    expect(uiTextForLocale(const Locale('ja'), '改修'), '近代化改修');
    expect(uiTextForLocale(const Locale('en'), '改修'), 'Modernization');
  });

  for (final scenario in <(Locale, String, String)>[
    (const Locale('zh'), '大成功运输桶数量 ≥ 4', '运输桶数量 ≥ 3'),
    (
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      '大成功運輸桶數量 ≥ 4',
      '運輸桶數量 ≥ 3',
    ),
    (const Locale('ja'), '大成功に必要なドラム缶数 ≥ 4', 'ドラム缶数 ≥ 3'),
    (const Locale('ko'), '대성공 드럼통 수 ≥ 4', '드럼통 수 ≥ 3'),
    (const Locale('en'), 'Drum count for great success ≥ 4', 'Drum count ≥ 3'),
  ]) {
    testWidgets('great success drum qualifier is retained in ${scenario.$1}', (
      tester,
    ) async {
      late ExpeditionStrings strings;
      await tester.pumpWidget(
        Localizations(
          locale: scenario.$1,
          delegates: const [DefaultWidgetsLocalizations.delegate],
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) {
                strings = ExpeditionStrings.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      const great = ExpeditionConditionResult(
        kind: ExpeditionConditionKind.drumCount,
        label: '大成功运输桶数量 ≥ 4',
        actual: '4 / 4',
        passed: true,
      );
      const normal = ExpeditionConditionResult(
        kind: ExpeditionConditionKind.drumCount,
        label: '运输桶数量 ≥ 3',
        actual: '4 / 3',
        passed: true,
      );
      expect(strings.conditionLabel(great), scenario.$2);
      expect(strings.conditionLabel(normal), scenario.$3);
      expect(strings.conditionActual(great), '4 / 4');
    });
  }
}
