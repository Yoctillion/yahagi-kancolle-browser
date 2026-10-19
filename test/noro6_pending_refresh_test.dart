// Synthetic API events verify export readiness without captured account data.
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_reducer.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_serializer.dart';
import 'fixtures/kcsapi_fixtures.dart';
import 'noro6_export_audit_test.dart' as fixture;

void main() {
  final reducer = GameStateReducer();
  GameState equip(GameState state, int id, int item) => reducer.reduce(
    state,
    kcsapiEvent(
      '/kcsapi/api_req_kaisou/slotset',
      null,
      includeApiData: false,
      requestParams: {
        'api_id': '$id',
        'api_slot_idx': '0',
        'api_item_id': '$item',
      },
    ),
  );
  GameState refresh(GameState state, List<Map<String, Object?>> values) =>
      reducer.reduce(
        state,
        kcsapiEvent('/kcsapi/api_get_member/ship3', {'api_ship_data': values}),
      );
  Map<String, Object?> full(int id, int asw) => {
    'api_id': id,
    'api_ship_id': 187,
    'api_slot': [-1, -1, -1],
    'api_taisen': [asw, 90],
  };

  test('each pending ship must refresh independently; zero ASW is valid', () {
    var state = equip(equip(fixture.auditState(), 7, -1), 8, 503);
    expect(state.pendingExportShipIds, {7, 8});
    state = refresh(state, [full(7, 50)]);
    expect(state.pendingExportShipIds, {8});
    expect(state.canExportFleet, isFalse);
    state = refresh(state, [
      {
        'api_id': 8,
        'api_ship_id': 187,
        'api_taisen': [1, 90],
      },
    ]);
    expect(state.pendingExportShipIds, {8});
    state = refresh(state, [full(8, 0)]);
    expect(state.canExportFleet, isTrue);
    expect(state.ships[8]!.antiSub, 0);
  });

  test('consuming one pending ship preserves the other pending ship', () {
    var state = equip(equip(fixture.auditState(), 7, -1), 8, 503);
    state = reducer.reduce(
      state,
      kcsapiEvent(
        '/kcsapi/api_req_kaisou/powerup',
        {},
        requestParams: {'api_id_items': '8', 'api_slot_dest_flag': '0'},
      ),
    );
    expect(state.pendingExportShipIds, {7});
    expect(state.canExportFleet, isFalse);
    expect(state.ships.containsKey(8), isFalse);
    state = refresh(state, [full(7, 60)]);
    expect(state.canExportFleet, isTrue);
  });

  test(
    'port without ships cannot release pending and reload remains unready',
    () {
      final dirty = equip(fixture.auditState(), 7, -1);
      final incomplete = reducer.reduce(
        dirty,
        kcsapiEvent('/kcsapi/api_port/port', {}),
      );
      expect(incomplete.pendingExportShipIds, {7});
      expect(incomplete.canExportFleet, isFalse);
      final cached = GameStateSerializer.deserialize(
        GameStateSerializer.serialize(dirty),
      );
      expect(cached.canExportFleet, isFalse);
      expect(cached.pendingExportShipIds, isEmpty);
    },
  );
}
