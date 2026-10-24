import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:yahagi_kancolle_browser/src/fleet/fleet_ship_minimal_row.dart';
import 'package:yahagi_kancolle_browser/src/fleet/minimal_status_glow.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_portrait.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_portrait_cache.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/layout/flat_portrait_backdrop.dart';
import 'package:yahagi_kancolle_browser/src/settings/battle_status_effect_settings.dart';
import 'package:yahagi_kancolle_browser/src/settings/fleet_display_options.dart';

const _master = MasterShip(
  id: 1,
  name: 'Paint probe',
  shipTypeId: 2,
  portraitVersion: '1',
);
const _state = GameState(masterShips: {1: _master});

class _PortraitCache extends ShipPortraitCache {
  _PortraitCache(http.Client client)
    : super(
        directoryProvider: () async => Directory.systemTemp,
        client: client,
      );
  var resolves = 0;

  @override
  Future<File?> resolve({required String cacheKey, required Uri uri}) {
    resolves++;
    return SynchronousFuture(File('unused-portrait.png'));
  }
}

class _PaintProbe extends SingleChildRenderObjectWidget {
  const _PaintProbe({
    required this.onPaint,
    this.onLayout,
    required super.child,
  });
  final VoidCallback onPaint;
  final VoidCallback? onLayout;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPaintProbe(onPaint, onLayout);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPaintProbe renderObject,
  ) {
    renderObject.onPaint = onPaint;
    renderObject.onLayout = onLayout;
  }
}

class _RenderPaintProbe extends RenderProxyBox {
  _RenderPaintProbe(this.onPaint, this.onLayout);
  VoidCallback onPaint;
  VoidCallback? onLayout;

  @override
  void performLayout() {
    onLayout?.call();
    super.performLayout();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint();
    super.paint(context, offset);
  }
}

Color _shadowColor(WidgetTester tester, {required bool morale}) {
  final decoration = tester.renderObject<RenderDecoratedBox>(
    find.descendant(
      of: find.byType(morale ? MoraleChip : MinimalDamagePulseGlow),
      matching: find.byElementPredicate(
        (element) =>
            element is RenderObjectElement &&
            element.renderObject is RenderDecoratedBox &&
            ((element.renderObject as RenderDecoratedBox).decoration
                        as BoxDecoration)
                    .boxShadow !=
                null,
      ),
    ),
  );
  return (decoration.decoration as BoxDecoration).boxShadow!.single.color;
}

void main() {
  for (final effect in ['morale', 'hp bar', 'hp number']) {
    testWidgets(
      'minimal $effect does not repaint its portrait or neighbouring row',
      (tester) async {
        final client = http.Client();
        addTearDown(client.close);
        final cache = _PortraitCache(client);
        final provider = MemoryImage(
          File('assets/images/material/01.png').readAsBytesSync(),
        );
        late BuildContext imageContext;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                imageContext = context;
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.runAsync(() => precacheImage(provider, imageContext));
        await tester.pump();
        var portraitPaints = 0;
        var neighbourPaints = 0;
        var rowLayouts = 0;
        final morale = effect == 'morale';
        final row = FleetShipMinimalRow(
          state: _state,
          ship: OwnedShip(
            id: 1,
            masterId: 1,
            level: 1,
            condition: morale ? 85 : 49,
            currentHp: morale ? 100 : 20,
            maxHp: 100,
          ),
          visible: {
            if (morale) 'morale' else 'hp',
            if (effect == 'hp bar') 'bars',
          },
          shipTypeLabelMode: FleetShipTypeLabelMode.localizedName,
          damagePulseFilter: DamagePulseFilter.heavyOnly,
          moraleSparkleMode: morale
              ? MoraleSparkleMode.blinking
              : MoraleSparkleMode.off,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                // Matches the shared card boundary supplied by ListView or HD masonry.
                child: RepaintBoundary(
                  child: SizedBox(
                    width: 320,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FlatPortraitBackdrop(
                          image: (width, height) => _PaintProbe(
                            onPaint: () => portraitPaints++,
                            child: ShipPortrait(
                              ship: _master,
                              serverOrigin: 'https://example.test',
                              width: width,
                              height: height,
                              cache: cache,
                              fileImageProviderBuilder: (_, _) => provider,
                            ),
                          ),
                          child: _PaintProbe(
                            onPaint: () {},
                            onLayout: () => rowLayouts++,
                            child: row,
                          ),
                        ),
                        _PaintProbe(
                          onPaint: () => neighbourPaints++,
                          child: const SizedBox(
                            height: 40,
                            child: ColoredBox(color: Colors.blue),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        final portraitBefore = portraitPaints;
        final neighbourBefore = neighbourPaints;
        final layoutsBefore = rowLayouts;
        final colors = {_shadowColor(tester, morale: morale)};
        final size = tester.getSize(find.byType(FleetShipMinimalRow));
        for (var frame = 0; frame < 10; frame++) {
          await tester.pump(const Duration(milliseconds: 50));
          colors.add(_shadowColor(tester, morale: morale));
          expect(tester.getSize(find.byType(FleetShipMinimalRow)), size);
        }
        expect(
          colors.length,
          greaterThan(1),
          reason: 'the same visible effect must keep animating',
        );
        expect(cache.resolves, 1);
        expect(
          rowLayouts - layoutsBefore,
          0,
          reason: 'effect ticks must not request surrounding row layout',
        );
        expect(
          portraitPaints - portraitBefore,
          0,
          reason: 'static portrait must retain its paint',
        );
        expect(
          neighbourPaints - neighbourBefore,
          0,
          reason: 'static neighbour must retain its paint',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }

  testWidgets(
    'minimal morale keeps its glow outside the chip without changing its size',
    (tester) async {
      final previousDisableShadows = debugDisableShadows;
      debugDisableShadows = false;
      try {
        const captureKey = Key('shadow-capture');
        Widget host(MoraleSparkleMode mode) => MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.transparent,
            body: Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: captureKey,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: MoraleChip(value: 85, sparkleMode: mode),
                ),
              ),
            ),
          ),
        );
        await tester.pumpWidget(host(MoraleSparkleMode.blinking));
        await tester.pump(const Duration(milliseconds: 550));
        final chip = find.byType(MoraleChip);
        final before = tester.getSize(chip);
        final capture = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(captureKey),
        );
        final chipRect = tester
            .getRect(chip)
            .shift(-tester.getTopLeft(find.byKey(captureKey)));
        final x = (chipRect.left - 2).floor();
        final y = chipRect.center.dy.floor();
        final shadowAlpha = await tester.runAsync(() async {
          final image = await capture.toImage(pixelRatio: 1);
          try {
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            return bytes.getUint8((y * image.width + x) * 4 + 3);
          } finally {
            image.dispose();
          }
        });
        expect(
          shadowAlpha,
          greaterThan(0),
          reason: 'the glow outside layout bounds must not be clipped',
        );
        expect(tester.getSize(chip), before);

        await tester.pumpWidget(host(MoraleSparkleMode.steady));
        expect(
          find.descendant(
            of: find.byType(MoraleChip),
            matching: find.byType(RepaintBoundary),
          ),
          findsNothing,
        );
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      } finally {
        debugDisableShadows = previousDisableShadows;
      }
    },
  );
}
