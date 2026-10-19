final class ShipSubtitleDataStrings {
  const ShipSubtitleDataStrings(this.localeName);
  final String localeName;

  String get partialFailure => switch (localeName.split('_').first) {
    'en' => 'Some updates failed. Existing data is still available.',
    'ja' => '一部の更新に失敗しました。既存のデータは引き続き利用できます。',
    'ko' => '일부 업데이트에 실패했습니다. 기존 자료는 계속 사용할 수 있습니다.',
    _ => localeName.contains('Hant') ? '一部分更新失敗，已有資料仍可用。' : '一部分更新失败，已有资料仍可用。',
  };

  String get updateFailed => switch (localeName.split('_').first) {
    'en' =>
      'Translation data updates failed. Existing data is still available.',
    'ja' => '翻訳データの更新に失敗しました。既存のデータは引き続き利用できます。',
    'ko' => '번역 자료 업데이트에 실패했습니다. 기존 자료는 계속 사용할 수 있습니다.',
    _ =>
      localeName.contains('Hant') ? '翻譯資料更新失敗，已有資料仍可用。' : '翻译资料更新失败，已有资料仍可用。',
  };

  String get title => switch (localeName.split('_').first) {
    'en' => 'Translation data',
    'ja' => '翻訳データ',
    'ko' => '번역 자료',
    _ => localeName.contains('Hant') ? '翻譯資料' : '翻译资料',
  };

  String languageLabel(String language) =>
      switch (localeName.split('_').first) {
        'en' => 'Subtitle language: $language',
        'ja' => '字幕言語：$language',
        'ko' => '자막 언어: $language',
        _ => localeName.contains('Hant') ? '字幕語言：$language' : '字幕语言：$language',
      };

  String get loading => switch (localeName.split('_').first) {
    'en' => 'Loading subtitle data…',
    'ja' => '字幕データを読み込み中…',
    'ko' => '자막 자료 불러오는 중…',
    _ => localeName.contains('Hant') ? '正在載入字幕資料…' : '正在加载字幕资料…',
  };

  String get loadFailed => switch (localeName.split('_').first) {
    'en' => 'Subtitle data could not be loaded. Tap to retry.',
    'ja' => '字幕データを読み込めませんでした。タップして再試行。',
    'ko' => '자막 자료를 불러오지 못했습니다. 눌러서 다시 시도하세요.',
    _ => localeName.contains('Hant') ? '字幕資料載入失敗，點擊重試。' : '字幕资料加载失败，点击重试。',
  };
}
