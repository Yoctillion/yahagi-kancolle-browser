import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/localization/runtime_message_text.dart';
import 'package:yahagi_kancolle_browser/src/localization/ui_text.dart';

void main() {
  test(
    'background retention failures translate app text and preserve details',
    () {
      const details = 'PlatformException(test, 原始错误 https://example.test/路径)';
      for (final (locale, settingPrefix, startupPrefix) in [
        (const Locale('zh'), '后台保活设置失败：', '后台保活启动失败：'),
        (
          const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
          '背景保活設定失敗：',
          '背景保活啟動失敗：',
        ),
        (const Locale('ja'), 'バックグラウンド動作の設定に失敗：', 'バックグラウンド動作の開始に失敗：'),
        (const Locale('ko'), '백그라운드 유지 설정 실패: ', '백그라운드 유지 시작 실패: '),
        (
          const Locale('en'),
          'Failed to configure background retention: ',
          'Failed to start background retention: ',
        ),
      ]) {
        expect(
          runtimeMessageForLocale(locale, '后台保活设置失败：$details'),
          '$settingPrefix$details',
          reason: locale.toString(),
        );
        expect(
          runtimeMessageForLocale(locale, '后台保活启动失败：$details'),
          '$startupPrefix$details',
          reason: locale.toString(),
        );
        expect(runtimeMessageForLocale(locale, details), details);
      }
    },
  );

  test(
    'background retention synchronization failures translate their prefix',
    () {
      const details = 'PlatformException(test, native failure)';
      for (final (locale, prefix) in [
        (const Locale('zh'), '后台保活状态同步失败：'),
        (
          const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
          '背景保活狀態同步失敗：',
        ),
        (const Locale('ja'), 'バックグラウンド動作の状態同期に失敗：'),
        (const Locale('ko'), '백그라운드 유지 상태 동기화 실패: '),
        (const Locale('en'), 'Failed to synchronize background retention: '),
      ]) {
        expect(
          runtimeMessageForLocale(locale, '后台保活状态同步失败：$details'),
          '$prefix$details',
          reason: locale.toString(),
        );
      }
    },
  );

  test('legacy UI and runtime catalogs provide every translated slot', () {
    for (final catalog in [uiTextTranslations, runtimeMessageTranslations]) {
      for (final entry in catalog.entries) {
        for (final translation in [
          entry.value.$1,
          entry.value.$2,
          entry.value.$3,
          entry.value.$4,
        ]) {
          expect(translation.trim(), isNotEmpty, reason: entry.key);
        }
        expect(
          RegExp(r'[\u3400-\u9fff\u3040-\u30ff\uac00-\ud7af]')
          // Preserve the certificate provider's actual product name.
          .hasMatch(entry.value.$4.replaceAll('岛风GO', '')),
          isFalse,
          reason: 'English UI text: ${entry.key}',
        );
      }
    }
  });
}
