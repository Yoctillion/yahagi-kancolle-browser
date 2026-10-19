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
  });

  for (final width in [240.0, 280.0, 360.0, 640.0]) {
    testWidgets('all bundled maps render within the $width viewport', (
      tester,
    ) async {
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
          await tester.pumpWidget(_app(progress: progress, geometry: map));
          expect(tester.takeException(), isNull, reason: '$mapKey / $width');
          final canvas = find.byKey(const Key('sortie-map-canvas'));
          expect(canvas, findsOneWidget, reason: mapKey);
          final bounds = tester.getRect(canvas);
          expect(bounds.width, lessThanOrEqualTo(math.min(430, width - 34)));
          _expectContained(Rect.fromLTWH(0, 0, width, 640), bounds, mapKey);
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
          for (var a = 0; a < paragraphs.length; a++) {
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
            (paintedCurrent - (positions[current]! - bounds.topLeft)).distance,
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
                find.descendant(of: canvas, matching: find.byType(Semantics)),
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
        'laterPaintedLabelsContainingCurrentMarkerCenter': currentOcclusions,
        'font': 'Flutter test default Ahem; conservative bounds',
      };
      debugPrint('SORTIE_MAP_RENDER_AUDIT ${jsonEncode(audit)}');
    });
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
      tester.getSize(canvas),
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
    final bounds = tester.getRect(canvas);
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

  testWidgets('displaced labels stay connected to their source nodes', (
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
    final bounds = tester.getRect(canvas);
    final points = _nodePositions(
      tester,
      canvas,
      geometry,
    ).values.map((point) => point - bounds.topLeft).toList();
    final paint = _recordPaint(tester, canvas);
    final leaders = paint.where((call) {
      if (call.invocation.memberName != #drawLine) return false;
      final args = call.invocation.positionalArguments;
      return !points.any(
            (point) => (point - (args[0] as Offset)).distance < .01,
          ) &&
          !points.any((point) => (point - (args[1] as Offset)).distance < .01);
    }).toList();
    expect(leaders, isNotEmpty);
    final firstMarker = paint.indexWhere(
      (call) => {
        #drawCircle,
        #drawRRect,
        #drawPath,
      }.contains(call.invocation.memberName),
    );
    for (final leader in leaders) {
      expect(paint.indexOf(leader), lessThan(firstMarker));
      final args = leader.invocation.positionalArguments;
      final start = args[0] as Offset;
      expect(
        points.map((point) => (point - start).distance).reduce(math.min),
        lessThanOrEqualTo(9.01),
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
        tester.getSize(canvas),
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
}

Widget _app({
  required SortieMapProgress progress,
  required FcdMapGeometry geometry,
}) => MaterialApp(
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
) => {
  for (final element
      in find
          .descendant(of: canvas, matching: find.byType(Semantics))
          .evaluate())
    if ((element.widget as Semantics).properties.label case final String label)
      if (map.spots.containsKey(label.split(' · ').first))
        label.split(' · ').first: tester
            .getRect(find.byWidget(element.widget))
            .center,
};

List<RecordedInvocation> _recordPaint(WidgetTester tester, Finder canvas) {
  final painter = tester.widget<CustomPaint>(
    find.descendant(of: canvas, matching: find.byType(CustomPaint)),
  );
  final recording = TestRecordingCanvas();
  painter.painter!.paint(recording, tester.getSize(canvas));
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
