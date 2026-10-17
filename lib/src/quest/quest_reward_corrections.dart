// Verified against the game screenshots and quest tables on 2026-10-07.
// Match the complete known-bad reward payload so newer upstream rewards win.
// Raw catalog JSON and its content hash remain unchanged.
Map<String, Object?> correctQuestRewardData(
  int gameId,
  Map<String, Object?> json,
) {
  final correction = _corrections[gameId];
  if (correction == null || !correction.matches(json)) return json;
  return <String, Object?>{
    ...json,
    'rewards': correction.rewards,
    'resources': correction.resources,
  };
}

const _corrections = <int, _RewardCorrection>{
  // https://wikiwiki.jp/kancolle/任務/編成任務#id-A31
  131: _RewardCorrection(
    code: 'A31',
    oldRewards: '開発資材',
    oldResources: [
      [150, 150, 0, 0],
      [0, 0, 1, 0],
    ],
    rewards: '開発資材×3',
    resources: [
      [150, 150, 0, 0],
      [0, 0, 3, 0],
    ],
  ),
  // https://wikiwiki.jp/kancolle/任務/演習任務#id-Cs3
  // https://kancolle.osshi-market.com/mission-spring-university-exercise-876
  315: _RewardCorrection(
    code: 'Cs3',
    oldRewards: '高速修復材×3, 給糧艦「間宮」, プレゼント箱',
    oldResources: [
      [0, 0, 1000, 300],
      [3, 0, 0, 0],
    ],
    rewards: '給糧艦「間宮」, プレゼント箱',
    resources: [
      [0, 0, 1000, 300],
      [0, 0, 0, 0],
    ],
  ),
  // https://zekamashi.net/kancolle-kouryaku/yourikusendangoeiensyuu/
  // The game quest-row screenshot confirms all four fixed amounts are 100.
  380: _RewardCorrection(
    code: 'L2507C1',
    oldRewards:
        '二回選択報酬：[高速修復材×3、改修資材、戦闘糧食]'
        '[開発資材×3、九四式爆雷投射機×2、三式爆雷投射機]',
    oldResources: [
      [100, 100, '', 100],
      [0, 0, 0, 0],
    ],
    rewards:
        '二回選択報酬：[高速修復材×3、改修資材、戦闘糧食]'
        '[開発資材×3、九四式爆雷投射機×2、三式爆雷投射機]',
    resources: [
      [100, 100, 100, 100],
      [0, 0, 0, 0],
    ],
  ),
  // https://wikiwiki.jp/kancolle/任務/工廠任務#id-F2
  602: _RewardCorrection(
    code: 'F2',
    oldRewards: '開発資材×2',
    oldResources: [
      [100, 100, 100, 100],
      [0, 0, 2, 0],
    ],
    rewards: '開発資材',
    resources: [
      [100, 100, 100, 100],
      [0, 0, 1, 0],
    ],
  ),
  // https://wikiwiki.jp/kancolle/任務/工廠任務#id-F3
  603: _RewardCorrection(
    code: 'F3',
    oldRewards: '開発資材×2, 高速建造材',
    oldResources: [
      [60, 60, 60, 60],
      [0, 1, 2, 0],
    ],
    rewards: '開発資材, 高速建造材',
    resources: [
      [60, 60, 60, 60],
      [0, 1, 1, 0],
    ],
  ),
  // https://wikiwiki.jp/kancolle/任務/出撃任務#id-B209
  // https://zekamashi.net/wp-content/uploads/2025/05/sentaku3.jpg
  1029: _RewardCorrection(
    code: 'B209',
    oldRewards:
        '二回選択報酬：[開発資材×17、新型砲熕兵装資材×2、改修資材×5]'
        '[25mm三連装機銃★9×2、13号対空電探改(後期型)★8、12.7cm連装砲D型改二★7]',
    oldResources: [
      [1944, 1111, 2025, 512],
      [0, 0, 0, 0],
    ],
    rewards:
        '二回選択報酬：[開発資材×13、新型砲熕兵装資材×2、改修資材×5]'
        '[25mm三連装機銃★9×2、13号対空電探改(後期型)★8、12.7cm連装砲D型改二★7]',
    resources: [
      [1944, 1111, 2025, 512],
      [0, 0, 0, 0],
    ],
  ),
};

class _RewardCorrection {
  const _RewardCorrection({
    required this.code,
    required this.oldRewards,
    required this.oldResources,
    required this.rewards,
    required this.resources,
  });

  final String code;
  final String oldRewards;
  final List<List<Object>> oldResources;
  final String rewards;
  final List<List<Object>> resources;

  bool matches(Map<String, Object?> json) {
    if (json['code'] != code || json['rewards'] != oldRewards) return false;
    final raw = json['resources'];
    if (raw is! List || raw.length != oldResources.length) return false;
    for (var row = 0; row < oldResources.length; row++) {
      final values = raw[row];
      if (values is! List || values.length != oldResources[row].length) {
        return false;
      }
      for (var column = 0; column < values.length; column++) {
        if (values[column] != oldResources[row][column]) return false;
      }
    }
    return true;
  }
}
