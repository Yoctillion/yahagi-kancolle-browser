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
  late FcdMapDataset dataset;
  setUpAll(() async {
    dataset = FcdMapDataset.parse(
      await rootBundle.loadString('assets/data/fcd/map.json'),
    );
  });

  testWidgets('sparse and dense maps share the same visible canvas size', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Size? reference;
    for (final (area, number) in [(1, 1), (1, 6), (62, 5)]) {
      await tester.pumpWidget(_app(dataset, area, number));
      final size = tester.getSize(_viewport());
      reference ??= size;
      expect(size, reference, reason: '$area-$number');
      expect(tester.takeException(), isNull);
    }
  });

  for (final (area, number) in [(1, 1), (1, 6), (62, 5)]) {
    testWidgets('$area-$number shrinks the entire composition uniformly', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final map = dataset.geometryFor(mapAreaId: area, mapInfoNo: number)!;
      Size? referenceSize;
      Size? referenceLogicalSize;
      List<Rect>? referenceLabels;
      Map<String, Offset>? referenceNodes;
      double? referenceScale;
      for (final width in [360.0, 240.0, 180.0, 280.0, 640.0]) {
        await tester.binding.setSurfaceSize(Size(width, 640));
        await tester.pumpWidget(_app(dataset, area, number));
        final size = tester.getSize(_viewport());
        final paintFinder = find.descendant(
          of: _viewport(),
          matching: find.byType(CustomPaint),
        );
        final paintBox = tester.renderObject<RenderBox>(paintFinder);
        final origin = paintBox.localToGlobal(Offset.zero);
        final scaleX =
            (paintBox.localToGlobal(const Offset(1, 0)) - origin).distance;
        final scaleY =
            (paintBox.localToGlobal(const Offset(0, 1)) - origin).distance;
        final nodes = <String, Offset>{
          for (final element
              in find
                  .descendant(of: _viewport(), matching: find.byType(Semantics))
                  .evaluate())
            if (map.spots.containsKey(
              (element.widget as Semantics).properties.label
                  ?.split(' · ')
                  .first,
            ))
              (element.widget as Semantics).properties.label!
                      .split(' · ')
                      .first:
                  (tester.getCenter(find.byWidget(element.widget)) - origin) /
                  size.width,
        };
        final recording = TestRecordingCanvas();
        tester
            .widget<CustomPaint>(paintFinder)
            .painter!
            .paint(recording, paintBox.size);
        final labels = <Rect>[
          for (final call in recording.invocations)
            if (call.invocation.memberName == #drawParagraph)
              (call.invocation.positionalArguments[1] as Offset) &
                  Size(
                    (call.invocation.positionalArguments[0] as ui.Paragraph)
                        .width,
                    (call.invocation.positionalArguments[0] as ui.Paragraph)
                        .height,
                  ),
        ];
        referenceSize ??= size;
        referenceLogicalSize ??= paintBox.size;
        referenceLabels ??= labels;
        referenceNodes ??= nodes;
        referenceScale ??= scaleX;
        expect(size.aspectRatio, closeTo(referenceSize.aspectRatio, .00001));
        expect(paintBox.size, referenceLogicalSize);
        expect(
          labels,
          referenceLabels,
          reason: 'labels must keep their layout',
        );
        expect(scaleX, closeTo(scaleY, .00001));
        expect(
          scaleX / referenceScale,
          closeTo(size.width / referenceSize.width, .00001),
        );
        expect(nodes.keys, unorderedEquals(map.spots.keys));
        for (final entry in nodes.entries) {
          expect(
            (entry.value - referenceNodes[entry.key]!).distance,
            lessThan(.00001),
            reason: '${entry.key} must retain its relative position at $width',
          );
        }
        expect(size.width, lessThanOrEqualTo(referenceSize.width));
        expect(tester.takeException(), isNull);
      }
    });
  }
}

Finder _viewport() => find.byKey(const Key('sortie-map-canvas'));

Widget _app(FcdMapDataset dataset, int area, int number) {
  final FcdMapGeometry map = dataset.geometryFor(
    mapAreaId: area,
    mapInfoNo: number,
  )!;
  return MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: SortieMapSection(
            progress: SortieMapProgress(
              mapAreaId: area,
              mapInfoNo: number,
              routeIds: [map.routes.keys.first],
            ),
            geometry: map,
            expanded: true,
            onToggleExpanded: () {},
          ),
        ),
      ),
    ),
  );
}
