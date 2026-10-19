import 'package:flutter/widgets.dart';

import 'sortie_map_models.dart';

class SortieMapQueryStrings {
  const SortieMapQueryStrings(this.locale);

  factory SortieMapQueryStrings.of(BuildContext context) =>
      SortieMapQueryStrings(
        Localizations.maybeLocaleOf(context) ?? const Locale('zh'),
      );

  final Locale locale;

  String _text(String zh, String hant, String ja, String ko, String en) =>
      locale.languageCode == 'en'
      ? en
      : locale.languageCode == 'ko'
      ? ko
      : locale.languageCode == 'ja'
      ? ja
      : locale.scriptCode == 'Hant' ||
            const ['TW', 'HK', 'MO'].contains(locale.countryCode)
      ? hant
      : zh;

  String get title => _text('海域查询', '海域查詢', '海域検索', '해역 조회', 'Map lookup');
  String get selectMap => _text('海域选择', '海域選擇', '海域選択', '해역 선택', 'Select map');
  String get routeMap => _text('路线图', '路線圖', 'ルートマップ', '경로 지도', 'Route map');
  String get nodeInformation =>
      _text('节点信息', '節點資訊', 'マス情報', '지점 정보', 'Sortie node details');
  String get difficulty => _text('难度', '難度', '難易度', '난이도', 'Difficulty');
  String get boss => 'BOSS';
  String get formation => _text('阵型', '陣形', '陣形', '진형', 'Formation');
  String get experience => _text('经验', '經驗', '経験値', '경험치', 'EXP');
  String get experienceUnknown =>
      _text('经验不明', '經驗不明', '経験値不明', '경험치 미확인', 'Unknown EXP');
  String get airPower => _text('制空值', '制空值', '制空値', '제공치', 'Air power');
  String get airSuperiority =>
      _text('空优值', '空優值', '航空優勢', '항공우세', 'Air superiority');
  String get airSupremacy =>
      _text('空确值', '空確值', '制空権確保', '제공권 확보', 'Air supremacy');
  String get airSuperiorityShort => _text('优', '優', '優', '우세', 'AS');
  String get airSupremacyShort => _text('确', '確', '確', '확보', 'AS+');
  String get fleet => _text('敌方舰队', '敵方艦隊', '敵艦隊', '적 함대', 'Enemy fleet');
  String fleetNumber(int number) => switch (number) {
    1 => _text('敌方主力舰队', '敵方主力艦隊', '敵主力艦隊', '적 주력 함대', 'Enemy main fleet'),
    2 => _text('敌方伴随舰队', '敵方伴隨艦隊', '敵随伴艦隊', '적 수반 함대', 'Enemy escort fleet'),
    _ => _text(
      '敌方第 $number 舰队',
      '敵方第 $number 艦隊',
      '敵第 $number 艦隊',
      '적 제$number함대',
      'Enemy fleet $number',
    ),
  };
  String configuration(int number) => _text(
    '配置 $number',
    '配置 $number',
    '編成 $number',
    '편성 $number',
    'Composition $number',
  );
  String get finalConfiguration =>
      _text('斩杀', '斬殺', '最終形態', '최종 형태', 'Final form');
  String get clearAfter => _text('攻略后', '攻略後', 'クリア後', '클리어 후', 'After clear');
  String get noEnemy => _text(
    '此节点没有敌方配置',
    '此節點沒有敵方配置',
    '敵編成なし',
    '이 지점에는 적 편성이 없습니다',
    'No enemy compositions at this node',
  );
  String get noNodes =>
      _text('暂无节点信息', '暫無節點資訊', 'マス情報なし', '지점 정보가 없습니다', 'No sortie node data');
  String get loading => _text(
    '正在加载海域资料…',
    '正在載入海域資料…',
    '海域情報を読み込み中…',
    '해역 데이터 불러오는 중…',
    'Loading map data…',
  );
  String get loadFailed => _text(
    '海域资料加载失败',
    '海域資料載入失敗',
    '海域情報を読み込めませんでした',
    '해역 데이터를 불러오지 못했습니다',
    'Could not load map data',
  );
  String get retry => _text('重新加载', '重新載入', '再読み込み', '다시 불러오기', 'Reload');
  String get attribution => _text(
    '感谢 kcwiki.cn 提供海域数据 · 知识共享署名',
    '感謝 kcwiki.cn 提供海域資料 · 知識共享署名',
    '海域データ提供：kcwiki.cn · クリエイティブ・コモンズ表示',
    '해역 데이터 제공: kcwiki.cn · 크리에이티브 커먼즈 저작자표시',
    'Map data: kcwiki.cn · Creative Commons Attribution',
  );

  String enemyShipName(EnemyShipEntry ship) =>
      const ['ja', 'ko', 'en'].contains(locale.languageCode)
      ? ship.nameJa
      : ship.displayName;

  String? sourceDetail(String? value) =>
      locale.languageCode == 'ja' ? null : value;

  String nodeKind(String kind) => switch (kind) {
    'boss' => boss,
    'resource' => _text('资源点', '資源點', '資源マス', '자원 지점', 'Resource node'),
    'air' => _text('航空战', '航空戰', '航空戦', '항공전', 'Air battle'),
    'airstrike' => _text('空袭', '空襲', '空襲戦', '공습전', 'Air raid'),
    'night' => _text('夜战', '夜戰', '夜戦', '야전', 'Night battle'),
    'battle' => _text('战斗点', '戰鬥點', '戦闘マス', '전투 지점', 'Battle node'),
    'noenemy' => _text('无战斗', '無戰鬥', '戦闘なし', '전투 없음', 'No battle'),
    'imaginary' => _text('战斗回避', '戰鬥回避', '戦闘回避', '전투 회피', 'Battle avoided'),
    'maelstorm1' => _text('漩涡', '漩渦', 'うずしお', '소용돌이', 'Whirlpool'),
    'maelstorm2' => _text(
      '漩涡（强）',
      '漩渦（強）',
      'うずしお（強）',
      '소용돌이(강)',
      'Whirlpool (strong)',
    ),
    'activebranch' => _text('能动分歧', '能動分歧', '能動分岐', '능동 분기', 'Route selection'),
    '未知' => _text('未知', '未知', '不明', '미확인', 'Unknown'),
    _ => _text('特殊点', '特殊點', '特殊マス', '특수 지점', 'Special node'),
  };
}
