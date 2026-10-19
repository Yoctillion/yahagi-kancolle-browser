import 'package:flutter/widgets.dart';

import '../localization/game_name_localizations.dart';
import 'development_dataset.dart';

/// The Chinese calculator already has its own labels; preserve those choices.
String developmentEquipmentLabel(
  BuildContext context,
  DevelopmentEquipmentRecord item,
) {
  final locale = Localizations.localeOf(context);
  return const ['en', 'ko'].contains(locale.languageCode)
      ? gameNames(context).equipmentName(item.name)
      : item.label(locale);
}

/// Pool labels contain a group, ship names, class suffixes and exclusions.
/// Only these source fields use the compound entity resolver.
String developmentPoolText(BuildContext context, String text) {
  final language = Localizations.localeOf(context).languageCode;
  if (language != 'en' && language != 'ko') return text;
  final korean = language == 'ko';
  final names = gameNames(context);
  if (names.bundle == null) return text;
  var output = text.replaceAllMapped(RegExp(r'([^,，\s()（）]+)[(（](\d+)[)）]'), (
    match,
  ) {
    final raw = match.group(1)!;
    final excluded = raw.startsWith('除外');
    final name = names.shipName(
      excluded ? raw.substring(2) : raw,
      shipId: int.parse(match.group(2)!),
    );
    return '${excluded ? '除外' : ''}$name (${match.group(2)})';
  });
  output = names.entityText(output);
  final groups = <String, String>{
    '水雷系': korean ? '수뢰계' : 'Torpedo fleet',
    '砲戦系': korean ? '포격계' : 'Gunnery',
    '空母系': korean ? '항모계' : 'Carrier',
    '潜水系': korean ? '잠수함계' : 'Submarine',
    '除外': korean ? '제외: ' : 'except ',
    '級': korean ? '급' : ' class',
    '型': korean ? '급' : ' class',
  };
  final pattern = RegExp(groups.keys.map(RegExp.escape).join('|'));
  return output.replaceAllMapped(pattern, (match) => groups[match.group(0)]!);
}
