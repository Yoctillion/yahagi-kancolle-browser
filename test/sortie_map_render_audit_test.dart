import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/battle/fcd_map_dataset.dart';
import 'package:yahagi_kancolle_browser/src/battle/fcd_map_geometry.dart';
import 'package:yahagi_kancolle_browser/src/battle/sortie_map_progress.dart';
import 'package:yahagi_kancolle_browser/src/battle/sortie_map_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FcdMapDataset dataset;
  late List<String> mapKeys;

  setUpAll(() async {
    final raw = await rootBundle.loadString('assets/data/fcd/map.json');
    dataset = FcdMapDataset.parse(raw);
    mapKeys = ((jsonDecode(raw) as Map<String, dynamic>)['data'] as Map).keys
        .cast<String>()
        .toList();
    await (FontLoader(
      'SortieMapAuditFont',
    )..addFont(rootBundle.load('assets/fonts/HarmonyOS_Sans.ttf'))).load();
  });

  for (final fontFamily in [null, 'SortieMapAuditFont']) {
    for (final width in [240.0, 280.0, 360.0, 640.0]) {
      testWidgets(
        'all bundled maps render within $width using ${fontFamily ?? 'Ahem'}',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 640));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final semantics = tester.ensureSemantics();
          final labelConflicts = <String>[];
          final currentOcclusions = <String>[];
          var renderedMaps = 0;
          var renderedRoutes = 0;
          var renderedSpots = 0;
          try {
            for (final mapKey in mapKeys) {
              final ids = mapKey.split('-').map(int.parse).toList();
              final geometry = dataset.geometryFor(
                mapAreaId: ids[0],
                mapInfoNo: ids[1],
              );
              expect(geometry, isNotNull, reason: mapKey);
              final map = geometry!;
              expect(map.spots, isNotEmpty, reason: mapKey);
              final candidates = _representativeRoutes(map);
              final currentId =
                  candidates[[240, 280, 360, 640].indexOf(width.toInt()) %
                      candidates.length];
              // All captured edges exercise every start, branch, loop and endpoint;
              // the current edge changes with viewport to cover distinct node types.
              final captured = [
                ...map.routes.keys.where((id) => id != currentId),
                currentId,
              ];
              final bossId = map.routes.keys.last;
              final progress = SortieMapProgress(
                mapAreaId: ids[0],
                mapInfoNo: ids[1],
                routeIds: captured,
                bossRouteId: bossId,
              );
              await tester.pumpWidget(
                _app(progress: progress, geometry: map, fontFamily: fontFamily),
              );
              expect(
                tester.takeException(),
                isNull,
                reason: '$mapKey / $width',
              );
              final canvas = find.byKey(const Key('sortie-map-canvas'));
              expect(canvas, findsOneWidget, reason: mapKey);
              final visibleBounds = tester.getRect(canvas);
              expect(
                visibleBounds.width,
                lessThanOrEqualTo(math.min(326, width - 34)),
              );
              _expectContained(
                Rect.fromLTWH(0, 0, width, 640),
                visibleBounds,
                mapKey,
              );
              _expectUniformScale(tester, canvas, mapKey);
              final bounds = _logicalBounds(tester, canvas);
              final positions = _nodePositions(tester, canvas, map);
              expect(
                positions.keys,
                unorderedEquals(map.spots.keys),
                reason: mapKey,
              );
              for (final entry in positions.entries) {
                _expectContained(
                  bounds,
                  Rect.fromCircle(center: entry.value, radius: 9),
                  '$mapKey / ${entry.key} marker',
                );
              }

              final current = map.routes[currentId]!.to;
              final boss = map.routes[bossId]!.to;
              final painted = _recordPaint(tester, canvas);
              _expectPaintWithinBounds(painted, bounds.size, mapKey);
              final paragraphs = painted
                  .where((call) => call.invocation.memberName == #drawParagraph)
                  .map(_paintedBounds)
                  .whereType<Rect>()
                  .toList();
              final labels = [
                ...map.spots.keys.where((label) => label != current),
                current,
              ];
              expect(paragraphs, hasLength(labels.length), reason: mapKey);
              final routePaths = _routePaths(tester, canvas);
              _expectOnlyRoutes(
                painted,
                map,
                positions,
                bounds.topLeft,
                captured,
                routePaths,
              );
              _expectRoutesClearMarkers(
                map,
                positions,
                bounds.topLeft,
                routePaths,
              );
              for (var a = 0; a < paragraphs.length; a++) {
                final point = positions[labels[a]]! - bounds.topLeft;
                expect(
                  _distanceToRect(point, paragraphs[a]),
                  lessThanOrEqualTo(labels[a] == current ? 13.01 : 10.01),
                  reason:
                      '$mapKey / ${labels[a]} must stay beside its own marker',
                );
                for (var b = a + 1; b < paragraphs.length; b++) {
                  if (paragraphs[a].overlaps(paragraphs[b])) {
                    labelConflicts.add('$mapKey/${labels[a]}/${labels[b]}');
                  }
                }
              }
              final ringCalls = painted.where((call) {
                if (call.invocation.memberName != #drawCircle) return false;
                final args = call.invocation.positionalArguments;
                final paint = args[2] as Paint;
                return paint.style == PaintingStyle.stroke &&
                    paint.color.toARGB32() == 0xffffcf67;
              }).toList();
              expect(ringCalls, hasLength(1), reason: '$mapKey current halo');
              final paintedCurrent =
                  ringCalls.single.invocation.positionalArguments[0] as Offset;
              // Inspect actual paint-call order, including the current node's own
              // label, rather than assuming the source node enumeration order.
              final currentRingIndex = painted.indexOf(ringCalls.single);
              for (
                var index = currentRingIndex + 1;
                index < painted.length;
                index++
              ) {
                final call = painted[index];
                if (call.invocation.memberName == #drawParagraph &&
                    _paintedBounds(call)!.contains(paintedCurrent)) {
                  currentOcclusions.add('$mapKey/$current/paint-call-$index');
                }
              }
              expect(
                (paintedCurrent - (positions[current]! - bounds.topLeft))
                    .distance,
                lessThan(.01),
                reason: '$mapKey current route $currentId must mark $current',
              );
              expect(
                find.bySemanticsLabel(
                  _nodeDescription(map, current, current: current, boss: boss),
                ),
                findsOneWidget,
                reason: '$mapKey current route $currentId',
              );
              expect(
                find.bySemanticsLabel(
                  _nodeDescription(map, boss, current: current, boss: boss),
                ),
                findsOneWidget,
                reason: '$mapKey boss route $bossId',
              );
              final semanticRoutes = tester
                  .widgetList<Semantics>(
                    find.descendant(
                      of: canvas,
                      matching: find.byType(Semantics),
                    ),
                  )
                  .map((widget) => widget.properties.label)
                  .whereType<String>()
                  .where((label) => label.startsWith('航段 '))
                  .toSet();
              for (final route in map.routes.entries) {
                if (route.value.from == null) continue;
                expect(
                  semanticRoutes,
                  contains(
                    '航段 ${route.key} · ${route.value.from} → '
                    '${route.value.to} · 已走',
                  ),
                  reason: '$mapKey route ${route.key}',
                );
              }
              expect(find.byType(InteractiveViewer), findsNothing);
              expect(find.byKey(const Key('sortie-map-enlarge')), findsNothing);
              renderedMaps++;
              renderedRoutes += map.routes.length;
              renderedSpots += map.spots.length;
            }
          } finally {
            semantics.dispose();
          }
          expect(renderedMaps, dataset.mapCount);
          expect(renderedRoutes, dataset.routeCount);
          expect(renderedSpots, greaterThan(3000));
          expect(currentOcclusions, isEmpty);
          if (fontFamily != null) expect(labelConflicts, isEmpty);
          final audit = {
            'viewport': width,
            'maps': renderedMaps,
            'routes': renderedRoutes,
            'spots': renderedSpots,
            'labelConflictMaps': labelConflicts
                .map((value) => value.split('/').first)
                .toSet()
                .length,
            'labelConflictPairs': labelConflicts.length,
            'labelConflictExamples': labelConflicts.take(20).toList(),
            'laterPaintedLabelsContainingCurrentMarkerCenter':
                currentOcclusions,
            'font':
                fontFamily ?? 'Flutter test default Ahem; conservative bounds',
          };
          debugPrint('SORTIE_MAP_RENDER_AUDIT ${jsonEncode(audit)}');
        },
      );
    }
  }

  testWidgets('map 49-4 draws current S above nearby X1 and other labels', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(240, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final map = dataset.geometryFor(mapAreaId: 49, mapInfoNo: 4)!;
    final route = map.routes.entries.firstWhere(
      (entry) => entry.value.to == 'S',
    );
    await tester.pumpWidget(
      _app(
        progress: SortieMapProgress(
          mapAreaId: 49,
          mapInfoNo: 4,
          routeIds: [route.key],
        ),
        geometry: map,
      ),
    );
    final positions = _nodePositions(
      tester,
      find.byKey(const Key('sortie-map-canvas')),
      map,
    );
    final canvas = find.byKey(const Key('sortie-map-canvas'));
    final paintCalls = _recordPaint(tester, canvas);
    final lastMarker = paintCalls.lastWhere(
      (call) => {
        #drawCircle,
        #drawRRect,
        #drawPath,
      }.contains(call.invocation.memberName),
    );
    expect(
      (_paintedBounds(lastMarker)!.center -
              (positions['S']! - tester.getRect(canvas).topLeft))
          .distance,
      lessThan(.01),
      reason:
          'Draw the current marker last so dense-map labels cannot cover it',
    );
  });

  testWidgets('supported long endpoint labels stay inside the canvas', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(240, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final geometry = FcdMapGeometry(
      routes: const {
        0: FcdMapRoute(from: null, to: 'LEFT_LONG_LABEL'),
        1: FcdMapRoute(from: 'LEFT_LONG_LABEL', to: 'RIGHT_LONG_LABEL'),
      },
      spots: const {
        'LEFT_LONG_LABEL': FcdMapSpot(x: 0, y: 0, type: 'start'),
        'RIGHT_LONG_LABEL': FcdMapSpot(x: 100, y: 0),
      },
    );
    await tester.pumpWidget(
      _app(
        progress: SortieMapProgress(
          mapAreaId: 99,
          mapInfoNo: 1,
          routeIds: const [0, 1],
        ),
        geometry: geometry,
      ),
    );
    expect(tester.takeException(), isNull);
    final canvas = find.byKey(const Key('sortie-map-canvas'));
    _expectPaintWithinBounds(
      _recordPaint(tester, canvas),
      _logicalBounds(tester, canvas).size,
      'long labels',
    );
  });

  testWidgets('2-5 labels avoid other labels and markers in a narrow canvas', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(240, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final geometry = dataset.geometryFor(mapAreaId: 2, mapInfoNo: 5)!;
    await tester.pumpWidget(
      _app(
        progress: SortieMapProgress(
          mapAreaId: 2,
          mapInfoNo: 5,
          routeIds: const [15],
        ),
        geometry: geometry,
      ),
    );
    final canvas = find.byKey(const Key('sortie-map-canvas'));
    final bounds = _logicalBounds(tester, canvas);
    final labels = _recordPaint(tester, canvas)
        .where((call) => call.invocation.memberName == #drawParagraph)
        .map(_paintedBounds)
        .whereType<Rect>()
        .toList();
    final positions = _nodePositions(tester, canvas, geometry);
    for (var a = 0; a < labels.length; a++) {
      for (var b = a + 1; b < labels.length; b++) {
        expect(labels[a].overlaps(labels[b]), isFalse);
      }
      for (final point in positions.values) {
        expect(labels[a].contains(point - bounds.topLeft), isFalse);
      }
    }
  });

  for (final mapKey in ['44-2', '48-3', '48-7']) {
    testWidgets('$mapKey routes avoid unrelated markers on a narrow canvas', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(240, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final ids = mapKey.split('-').map(int.parse).toList();
      final geometry = dataset.geometryFor(
        mapAreaId: ids[0],
        mapInfoNo: ids[1],
      )!;
      await tester.pumpWidget(
        _app(
          progress: SortieMapProgress(
            mapAreaId: ids[0],
            mapInfoNo: ids[1],
            routeIds: const [],
          ),
          geometry: geometry,
        ),
      );
      final canvas = find.byKey(const Key('sortie-map-canvas'));
      final origin = tester.getRect(canvas).topLeft;
      final positions = _nodePositions(tester, canvas, geometry);
      final paths = _routePaths(tester, canvas);
      _expectOnlyRoutes(
        _recordPaint(tester, canvas),
        geometry,
        positions,
        origin,
        const [],
        paths,
      );
      _expectRoutesClearMarkers(geometry, positions, origin, paths);
    });
  }

  for (final width in [240.0, 280.0, 360.0, 640.0]) {
    testWidgets('1-6 I label stays clear of the D-J route at width $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final geometry = dataset.geometryFor(mapAreaId: 1, mapInfoNo: 6)!;
      await tester.pumpWidget(
        _app(
          progress: SortieMapProgress(
            mapAreaId: 1,
            mapInfoNo: 6,
            routeIds: const [0, 1, 3],
          ),
          geometry: geometry,
        ),
      );
      final canvas = find.byKey(const Key('sortie-map-canvas'));
      final origin = tester.getRect(canvas).topLeft;
      final positions = _nodePositions(tester, canvas, geometry);
      final labels = [
        ...geometry.spots.keys.where((label) => label != 'E'),
        'E',
      ];
      final paragraphs = _recordPaint(tester, canvas)
          .where((call) => call.invocation.memberName == #drawParagraph)
          .map(_paintedBounds)
          .whereType<Rect>()
          .toList();
      final label = paragraphs[labels.indexOf('I')];
      expect(
        _segmentCrossesRect(
          positions['D']! - origin,
          positions['J']! - origin,
          label.inflate(2),
        ),
        isFalse,
        reason: 'The D-J route must not look like an I-J connection',
      );
      expect(
        geometry.routes.values.any(
          (route) =>
              (route.from == 'I' && route.to == 'J') ||
              (route.from == 'J' && route.to == 'I'),
        ),
        isFalse,
      );
    });
  }

  testWidgets('labels stay beside their nodes without auxiliary lines', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(240, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final geometry = dataset.geometryFor(mapAreaId: 2, mapInfoNo: 5)!;
    await tester.pumpWidget(
      _app(
        progress: SortieMapProgress(
          mapAreaId: 2,
          mapInfoNo: 5,
          routeIds: const [15],
        ),
        geometry: geometry,
      ),
    );
    final canvas = find.byKey(const Key('sortie-map-canvas'));
    final bounds = _logicalBounds(tester, canvas);
    final positions = _nodePositions(tester, canvas, geometry);
    final paint = _recordPaint(tester, canvas);
    _expectOnlyRoutes(paint, geometry, positions, bounds.topLeft, const [
      15,
    ], _routePaths(tester, canvas));
    final current = geometry.routes[15]!.to;
    final labels = [
      ...geometry.spots.keys.where((label) => label != current),
      current,
    ];
    final paragraphs = paint
        .where((call) => call.invocation.memberName == #drawParagraph)
        .map(_paintedBounds)
        .whereType<Rect>()
        .toList();
    for (var i = 0; i < labels.length; i++) {
      expect(
        _distanceToRect(positions[labels[i]]! - bounds.topLeft, paragraphs[i]),
        lessThanOrEqualTo(labels[i] == current ? 13.01 : 10.01),
        reason: labels[i],
      );
    }
  });

  for (final spots in <String, Map<String, FcdMapSpot>>{
    'one point': const {'A': FcdMapSpot(x: 0, y: 0)},
    'coincident points': const {
      'A': FcdMapSpot(x: 10, y: 10),
      'B': FcdMapSpot(x: 10, y: 10),
    },
  }.entries) {
    testWidgets('${spots.key} do not create nonfinite render positions', (
      tester,
    ) async {
      final labels = spots.value.keys.toList();
      final geometry = FcdMapGeometry(
        routes: {0: FcdMapRoute(from: labels.first, to: labels.last)},
        spots: spots.value,
      );
      await tester.pumpWidget(
        _app(
          progress: SortieMapProgress(
            mapAreaId: 99,
            mapInfoNo: 1,
            routeIds: const [0],
          ),
          geometry: geometry,
        ),
      );
      expect(tester.takeException(), isNull);
      final canvas = find.byKey(const Key('sortie-map-canvas'));
      _expectPaintWithinBounds(
        _recordPaint(tester, canvas),
        _logicalBounds(tester, canvas).size,
        spots.key,
      );
    });
  }
  testWidgets('overflowing finite coordinate span uses the update fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        progress: SortieMapProgress(
          mapAreaId: 99,
          mapInfoNo: 1,
          routeIds: const [0],
        ),
        geometry: FcdMapGeometry(
          routes: const {0: FcdMapRoute(from: 'A', to: 'B')},
          spots: const {
            'A': FcdMapSpot(x: -1e308, y: -1e308),
            'B': FcdMapSpot(x: 1e308, y: 1e308),
          },
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('sortie-map-canvas')), findsNothing);
    expect(find.textContaining('该地图未更新'), findsWidgets);
  });

  testWidgets('repainting follows immutable geometry and progress changes', (
    tester,
  ) async {
    final geometry = dataset.geometryFor(mapAreaId: 2, mapInfoNo: 5)!;
    final progress = SortieMapProgress(
      mapAreaId: 2,
      mapInfoNo: 5,
      routeIds: const [0, 1],
    );
    CustomPainter painter() => tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byKey(const Key('sortie-map-canvas')),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    await tester.pumpWidget(_app(progress: progress, geometry: geometry));
    final original = painter();
    await tester.pumpWidget(_app(progress: progress, geometry: geometry));
    expect(painter().shouldRepaint(original), isFalse);
    await tester.pumpWidget(
      _app(
        progress: SortieMapProgress(
          mapAreaId: 2,
          mapInfoNo: 5,
          routeIds: const [0, 1, 15],
        ),
        geometry: geometry,
      ),
    );
    expect(painter().shouldRepaint(original), isTrue);
    await tester.pumpWidget(
      _app(
        progress: progress,
        geometry: FcdMapGeometry(
          routes: geometry.routes,
          spots: geometry.spots,
        ),
      ),
    );
    expect(painter().shouldRepaint(original), isTrue);
  });

  testWidgets('changing the app font refreshes measured label placement', (
    tester,
  ) async {
    final geometry = dataset.geometryFor(mapAreaId: 1, mapInfoNo: 6)!;
    final progress = SortieMapProgress(
      mapAreaId: 1,
      mapInfoNo: 6,
      routeIds: const [0, 1, 3],
    );
    CustomPainter painter() => tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byKey(const Key('sortie-map-canvas')),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter!;
    await tester.pumpWidget(
      _app(progress: progress, geometry: geometry, fontFamily: 'FirstMapFont'),
    );
    final original = painter();
    await tester.pumpWidget(
      _app(progress: progress, geometry: geometry, fontFamily: 'SecondMapFont'),
    );
    await tester.pumpAndSettle();
    expect(painter().shouldRepaint(original), isTrue);
  });

  testWidgets('62-5 L1 stays with its own marker while nearby K is current', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(240, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final map = dataset.geometryFor(mapAreaId: 62, mapInfoNo: 5)!;
    final route = map.routes.entries.firstWhere(
      (entry) => entry.value.to == 'K',
    );
    await tester.pumpWidget(
      _app(
        progress: SortieMapProgress(
          mapAreaId: 62,
          mapInfoNo: 5,
          routeIds: [route.key],
        ),
        geometry: map,
        fontFamily: 'SortieMapAuditFont',
      ),
    );
    final canvas = find.byKey(const Key('sortie-map-canvas'));
    final origin = tester.getRect(canvas).topLeft;
    final points = _nodePositions(tester, canvas, map);
    final names = [...map.spots.keys.where((name) => name != 'K'), 'K'];
    final labels = _recordPaint(tester, canvas)
        .where((call) => call.invocation.memberName == #drawParagraph)
        .map(_paintedBounds)
        .whereType<Rect>()
        .toList();
    final label = labels[names.indexOf('L1')];
    final own = _distanceToRect(points['L1']! - origin, label);
    for (final other in points.entries.where((entry) => entry.key != 'L1')) {
      expect(
        _distanceToRect(other.value - origin, label),
        greaterThanOrEqualTo(own - .25),
        reason: 'L1 must not appear to name ${other.key}',
      );
    }
  });
}

Widget _app({
  required SortieMapProgress progress,
  required FcdMapGeometry geometry,
  String? fontFamily,
}) => MaterialApp(
  theme: ThemeData(fontFamily: fontFamily),
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SortieMapSection(
          progress: progress,
          geometry: geometry,
          expanded: true,
          onToggleExpanded: () {},
        ),
      ),
    ),
  ),
);

List<int> _representativeRoutes(FcdMapGeometry map) => [
  map.routes.keys.first,
  (map.routes.entries.where((entry) => entry.value.to.length > 1).firstOrNull ??
          map.routes.entries.elementAt(map.routes.length ~/ 2))
      .key,
  map.routes.keys.last,
  map.routes.entries
      .where((entry) => map.spots[entry.value.to]!.type != 'start')
      .first
      .key,
];

String _nodeDescription(
  FcdMapGeometry map,
  String label, {
  required String current,
  required String boss,
}) => [
  label,
  if (map.spots[label]!.type == 'start') '起点',
  if (label == boss) 'Boss',
  if (label == current) '当前',
  if (map.routes.values.any(
    (route) => route.from == label || route.to == label,
  ))
    '已走',
].join(' · ');

Map<String, Offset> _nodePositions(
  WidgetTester tester,
  Finder canvas,
  FcdMapGeometry map,
) {
  final paintBox = tester.renderObject<RenderBox>(_mapPaint(canvas));
  final origin = tester.getRect(canvas).topLeft;
  // Keep the existing audit origin while undoing the FittedBox transform.
  // Paint calls and route paths are measured in the fixed logical canvas.
  return {
    for (final element
        in find
            .descendant(of: canvas, matching: find.byType(Semantics))
            .evaluate())
      if ((element.widget as Semantics).properties.label
          case final String label)
        if (map.spots.containsKey(label.split(' · ').first))
          label.split(' · ').first:
              paintBox.globalToLocal(
                tester.getRect(find.byWidget(element.widget)).center,
              ) +
              origin,
  };
}

Finder _mapPaint(Finder canvas) =>
    find.descendant(of: canvas, matching: find.byType(CustomPaint));

Rect _logicalBounds(WidgetTester tester, Finder canvas) =>
    tester.getRect(canvas).topLeft & tester.getSize(_mapPaint(canvas));

void _expectUniformScale(WidgetTester tester, Finder canvas, String reason) {
  final visible = tester.getRect(canvas);
  final paintBox = tester.renderObject<RenderBox>(_mapPaint(canvas));
  expect(paintBox.size, const Size(326, 240), reason: reason);
  expect(
    visible.height,
    closeTo(visible.width * 240 / 326, .01),
    reason: '$reason fixed visible aspect ratio',
  );
  for (final corner in [
    (Offset.zero, visible.topLeft),
    (const Offset(326, 0), visible.topRight),
    (const Offset(0, 240), visible.bottomLeft),
    (const Offset(326, 240), visible.bottomRight),
  ]) {
    expect(
      (paintBox.localToGlobal(corner.$1) - corner.$2).distance,
      lessThan(.01),
      reason: '$reason paint and semantics share the uniform transform',
    );
  }
}

List<RecordedInvocation> _recordPaint(WidgetTester tester, Finder canvas) {
  final painter = tester.widget<CustomPaint>(_mapPaint(canvas));
  final recording = TestRecordingCanvas();
  painter.painter!.paint(recording, tester.getSize(_mapPaint(canvas)));
  return recording.invocations;
}

void _expectPaintWithinBounds(
  List<RecordedInvocation> calls,
  Size size,
  String reason,
) {
  final bounds = Offset.zero & size;
  for (final call in calls) {
    final painted = _paintedBounds(call);
    if (painted != null) {
      _expectContained(
        bounds,
        painted,
        '$reason ${call.invocation.memberName}',
      );
    }
  }
}

Rect? _paintedBounds(RecordedInvocation call) {
  final args = call.invocation.positionalArguments;
  return switch (call.invocation.memberName) {
    #drawCircle => Rect.fromCircle(
      center: args[0] as Offset,
      radius: args[1] as double,
    ),
    #drawRRect => (args[0] as RRect).outerRect,
    #drawPath => (args[0] as Path).getBounds(),
    #drawLine => Rect.fromPoints(args[0] as Offset, args[1] as Offset),
    #drawParagraph => Rect.fromLTWH(
      (args[1] as Offset).dx,
      (args[1] as Offset).dy,
      (args[0] as ui.Paragraph).longestLine,
      (args[0] as ui.Paragraph).height,
    ),
    _ => null,
  };
}

void _expectContained(Rect outer, Rect inner, String reason) {
  expect(inner.isFinite, isTrue, reason: '$reason: $inner');
  expect(inner.left, greaterThanOrEqualTo(outer.left - .01), reason: reason);
  expect(inner.top, greaterThanOrEqualTo(outer.top - .01), reason: reason);
  expect(inner.right, lessThanOrEqualTo(outer.right + .01), reason: reason);
  expect(inner.bottom, lessThanOrEqualTo(outer.bottom + .01), reason: reason);
}

bool _segmentCrossesRect(Offset from, Offset to, Rect rect) {
  var enter = 0.0;
  var leave = 1.0;
  for (final axis in [
    (from.dx, to.dx - from.dx, rect.left, rect.right),
    (from.dy, to.dy - from.dy, rect.top, rect.bottom),
  ]) {
    if (axis.$2 == 0) {
      if (axis.$1 < axis.$3 || axis.$1 > axis.$4) return false;
      continue;
    }
    final a = (axis.$3 - axis.$1) / axis.$2;
    final b = (axis.$4 - axis.$1) / axis.$2;
    enter = math.max(enter, math.min(a, b));
    leave = math.min(leave, math.max(a, b));
    if (enter > leave) return false;
  }
  return true;
}

double _distanceToRect(Offset point, Rect rect) =>
    (point -
            Offset(
              point.dx.clamp(rect.left, rect.right),
              point.dy.clamp(rect.top, rect.bottom),
            ))
        .distance;

double _pointSegmentDistance(Offset point, Offset from, Offset to) {
  final delta = to - from;
  if (delta.distanceSquared == 0) return (point - from).distance;
  final t =
      (((point.dx - from.dx) * delta.dx + (point.dy - from.dy) * delta.dy) /
              delta.distanceSquared)
          .clamp(0.0, 1.0);
  return (point - from - delta * t).distance;
}

void _expectOnlyRoutes(
  List<RecordedInvocation> calls,
  FcdMapGeometry map,
  Map<String, Offset> positions,
  Offset origin,
  List<int> captured,
  Map<int, List<Offset>> paths,
) {
  expect(
    paths.keys,
    unorderedEquals(
      map.routes.entries
          .where((entry) => entry.value.from != null)
          .map((entry) => entry.key),
    ),
  );
  for (final entry in paths.entries) {
    final route = map.routes[entry.key]!;
    expect(
      (entry.value.first - (positions[route.from]! - origin)).distance,
      lessThan(.01),
    );
    expect(
      (entry.value.last - (positions[route.to]! - origin)).distance,
      lessThan(.01),
    );
  }
  final expected = [
    for (final path in [...paths.values, for (final id in captured) ?paths[id]])
      for (var i = 1; i < path.length; i++) (path[i - 1], path[i]),
  ];
  final lines = calls
      .where((call) => call.invocation.memberName == #drawLine)
      .toList();
  expect(
    lines,
    hasLength(expected.length),
    reason: 'Only real routes may be drawn',
  );
  for (var i = 0; i < lines.length; i++) {
    final args = lines[i].invocation.positionalArguments;
    expect(((args[0] as Offset) - expected[i].$1).distance, lessThan(.01));
    expect(((args[1] as Offset) - expected[i].$2).distance, lessThan(.01));
  }
}

Map<int, List<Offset>> _routePaths(WidgetTester tester, Finder canvas) {
  final painter = tester
      .widget<CustomPaint>(
        find.descendant(of: canvas, matching: find.byType(CustomPaint)),
      )
      .painter!;
  final dynamic projection = (painter as dynamic).projection;
  return projection.routePaths as Map<int, List<Offset>>;
}

void _expectRoutesClearMarkers(
  FcdMapGeometry map,
  Map<String, Offset> positions,
  Offset origin,
  Map<int, List<Offset>> paths,
) {
  for (final entry in paths.entries) {
    final route = map.routes[entry.key]!;
    for (final node in positions.entries) {
      if (node.key == route.from || node.key == route.to) continue;
      for (var i = 1; i < entry.value.length; i++) {
        expect(
          _pointSegmentDistance(
            node.value - origin,
            entry.value[i - 1],
            entry.value[i],
          ),
          greaterThanOrEqualTo(6.59),
          reason: 'Route ${entry.key} must not appear connected to ${node.key}',
        );
      }
    }
  }
}
