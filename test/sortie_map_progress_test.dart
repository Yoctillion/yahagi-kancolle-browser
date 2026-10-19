import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/battle/sortie_map_progress.dart';

void main() {
  test(
    'progress exposes the map, current route, boss and capture completeness',
    () {
      final progress = SortieMapProgress(
        mapAreaId: 5,
        mapInfoNo: 6,
        routeIds: [0, 42, 43, 42],
        bossRouteId: 45,
        isPartial: true,
      );

      expect(progress.mapKey, '5-6');
      expect(progress.currentRouteId, 42);
      expect(progress.bossRouteId, 45);
      expect(progress.isPartial, isTrue);
      expect(progress.routeIds, [0, 42, 43, 42]);
    },
  );

  test('route history is an immutable snapshot of the supplied list', () {
    final routes = [0, 42];
    final progress = SortieMapProgress(
      mapAreaId: 5,
      mapInfoNo: 6,
      routeIds: routes,
    );
    routes.add(43);

    expect(progress.routeIds, [0, 42]);
    expect(() => progress.routeIds.add(44), throwsUnsupportedError);
    expect(progress.isPartial, isFalse);
  });

  test('an empty observed history has no current route', () {
    final progress = SortieMapProgress(
      mapAreaId: 1,
      mapInfoNo: 1,
      routeIds: [],
    );

    expect(progress.currentRouteId, isNull);
    expect(progress.bossRouteId, isNull);
  });
}
