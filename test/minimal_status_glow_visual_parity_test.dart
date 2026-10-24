import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderDecoratedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/fleet/minimal_status_glow.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_damage_level.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_status_style.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_status_visuals.dart';
import 'package:yahagi_kancolle_browser/src/settings/battle_status_effect_settings.dart';

const _originalKey = Key('original-glow-slot');
const _minimalKey = Key('minimal-glow-slot');
const _normalColor = Color(0xff29a634);

Widget _pair({
  required int hp,
  DamagePulseFilter filter = DamagePulseFilter.all,
  bool visible = true,
  BorderRadius? radius = const BorderRadius.all(Radius.circular(2)),
  Color normalColor = _normalColor,
  String mount = 'stable',
}) => MaterialApp(
  home: Scaffold(
    body: TickerMode(
      enabled: visible,
      child: Center(
        child: Row(
          key: ValueKey(mount),
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              key: _originalKey,
              width: 96,
              height: 18,
              child: DamagePulseGlow(
                currentHp: hp,
                maxHp: 100,
                filter: filter,
                normalColor: normalColor,
                borderRadius: radius,
                child: const ColoredBox(color: Colors.green),
              ),
            ),
            const SizedBox(width: 32),
            SizedBox(
              key: _minimalKey,
              width: 96,
              height: 18,
              child: MinimalDamagePulseGlow(
                currentHp: hp,
                maxHp: 100,
                filter: filter,
                normalColor: normalColor,
                borderRadius: radius,
                child: const ColoredBox(color: Colors.green),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

Future<void> _pumpPair(WidgetTester tester, Widget pair) async {
  await tester.pumpWidget(pair);
  await tester.pump();
}

// Inspect the live render decoration, including paint-only changes that never
// replace the DecoratedBox widget. The original component is the oracle.
BoxDecoration? _paintDecoration(WidgetTester tester, Key key) {
  final decorations = <BoxDecoration>[];
  void visit(RenderObject object) {
    if (object is RenderDecoratedBox) {
      final decoration = object.decoration;
      if (decoration is BoxDecoration &&
          (decoration.boxShadow?.isNotEmpty ?? false)) {
        decorations.add(decoration);
      }
    }
    object.visitChildren(visit);
  }

  visit(tester.renderObject(find.byKey(key)));
  expect(decorations.length, lessThanOrEqualTo(1));
  return decorations.firstOrNull;
}

void _expectParity(WidgetTester tester, {String? reason}) {
  final original = _paintDecoration(tester, _originalKey);
  final minimal = _paintDecoration(tester, _minimalKey);
  if (original == null) {
    expect(minimal, isNull, reason: reason);
    return;
  }
  expect(minimal, isNotNull, reason: reason);
  expect(minimal!.borderRadius, original.borderRadius, reason: reason);
  final expected = original.boxShadow!.single;
  final actual = minimal.boxShadow!.single;
  expect(actual.color, expected.color, reason: reason);
  expect(actual.blurRadius, expected.blurRadius, reason: reason);
  expect(actual.spreadRadius, expected.spreadRadius, reason: reason);
  expect(actual.offset, expected.offset, reason: reason);
  expect(actual.blurStyle, expected.blurStyle, reason: reason);
  expect(
    tester.getSize(find.byKey(_minimalKey)),
    tester.getSize(find.byKey(_originalKey)),
    reason: reason,
  );
}

void main() {
  testWidgets(
    'minimal HP glow matches every damage level through a full cycle',
    (tester) async {
      for (final hp in [25, 50, 75]) {
        await _pumpPair(tester, _pair(hp: hp, mount: 'cycle-$hp'));
        final period = damagePulseVisualSpec(
          damageLevel: shipDamageLevel(currentHp: hp, maxHp: 100),
          filter: DamagePulseFilter.all,
          normalColor: _normalColor,
        ).duration;
        final step = Duration(microseconds: period.inMicroseconds ~/ 8);
        final originalShadows = <BoxShadow>{};
        // Includes the next cycle's first eighth, so wraparound is compared too.
        for (var sample = 0; sample <= 9; sample++) {
          if (sample > 0) await tester.pump(step);
          _expectParity(tester, reason: 'HP $hp, cycle sample $sample');
          originalShadows.add(
            _paintDecoration(tester, _originalKey)!.boxShadow!.single,
          );
        }
        expect(originalShadows.length, greaterThanOrEqualTo(4));
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.binding.transientCallbackCount, 0);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('off, healthy, zero HP and unmatched filters stay undecorated', (
    tester,
  ) async {
    for (final sample in const [
      (hp: 25, filter: DamagePulseFilter.off),
      (hp: 100, filter: DamagePulseFilter.all),
      (hp: 0, filter: DamagePulseFilter.all),
      (hp: 75, filter: DamagePulseFilter.heavyOnly),
    ]) {
      await _pumpPair(tester, _pair(hp: sample.hp, filter: sample.filter));
      _expectParity(tester);
      expect(_paintDecoration(tester, _originalKey), isNull);
      expect(_paintDecoration(tester, _minimalKey), isNull);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pump(const Duration(seconds: 2));
      _expectParity(tester);
      expect(tester.binding.transientCallbackCount, 0);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('TickerMode freezes both glows and restores the same phase', (
    tester,
  ) async {
    await _pumpPair(tester, _pair(hp: 25));
    await tester.pump(const Duration(milliseconds: 197));
    _expectParity(tester);
    await _pumpPair(tester, _pair(hp: 25, visible: false));
    final frozenOriginal = _paintDecoration(tester, _originalKey);
    final frozenMinimal = _paintDecoration(tester, _minimalKey);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(_paintDecoration(tester, _originalKey), frozenOriginal);
    expect(_paintDecoration(tester, _minimalKey), frozenMinimal);
    _expectParity(tester);

    await _pumpPair(tester, _pair(hp: 25));
    _expectParity(tester);
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 183));
    _expectParity(tester);
    expect(_paintDecoration(tester, _originalKey), isNot(frozenOriginal));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'live HP, filter, color and radius changes keep original visuals',
    (tester) async {
      var index = 0;
      // Keep both element paths stable while changing running controller inputs.
      for (final sample in const [
        (hp: 25, filter: DamagePulseFilter.all),
        (hp: 50, filter: DamagePulseFilter.all),
        (hp: 75, filter: DamagePulseFilter.minorOnly),
        (hp: 75, filter: DamagePulseFilter.heavyOnly),
        (hp: 75, filter: DamagePulseFilter.minorOnly),
        (hp: 100, filter: DamagePulseFilter.all),
        (hp: 20, filter: DamagePulseFilter.heavyOnly),
        (hp: 20, filter: DamagePulseFilter.off),
        (hp: 50, filter: DamagePulseFilter.moderateOnly),
      ]) {
        await _pumpPair(
          tester,
          _pair(
            hp: sample.hp,
            filter: sample.filter,
            radius: index.isEven ? BorderRadius.circular(2.0 + index) : null,
            normalColor: index.isEven ? Colors.green : Colors.blue,
          ),
        );
        final reason = 'live step $index: HP ${sample.hp}, ${sample.filter}';
        _expectParity(tester, reason: reason);
        await tester.pump(Duration(milliseconds: 137 + index * 19));
        _expectParity(tester, reason: reason);
        index++;
      }
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
