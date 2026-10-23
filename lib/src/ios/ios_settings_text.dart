import 'package:flutter/foundation.dart';

import '../../l10n/app_localizations.dart';

/// iOS-only settings tweaks live here so the shared settings pages carry as
/// few iOS edits as possible (fewer conflicts when merging upstream).
bool get isIOSPlatform => defaultTargetPlatform == TargetPlatform.iOS;

const iosUnsupportedFeatureText = 'iOS 因系统底层限制，暂不支持此功能';

String iosLegacyProxyNote(AppLocalizations l10n) {
  final locale = l10n.localeName;
  if (locale.startsWith('ja')) {
    return 'APIの制限により、iOS 17.0 未満のバージョンではアプリ内独立プロキシはサポートされていません';
  }
  if (locale.startsWith('zh_Hant')) {
    return '因底層 API 限制，iOS 17.0 以下版本暫不支援應用程式內獨立代理';
  }
  return '因底层 API 限制，iOS 17.0 以下版本暂不支持应用内独立代理';
}
