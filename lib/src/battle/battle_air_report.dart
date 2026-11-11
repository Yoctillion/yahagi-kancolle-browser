final class PlaneCount {
  const PlaneCount(this.count, this.lost);

  final int count;
  final int lost;

  @override
  bool operator ==(Object other) =>
      other is PlaneCount && other.count == count && other.lost == lost;

  @override
  int get hashCode => Object.hash(count, lost);

  @override
  String toString() => 'PlaneCount($count, $lost)';
}

final class PlaneExchange {
  const PlaneExchange({this.friend, this.enemy});

  final PlaneCount? friend;
  final PlaneCount? enemy;

  bool get isEmpty => (friend?.count ?? 0) == 0 && (enemy?.count ?? 0) == 0;

  @override
  bool operator ==(Object other) =>
      other is PlaneExchange && other.friend == friend && other.enemy == enemy;

  @override
  int get hashCode => Object.hash(friend, enemy);

  @override
  String toString() => 'PlaneExchange($friend, $enemy)';
}

enum AirPhaseKind {
  landBaseJet,
  landBase,
  friendly,
  supportAir,
  supportShelling,
  supportTorpedo,
  supportAntiSub,
}

final class AirPhaseLine {
  const AirPhaseLine({
    required this.kind,
    this.planes = const PlaneExchange(),
    this.damage,
    this.baseId,
    this.wave,
  });

  final AirPhaseKind kind;
  final PlaneExchange planes;
  final int? damage;
  final int? baseId;
  final int? wave;

  @override
  bool operator ==(Object other) =>
      other is AirPhaseLine &&
      other.kind == kind &&
      other.planes == planes &&
      other.damage == damage &&
      other.baseId == baseId &&
      other.wave == wave;

  @override
  int get hashCode => Object.hash(kind, planes, damage, baseId, wave);

  @override
  String toString() =>
      'AirPhaseLine($kind, $planes, damage: $damage, baseId: $baseId, '
      'wave: $wave)';
}

final class AntiAirCutIn {
  const AntiAirCutIn({required this.position, required this.kind});

  final int position;
  final int kind;

  @override
  bool operator ==(Object other) =>
      other is AntiAirCutIn && other.position == position && other.kind == kind;

  @override
  int get hashCode => Object.hash(position, kind);

  @override
  String toString() => 'AntiAirCutIn(position: $position, kind: $kind)';
}

final class DayAirReport {
  const DayAirReport({
    this.jet,
    this.fighter,
    this.antiAir,
    this.secondWave = false,
    this.friendContactPlaneId = -1,
    this.enemyContactPlaneId = -1,
    this.antiAirCutIns = const [],
    this.phases = const [],
  });

  final PlaneExchange? jet;
  final PlaneExchange? fighter;
  final PlaneExchange? antiAir;
  final bool secondWave;
  final int friendContactPlaneId;
  final int enemyContactPlaneId;
  final List<AntiAirCutIn> antiAirCutIns;
  final List<AirPhaseLine> phases;

  bool get hasMainTable => jet != null || fighter != null || antiAir != null;

  bool get isEmpty => !hasMainTable && phases.isEmpty;
}

final class NightReport {
  const NightReport({
    this.friendContactPlaneId = -1,
    this.enemyContactPlaneId = -1,
    this.friendFlarePosition = -1,
    this.enemyFlarePosition = -1,
    this.supportDamage,
  });

  final int friendContactPlaneId;
  final int enemyContactPlaneId;
  final int friendFlarePosition;
  final int enemyFlarePosition;
  final int? supportDamage;

  bool get isEmpty =>
      friendContactPlaneId <= 0 &&
      enemyContactPlaneId <= 0 &&
      friendFlarePosition < 0 &&
      enemyFlarePosition < 0 &&
      supportDamage == null;

  @override
  bool operator ==(Object other) =>
      other is NightReport &&
      other.friendContactPlaneId == friendContactPlaneId &&
      other.enemyContactPlaneId == enemyContactPlaneId &&
      other.friendFlarePosition == friendFlarePosition &&
      other.enemyFlarePosition == enemyFlarePosition &&
      other.supportDamage == supportDamage;

  @override
  int get hashCode => Object.hash(
    friendContactPlaneId,
    enemyContactPlaneId,
    friendFlarePosition,
    enemyFlarePosition,
    supportDamage,
  );

  @override
  String toString() =>
      'NightReport(friendContact: $friendContactPlaneId, '
      'enemyContact: $enemyContactPlaneId, friendFlare: $friendFlarePosition, '
      'enemyFlare: $enemyFlarePosition, supportDamage: $supportDamage)';
}

DayAirReport? parseDayAirReport(Map<String, Object?> data) {
  final kouku = _map(data['api_kouku']);
  final kouku2 = _map(data['api_kouku2']);
  final stage1 = _map(kouku?['api_stage1']);
  final stage2 = _map(kouku?['api_stage2']);
  final stage1b = _map(kouku2?['api_stage1']);
  final stage2b = _map(kouku2?['api_stage2']);

  final jetData = _map(data['api_injection_kouku']);
  final jet = jetData == null ? null : _nonEmpty(_exchange(jetData));
  final fighter = _nonEmpty(
    _addLost(_stageExchange(stage1), _stageExchange(stage1b)),
  );
  final antiAir = _nonEmpty(
    _addLost(_stageExchange(stage2), _stageExchange(stage2b)),
  );

  final touch = _list(stage1?['api_touch_plane']);
  final cutIns = [..._cutIns(stage2), ..._cutIns(stage2b)];

  final phases = <AirPhaseLine>[];
  final injection = _map(data['api_air_base_injection']);
  if (injection != null) {
    phases.add(
      AirPhaseLine(
        kind: AirPhaseKind.landBaseJet,
        planes: _exchange(injection),
        damage: _airDamage(injection),
      ),
    );
  }
  final waves = <int, int>{};
  for (final raw in _list(data['api_air_base_attack'])) {
    final attack = _map(raw);
    if (attack == null) continue;
    final baseId = _int(attack['api_base_id']);
    final wave = (waves[baseId] ?? 0) + 1;
    waves[baseId] = wave;
    phases.add(
      AirPhaseLine(
        kind: AirPhaseKind.landBase,
        planes: _exchange(attack),
        damage: _airDamage(attack),
        baseId: baseId,
        wave: wave,
      ),
    );
  }
  final friendly = _map(data['api_friendly_kouku']);
  if (friendly != null) {
    phases.add(
      AirPhaseLine(
        kind: AirPhaseKind.friendly,
        planes: _exchange(friendly),
        damage: _airDamage(friendly),
      ),
    );
  }
  final support = _supportLine(
    _map(data['api_support_info']),
    _int(data['api_support_flag']),
  );
  if (support != null) phases.add(support);

  final report = DayAirReport(
    jet: jet,
    fighter: fighter,
    antiAir: antiAir,
    secondWave: kouku2 != null,
    friendContactPlaneId: _contact(touch, 0),
    enemyContactPlaneId: _contact(touch, 1),
    antiAirCutIns: cutIns,
    phases: phases,
  );
  return report.isEmpty ? null : report;
}

NightReport? parseNightReport(Map<String, Object?> data) {
  final touch = _list(data['api_touch_plane']);
  final flare = _list(data['api_flare_pos']);
  final support = _supportLine(
    _map(data['api_n_support_info']),
    _int(data['api_n_support_flag']),
  );
  final report = NightReport(
    friendContactPlaneId: _contact(touch, 0),
    enemyContactPlaneId: _contact(touch, 1),
    friendFlarePosition: _flare(flare, 0),
    enemyFlarePosition: _flare(flare, 1),
    supportDamage: support?.damage,
  );
  return report.isEmpty ? null : report;
}

// 行总损失里只并入 stage2 的我方损失，敌方对空损失属于对空表。
PlaneExchange _exchange(Map<String, Object?> kouku) {
  final stage1 = _map(kouku['api_stage1']);
  final stage2 = _map(kouku['api_stage2']);
  if (stage1 == null) return const PlaneExchange();
  return PlaneExchange(
    friend: PlaneCount(
      _int(stage1['api_f_count']),
      _int(stage1['api_f_lostcount']) + _int(stage2?['api_f_lostcount']),
    ),
    enemy: PlaneCount(
      _int(stage1['api_e_count']),
      _int(stage1['api_e_lostcount']),
    ),
  );
}

PlaneExchange? _stageExchange(Map<String, Object?>? stage) {
  if (stage == null) return null;
  return PlaneExchange(
    friend: PlaneCount(
      _int(stage['api_f_count']),
      _int(stage['api_f_lostcount']),
    ),
    enemy: PlaneCount(
      _int(stage['api_e_count']),
      _int(stage['api_e_lostcount']),
    ),
  );
}

// 第二波只累加损失，数量以第一波为准。
PlaneExchange? _addLost(PlaneExchange? first, PlaneExchange? second) {
  if (first == null || second == null) return first;
  PlaneCount? merge(PlaneCount? a, PlaneCount? b) =>
      a == null ? null : PlaneCount(a.count, a.lost + (b?.lost ?? 0));
  return PlaneExchange(
    friend: merge(first.friend, second.friend),
    enemy: merge(first.enemy, second.enemy),
  );
}

PlaneExchange? _nonEmpty(PlaneExchange? exchange) =>
    exchange == null || exchange.isEmpty ? null : exchange;

List<AntiAirCutIn> _cutIns(Map<String, Object?>? stage2) {
  final fire = _map(stage2?['api_air_fire']);
  if (fire == null || fire['api_idx'] == null) return const [];
  return [
    AntiAirCutIn(position: _int(fire['api_idx']), kind: _int(fire['api_kind'])),
  ];
}

int? _airDamage(Map<String, Object?>? kouku) {
  final stage3 = _map(kouku?['api_stage3']);
  final combined = _map(kouku?['api_stage3_combined']);
  if (stage3 == null && combined == null) return null;
  return _floorSum(stage3?['api_edam']) + _floorSum(combined?['api_edam']);
}

AirPhaseLine? _supportLine(Map<String, Object?>? info, int flag) {
  if (info == null) return null;
  switch (flag) {
    case 1:
    case 4:
      return AirPhaseLine(
        kind: flag == 1 ? AirPhaseKind.supportAir : AirPhaseKind.supportAntiSub,
        damage: _airDamage(_map(info['api_support_airatack'])),
      );
    case 2:
    case 3:
      final hourai = _map(info['api_support_hourai']);
      return AirPhaseLine(
        kind: flag == 2
            ? AirPhaseKind.supportShelling
            : AirPhaseKind.supportTorpedo,
        damage: hourai == null ? null : _floorSum(hourai['api_damage']),
      );
  }
  return null;
}

int _floorSum(Object? values) {
  var total = 0;
  for (final value in _list(values)) {
    total += value is num ? value.floor() : _int(value);
  }
  return total;
}

int _contact(List<Object?> touch, int index) {
  final id = index < touch.length ? _int(touch[index]) : -1;
  return id > 0 ? id : -1;
}

// 联合舰队夜战由随伴舰队进行，序号需折回该舰队内。
int _flare(List<Object?> flare, int index) {
  final position = index < flare.length ? _int(flare[index]) : -1;
  return position >= 0 ? position % 6 : -1;
}

Map<String, Object?>? _map(Object? value) => value is Map
    ? value.map((key, child) => MapEntry(key.toString(), child))
    : null;

List<Object?> _list(Object? value) =>
    value is List ? List<Object?>.from(value) : const <Object?>[];

int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
