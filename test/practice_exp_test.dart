import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/practice/practice_exp.dart';

const _katori = 154;
const _kashima = 465;
const _asahi = 953;
const _fubuki = 1;

GameState _fleet(List<(int masterId, int level)> ships) {
  return GameState.empty.copyWith(
    masterShips: {
      _katori: const MasterShip(id: _katori, name: '香取', shipTypeId: 21),
      _kashima: const MasterShip(id: _kashima, name: '鹿島', shipTypeId: 21),
      _asahi: const MasterShip(id: _asahi, name: '朝日', shipTypeId: 21),
      _fubuki: const MasterShip(id: _fubuki, name: '吹雪', shipTypeId: 2),
    },
    ships: {
      for (var i = 0; i < ships.length; i++)
        100 + i: OwnedShip(
          id: 100 + i,
          masterId: ships[i].$1,
          level: ships[i].$2,
        ),
    },
    fleets: [
      Fleet(
        id: 1,
        name: '第1舰队',
        shipIds: [for (var i = 0; i < ships.length; i++) 100 + i],
      ),
    ],
  );
}

void main() {
  test('base exp adds the max random 3 and caps above 500', () {
    expect(practiceBaseExp(50, 0), 526);
    expect(practiceBaseExp(80, 60), 562);
    expect(practiceBaseExp(10, 10), 63);
    expect(practiceBaseExp(1, 1), 3);
    expect(practiceBaseExp(0, 80), 0);
    expect(practiceBaseExp(-1, 80), 0);
    expect(practiceBaseExp(80, -5), practiceBaseExp(80, 0));
  });

  test('rank exp floors each step', () {
    const none = PracticeCtBonus.none;
    expect(
      [for (final r in PracticeRank.values) practiceRankExp(526, r, none)],
      [631, 526, 526, 336, 294, 210],
    );
    const ct = PracticeCtBonus(modifier: 1.15, submarineModifier: 1.15);
    expect(practiceRankExp(526, PracticeRank.s, ct), 725);
    expect(practiceRankExp(526, PracticeRank.a, ct), 604);
  });

  group('training cruiser bonus', () {
    test('no CT gives no bonus', () {
      final bonus = practiceCtBonus(_fleet([(_fubuki, 99), (_fubuki, 99)]));
      expect(bonus.modifier, 1);
      expect(bonus.submarineModifier, 1);
    });

    test('CT flagship alone', () {
      expect(practiceCtBonus(_fleet([(_katori, 65)])).modifier, 1.15);
    });

    test('CT flagship with escort uses flagship level', () {
      expect(
        practiceCtBonus(_fleet([(_katori, 65), (_kashima, 120)])).modifier,
        1.20,
      );
    });

    test('single CT escort', () {
      expect(
        practiceCtBonus(_fleet([(_fubuki, 50), (_kashima, 5)])).modifier,
        1.03,
      );
    });

    test('two CT escorts use the highest level', () {
      expect(
        practiceCtBonus(
          _fleet([(_fubuki, 50), (_kashima, 30), (_katori, 99)]),
        ).modifier,
        1.12,
      );
    });

    test('asahi flagship alone uses flagship CT row with asahi modifiers', () {
      final bonus = practiceCtBonus(_fleet([(_asahi, 50)]));
      expect(bonus.modifier, 0.672);
      expect(bonus.submarineModifier, 1.456);
    });

    test('asahi flagship with katori escort adds katori modifiers', () {
      final bonus = practiceCtBonus(_fleet([(_asahi, 50), (_katori, 10)]));
      // base 1.12 (asahi Lv50 on flagship row) × (0.6+0.45) / (1.3+0.15)
      expect(bonus.modifier, 1.176);
      expect(bonus.submarineModifier, 1.624);
    });

    test('asahi as escort without CT flagship has no effect', () {
      final bonus = practiceCtBonus(_fleet([(_fubuki, 50), (_asahi, 50)]));
      expect(bonus.modifier, 1);
      expect(bonus.submarineModifier, 1);
    });
  });
}
