/// Subtitle text languages are independent of the app's interface language.
enum ShipSubtitleLanguage {
  simplifiedChinese('zh-cn', '简体中文'),
  traditionalChinese('zh-tw', '繁體中文'),
  japanese('ja-jp', '日本語'),
  english('en-us', 'English'),
  korean('ko-kr', '한국어');

  const ShipSubtitleLanguage(this.code, this.label);

  final String code;
  final String label;

  bool get usesKc3Quotes => this == english || this == korean;

  String get bundledAsset => 'assets/data/subtitles/$code.json';

  static ShipSubtitleLanguage fromStoredValue(Object? value) =>
      values.firstWhere(
        (language) => language.code == value,
        orElse: () => simplifiedChinese,
      );
}
