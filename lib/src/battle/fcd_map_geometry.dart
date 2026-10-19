abstract interface class BattleMapGeometryResolver {
  FcdMapGeometry? geometryFor({required int mapAreaId, required int mapInfoNo});
}

final class FcdMapGeometry {
  FcdMapGeometry({
    required Map<int, FcdMapRoute> routes,
    required Map<String, FcdMapSpot> spots,
  }) : routes = Map<int, FcdMapRoute>.unmodifiable(routes),
       spots = Map<String, FcdMapSpot>.unmodifiable(spots);

  final Map<int, FcdMapRoute> routes;
  final Map<String, FcdMapSpot> spots;
}

final class FcdMapRoute {
  const FcdMapRoute({required this.from, required this.to});

  final String? from;
  final String to;
}

final class FcdMapSpot {
  const FcdMapSpot({required this.x, required this.y, this.type = ''});

  final double x;
  final double y;
  final String type;
}
