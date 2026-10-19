import 'package:flutter/widgets.dart';

import 'ship_subtitle_settings.dart';

/// Interface labels follow the app language independently of subtitle text.
class ShipSubtitleStrings {
  const ShipSubtitleStrings(this.locale);
  factory ShipSubtitleStrings.of(BuildContext context) => ShipSubtitleStrings(
    Localizations.maybeLocaleOf(context) ?? const Locale('zh'),
  );

  final Locale locale;

  String _t(String zh, String hant, String ja, String en, String ko) =>
      switch (locale.languageCode) {
        'en' => en,
        'ja' => ja,
        'ko' => ko,
        _ =>
          locale.scriptCode == 'Hant' ||
                  const ['TW', 'HK', 'MO'].contains(locale.countryCode)
              ? hant
              : zh,
      };

  String get title =>
      _t('舰娘语音字幕', '艦娘語音字幕', '艦娘ボイス字幕', 'Ship voice subtitles', '함선 음성 자막');

  String get description => _t(
    '在游戏画面内显示舰娘语音字幕',
    '在遊戲畫面內顯示艦娘語音字幕',
    'ゲーム画面に艦娘ボイスの字幕を表示',
    'Show ship voice subtitles inside the game',
    '게임 화면에 함선 음성 자막 표시',
  );

  String get fontSize =>
      _t('字幕字体大小', '字幕字體大小', '字幕の文字サイズ', 'Subtitle font size', '자막 글꼴 크기');

  String get language =>
      _t('字幕语言', '字幕語言', '字幕の言語', 'Subtitle language', '자막 언어');

  String sizeLabel(ShipSubtitleFontSize size) => switch (size) {
    ShipSubtitleFontSize.small => _t('小', '小', '小', 'Small', '작게'),
    ShipSubtitleFontSize.medium => _t('中', '中', '中', 'Medium', '중간'),
    ShipSubtitleFontSize.large => _t('大', '大', '大', 'Large', '크게'),
  };

  String get dragHandleLabel =>
      _t('移动字幕', '移動字幕', '字幕を移動', 'Move subtitles', '자막 이동');

  String get saveFailed => _t(
    '字幕设置保存失败，请重试',
    '字幕設定儲存失敗，請重試',
    '字幕設定を保存できませんでした。もう一度お試しください',
    'Subtitle settings could not be saved. Please try again.',
    '자막 설정을 저장하지 못했습니다. 다시 시도하세요.',
  );

  String get dataTitle => _t(
    '舰娘语音字幕资料',
    '艦娘語音字幕資料',
    '艦娘ボイス字幕データ',
    'Ship subtitle data',
    '함선 음성 자막 데이터',
  );

  String get dataDescription => _t(
    '舰娘语音字幕文本',
    '艦娘語音字幕文字',
    '艦娘ボイスの字幕テキスト',
    'Ship voice subtitle text',
    '함선 음성 자막 텍스트',
  );
}
