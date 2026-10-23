import 'package:flutter/foundation.dart';

import '../account/account_session.dart';
import '../bridge/captured_api_event.dart';
import '../game_state/game_api_decoder.dart';
import '../game_state/game_api_event_pipeline.dart';

enum PracticeView { list, detail }

/// `api_get_member/practice` reports ranks as Japanese text, while
/// `get_practice_enemyinfo` reports the numeric id; index = rank id.
const practiceRankNamesJa = [
  '',
  '元帥',
  '大将',
  '中将',
  '少将',
  '大佐',
  '中佐',
  '新米中佐',
  '少佐',
  '中堅少佐',
  '新米少佐',
];

final class PracticeOpponent {
  const PracticeOpponent({
    required this.memberId,
    required this.name,
    required this.level,
    required this.rankId,
    required this.comment,
    required this.flagshipMasterId,
    required this.result,
  });

  final int memberId;
  final String name;
  final int level;
  final int rankId;
  final String comment;
  final int flagshipMasterId;

  /// 0 = not fought yet, 1..6 = E D C B A S.
  final int result;
}

final class PracticeOpponentShip {
  const PracticeOpponentShip({
    required this.masterId,
    required this.level,
    required this.star,
  });

  final int masterId;
  final int level;
  final int star;
}

final class PracticeOpponentFleet {
  const PracticeOpponentFleet({
    required this.name,
    required this.level,
    required this.rankId,
    required this.deckName,
    required this.ships,
  });

  final String name;
  final int level;
  final int rankId;
  final String deckName;
  final List<PracticeOpponentShip> ships;
}

class PracticeOpponentController extends ChangeNotifier
    implements GameApiEventConsumer {
  PracticeOpponentController({this.accountSession})
    : _scope = accountSession?.current {
    accountSession?.addListener(_onAccountChanged);
  }

  final AccountSession? accountSession;

  static const _listPath = '/kcsapi/api_get_member/practice';
  static const _detailPath = '/kcsapi/api_req_member/get_practice_enemyinfo';

  AccountScope? _scope;
  PracticeView _view = PracticeView.list;
  List<PracticeOpponent> _opponents = const [];
  PracticeOpponentFleet? _selected;
  bool _disposed = false;

  PracticeView get view => _view;
  List<PracticeOpponent> get opponents => _opponents;
  PracticeOpponentFleet? get selected => _selected;

  @override
  Future<void> get idle => Future<void>.value();

  @override
  bool supportsPath(String path) => path == _listPath || path == _detailPath;

  @override
  void accept(CapturedApiEvent event) {
    if (_disposed || !supportsPath(event.path)) return;
    final Object? data;
    try {
      data = GameApiDecoder.decodeEventData(event);
    } on Object {
      return;
    }
    if (data is! Map) return;
    if (event.path == _listPath) {
      final list = data['api_list'];
      if (list is! List) return;
      _opponents = [
        for (final raw in list)
          if (raw is Map) _parseOpponent(raw),
      ];
      _view = PracticeView.list;
    } else {
      final fleet = _parseFleet(data);
      if (fleet == null) return;
      _selected = fleet;
      _view = PracticeView.detail;
    }
    notifyListeners();
  }

  static PracticeOpponent _parseOpponent(Map raw) {
    final rankIndex = practiceRankNamesJa.indexOf('${raw['api_enemy_rank']}');
    return PracticeOpponent(
      memberId: _asInt(raw['api_enemy_id']),
      name: '${raw['api_enemy_name'] ?? ''}',
      level: _asInt(raw['api_enemy_level']),
      rankId: rankIndex > 0 ? rankIndex : 0,
      comment: '${raw['api_enemy_comment'] ?? ''}',
      flagshipMasterId: _asInt(raw['api_enemy_flag_ship']),
      result: _asInt(raw['api_state']),
    );
  }

  static PracticeOpponentFleet? _parseFleet(Map data) {
    final deck = data['api_deck'];
    if (deck is! Map) return null;
    final ships = deck['api_ships'];
    if (ships is! List) return null;
    return PracticeOpponentFleet(
      name: '${data['api_nickname'] ?? ''}',
      level: _asInt(data['api_level']),
      rankId: _asInt(data['api_rank']),
      deckName: '${data['api_deckname'] ?? ''}',
      ships: [
        for (final ship in ships)
          if (ship is Map && _asInt(ship['api_id']) > 0)
            PracticeOpponentShip(
              masterId: _asInt(ship['api_ship_id']),
              level: _asInt(ship['api_level']),
              star: _asInt(ship['api_star']),
            ),
      ],
    );
  }

  static int _asInt(Object? value) => switch (value) {
    num number => number.toInt(),
    String text => int.tryParse(text) ?? 0,
    _ => 0,
  };

  void _onAccountChanged() {
    // AccountSession also notifies for admiral name updates on the same account.
    final current = accountSession?.current;
    if (identical(current, _scope)) return;
    _scope = current;
    _view = PracticeView.list;
    _opponents = const [];
    _selected = null;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    accountSession?.removeListener(_onAccountChanged);
    super.dispose();
  }
}
