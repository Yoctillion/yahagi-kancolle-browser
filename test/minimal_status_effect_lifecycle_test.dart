import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/battle/prophet_hp_bar.dart';
import 'package:yahagi_kancolle_browser/src/fleet/fleet_ship_minimal_row.dart';
import 'package:yahagi_kancolle_browser/src/fleet/fleet_ship_status_capsule.dart';
import 'package:yahagi_kancolle_browser/src/fleet/minimal_status_glow.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_repair_status.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_status_visuals.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/settings/battle_status_effect_settings.dart';
import 'package:yahagi_kancolle_browser/src/settings/fleet_display_options.dart';

const _state = GameState(
  masterShips: {1: MasterShip(id: 1, name: 'fixture', shipTypeId: 2)},
);

OwnedShip _ship({int hp = 20, int condition = 49}) => OwnedShip(
  id: 1,
  masterId: 1,
  level: 1,
  condition: condition,
  currentHp: hp,
  maxHp: 100,
);

Widget _app(Widget child, {bool visible = true, double width = 320}) =>
    MaterialApp(
      home: Scaffold(
        body: TickerMode(
          enabled: visible,
          child: Center(
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );

Widget _row({
  bool bars = true,
  int hp = 20,
  DamagePulseFilter filter = DamagePulseFilter.all,
  ShipRepairStatus? repairStatus,
  bool showHp = true,
}) => FleetShipMinimalRow(
  state: _state,
  ship: _ship(hp: hp),
  visible: {if (showHp) 'hp', if (bars) 'bars'},
  shipTypeLabelMode: FleetShipTypeLabelMode.localizedName,
  damagePulseFilter: filter,
  moraleSparkleMode: MoraleSparkleMode.off,
  repairStatus: repairStatus,
);

Finder _glowDecoration() => find.descendant(
  of: find.byType(MinimalDamagePulseGlow),
  matching: find.byElementPredicate(
    (element) =>
        element is RenderObjectElement &&
        element.renderObject is RenderDecoratedBox &&
        ((((element.renderObject as RenderDecoratedBox).decoration
                        as BoxDecoration)
                    .boxShadow)
                ?.isNotEmpty ??
            false),
  ),
);

BoxShadow _damageShadow(WidgetTester tester) =>
    (tester.renderObject<RenderDecoratedBox>(_glowDecoration()).decoration
            as BoxDecoration)
        .boxShadow!
        .single;

List<BoxShadow>? _moraleShadows(WidgetTester tester) =>
    (tester
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
            as BoxDecoration)
        .boxShadow;

Future<void> _pumpEffects(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  for (final bars in [true, false]) {
    final presentation = bars ? 'bar' : 'number';
    testWidgets('minimal hp $presentation obeys every global damage filter', (
      tester,
    ) async {
      for (final sample in [
        (hp: 75, matching: DamagePulseFilter.minorOnly),
        (hp: 50, matching: DamagePulseFilter.moderateOnly),
        (hp: 25, matching: DamagePulseFilter.heavyOnly),
      ]) {
        for (final filter in DamagePulseFilter.values) {
          await _pumpEffects(
            tester,
            _app(_row(bars: bars, hp: sample.hp, filter: filter)),
          );
          final pulses =
              filter == DamagePulseFilter.all || filter == sample.matching;
          final reason = '$presentation hp=${sample.hp}, filter=$filter';
          expect(
            _glowDecoration(),
            pulses ? findsOneWidget : findsNothing,
            reason: reason,
          );
          expect(
            tester.binding.transientCallbackCount,
            pulses ? greaterThan(0) : 0,
            reason: reason,
          );
          expect(find.text('${sample.hp}/100'), findsOneWidget);
          expect(
            find.byType(ProphetHpBar),
            bars ? findsOneWidget : findsNothing,
          );
          expect(find.byType(ShipHpFrame), findsNothing);
          expect(find.byType(ShipMoraleMark), findsNothing);
        }
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'minimal hp $presentation stops and restarts across lifecycle changes',
      (tester) async {
        Future<void> render({
          int hp = 20,
          DamagePulseFilter filter = DamagePulseFilter.heavyOnly,
          bool visible = true,
          bool showHp = true,
          ShipRepairStatus? repairStatus,
        }) => _pumpEffects(
          tester,
          _app(
            _row(
              bars: bars,
              hp: hp,
              filter: filter,
              repairStatus: repairStatus,
              showHp: showHp,
            ),
            visible: visible,
          ),
        );

        await render();
        final before = _damageShadow(tester);
        await tester.pump(const Duration(milliseconds: 190));
        final after = _damageShadow(tester);
        expect(after.color, isNot(before.color));
        expect(after.blurRadius, isNot(before.blurRadius));
        expect(tester.binding.transientCallbackCount, greaterThan(0));

        await render(filter: DamagePulseFilter.off);
        expect(_glowDecoration(), findsNothing);
        expect(tester.binding.transientCallbackCount, 0);
        await render();
        expect(tester.binding.transientCallbackCount, greaterThan(0));

        await render(hp: 100);
        expect(_glowDecoration(), findsNothing);
        expect(tester.binding.transientCallbackCount, 0);
        await render();
        expect(tester.binding.transientCallbackCount, greaterThan(0));

        await render(visible: false);
        final muted = _damageShadow(tester);
        expect(tester.binding.transientCallbackCount, 0);
        await tester.pump(const Duration(seconds: 2));
        expect(_damageShadow(tester), muted);
        expect(tester.binding.transientCallbackCount, 0);
        await render();
        expect(tester.binding.transientCallbackCount, greaterThan(0));
        final resumed = _damageShadow(tester);
        await tester.pump(const Duration(milliseconds: 190));
        expect(_damageShadow(tester), isNot(resumed));

        await render(repairStatus: ShipRepairStatus.retreat);
        expect(find.text('0/100'), findsOneWidget);
        expect(find.byType(DamagePulseGlow), findsNothing);
        expect(find.byType(MinimalDamagePulseGlow), findsNothing);
        expect(tester.binding.transientCallbackCount, 0);
        await render();
        expect(tester.binding.transientCallbackCount, greaterThan(0));
        await render(showHp: false);
        expect(find.byType(DamagePulseGlow), findsNothing);
        expect(find.byType(MinimalDamagePulseGlow), findsNothing);
        expect(tester.binding.transientCallbackCount, 0);
        await render();
        expect(tester.binding.transientCallbackCount, greaterThan(0));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 2));
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'minimal morale glow follows mode threshold and ticker lifecycle',
    (tester) async {
      Future<void> render({
        int condition = 50,
        MoraleSparkleMode mode = MoraleSparkleMode.blinking,
        bool visible = true,
      }) => _pumpEffects(
        tester,
        _app(
          MoraleChip(value: condition, sparkleMode: mode),
          visible: visible,
        ),
      );

      await render();
      final before = _moraleShadows(tester)!.single.color;
      await tester.pump(const Duration(milliseconds: 250));
      expect(_moraleShadows(tester)!.single.color, isNot(before));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      expect(find.byType(ShipMoraleMark), findsNothing);

      await render(mode: MoraleSparkleMode.steady);
      final steady = _moraleShadows(tester);
      expect(steady, isNotEmpty);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pump(const Duration(seconds: 2));
      expect(_moraleShadows(tester), steady);
      expect(tester.binding.transientCallbackCount, 0);

      await render(mode: MoraleSparkleMode.off);
      expect(_moraleShadows(tester), isNull);
      expect(find.text('50'), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      await render();
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await render(condition: 49);
      expect(_moraleShadows(tester), isNull);
      expect(tester.binding.transientCallbackCount, 0);
      await render();
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      await render(visible: false);
      final muted = _moraleShadows(tester);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pump(const Duration(seconds: 2));
      expect(_moraleShadows(tester), muted);
      expect(tester.binding.transientCallbackCount, 0);
      await render();
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      final resumed = _moraleShadows(tester)!.single.color;
      await tester.pump(const Duration(milliseconds: 250));
      expect(_moraleShadows(tester)!.single.color, isNot(resumed));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [360.0, 600.0]) {
    testWidgets('original capsule keeps frame and stars at ${width}dp', (
      tester,
    ) async {
      Future<void> render({bool visible = true, bool effects = true}) =>
          _pumpEffects(
            tester,
            _app(
              FleetShipStatusCapsule(
                state: _state,
                ship: _ship(condition: 50),
                damagePulseFilter: effects
                    ? DamagePulseFilter.heavyOnly
                    : DamagePulseFilter.off,
                moraleSparkleMode: effects
                    ? MoraleSparkleMode.blinking
                    : MoraleSparkleMode.off,
              ),
              visible: visible,
              width: width,
            ),
          );

      await render();
      expect(find.byType(ShipHpFrame), findsOneWidget);
      expect(find.byType(ShipMoraleMark), findsOneWidget);
      expect(find.byType(DamagePulseGlow), findsNothing);
      expect(find.byType(MoraleChip), findsNothing);
      final tint = find.byKey(const Key('fleet-damage-tint-1'));
      final pulse = find.byKey(const Key('fleet-damage-pulse-1'));
      expect(tint, findsOneWidget);
      expect(pulse, findsOneWidget);
      expect(find.byKey(const Key('fleet-morale-stars-1')), findsOneWidget);
      final before = tester.widget<Opacity>(tint).opacity;
      await tester.pump(const Duration(milliseconds: 190));
      expect(tester.widget<Opacity>(tint).opacity, isNot(before));
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      await render(visible: false);
      expect(tester.binding.transientCallbackCount, 0);
      await render();
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await render(effects: false);
      expect(find.byType(ShipHpFrame), findsOneWidget);
      expect(tint, findsNothing);
      expect(pulse, findsNothing);
      expect(find.byKey(const Key('fleet-morale-stars-1')), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
