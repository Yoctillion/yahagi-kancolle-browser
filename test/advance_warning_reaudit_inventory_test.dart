import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/prediction/battle_prediction_executor.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/capture/advance_warning_details.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_api_event_pipeline.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';

void main() {
  test(
    '8 partial consumptions retain only the one unconsumed control',
    () async {
      for (var scenario = 0; scenario < 8; scenario++) {
        final ships = <_InventoryShip>[
          _InventoryShip.flagship(1000),
          _InventoryShip(
            1001,
            37,
            <(int, int)>[(-1, 0), (501, scenario.isEven ? 42 : 43)],
            (502, scenario.isEven ? 43 : 42),
          )..hp = 37,
        ];
        final staleShips = _shipSnapshot(ships);
        final staleItems = _itemSnapshot(ships);
        final fixture = await _InventoryFixture.create(ships);
        try {
          await fixture.start();
          await fixture.consumeRound(ships, <int>[1], controlsPerShip: 1);
          await fixture.publish('/kcsapi/api_get_member/slot_item', staleItems);
          await fixture.publish('/kcsapi/api_get_member/ship_deck', staleShips);
          _expectInventory(
            fixture,
            ships,
            reason: 'partial late snapshot $scenario',
          );
          expect(_warnings(fixture).single.remainingDamageControls, <int, int>{
            scenario.isEven ? 43 : 42: 1,
          });
          await fixture.next(2);
          await fixture.consumeRound(ships, <int>[1], controlsPerShip: 1);
          _expectInventory(
            fixture,
            ships,
            reason: 'partial remaining control used $scenario',
          );
          expect(
            _warnings(fixture).single.damageControlStatus,
            AdvanceDamageControlStatus.missing,
          );
        } finally {
          fixture.dispose();
        }
      }
    },
  );

  test(
    '8 relocated consumed instances stay absent on every ship and slot',
    () async {
      for (var scenario = 0; scenario < 8; scenario++) {
        final masterId = scenario.isEven ? 42 : 43;
        final ships = <_InventoryShip>[
          _InventoryShip.flagship(1000),
          _InventoryShip(1001, 37, <(int, int)>[(501, masterId)], null),
          _InventoryShip(1002, 37, <(int, int)>[(601, 1)], null),
        ];
        final fixture = await _InventoryFixture.create(ships);
        try {
          await fixture.start();
          await fixture.consumeRound(ships, <int>[1], controlsPerShip: 1);
          final relocated = _shipSnapshot(ships);
          final snapshots = relocated['api_ship_data']! as List<Object?>;
          final otherShip = snapshots[2]! as Map<String, Object?>;
          otherShip['api_nowhp'] = 37;
          if (scenario % 4 < 2) {
            otherShip['api_slot'] = <int>[501, 601];
          } else {
            otherShip['api_slot_ex'] = 501;
          }
          final items = _itemSnapshot(
            ships,
          )..add(<String, Object?>{'api_id': 501, 'api_slotitem_id': masterId});
          if (scenario < 4) {
            await fixture.publish(
              '/kcsapi/api_get_member/ship_deck',
              relocated,
            );
            await fixture.publish('/kcsapi/api_get_member/slot_item', items);
          } else {
            await fixture.publish('/kcsapi/api_get_member/slot_item', items);
            await fixture.publish(
              '/kcsapi/api_get_member/ship_deck',
              relocated,
            );
          }
          final state = fixture.state.state;
          expect(state.slotItems.containsKey(501), isFalse);
          expect(state.slotItems.containsKey(601), isTrue);
          expect(state.ships[1002]!.currentHp, 7);
          for (final ship in state.ships.values) {
            expect(<int>[
              ...ship.slotIds,
              ship.extraSlotId,
            ], isNot(contains(501)));
          }
          expect(_warnings(fixture), hasLength(2));
          expect(
            _warnings(fixture).map((warning) => warning.damageControlStatus),
            everyElement(AdvanceDamageControlStatus.missing),
          );
        } finally {
          fixture.dispose();
        }
      }
    },
  );

  test('8 nonconflicting live HP recoveries remain authoritative', () async {
    for (var scenario = 0; scenario < 8; scenario++) {
      final ships = <_InventoryShip>[
        _InventoryShip.flagship(1000),
        _InventoryShip(1001, 37, <(int, int)>[(501, 42)], (502, 43)),
        _InventoryShip(1002, 81, <(int, int)>[(601, 1)], null),
      ];
      final fixture = await _InventoryFixture.create(ships);
      try {
        await fixture.start();
        await fixture.consumeRound(ships, <int>[1], controlsPerShip: 1);
        ships[1].hp = 37;
        ships[2].hp = 81;
        await fixture.publish(
          '/kcsapi/api_get_member/ship_deck',
          _shipSnapshot(ships),
        );
        expect(fixture.state.state.ships[1001]!.currentHp, 37);
        expect(fixture.state.state.ships[1002]!.currentHp, 81);
        expect(fixture.state.state.ships[1001]!.extraSlotId, 502);
        expect(
          fixture.state.state.slotItems.keys,
          unorderedEquals(<int>[502, 601]),
        );
        expect(_warnings(fixture), isEmpty);
      } finally {
        fixture.dispose();
      }
    }
  });

  test(
    '32 combined fleets keep main and escort consumption instances separate',
    () async {
      final random = Random(0x7f42c943);
      var consumedControls = 0;
      for (var scenario = 0; scenario < 32; scenario++) {
        final ships = <_InventoryShip>[
          for (var position = 0; position < 12; position++)
            position % 6 == 0
                ? _InventoryShip.flagship(1000 + position)
                : _InventoryShip.random(1000 + position, random),
        ];
        final fixture = await _InventoryFixture.create(ships, combined: true);
        try {
          await fixture.start();
          for (var node = 1; node <= 4; node++) {
            if (node > 1) await fixture.next(node);
            final order = <int>[
              for (var position = 1; position < 12; position++)
                if (position != 6) position,
            ]..shuffle(random);
            await fixture.consumeRound(ships, order, controlsPerShip: 2);
            _expectInventory(
              fixture,
              ships,
              reason: 'combined scenario $scenario node $node',
            );
          }
          final warnings = _warnings(fixture);
          expect(warnings, hasLength(10));
          expect(
            warnings.where((warning) => warning.fleetId == 1),
            hasLength(5),
          );
          expect(
            warnings.where((warning) => warning.fleetId == 2),
            hasLength(5),
          );
          expect(
            warnings.map((warning) => warning.damageControlStatus),
            everyElement(AdvanceDamageControlStatus.missing),
          );
          consumedControls += ships.fold<int>(
            0,
            (total, ship) => total + ship.consumed.length,
          );
        } finally {
          fixture.dispose();
        }
      }
      expect(consumedControls, 1282);
    },
  );

  test(
    'delayed healthy snapshot cannot hide a depleted heavily damaged ship',
    () async {
      final ships = <_InventoryShip>[
        _InventoryShip.flagship(1000),
        _InventoryShip(1001, 37, <(int, int)>[(501, 42)], (502, 43))..hp = 37,
      ];
      final delayedShipData = _shipSnapshot(ships);
      final delayedItemData = _itemSnapshot(ships);
      final fixture = await _InventoryFixture.create(ships);
      addTearDown(fixture.dispose);
      await fixture.start();
      await fixture.consumeRound(ships, <int>[1], controlsPerShip: 2);
      _expectInventory(
        fixture,
        ships,
        reason: 'healthy snapshot depletion setup',
      );
      await fixture.publish(
        '/kcsapi/api_get_member/slot_item',
        delayedItemData,
      );
      await fixture.publish(
        '/kcsapi/api_get_member/ship_deck',
        delayedShipData,
      );

      expect(
        _warnings(fixture).map((warning) => warning.ship.id),
        contains(1001),
        reason: 'pre-battle healthy HP cannot suppress a known heavy warning',
      );
      expect(_warnings(fixture).single.hasConfirmedDamageControl, isFalse);
    },
  );

  test(
    '8 delayed snapshots with fresh sequences never confirm consumed items',
    () async {
      for (var scenario = 0; scenario < 8; scenario++) {
        final ships = <_InventoryShip>[
          _InventoryShip.flagship(1000),
          _InventoryShip(
            1001,
            37,
            <(int, int)>[(501, scenario.isEven ? 42 : 43)],
            (502, scenario.isEven ? 43 : 42),
          ),
        ];
        final delayedShipData = _shipSnapshot(ships);
        final delayedItemData = _itemSnapshot(ships);
        final fixture = await _InventoryFixture.create(ships);
        try {
          await fixture.start();
          await fixture.consumeRound(ships, <int>[1], controlsPerShip: 2);
          _expectInventory(
            fixture,
            ships,
            reason: 'fresh-sequence delayed setup $scenario',
          );
          if (scenario % 4 < 2) {
            await fixture.publish(
              '/kcsapi/api_get_member/slot_item',
              delayedItemData,
            );
            await fixture.publish(
              '/kcsapi/api_get_member/ship_deck',
              delayedShipData,
            );
          } else {
            await fixture.publish(
              '/kcsapi/api_get_member/ship_deck',
              delayedShipData,
            );
            await fixture.publish(
              '/kcsapi/api_get_member/slot_item',
              delayedItemData,
            );
          }
          expect(
            _warnings(fixture).single.hasConfirmedDamageControl,
            isFalse,
            reason: 'fresh-sequence delayed pair $scenario',
          );
          _expectInventory(
            fixture,
            ships,
            reason: 'reappearing instances reconciled $scenario',
          );
          await fixture.publish('/kcsapi/api_port/port', <String, Object?>{
            'api_ship': _shipSnapshot(ships)['api_ship_data'],
            'api_slot_item': _itemSnapshot(ships),
          });
          await fixture.start();
          _expectInventory(
            fixture,
            ships,
            reason: 'fresh port resolves delayed inventory $scenario',
          );
        } finally {
          fixture.dispose();
        }
      }
    },
  );

  test(
    '8 unseen stale snapshot pairs cannot restore consumed instances',
    () async {
      for (var scenario = 0; scenario < 8; scenario++) {
        final ships = <_InventoryShip>[
          _InventoryShip.flagship(1000),
          _InventoryShip(
            1001,
            37,
            <(int, int)>[(-1, 0), (501, scenario.isEven ? 42 : 43)],
            (502, scenario.isEven ? 43 : 42),
          ),
        ];
        final fixture = await _InventoryFixture.create(ships);
        try {
          final unseenShips = _packet(
            '/kcsapi/api_get_member/ship_deck',
            _shipSnapshot(ships),
            sequence: 11,
          );
          final unseenItems = _packet(
            '/kcsapi/api_get_member/slot_item',
            _itemSnapshot(ships),
            sequence: 12,
          );
          fixture.sequence = 40;
          await fixture.start();
          await fixture.consumeRound(ships, <int>[1], controlsPerShip: 2);
          _expectInventory(
            fixture,
            ships,
            reason: 'unseen stale setup $scenario',
          );
          final late = <CapturedApiEvent>[unseenShips, unseenItems];
          if (scenario % 4 < 2) late.setAll(0, late.reversed.toList());
          for (final event in late) {
            fixture.pipeline.add(event);
          }
          await fixture.pipeline.idle;
          expect(
            _warnings(fixture).single.hasConfirmedDamageControl,
            isFalse,
            reason: 'unseen stale snapshot pair $scenario',
          );
          _expectInventory(
            fixture,
            ships,
            reason: 'unseen stale inventory $scenario',
          );
        } finally {
          fixture.dispose();
        }
      }
    },
  );

  test(
    '8 new documents accept reset sequences and fresh authoritative items',
    () async {
      for (var scenario = 0; scenario < 8; scenario++) {
        final oldShips = <_InventoryShip>[
          _InventoryShip.flagship(1000),
          _InventoryShip(1001, 81, <(int, int)>[(501, 42)], (502, 43)),
        ];
        final fixture = await _InventoryFixture.create(oldShips);
        try {
          fixture.sequence = 100;
          await fixture.start();
          await fixture.consumeRound(oldShips, <int>[1], controlsPerShip: 2);
          fixture.documentId = 'inventory-audit-document-${scenario + 2}';
          fixture.documentStartedAt = 2000;
          fixture.sequence = 0;
          await fixture.publish(
            '/kcsapi/api_start2/getData',
            <String, Object?>{},
          );
          final fresh = <_InventoryShip>[
            _InventoryShip.flagship(1000),
            _InventoryShip(
              1001,
              81,
              <(int, int)>[(601, scenario.isEven ? 42 : 43)],
              (602, scenario.isEven ? 43 : 42),
            ),
          ];
          await fixture.publish('/kcsapi/api_port/port', <String, Object?>{
            'api_ship': _shipSnapshot(fresh)['api_ship_data'],
            'api_slot_item': _itemSnapshot(fresh),
            'api_deck_port': <Object?>[
              <String, Object?>{
                'api_id': 1,
                'api_name': 'New document',
                'api_ship': <int>[1000, 1001],
              },
            ],
          });
          await fixture.start();
          _expectInventory(
            fixture,
            fresh,
            reason: 'new document fresh inventory $scenario',
          );
          await fixture.consumeRound(fresh, <int>[1], controlsPerShip: 2);
          _expectInventory(
            fixture,
            fresh,
            reason: 'new document fresh consumption $scenario',
          );
          expect(
            _warnings(fixture).single.damageControlStatus,
            AdvanceDamageControlStatus.missing,
          );
        } finally {
          fixture.dispose();
        }
      }
    },
  );

  test(
    '8 legacy sequence-zero pipelines still consume every distinct packet',
    () async {
      for (var scenario = 0; scenario < 8; scenario++) {
        final ships = <_InventoryShip>[
          _InventoryShip.flagship(1000),
          _InventoryShip(
            1001,
            101,
            <(int, int)>[
              (501, scenario.isEven ? 43 : 42),
              (502, scenario.isEven ? 42 : 43),
            ],
            (503, 43),
          ),
        ];
        final fixture = await _InventoryFixture.create(ships)
          ..legacy = true;
        try {
          await fixture.start();
          await fixture.consumeRound(ships, <int>[1], controlsPerShip: 1);
          await fixture.next(2);
          await fixture.consumeRound(ships, <int>[1], controlsPerShip: 2);
          _expectInventory(
            fixture,
            ships,
            reason: 'sequence-zero distinct packets $scenario',
          );
          expect(
            _warnings(fixture).single.damageControlStatus,
            AdvanceDamageControlStatus.missing,
          );
        } finally {
          fixture.dispose();
        }
      }
    },
  );

  test(
    'replayed pre-sortie snapshots cannot resurrect depleted controls',
    () async {
      final ships = <_InventoryShip>[
        _InventoryShip.flagship(1000),
        _InventoryShip(1001, 37, <(int, int)>[(501, 42)], (502, 43)),
      ];
      final fixture = await _InventoryFixture.create(ships);
      addTearDown(fixture.dispose);
      final oldShips = await fixture.publish(
        '/kcsapi/api_get_member/ship_deck',
        _shipSnapshot(ships),
      );
      final oldItems = await fixture.publish(
        '/kcsapi/api_get_member/slot_item',
        _itemSnapshot(ships),
      );
      await fixture.start();
      await fixture.consumeRound(ships, <int>[1], controlsPerShip: 2);
      _expectInventory(fixture, ships, reason: 'both controls consumed');
      expect(
        _warnings(fixture).single.damageControlStatus,
        AdvanceDamageControlStatus.missing,
      );

      fixture.pipeline.add(oldItems);
      fixture.pipeline.add(oldShips);
      await fixture.pipeline.idle;

      expect(
        _warnings(fixture).single.hasConfirmedDamageControl,
        isFalse,
        reason:
            'replayed snapshots must not confirm the consumed 501/502 again',
      );
      expect(fixture.state.state.ships[1001]!.slotIds, <int>[-1]);
      expect(fixture.state.state.ships[1001]!.extraSlotId, -1);
    },
  );

  test(
    '96 seeded fleets reconcile every instance and exhaust before re-damage',
    () async {
      final random = Random(0x6d5342a7);
      var battles = 0;
      var snapshotPairs = 0;
      var consumedControls = 0;
      var depletedWarnings = 0;
      for (var scenario = 0; scenario < 96; scenario++) {
        final count = scenario.isEven ? 7 : 6;
        final ships = <_InventoryShip>[
          _InventoryShip.flagship(1000),
          for (var position = 1; position < count; position++)
            _InventoryShip.random(1000 + position, random),
        ];
        final fixture = await _InventoryFixture.create(
          ships,
          fleetId: count == 7 ? 3 : 1,
        );
        try {
          await fixture.start();
          CapturedApiEvent? previousBattle;
          for (var node = 1; node <= 6; node++) {
            if (node > 1) await fixture.next(node);
            final order = <int>[
              for (var position = 1; position < count; position++) position,
            ]..shuffle(random);
            final before = ships.fold<int>(
              0,
              (total, ship) => total + ship.consumed.length,
            );
            final battle = await fixture.consumeRound(
              ships,
              order,
              controlsPerShip: node.isEven ? 2 : 1,
            );
            battles++;
            consumedControls +=
                ships.fold<int>(
                  0,
                  (total, ship) => total + ship.consumed.length,
                ) -
                before;
            _expectInventory(
              fixture,
              ships,
              reason: 'seed scenario $scenario node $node',
            );
            fixture.pipeline.add(battle);
            if (previousBattle != null) fixture.pipeline.add(previousBattle);
            await fixture.pipeline.idle;
            _expectInventory(
              fixture,
              ships,
              reason: 'battle replay $scenario/$node',
            );
            previousBattle = battle;

            final snapshotOrder = List<_InventoryShip>.from(ships)
              ..shuffle(random);
            await fixture.publish(
              '/kcsapi/api_get_member/ship_deck',
              _shipSnapshot(snapshotOrder),
            );
            await fixture.publish(
              '/kcsapi/api_get_member/slot_item',
              _itemSnapshot(snapshotOrder),
            );
            snapshotPairs++;
            _expectInventory(
              fixture,
              ships,
              reason: 'authoritative reconciliation $scenario/$node',
            );
          }
          for (final ship in ships.skip(1)) {
            expect(ship.remainingControls, isEmpty);
          }
          expect(_warnings(fixture), hasLength(count - 1));
          for (final warning in _warnings(fixture)) {
            expect(
              warning.damageControlStatus,
              AdvanceDamageControlStatus.missing,
            );
            depletedWarnings++;
          }
          await fixture.next(7);
          final openingHp = ships.map((ship) => ship.hp).toList();
          final attacks = <(int, int)>[];
          for (var position = 1; position < count; position++) {
            attacks.add((position, 1));
            ships[position].receive(1);
          }
          await fixture.publish(
            '/kcsapi/api_req_sortie/battle',
            _battleData(fixture.fleetId, ships, openingHp, attacks),
          );
          battles++;
          _expectInventory(
            fixture,
            ships,
            reason: 'depleted re-damage scenario $scenario',
          );
          for (final warning in _warnings(fixture)) {
            expect(
              warning.damageControlStatus,
              AdvanceDamageControlStatus.missing,
            );
            expect(warning.remainingDamageControls, isEmpty);
            depletedWarnings++;
          }
        } finally {
          fixture.dispose();
        }
      }
      expect(battles, 672);
      expect(snapshotPairs, 576);
      expect(depletedWarnings, 1056);
      expect(consumedControls, 2082);
    },
  );

  test(
    '32 authoritative port replacements use fresh slots after old depletion',
    () async {
      var freshConsumptions = 0;
      for (var scenario = 0; scenario < 32; scenario++) {
        final oldShips = <_InventoryShip>[
          _InventoryShip.flagship(1000),
          _InventoryShip(1001, 81, <(int, int)>[(501, 42)], (502, 43)),
          _InventoryShip(1002, 101, <(int, int)>[(601, 43)], (602, 42)),
        ];
        final fixture = await _InventoryFixture.create(oldShips);
        try {
          await fixture.start();
          await fixture.consumeRound(oldShips, <int>[2, 1], controlsPerShip: 2);
          _expectInventory(
            fixture,
            oldShips,
            reason: 'old inventory $scenario',
          );
          final freshShips = <_InventoryShip>[
            _InventoryShip.flagship(1000),
            _InventoryShip(
              1001,
              81,
              <(int, int)>[
                (-1, 0),
                (10001, scenario.isEven ? 43 : 42),
                (10002, scenario % 3 == 0 ? 42 : 43),
              ],
              (10003, scenario % 5 == 0 ? 43 : 42),
            ),
            _InventoryShip(
              1002,
              101,
              <(int, int)>[(11001, scenario.isEven ? 42 : 43), (11002, 1)],
              (11003, scenario % 3 == 0 ? 43 : 42),
            ),
          ];
          await fixture.publish('/kcsapi/api_port/port', <String, Object?>{
            'api_ship': _shipSnapshot(freshShips)['api_ship_data'],
            'api_slot_item': _itemSnapshot(freshShips),
          });
          await fixture.start();
          _expectInventory(
            fixture,
            freshShips,
            reason: 'fresh authoritative inventory $scenario',
          );
          await fixture.consumeRound(freshShips, <int>[
            1,
            2,
          ], controlsPerShip: 2);
          await fixture.next(2);
          await fixture.consumeRound(freshShips, <int>[
            2,
            1,
          ], controlsPerShip: 1);
          _expectInventory(
            fixture,
            freshShips,
            reason: 'fresh instances depleted $scenario',
          );
          freshConsumptions += freshShips.fold<int>(
            0,
            (total, ship) => total + ship.consumed.length,
          );
          expect(
            _warnings(fixture).map((warning) => warning.damageControlStatus),
            everyElement(AdvanceDamageControlStatus.missing),
          );
        } finally {
          fixture.dispose();
        }
      }
      expect(freshConsumptions, 160);
    },
  );
}

List<AdvanceWarningShip> _warnings(_InventoryFixture fixture) =>
    collectAdvanceWarningShips(
      fixture.state.state,
      damageControlStateTrusted: fixture.battle.isDamageControlStateTrusted,
    );

void _expectInventory(
  _InventoryFixture fixture,
  List<_InventoryShip> ships, {
  required String reason,
}) {
  expect(fixture.state.lastError, isNull, reason: reason);
  expect(fixture.battle.lastError, isNull, reason: reason);
  expect(fixture.battle.isDamageControlStateTrusted, isTrue, reason: reason);
  final state = fixture.state.state;
  for (final ship in ships) {
    final actual = state.ships[ship.id]!;
    expect(actual.currentHp, ship.hp, reason: '$reason ship ${ship.id}');
    expect(
      actual.slotIds,
      ship.remainingSlots,
      reason: '$reason ship ${ship.id}',
    );
    expect(
      actual.extraSlotId,
      ship.remainingExtra,
      reason: '$reason ship ${ship.id}',
    );
  }
  expect(
    state.slotItems.keys,
    unorderedEquals(<int>[
      for (final ship in ships)
        for (final item in ship.remainingItems) item.$1,
    ]),
    reason: reason,
  );
  final warnings = _warnings(fixture);
  final flagships = state.fleets.map((fleet) => fleet.shipIds.first).toSet();
  expect(
    warnings.map((warning) => warning.ship.id),
    unorderedEquals(
      ships
          .where(
            (ship) =>
                !flagships.contains(ship.id) &&
                ship.hp > 0 &&
                ship.hp * 4 <= ship.maxHp,
          )
          .map((ship) => ship.id),
    ),
    reason: reason,
  );
  for (final warning in warnings) {
    final ship = ships.firstWhere((ship) => ship.id == warning.ship.id);
    final counts = <int, int>{};
    for (final item in ship.remainingControls) {
      counts.update(item.$2, (count) => count + 1, ifAbsent: () => 1);
    }
    expect(warning.remainingDamageControls, counts, reason: reason);
    expect(
      warning.damageControlStatus,
      counts.isEmpty
          ? AdvanceDamageControlStatus.missing
          : AdvanceDamageControlStatus.equipped,
      reason: reason,
    );
  }
}

final class _InventoryShip {
  _InventoryShip(this.id, this.maxHp, this.normal, this.extra)
    : hp = maxHp ~/ 5;

  factory _InventoryShip.flagship(int id) =>
      _InventoryShip(id, 100, <(int, int)>[], null)..hp = 100;

  factory _InventoryShip.random(int id, Random random) {
    final count = 2 + random.nextInt(3);
    final normal = <(int, int)>[];
    for (var slot = 0; slot < count; slot++) {
      if (slot == 1) normal.add((-1, 0));
      normal.add((id * 10 + slot, random.nextBool() ? 42 : 43));
    }
    if (normal.length < 5) {
      normal.insert(random.nextInt(normal.length + 1), (id * 10 + 8, 1));
    }
    return _InventoryShip(
      id,
      <int>[30, 37, 81, 101][random.nextInt(4)],
      normal,
      (id * 10 + 9, random.nextBool() ? 42 : 43),
    );
  }

  final int id;
  final int maxHp;
  final List<(int, int)> normal;
  final (int, int)? extra;
  final consumed = <int>[];
  var hp = 0;

  List<(int, int)> get remainingItems => <(int, int)>[
    for (final item in <(int, int)>[...normal, ?extra])
      if (item.$1 > 0 && !consumed.contains(item.$1)) item,
  ];

  List<(int, int)> get remainingControls =>
      remainingItems.where((item) => item.$2 == 42 || item.$2 == 43).toList();

  List<int> get remainingSlots => <int>[
    for (final item in normal) consumed.contains(item.$1) ? -1 : item.$1,
  ];

  int get remainingExtra =>
      extra == null || consumed.contains(extra!.$1) ? -1 : extra!.$1;

  void receive(int damage) {
    hp = max(0, hp - damage);
    if (hp > 0 || remainingControls.isEmpty) return;
    final item = remainingControls.first;
    consumed.add(item.$1);
    hp = item.$2 == 42 ? max(1, maxHp ~/ 5) : maxHp;
  }
}

Map<String, Object?> _shipSnapshot(List<_InventoryShip> ships) =>
    <String, Object?>{
      'api_ship_data': <Object?>[
        for (final ship in ships)
          <String, Object?>{
            'api_id': ship.id,
            'api_ship_id': ship.id,
            'api_lv': 50,
            'api_nowhp': ship.hp,
            'api_maxhp': ship.maxHp,
            'api_slot': ship.remainingSlots,
            'api_slot_ex': ship.remainingExtra,
          },
      ],
    };

List<Object?> _itemSnapshot(List<_InventoryShip> ships) => <Object?>[
  for (final ship in ships)
    for (final item in ship.remainingItems)
      <String, Object?>{'api_id': item.$1, 'api_slotitem_id': item.$2},
];

Map<String, Object?> _battleData(
  int fleetId,
  List<_InventoryShip> ships,
  List<int> openingHp,
  List<(int, int)> attacks, {
  bool combined = false,
}) => <String, Object?>{
  'api_deck_id': fleetId,
  'api_f_nowhps': <int>[-1, ...combined ? openingHp.take(6) : openingHp],
  'api_f_maxhps': <int>[
    -1,
    ...(combined ? ships.take(6) : ships).map((ship) => ship.maxHp),
  ],
  if (combined) 'api_f_nowhps_combined': <int>[-1, ...openingHp.skip(6)],
  if (combined)
    'api_f_maxhps_combined': <int>[
      -1,
      ...ships.skip(6).map((ship) => ship.maxHp),
    ],
  'api_e_nowhps': <int>[-1, 20],
  'api_e_maxhps': <int>[-1, 20],
  'api_ship_ke': <int>[-1, 501],
  'api_hougeki1': <String, Object?>{
    'api_at_eflag': List<int>.filled(attacks.length, 1),
    'api_at_list': List<int>.filled(attacks.length, 0),
    'api_df_list': <Object?>[
      for (final attack in attacks) <int>[attack.$1],
    ],
    'api_damage': <Object?>[
      for (final attack in attacks) <int>[attack.$2],
    ],
  },
};

final class _InventoryFixture {
  _InventoryFixture(
    this.state,
    this.battle,
    this.pipeline,
    this.fleetId,
    this.combined,
  );

  final GameStateController state;
  final BattleController battle;
  final GameApiEventPipeline pipeline;
  final int fleetId;
  final bool combined;
  var sequence = 0;
  var legacy = false;
  var documentId = 'inventory-audit-document';
  var documentStartedAt = 1000.0;

  static Future<_InventoryFixture> create(
    List<_InventoryShip> ships, {
    int fleetId = 1,
    bool combined = false,
  }) async {
    final state = GameStateController(
      initialState: GameState(
        hasPortData: true,
        hasEquipmentInventory: true,
        combinedFleetType: combined
            ? CombinedFleetType.carrierTaskForce
            : CombinedFleetType.none,
        ships: <int, OwnedShip>{
          for (final ship in ships)
            ship.id: OwnedShip(
              id: ship.id,
              masterId: ship.id,
              level: 50,
              currentHp: ship.hp,
              maxHp: ship.maxHp,
              slotIds: ship.remainingSlots,
              extraSlotId: ship.remainingExtra,
            ),
        },
        slotItems: <int, OwnedSlotItem>{
          for (final ship in ships)
            for (final item in ship.remainingItems)
              item.$1: OwnedSlotItem(
                instanceId: item.$1,
                masterSlotItemId: item.$2,
              ),
        },
        fleets: <Fleet>[
          Fleet(
            id: fleetId,
            name: 'Inventory audit',
            shipIds: (combined ? ships.take(6) : ships)
                .map((ship) => ship.id)
                .toList(),
            slotCount: combined ? 6 : ships.length,
          ),
          if (combined)
            Fleet(
              id: 2,
              name: 'Inventory escort',
              shipIds: ships.skip(6).map((ship) => ship.id).toList(),
            ),
        ],
      ),
    );
    await state.initialize();
    final battle = BattleController(
      gameState: () => state.state,
      waitForGameState: () => state.idle,
      onFriendlyHpUpdated: state.applyFriendlyBattleHp,
      onDamageControlConsumed: state.applyDamageControlConsumption,
      predictionExecutor: const ImmediateBattlePredictionExecutor(),
    );
    final pipeline = GameApiEventPipeline(
      consumers: <GameApiEventConsumer>[state, battle],
      settleGameState: () async {
        await state.idle;
        await battle.idle;
        await state.idle;
      },
    );
    return _InventoryFixture(state, battle, pipeline, fleetId, combined);
  }

  Future<void> start() async {
    await publish(
      '/kcsapi/api_req_map/start',
      _node(1),
      requestParams: {'api_deck_id': '$fleetId'},
    );
  }

  Future<void> next(int node) async {
    await publish('/kcsapi/api_req_map/next', _node(node));
  }

  Future<CapturedApiEvent> consumeRound(
    List<_InventoryShip> ships,
    List<int> order, {
    required int controlsPerShip,
  }) async {
    final openingHp = ships.map((ship) => ship.hp).toList();
    final attacks = <(int, int)>[];
    for (final position in order) {
      final ship = ships[position];
      for (
        var use = 0;
        use < controlsPerShip && ship.remainingControls.isNotEmpty;
        use++
      ) {
        final damage = ship.hp;
        attacks.add((position, damage));
        ship.receive(damage);
        final followupDamage = ship.hp - ship.maxHp ~/ 5;
        if (followupDamage > 0) {
          attacks.add((position, followupDamage));
          ship.receive(followupDamage);
        }
      }
    }
    return publish(
      combined
          ? '/kcsapi/api_req_combined_battle/battle'
          : '/kcsapi/api_req_sortie/battle',
      _battleData(fleetId, ships, openingHp, attacks, combined: combined),
    );
  }

  Future<CapturedApiEvent> publish(
    String path,
    Object? data, {
    Map<String, Object?> requestParams = const <String, Object?>{},
  }) async {
    final event = _packet(
      path,
      data,
      requestParams: requestParams,
      sequence: legacy ? 0 : ++sequence,
      documentId: legacy ? null : documentId,
      documentStartedAt: legacy ? null : documentStartedAt,
    );
    pipeline.add(event);
    await pipeline.idle;
    return event;
  }

  void dispose() {
    battle.dispose();
    state.dispose();
  }
}

CapturedApiEvent _packet(
  String path,
  Object? data, {
  required int sequence,
  Map<String, Object?> requestParams = const <String, Object?>{},
  String? documentId = 'inventory-audit-document',
  double? documentStartedAt = 1000,
}) => CapturedApiEvent(
  path: path,
  responseBody: jsonEncode({'api_result': 1, 'api_data': data}),
  requestParams: requestParams,
  source: sequence == 0 ? CaptureSource.manual : CaptureSource.xhr,
  sourceOrigin: 'https://w01y.kancolle-server.com',
  capturedAt: DateTime.utc(2026, 10, 23).add(Duration(seconds: sequence)),
  sequence: sequence,
  captureSessionId: 'inventory-audit-session',
  captureDocumentId: documentId,
  captureDocumentStartedAtEpochMs: documentStartedAt,
);

Map<String, Object?> _node(int node) => <String, Object?>{
  'api_maparea_id': 1,
  'api_mapinfo_no': 1,
  'api_no': node,
};
