/// Captured internal route IDs for one sortie, in the order they were visited.
///
/// Route IDs identify FCD edges, rather than the letters drawn on map nodes.
final class SortieMapProgress {
  SortieMapProgress({
    required this.mapAreaId,
    required this.mapInfoNo,
    required List<int> routeIds,
    this.bossRouteId,
    this.isPartial = false,
  }) : routeIds = List<int>.unmodifiable(routeIds);

  final int mapAreaId;
  final int mapInfoNo;
  final List<int> routeIds;
  final int? bossRouteId;

  /// True when capture began after the sortie had already started.
  final bool isPartial;

  int? get currentRouteId => routeIds.lastOrNull;
  String get mapKey => '$mapAreaId-$mapInfoNo';
}
