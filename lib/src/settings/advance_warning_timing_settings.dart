import 'package:flutter/foundation.dart';

@immutable
class AdvanceWarningTimingSettings {
  const AdvanceWarningTimingSettings({
    this.postBattle = false,
    this.afterAdvance = true,
  });

  static const advanceOnly = AdvanceWarningTimingSettings();
  static const battleAndAdvance = AdvanceWarningTimingSettings(
    postBattle: true,
  );
  static const battleOnly = AdvanceWarningTimingSettings(
    postBattle: true,
    afterAdvance: false,
  );
  static const values = <AdvanceWarningTimingSettings>[
    advanceOnly,
    battleAndAdvance,
    battleOnly,
  ];

  final bool postBattle;
  final bool afterAdvance;

  bool get hasAny => postBattle || afterAdvance;

  AdvanceWarningTimingSettings copyWith({
    bool? postBattle,
    bool? afterAdvance,
  }) => AdvanceWarningTimingSettings(
    postBattle: postBattle ?? this.postBattle,
    afterAdvance: afterAdvance ?? this.afterAdvance,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdvanceWarningTimingSettings &&
          postBattle == other.postBattle &&
          afterAdvance == other.afterAdvance;

  @override
  int get hashCode => Object.hash(postBattle, afterAdvance);

  @override
  String toString() =>
      'AdvanceWarningTimingSettings(postBattle: $postBattle, afterAdvance: $afterAdvance)';
}
