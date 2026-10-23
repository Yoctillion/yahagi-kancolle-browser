import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_models.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_ship_details_popover.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_mouse_wheel_region.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/layout/camera_avoidance.dart';
import 'package:yahagi_kancolle_browser/src/logbook/logbook_database.dart';
import 'package:yahagi_kancolle_browser/src/logbook/logbook_page.dart';
import 'package:yahagi_kancolle_browser/src/widgets/top_notice.dart';

DisplayFeature _cutout(Rect bounds) => DisplayFeature(
  bounds: bounds,
  type: DisplayFeatureType.cutout,
  state: DisplayFeatureState.unknown,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final scenario in [
    (name: 'top', cutout: const Rect.fromLTWH(180, 0, 40, 30)),
    (name: 'left', cutout: const Rect.fromLTWH(0, 350, 30, 40)),
    (name: 'right', cutout: const Rect.fromLTWH(370, 350, 30, 40)),
    (name: 'bottom', cutout: const Rect.fromLTWH(180, 770, 40, 30)),
  ]) {
    testWidgets(
      'real logbook filter stays attached and tappable with ${scenario.name} camera margin',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(400, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final database = await LogbookDatabase.openForTesting();
        addTearDown(database.close);
        final controller = BattleController(gameState: () => GameState.empty);
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQueryData(
                size: const Size(400, 800),
                displayFeatures: [_cutout(scenario.cutout)],
              ),
              child: CameraAvoidanceViewport(
                enabled: true,
                distance: 48,
                child: child!,
              ),
            ),
            home: Scaffold(
              body: LogbookPage(
                battleController: controller,
                database: database,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final button = find.byKey(const Key('logbook-filter-button'));
        final buttonBounds = tester.getRect(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        final panel = find.byKey(const Key('logbook-filter-panel'));
        expect(panel, findsOneWidget);
        expect(
          tester.getRect(panel).top,
          closeTo(buttonBounds.bottom + 4, .001),
          reason:
              'The global button and dialog positions must share one origin.',
        );
        await tester.tap(find.byKey(const Key('logbook-filter-apply')));
        await tester.pumpAndSettle();
        expect(panel, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('disabled scope preserves MediaQuery identity and state', (
    tester,
  ) async {
    const media = MediaQueryData(
      size: Size(400, 800),
      padding: EdgeInsets.fromLTRB(12, 30, 16, 24),
      viewPadding: EdgeInsets.fromLTRB(12, 30, 16, 24),
      viewInsets: EdgeInsets.only(bottom: 250),
      systemGestureInsets: EdgeInsets.all(15),
      textScaler: TextScaler.linear(1.2),
    );
    final navigator = GlobalKey<NavigatorState>();
    final probe = GlobalKey<_StateProbeState>();
    late MediaQueryData observed;
    Future<void> pump(bool enabled) => tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => MediaQuery(
          data: media.copyWith(
            displayFeatures: [_cutout(const Rect.fromLTWH(180, 0, 40, 30))],
          ),
          child: Builder(
            builder: (context) {
              final parentMedia = MediaQuery.of(context);
              return CameraAvoidanceViewport(
                enabled: enabled,
                distance: 48,
                child: Builder(
                  builder: (context) {
                    observed = MediaQuery.of(context);
                    if (!enabled) {
                      expect(identical(observed, parentMedia), isTrue);
                    }
                    return child!;
                  },
                ),
              );
            },
          ),
        ),
        home: _StateProbe(key: probe),
      ),
    );
    await pump(false);
    final originalNavigator = navigator.currentState;
    final originalProbe = probe.currentState;
    expect(observed.size, media.size);
    expect(observed.padding, media.padding);
    expect(observed.viewInsets, media.viewInsets);
    await pump(true);
    expect(navigator.currentState, same(originalNavigator));
    expect(probe.currentState, same(originalProbe));
    await pump(false);
    expect(navigator.currentState, same(originalNavigator));
    expect(probe.currentState, same(originalProbe));
  });

  testWidgets(
    'battle OverlayPortal keeps its row anchor when camera side changes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 500);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      const ship = BattleShipSnapshot(
        masterId: 1,
        name: 'Audit ship',
        side: BattleSide.enemy,
        fleetRole: BattleFleetRole.main,
        position: 1,
        initialHp: 30,
        maxHp: 30,
        currentHp: 30,
      );
      final popover = find.byKey(const Key('battle-ship-details-popover'));
      Future<void> pump(List<DisplayFeature> features) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQueryData(
                size: const Size(900, 500),
                displayFeatures: features,
              ),
              child: CameraAvoidanceViewport(
                enabled: true,
                distance: 48,
                child: child!,
              ),
            ),
            home: Scaffold(
              body: BattleShipDetailsHost(
                battle: const LiveBattle(context: BattleContext()),
                child: Stack(
                  children: const [
                    Positioned(
                      left: 100,
                      top: 80,
                      width: 100,
                      height: 40,
                      child: BattleShipDetailsTap(
                        ship: ship,
                        child: SizedBox.expand(key: Key('audit-battle-row')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pump([
        _cutout(const Rect.fromLTWH(400, 0, 40, 30)),
        _cutout(const Rect.fromLTWH(0, 200, 30, 40)),
      ]);
      await tester.tap(
        find.ancestor(
          of: find.byKey(const Key('audit-battle-row')),
          matching: find.byType(InkWell),
        ),
      );
      await tester.pumpAndSettle();
      for (final features in [
        [
          _cutout(const Rect.fromLTWH(400, 0, 40, 30)),
          _cutout(const Rect.fromLTWH(0, 200, 30, 40)),
        ],
        [_cutout(const Rect.fromLTWH(870, 200, 30, 40))],
        <DisplayFeature>[],
      ]) {
        await pump(features);
        expect(popover, findsOneWidget);
        final row = tester.getRect(find.byKey(const Key('audit-battle-row')));
        final bounds = tester.getRect(popover);
        expect(bounds.left, row.right + 8);
        expect(bounds.top, row.top);
      }
      await tester.tap(find.byKey(const Key('battle-ship-details-close')));
      await tester.pumpAndSettle();
      expect(popover, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'notice and game wheel keep global hit positions after top-left inset',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 500);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var taps = 0;
      final scrolls = <GameMouseWheelInput>[];
      late BuildContext noticeContext;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQueryData(
              size: const Size(900, 500),
              displayFeatures: [
                _cutout(const Rect.fromLTWH(400, 0, 40, 30)),
                _cutout(const Rect.fromLTWH(0, 200, 30, 40)),
              ],
            ),
            child: CameraAvoidanceViewport(
              enabled: true,
              distance: 48,
              child: child!,
            ),
          ),
          home: TopNoticeHost(
            child: Builder(
              builder: (context) {
                noticeContext = context;
                return GameMouseWheelRegion(
                  enabled: true,
                  onScroll: scrolls.add,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => taps++,
                    child: const SizedBox.expand(key: Key('audit-game')),
                  ),
                );
              },
            ),
          ),
        ),
      );
      TopNotice.show(noticeContext, message: 'Audit notice');
      await tester.pumpAndSettle();
      final game = tester.getRect(find.byKey(const Key('audit-game')));
      expect(game.topLeft, const Offset(48, 48));
      final notice = tester.getRect(find.byKey(topNoticeKey));
      expect(notice.top, 52);
      await tester.tapAt(notice.center);
      expect(taps, 1, reason: 'The notice must preserve game hit testing.');
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: game.topLeft + Offset(game.width * .25, game.height * .75),
          kind: PointerDeviceKind.mouse,
          scrollDelta: const Offset(0, 120),
        ),
      );
      expect(scrolls, hasLength(1));
      expect(scrolls.single.xRatio, closeTo(.25, .0001));
      expect(scrolls.single.yRatio, closeTo(.75, .0001));
      await tester.tapAt(const Offset(10, 10));
      expect(taps, 1, reason: 'The camera margin must stay outside the game.');
      TopNotice.hide(noticeContext);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

class _StateProbe extends StatefulWidget {
  const _StateProbe({super.key});

  @override
  State<_StateProbe> createState() => _StateProbeState();
}

class _StateProbeState extends State<_StateProbe> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
