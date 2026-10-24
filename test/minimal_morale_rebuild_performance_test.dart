import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/fleet/fleet_ship_minimal_row.dart';
import 'package:yahagi_kancolle_browser/src/fleet/minimal_status_glow.dart';
import 'package:yahagi_kancolle_browser/src/settings/battle_status_effect_settings.dart';

class _TrackedAnimation extends Animation<double> {
  var _value = 0.0;
  final _listeners = <VoidCallback>{};

  int get listenerCount => _listeners.length;

  @override
  double get value => _value;

  set value(double next) {
    if (_value == next) return;
    _value = next;
    for (final listener in _listeners.toList()) {
      listener();
    }
  }

  @override
  AnimationStatus get status => AnimationStatus.forward;

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  @override
  void addStatusListener(AnimationStatusListener listener) {}

  @override
  void removeStatusListener(AnimationStatusListener listener) {}
}

Widget _app({
  int value = 85,
  MoraleSparkleMode mode = MoraleSparkleMode.blinking,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: MoraleChip(value: value, sparkleMode: mode),
    ),
  ),
);

BoxDecoration _decoration(WidgetTester tester) =>
    tester
            .renderObject<RenderDecoratedBox>(
              find.descendant(
                of: find.byType(MoraleChip),
                matching: find.byElementPredicate(
                  (element) =>
                      element is RenderObjectElement &&
                      element.renderObject is RenderDecoratedBox,
                ),
              ),
            )
            .decoration
        as BoxDecoration;

void main() {
  testWidgets(
    'minimal paint listener reattaches and releases replaced animation owners',
    (tester) async {
      final first = _TrackedAnimation();
      final second = _TrackedAnimation();
      final decorationKey = GlobalKey();
      BoxDecoration decoration(double value) => BoxDecoration(
        boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: value))],
      );
      Widget host(Animation<double> animation, {bool right = false}) {
        final glow = MinimalAnimatedDecoration(
          key: decorationKey,
          animation: animation,
          decorationBuilder: decoration,
          child: const SizedBox(width: 20, height: 10),
        );
        return MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                SizedBox(width: 100, child: right ? const SizedBox() : glow),
                SizedBox(width: 100, child: right ? glow : const SizedBox()),
              ],
            ),
          ),
        );
      }

      expect(first.listenerCount, 0);
      await tester.pumpWidget(host(first));
      final render = tester.renderObject<RenderDecoratedBox>(
        find.byKey(decorationKey),
      );
      expect(first.listenerCount, 1);
      first.value = .25;
      await tester.pump();
      expect(render.decoration, decoration(.25));

      await tester.pumpWidget(host(first, right: true));
      expect(
        tester.renderObject<RenderDecoratedBox>(find.byKey(decorationKey)),
        same(render),
      );
      expect(first.listenerCount, 1);
      first.value = .5;
      await tester.pump();
      expect(render.decoration, decoration(.5));

      await tester.pumpWidget(host(second, right: true));
      expect(first.listenerCount, 0);
      expect(second.listenerCount, 1);
      first.value = .75;
      expect(render.decoration, decoration(0));
      second.value = .6;
      await tester.pump();
      expect(render.decoration, decoration(.6));

      await tester.pumpWidget(const SizedBox());
      expect(second.listenerCount, 0);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'morale animation reuses the number and icon while the glow changes',
    (tester) async {
      var textBuilds = 0;
      var iconBuilds = 0;
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        final widget = element.widget;
        if (widget is Text && widget.data == '85') textBuilds++;
        if (widget is Icon && widget.icon == Icons.auto_awesome) iconBuilds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);

      await tester.pumpWidget(_app());
      final initialTextBuilds = textBuilds;
      final initialIconBuilds = iconBuilds;
      expect(initialTextBuilds, greaterThan(0));
      expect(initialIconBuilds, greaterThan(0));
      final originalText = tester.widget<Text>(find.text('85'));
      final originalIcon = tester.widget<Icon>(find.byIcon(Icons.auto_awesome));
      final originalSize = tester.getSize(find.byType(MoraleChip));
      final colors = <Color>{_decoration(tester).boxShadow!.single.color};

      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
        final decoration = _decoration(tester);
        colors.add(decoration.boxShadow!.single.color);
        expect(decoration.boxShadow!.single.blurRadius, 5);
        expect(tester.getSize(find.byType(MoraleChip)), originalSize);
      }

      expect(
        colors.length,
        greaterThan(1),
        reason: 'the visible glow must still animate',
      );
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      expect(
        textBuilds,
        initialTextBuilds,
        reason: 'animation phases must not rebuild the unchanged number',
      );
      expect(
        iconBuilds,
        initialIconBuilds,
        reason: 'animation phases must not rebuild the unchanged morale icon',
      );
      expect(tester.widget<Text>(find.text('85')), same(originalText));
      expect(
        tester.widget<Icon>(find.byIcon(Icons.auto_awesome)),
        same(originalIcon),
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'reused morale content still responds to value and effect settings',
    (tester) async {
      await tester.pumpWidget(_app());
      await tester.pump(const Duration(milliseconds: 200));
      final originalSize = tester.getSize(find.byType(MoraleChip));

      await tester.pumpWidget(_app(value: 86));
      expect(find.text('85'), findsNothing);
      expect(find.text('86'), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
      final before = _decoration(tester).boxShadow!.single.color;
      await tester.pump(const Duration(milliseconds: 200));
      expect(_decoration(tester).boxShadow!.single.color, isNot(before));

      await tester.pumpWidget(_app(value: 86, mode: MoraleSparkleMode.steady));
      final steady = _decoration(tester).boxShadow!.single;
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pump(const Duration(milliseconds: 200));
      expect(_decoration(tester).boxShadow!.single, steady);
      expect(tester.getSize(find.byType(MoraleChip)), originalSize);

      await tester.pumpWidget(_app(value: 49));
      expect(find.text('49'), findsOneWidget);
      expect(find.byIcon(Icons.sentiment_satisfied), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome), findsNothing);
      expect(_decoration(tester).boxShadow, isNull);
      expect(tester.binding.transientCallbackCount, 0);

      await tester.pumpWidget(_app(value: 86, mode: MoraleSparkleMode.off));
      expect(find.text('86'), findsOneWidget);
      expect(_decoration(tester).boxShadow, isNull);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.getSize(find.byType(MoraleChip)), originalSize);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
