import 'dart:math' as math;
import 'dart:ui';

/// Places every label beside its own marker, without leader lines.
///
/// Candidates stay on three small rings around the marker. A bounded global
/// relaxation lets previously placed labels make room for their neighbours.
Map<String, Rect> layoutSortieMapLabels({
  required Map<String, Offset> points,
  required Map<String, Size> labelSizes,
  required List<(Offset, Offset)> routes,
  required Size canvas,
  String? current,
  Map<String, double> markerClearances = const {},
}) {
  final labels = <_Label>[];
  for (final entry in points.entries) {
    final size = labelSizes[entry.key];
    if (size == null) continue;
    final at = entry.key == current;
    final candidates = <_Candidate>[];
    for (final gap in at ? [9.25, 10.75, 12.5] : [4.5, 7.5, 9.5]) {
      final diagonal = gap / math.sqrt2;
      final shallow = gap / 2;
      final steep = gap * math.sqrt(3) / 2;
      final offsets = [
        Offset(-size.width / 2, -size.height - gap),
        Offset(-size.width / 2, gap),
        Offset(gap, -size.height / 2),
        Offset(-size.width - gap, -size.height / 2),
        Offset(diagonal, -size.height - diagonal),
        Offset(-size.width - diagonal, -size.height - diagonal),
        Offset(diagonal, diagonal),
        Offset(-size.width - diagonal, diagonal),
        // Sliding along a nearby side fills the gaps between the cardinal and
        // diagonal placements without sending the letter farther from its dot.
        Offset(-size.width * .375, -size.height - gap),
        Offset(-size.width * .625, -size.height - gap),
        Offset(-size.width * .375, gap),
        Offset(-size.width * .625, gap),
        Offset(gap, -size.height * .375),
        Offset(gap, -size.height * .625),
        Offset(-size.width - gap, -size.height * .375),
        Offset(-size.width - gap, -size.height * .625),
        Offset(-size.width * .15, -size.height - gap),
        Offset(-size.width * .85, -size.height - gap),
        Offset(-size.width * .15, gap),
        Offset(-size.width * .85, gap),
        Offset(gap, -size.height * .15),
        Offset(gap, -size.height * .85),
        Offset(-size.width - gap, -size.height * .15),
        Offset(-size.width - gap, -size.height * .85),
        // Intermediate corner angles let tight groups use their remaining
        // space without increasing the label's distance from its own marker.
        Offset(shallow, -size.height - steep),
        Offset(-size.width - shallow, -size.height - steep),
        Offset(shallow, steep),
        Offset(-size.width - shallow, steep),
        Offset(steep, -size.height - shallow),
        Offset(-size.width - steep, -size.height - shallow),
        Offset(steep, shallow),
        Offset(-size.width - steep, shallow),
      ];
      for (var direction = 0; direction < offsets.length; direction++) {
        final topLeft = entry.value + offsets[direction];
        final bounds = Rect.fromLTWH(
          topLeft.dx.clamp(1.0, math.max(1, canvas.width - size.width - 1)),
          topLeft.dy.clamp(1.0, math.max(1, canvas.height - size.height - 1)),
          size.width,
          size.height,
        );
        final ownDistance = _distance(entry.value, bounds);
        if (ownDistance < (at ? 9.24 : 4.49) ||
            ownDistance > (at ? 12.51 : 9.51)) {
          continue;
        }
        if (candidates.any((candidate) => candidate.bounds == bounds)) continue;
        var nodes = 0.0;
        var ambiguity = 0.0;
        for (final other in points.entries) {
          final distance = _distance(other.value, bounds);
          final clearance =
              markerClearances[other.key] ?? (other.key == current ? 9.0 : 5.5);
          final penetration = clearance - distance;
          if (penetration > 0) nodes += penetration * penetration;
          if (other.key != entry.key && distance + .25 < ownDistance) {
            ambiguity += ownDistance + .25 - distance;
          }
        }
        candidates.add(
          _Candidate(
            bounds,
            nodes,
            ambiguity,
            _routeOverlap(bounds.inflate(2), routes),
            ownDistance + direction * .01,
          ),
        );
      }
    }
    // Very long optional names can be clamped along the canvas edge. Keep a
    // bounded fallback even when no ring candidate fits a degenerate canvas.
    if (candidates.isEmpty) {
      candidates.add(
        _Candidate(
          Rect.fromLTWH(
            (entry.value.dx - size.width / 2).clamp(
              1.0,
              math.max(1, canvas.width - size.width - 1),
            ),
            (entry.value.dy - size.height - (at ? 9.25 : 5.5)).clamp(
              1.0,
              math.max(1, canvas.height - size.height - 1),
            ),
            size.width,
            size.height,
          ),
          0,
          0,
          0,
          0,
        ),
      );
    }
    // Never trade a clear marker for a lower-priority label/route improvement.
    final minimum = candidates
        .map((candidate) => candidate.nodes)
        .reduce(math.min);
    candidates.removeWhere((candidate) => candidate.nodes > minimum + .00001);
    labels.add(_Label(entry.key, at, candidates));
  }
  if (labels.isEmpty) return {};

  final order = List<int>.generate(labels.length, (index) => index)
    ..sort((a, b) {
      if (labels[a].current != labels[b].current) {
        return labels[a].current ? -1 : 1;
      }
      final comparison = labels[a].clearOptions.compareTo(
        labels[b].clearOptions,
      );
      return comparison != 0 ? comparison : a.compareTo(b);
    });
  List<int> solve(List<int> sequence) {
    final placed = List<int>.filled(labels.length, -1);
    void place(int index) {
      final label = labels[index];
      var best = 0;
      var bestScore = double.infinity;
      for (var choice = 0; choice < label.candidates.length; choice++) {
        final candidate = label.candidates[choice];
        var overlap = 0.0;
        for (var other = 0; other < labels.length; other++) {
          if (other == index || placed[other] < 0) continue;
          overlap +=
              _overlap(candidate, labels[other].candidates[placed[other]]) *
              (label.current || labels[other].current ? 2 : 1);
        }
        final score =
            overlap * 10000 +
            candidate.ambiguity * 1000 +
            candidate.routes * 3 +
            candidate.preference;
        if (score < bestScore - .00001) {
          bestScore = score;
          best = choice;
        }
      }
      placed[index] = best;
    }

    for (final index in sequence) {
      place(index);
    }
    for (var pass = 0; pass < 6; pass++) {
      final previous = List<int>.of(placed);
      for (final index in pass.isEven ? sequence.reversed : sequence) {
        place(index);
      }
      if (List.generate(
        placed.length,
        (i) => placed[i] == previous[i],
      ).every((same) => same)) {
        break;
      }
    }
    return placed;
  }

  double quality(List<int> placed) {
    var score = 0.0;
    for (var a = 0; a < labels.length; a++) {
      final candidate = labels[a].candidates[placed[a]];
      score +=
          candidate.ambiguity * 1000 +
          candidate.routes * 3 +
          candidate.preference;
      for (var b = a + 1; b < labels.length; b++) {
        score +=
            _overlap(candidate, labels[b].candidates[placed[b]]) *
            (labels[a].current || labels[b].current ? 2 : 1) *
            10000;
      }
    }
    return score;
  }

  var placed = solve(order);
  // A second deterministic start avoids the insertion-order traps on busy maps.
  if (labels.length > 12) {
    final alternative = solve([
      ...order.where((index) => labels[index].current),
      ...order.reversed.where((index) => !labels[index].current),
    ]);
    if (quality(alternative) < quality(placed)) placed = alternative;
  }

  // Moving a single label can be blocked by its neighbour's current choice.
  // Coordinate just the remaining troublesome pairs, keeping the work bounded
  // and leaving the common, already-clear maps on the inexpensive path.
  for (var pass = 0; pass < 3; pass++) {
    final pairs = <(int, int, double)>[];
    for (var a = 0; a < labels.length; a++) {
      final first = labels[a].candidates[placed[a]];
      for (var b = a + 1; b < labels.length; b++) {
        final second = labels[b].candidates[placed[b]];
        final overlap = _overlap(first, second);
        final ambiguous = first.ambiguity + second.ambiguity;
        if (overlap > .00001 ||
            (ambiguous > 0 &&
                (first.bounds.center - second.bounds.center).distance < 40)) {
          pairs.add((a, b, overlap * 10000 + ambiguous * 1000));
        }
      }
    }
    if (pairs.isEmpty) break;
    pairs.sort((a, b) {
      final priority = b.$3.compareTo(a.$3);
      if (priority != 0) return priority;
      final first = a.$1.compareTo(b.$1);
      return first != 0 ? first : a.$2.compareTo(b.$2);
    });
    var changed = false;
    for (final (a, b, _) in pairs.take(16)) {
      List<double> externalCosts(int index, int partner) => [
        for (final candidate in labels[index].candidates)
          candidate.ambiguity * 1000 +
              candidate.routes * 3 +
              candidate.preference +
              [
                for (var other = 0; other < labels.length; other++)
                  if (other != index && other != partner)
                    _overlap(
                          candidate,
                          labels[other].candidates[placed[other]],
                        ) *
                        (labels[index].current || labels[other].current
                            ? 2
                            : 1) *
                        10000,
              ].fold<double>(0, (sum, value) => sum + value),
      ];
      final costsA = externalCosts(a, b);
      final costsB = externalCosts(b, a);
      final weight = (labels[a].current || labels[b].current ? 2 : 1) * 10000;
      double pairScore(int first, int second) =>
          costsA[first] +
          costsB[second] +
          _overlap(labels[a].candidates[first], labels[b].candidates[second]) *
              weight;
      var bestA = placed[a];
      var bestB = placed[b];
      var bestScore = pairScore(bestA, bestB);
      for (var first = 0; first < costsA.length; first++) {
        for (var second = 0; second < costsB.length; second++) {
          final score = pairScore(first, second);
          if (score < bestScore - .00001) {
            bestScore = score;
            bestA = first;
            bestB = second;
          }
        }
      }
      if (bestA != placed[a] || bestB != placed[b]) {
        placed[a] = bestA;
        placed[b] = bestB;
        changed = true;
      }
    }
    if (!changed) break;
  }
  return {
    for (var i = 0; i < labels.length; i++)
      labels[i].name: labels[i].candidates[placed[i]].bounds,
  };
}

final class _Label {
  _Label(this.name, this.current, this.candidates);
  final String name;
  final bool current;
  final List<_Candidate> candidates;
  int get clearOptions => candidates
      .where((candidate) => candidate.ambiguity == 0 && candidate.routes == 0)
      .length;
}

final class _Candidate {
  // Separate neighbouring letters visually as well as geometrically. A narrow
  // gap can make distinct node names read as one multi-letter node name.
  _Candidate(
    this.bounds,
    this.nodes,
    this.ambiguity,
    this.routes,
    this.preference,
  ) : padded = bounds.inflate(1.5);
  final Rect bounds;
  final Rect padded;
  final double nodes;
  final double ambiguity;
  final double routes;
  final double preference;
}

double _distance(Offset point, Rect bounds) =>
    (point -
            Offset(
              point.dx.clamp(bounds.left, bounds.right),
              point.dy.clamp(bounds.top, bounds.bottom),
            ))
        .distance;

double _overlap(_Candidate a, _Candidate b) {
  if (!a.padded.overlaps(b.padded)) return 0;
  final padding = a.padded.intersect(b.padded);
  var overlap = padding.width * padding.height * .01;
  // Readable separation is a preference; actual glyph-box intersections must
  // outweigh both that preference and node-ownership ambiguity.
  if (a.bounds.overlaps(b.bounds)) {
    final actual = a.bounds.intersect(b.bounds);
    overlap += actual.width * actual.height * 100;
  }
  return overlap;
}

double _routeOverlap(Rect bounds, List<(Offset, Offset)> routes) {
  var overlap = 0.0;
  for (final (from, to) in routes) {
    if (!Rect.fromPoints(from, to).overlaps(bounds)) continue;
    final delta = to - from;
    var enter = 0.0;
    var leave = 1.0;
    for (final axis in [
      (from.dx, delta.dx, bounds.left, bounds.right),
      (from.dy, delta.dy, bounds.top, bounds.bottom),
    ]) {
      if (axis.$2 == 0) continue;
      final a = (axis.$3 - axis.$1) / axis.$2;
      final b = (axis.$4 - axis.$1) / axis.$2;
      enter = math.max(enter, math.min(a, b));
      leave = math.min(leave, math.max(a, b));
    }
    if (enter < leave) overlap += (leave - enter) * delta.distance;
  }
  return overlap;
}
