import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/battle/fcd_map_geometry.dart';
import 'package:yahagi_kancolle_browser/src/battle/sortie_map_progress.dart';
import 'package:yahagi_kancolle_browser/src/battle/sortie_map_section.dart';

void main() {
  final geometry = FcdMapGeometry(
    routes: const {
      0: FcdMapRoute(from: null, to: 'A'),
      3: FcdMapRoute(from: 'A', to: 'B'),
      11: FcdMapRoute(from: 'B', to: 'C'),
      19: FcdMapRoute(from: 'B', to: 'C'),
    },
    spots: const {
      'A': FcdMapSpot(x: 0, y: 0, type: 'start'),
      'B': FcdMapSpot(x: 100, y: 40),
      'C': FcdMapSpot(x: 200, y: 0),
    },
  );
  SortieMapProgress progress(List<int> ids) => SortieMapProgress(
    mapAreaId: 2,
    mapInfoNo: 5,
    routeIds: ids,
    bossRouteId: 11,
  );

  testWidgets('60 ancestor paint updates do not repaint the map canvas', (
    tester,
  ) async {
    final parent = ValueNotifier(0);
    addTearDown(parent.dispose);
    await tester.pumpWidget(_app(geometry, progress([0, 3, 11]), parent));
    await tester.pumpAndSettle();
    final render = tester.renderObject<RenderCustomPaint>(_mapPaint());
    final counting = _CountingPainter(render.painter!);
    render.painter = counting;
    await tester.pump();
    counting.paints = 0;

    for (var i = 1; i <= 60; i++) {
      parent.value = i;
      await tester.pump(const Duration(milliseconds: 16));
    }
    final ancestorPaints = counting.paints;
    counting.paints = 0;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    debugPrint(
      'SORTIE_MAP_PERFORMANCE ancestorUpdates=60 '
      'mapPaints=$ancestorPaints idlePaints=${counting.paints}',
    );
    expect(ancestorPaints, 0);
    expect(counting.paints, 0);
    expect(_mapBoundary(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one scene reuses visited nodes across semantics and painting', (
    tester,
  ) async {
    final parent = ValueNotifier(0);
    addTearDown(parent.dispose);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_app(geometry, progress([0, 3, 3, 11]), parent));
      final painter = tester.widget<CustomPaint>(_mapPaint()).painter!;
      // Inspect the existing scene on the real painter without a production
      // testing API. Identity here only checks reuse within this immutable scene.
      final dynamic scene = (painter as dynamic).scene;
      final Set<String> visited = scene.visited as Set<String>;
      for (final label in geometry.spots.keys) {
        scene.nodeDescription(label);
      }
      painter.paint(TestRecordingCanvas(), tester.getSize(_canvas()));

      expect(visited, {'A', 'B', 'C'});
      expect(identical(scene.visited, visited), isTrue);
      expect(find.bySemanticsLabel('A · 起点 · 已走'), findsOneWidget);
      expect(find.bySemanticsLabel('C · Boss · 当前 · 已走'), findsOneWidget);
      expect(find.bySemanticsLabel('航段 11 · B → C · 已走'), findsOneWidget);
      expect(find.bySemanticsLabel('航段 19 · B → C'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'progress geometry and size changes repaint the isolated canvas',
    (tester) async {
      final parent = ValueNotifier(0);
      addTearDown(parent.dispose);
      final semantics = tester.ensureSemantics();
      try {
        final initialProgress = progress([0, 3]);
        await tester.pumpWidget(_app(geometry, initialProgress, parent));
        expect(_mapBoundary(), findsOneWidget);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          _mapBoundary(),
        );
        final initialPicture = _mapPicture(boundary);

        final latestProgress = progress([0, 3, 11]);
        await tester.pumpWidget(_app(geometry, latestProgress, parent));
        final progressPicture = _mapPicture(boundary);
        expect(progressPicture, isNot(same(initialPicture)));
        expect(find.bySemanticsLabel('C · Boss · 当前 · 已走'), findsOneWidget);
        final oldB = tester.getRect(find.bySemanticsLabel('B · 已走')).center;

        final movedGeometry = FcdMapGeometry(
          routes: geometry.routes,
          spots: {...geometry.spots, 'B': const FcdMapSpot(x: 50, y: 40)},
        );
        await tester.pumpWidget(_app(movedGeometry, latestProgress, parent));
        final geometryPicture = _mapPicture(boundary);
        expect(geometryPicture, isNot(same(progressPicture)));
        expect(
          tester.getRect(find.bySemanticsLabel('B · 已走')).center,
          isNot(oldB),
        );
        final originalSize = tester.getSize(_canvas());

        await tester.pumpWidget(
          _app(movedGeometry, latestProgress, parent, width: 200),
        );
        final resized = tester.getSize(_canvas());
        expect(resized.width, lessThan(originalSize.width));
        expect(resized.height, 125);
        expect(
          originalSize.height,
          (originalSize.width * .44 + 16).clamp(125, 175),
        );
        expect(_mapPicture(boundary), isNot(same(geometryPicture)));
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('collapse removes the canvas and its drawing layer', (
    tester,
  ) async {
    final parent = ValueNotifier(0);
    addTearDown(parent.dispose);
    final value = progress([0, 3, 11]);
    await tester.pumpWidget(_app(geometry, value, parent));
    expect(_mapBoundary(), findsOneWidget);
    final boundary = tester.renderObject<RenderRepaintBoundary>(_mapBoundary());
    final layer = boundary.debugLayer!;
    expect(layer.attached, isTrue);

    await tester.pumpWidget(_app(geometry, value, parent, expanded: false));
    expect(_canvas(), findsNothing);
    expect(_mapBoundary(), findsNothing);
    expect(boundary.attached, isFalse);
    expect(layer.attached, isFalse);
    for (var i = 1; i <= 60; i++) {
      parent.value = i;
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(_canvas(), findsNothing);
    expect(_mapBoundary(), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Finder _canvas() => find.byKey(const Key('sortie-map-canvas'));

Finder _mapPaint() =>
    find.descendant(of: _canvas(), matching: find.byType(CustomPaint));

Finder _mapBoundary() => find.descendant(
  of: find.byKey(const Key('sortie-map-section')),
  matching: find.byType(RepaintBoundary),
);

PictureLayer _mapPicture(RenderRepaintBoundary boundary) {
  final layer = boundary.debugLayer!;
  final pictures = <PictureLayer>[];
  void collect(ContainerLayer parent) {
    for (
      var child = parent.firstChild;
      child != null;
      child = child.nextSibling
    ) {
      if (child is PictureLayer) pictures.add(child);
      if (child is ContainerLayer) collect(child);
    }
  }

  collect(layer);
  expect(pictures, hasLength(1));
  return pictures.single;
}

class _CountingPainter extends CustomPainter {
  _CountingPainter(this.delegate);

  final CustomPainter delegate;
  int paints = 0;

  @override
  void paint(Canvas canvas, Size size) {
    paints++;
    delegate.paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _CountingPainter oldDelegate) => false;
}

Widget _app(
  FcdMapGeometry geometry,
  SortieMapProgress progress,
  ValueNotifier<int> parent, {
  bool expanded = true,
  double width = 360,
}) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SingleChildScrollView(
      child: Center(
        child: SizedBox(
          width: width,
          child: ValueListenableBuilder<int>(
            valueListenable: parent,
            child: SortieMapSection(
              progress: progress,
              geometry: geometry,
              expanded: expanded,
              onToggleExpanded: () {},
            ),
            builder: (_, count, child) => ColoredBox(
              color: count.isEven ? Colors.black : Colors.white,
              child: child,
            ),
          ),
        ),
      ),
    ),
  ),
);
