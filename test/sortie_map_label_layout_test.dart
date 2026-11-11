import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/battle/sortie_map_label_layout.dart';

void main() {
  test(
    'nearby letters remain separate instead of reading as a combined name',
    () {
      // A/B were visually joined in the 1-6 actual-font audit despite not
      // intersecting. Each label must keep its own marker and its reading space.
      final points = {
        'A': const Offset(72.56, 126.54),
        'B': const Offset(81.43, 104.62),
      };
      final labels = layoutSortieMapLabels(
        points: points,
        labelSizes: const {'A': Size(6.52, 12), 'B': Size(6.23, 12)},
        routes: const [],
        canvas: const Size(326, 180),
        markerClearances: const {'A': 4.5, 'B': 4.5},
      );
      expect(
        labels['A']!.inflate(1.5).overlaps(labels['B']!.inflate(1.5)),
        isFalse,
      );
      for (final name in points.keys) {
        final own = _distance(points[name]!, labels[name]!);
        expect(own, inInclusiveRange(4.49, 10));
        for (final other in points.keys.where((other) => other != name)) {
          expect(
            _distance(points[other]!, labels[name]!),
            greaterThanOrEqualTo(own - .25),
          );
        }
      }
    },
  );

  test(
    'close nodes label opposite free sides while protecting the current halo',
    () {
      const points = {
        'K': Offset(50, 50),
        'K1': Offset(58, 50),
        'K2': Offset(54, 67),
      };
      final labels = layoutSortieMapLabels(
        points: points,
        labelSizes: const {
          'K': Size(7, 12),
          'K1': Size(12, 12),
          'K2': Size(12, 12),
        },
        routes: const [
          (Offset(50, 50), Offset(58, 50)),
          (Offset(58, 50), Offset(54, 67)),
        ],
        canvas: const Size(120, 120),
        current: 'K',
      );
      for (final entry in labels.entries) {
        expect(
          _distance(points[entry.key]!, entry.value),
          lessThanOrEqualTo(entry.key == 'K' ? 13 : 10),
        );
        expect(
          _distance(points['K']!, entry.value),
          greaterThanOrEqualTo(8.99),
        );
        for (final other in points.entries) {
          expect(entry.value.contains(other.value), isFalse);
        }
      }
    },
  );

  test('identical inputs keep a deterministic compact layout', () {
    Map<String, Rect> arrange() => layoutSortieMapLabels(
      points: const {
        'A': Offset(20, 20),
        'B': Offset(40, 35),
        'C': Offset(30, 55),
      },
      labelSizes: const {'A': Size(7, 12), 'B': Size(7, 12), 'C': Size(7, 12)},
      routes: const [(Offset(20, 20), Offset(40, 35))],
      canvas: const Size(100, 100),
      current: 'A',
    );
    expect(arrange(), equals(arrange()));
  });
}

double _distance(Offset point, Rect rect) =>
    (point -
            Offset(
              point.dx.clamp(rect.left, rect.right),
              point.dy.clamp(rect.top, rect.bottom),
            ))
        .distance;
