import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/main.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/performance/second_tick_scope.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/ui_display_size.dart';
import 'package:yahagi_kancolle_browser/src/theme/app_palette.dart';
import 'package:yahagi_kancolle_browser/src/theme/app_theme.dart';

import 'fixtures/kcsapi_fixtures.dart';

const _listKey = Key('workspace-navigation-list');
const _staticIds = ['game', 'fleet', 'settings'];
const _timedIds = ['expedition', 'construction', 'repair'];

class _NavigationFixture {
  _NavigationFixture(this.layout, this.game);

  final LayoutSettingsController layout;
  final GameStateController game;
  final selected = ValueNotifier<int>(0);
  final visible = ValueNotifier<bool>(true);
  final selections = <int>[];
  DateTime now = DateTime.utc(2026, 9, 11, 12);

  static Future<_NavigationFixture> create({
    UiDisplaySize size = UiDisplaySize.minimal,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final layout = await LayoutSettingsController.load(
      SharedPreferencesLayoutSettingsStore(),
    );
    final game = GameStateController();
    final fixture = _NavigationFixture(layout, game);
    addTearDown(() {
      fixture.selected.dispose();
      fixture.visible.dispose();
      game.dispose();
      layout.dispose();
    });
    await game.initialize();
    await layout.setUiDisplaySize(size);
    return fixture;
  }

  Future<void> accept(String endpoint, Object data) async {
    game.accept(kcsapiEvent('/kcsapi/api_get_member/$endpoint', data));
    await game.idle;
  }

  Future<void> seedActiveTimers() async {
    final finish = now.add(const Duration(seconds: 12)).millisecondsSinceEpoch;
    await accept('kdock', [
      {
        'api_id': 1,
        'api_state': 3,
        'api_created_ship_id': 1,
        'api_complete_time': 0,
      },
      {
        'api_id': 2,
        'api_state': 2,
        'api_created_ship_id': 2,
        'api_complete_time': finish,
      },
    ]);
    await accept('ndock', [
      {
        'api_id': 1,
        'api_state': 1,
        'api_ship_id': 1,
        'api_complete_time': finish,
      },
      {
        'api_id': 2,
        'api_state': 1,
        'api_ship_id': 2,
        'api_complete_time': finish + 60000,
      },
    ]);
    await accept('deck', [
      {
        'api_id': 1,
        'api_mission': [0, 0, 0],
      },
      {
        'api_id': 2,
        'api_mission': [1, 5, finish],
      },
      {
        'api_id': 3,
        'api_mission': [1, 21, finish + 60000],
      },
    ]);
  }

  Widget host({bool hd = false}) => MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SecondTickScope(
        now: () => now,
        child: ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (context, enabled, child) =>
              TickerMode(enabled: enabled, child: child!),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: layout.workspaceMenuHorizontal ? 760 : null,
              height: layout.workspaceMenuHorizontal ? 41 : 590,
              child: ValueListenableBuilder<int>(
                valueListenable: selected,
                builder: (context, selectedIndex, _) => WorkspaceNavigation(
                  controller: layout,
                  gameStateController: game,
                  clock: () => now,
                  selectedIndex: selectedIndex,
                  hd: hd,
                  onRight: false,
                  onSelected: (page) {
                    selections.add(page);
                    selected.value = page;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> tick(WidgetTester tester, {int seconds = 1}) async {
    for (var i = 0; i < seconds; i++) {
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }
  }
}

class _BuildProbe {
  final counts = <Key, int>{};

  void attach() {
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      final key = element.widget.key;
      if (key == _listKey ||
          [
            ..._staticIds,
            ..._timedIds,
          ].any((id) => key == Key('workspace-nav-$id'))) {
        counts.update(key!, (value) => value + 1, ifAbsent: () => 1);
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);
  }

  int count(Key key) => counts[key] ?? 0;
}

Finder _button(String id) => find.byKey(Key('workspace-nav-$id'));

void _expectBadge(String key, String text) => expect(
  find.descendant(of: find.byKey(Key(key)), matching: find.text(text)),
  findsOneWidget,
);

Color? _buttonBackground(WidgetTester tester, String id) => tester
    .widget<IconButton>(
      find.descendant(of: _button(id), matching: find.byType(IconButton)),
    )
    .style!
    .backgroundColor!
    .resolve(const <WidgetState>{});

void main() {
  testWidgets(
    'live cached navigation follows appearance, mode and viewport changes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final semantics = tester.ensureSemantics();
      try {
        final fixture = await _NavigationFixture.create(
          size: UiDisplaySize.normal,
        );
        await fixture.seedActiveTimers();
        final appearance = ValueNotifier((
          locale: const Locale('zh'),
          theme: AppThemeMode.dark,
          textScale: 1.0,
        ));
        addTearDown(appearance.dispose);
        final themes = {
          for (final mode in AppThemeMode.values)
            mode: ThemeData(
              brightness: AppPalette(mode).brightness,
              extensions: [AppPalette(mode)],
            ),
        };

        // Keep the home widget fixed when only inherited appearance changes.
        // Layout preferences rebuild this pane as the real shell does, retaining
        // the same navigation and badge-clock elements throughout the sequence.
        final home = Scaffold(
          body: SecondTickScope(
            now: () => fixture.now,
            child: AnimatedBuilder(
              animation: Listenable.merge([fixture.layout, fixture.selected]),
              builder: (context, _) {
                final horizontal = fixture.layout.workspaceMenuHorizontal;
                final extent = workspaceNavigationExtent(
                  fixture.layout.uiDisplaySize,
                );
                final viewport = MediaQuery.sizeOf(context);
                return Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: horizontal ? viewport.width : extent,
                    height: horizontal ? extent : viewport.height,
                    child: WorkspaceNavigation(
                      controller: fixture.layout,
                      gameStateController: fixture.game,
                      selectedIndex: fixture.selected.value,
                      hd: fixture.layout.hdSettings.enabled,
                      clock: () => fixture.now,
                      onRight: fixture.layout.workspaceMenuOnRight,
                      onSelected: (page) {
                        fixture.selections.add(page);
                        fixture.selected.value = page;
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpWidget(
          ValueListenableBuilder(
            valueListenable: appearance,
            child: home,
            builder: (context, value, child) => MaterialApp(
              locale: value.locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: themes[value.theme],
              builder: (context, appChild) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(value.textScale)),
                child: appChild!,
              ),
              home: child,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final nav = find.byType(WorkspaceNavigation);
        final navElement = tester.element(nav);
        Finder clockFor(String id) => find.descendant(
          of: find.byKey(Key('workspace-nav-item-$id')),
          matching: find.byType(SecondTickBuilder),
        );
        final clockElements = {
          for (final id in _timedIds) id: tester.element(clockFor(id)),
        };
        Finder repairNumber() => find.descendant(
          of: find.byKey(const Key('repair-active-count')),
          matching: find.byType(Text),
        );
        final oldButton = tester.widget(_button('repair'));
        final oldNumberHeight = tester.getSize(repairNumber()).height;
        appearance.value = (
          locale: const Locale('zh'),
          theme: AppThemeMode.dark,
          textScale: 1.3,
        );
        await tester.pumpAndSettle();
        expect(tester.widget(_button('repair')), same(oldButton));
        expect(
          tester.getSize(repairNumber()).height,
          greaterThan(oldNumberHeight * 1.2),
          reason: 'cached buttons must still receive inherited text scaling',
        );

        const steps = [
          (
            mode: UiDisplaySize.normal,
            hd: false,
            size: Size(800, 600),
            position: 'left',
            locale: Locale('zh'),
            theme: AppThemeMode.dark,
            textScale: 1.0,
          ),
          (
            mode: UiDisplaySize.compact,
            hd: false,
            size: Size(360, 800),
            position: 'left',
            locale: Locale('zh'),
            theme: AppThemeMode.seaSalt,
            textScale: 1.3,
          ),
          (
            mode: UiDisplaySize.minimal,
            hd: false,
            size: Size(800, 360),
            position: 'bottom',
            locale: Locale('en'),
            theme: AppThemeMode.skyBlue,
            textScale: 1.3,
          ),
          (
            mode: UiDisplaySize.normal,
            hd: true,
            size: Size(840, 600),
            position: 'bottom',
            locale: Locale('en'),
            theme: AppThemeMode.dark,
            textScale: 1.0,
          ),
          (
            mode: UiDisplaySize.compact,
            hd: true,
            size: Size(600, 840),
            position: 'right',
            locale: Locale('ja'),
            theme: AppThemeMode.seaSalt,
            textScale: 1.3,
          ),
          (
            mode: UiDisplaySize.minimal,
            hd: true,
            size: Size(840, 600),
            position: 'top',
            locale: Locale('ja'),
            theme: AppThemeMode.skyBlue,
            textScale: 1.0,
          ),
          (
            mode: UiDisplaySize.minimal,
            hd: false,
            size: Size(360, 800),
            position: 'left',
            locale: Locale('zh'),
            theme: AppThemeMode.dark,
            textScale: 1.3,
          ),
        ];
        var seconds = 0;
        for (final step in steps) {
          tester.view.physicalSize = step.size;
          await fixture.layout.setUiDisplaySize(step.mode);
          await fixture.layout.setHdEnabled(step.hd);
          await fixture.layout.setWorkspaceMenuPosition(step.position);
          appearance.value = (
            locale: step.locale,
            theme: step.theme,
            textScale: step.textScale,
          );
          await tester.pumpAndSettle();
          expect(tester.element(nav), same(navElement));
          for (final id in _timedIds) {
            expect(tester.element(clockFor(id)), same(clockElements[id]));
          }
          _expectBadge('expedition-active-count', '②');
          _expectBadge('construction-completion-count', '①');
          _expectBadge('repair-active-count', '②');
          final labels = lookupAppLocalizations(step.locale);
          expect(
            tester
                .getSemantics(find.byKey(const Key('repair-active-count')))
                .label,
            contains('${labels.repair}: 2'),
          );

          final horizontal = fixture.layout.workspaceMenuHorizontal;
          final gameRect = tester.getRect(_button('game'));
          final fleetRect = tester.getRect(_button('fleet'));
          expect(
            horizontal ? fleetRect.center.dx : fleetRect.center.dy,
            greaterThan(horizontal ? gameRect.center.dx : gameRect.center.dy),
          );
          expect(
            horizontal ? fleetRect.center.dy : fleetRect.center.dx,
            closeTo(horizontal ? gameRect.center.dy : gameRect.center.dx, .01),
          );
          final icon = tester.widget<Icon>(
            find.descendant(of: _button('fleet'), matching: find.byType(Icon)),
          );
          expect(icon.size, step.mode == UiDisplaySize.normal ? 22 : 20);
          final target = seconds.isEven ? 'repair' : 'fleet';
          final page = target == 'repair' ? 3 : 1;
          await tester.tap(_button(target));
          await tester.pumpAndSettle();
          expect(fixture.selections.last, page);
          expect(
            _buttonBackground(tester, target),
            AppPalette(step.theme).color(const Color(0xff2b2c22)),
          );
          await fixture.tick(tester);
          seconds++;
          expect(tester.takeException(), isNull);
        }
        await fixture.tick(tester, seconds: 12 - seconds);
        _expectBadge('expedition-active-count', '①');
        _expectBadge('construction-completion-count', '②');
        _expectBadge('repair-active-count', '①');
        for (final id in _timedIds) {
          expect(tester.element(clockFor(id)), same(clockElements[id]));
        }

        await fixture.accept('deck', [
          {
            'api_id': 3,
            'api_mission': [0, 0, 0],
          },
        ]);
        await fixture.accept('ndock', [
          {'api_id': 2, 'api_state': 0, 'api_ship_id': 0},
        ]);
        await fixture.accept('kdock', [
          {'api_id': 1, 'api_state': 0},
          {'api_id': 2, 'api_state': 0},
        ]);
        await tester.pump();
        for (final key in [
          'expedition-active-count',
          'construction-completion-count',
          'repair-active-count',
        ]) {
          expect(find.byKey(Key(key)), findsNothing);
        }
        await fixture.tick(tester, seconds: 2);
        for (final key in [
          'expedition-active-count',
          'construction-completion-count',
          'repair-active-count',
        ]) {
          expect(find.byKey(Key(key)), findsNothing);
        }
        await tester.tap(_button('construction'));
        await tester.pumpAndSettle();
        expect(fixture.selections.last, 4);
        expect(tester.element(nav), same(navElement));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        semantics.dispose();
      }
    },
  );

  for (final active in [false, true]) {
    for (final size in UiDisplaySize.values) {
      testWidgets(
        '$size navigation ${active ? 'active' : 'idle'} ticks retain list and buttons for ten seconds',
        (tester) async {
          final fixture = await _NavigationFixture.create(size: size);
          if (active) await fixture.seedActiveTimers();
          final probe = _BuildProbe()..attach();
          await tester.pumpWidget(fixture.host());
          await tester.pumpAndSettle();

          final list = tester.widget(find.byKey(_listKey));
          final before = {
            for (final id in [..._staticIds, ..._timedIds])
              id: tester.widget(_button(id)),
          };
          final countsBefore = Map<Key, int>.from(probe.counts);
          expect(probe.count(_listKey), greaterThan(0));
          if (active) {
            _expectBadge('expedition-active-count', '②');
            _expectBadge('construction-completion-count', '①');
            _expectBadge('repair-active-count', '②');
          }

          for (var second = 0; second < 10; second++) {
            await fixture.tick(tester);
            expect(tester.widget(find.byKey(_listKey)), same(list));
            for (final entry in before.entries) {
              expect(
                tester.widget(_button(entry.key)),
                same(entry.value),
                reason: '${entry.key} changed without a count or data change',
              );
            }
          }
          for (final key in countsBefore.keys) {
            expect(probe.count(key), countsBefore[key], reason: '$key rebuilt');
          }

          if (active) {
            await fixture.tick(tester, seconds: 2);
            _expectBadge('expedition-active-count', '①');
            _expectBadge('construction-completion-count', '②');
            _expectBadge('repair-active-count', '①');
            expect(tester.widget(find.byKey(_listKey)), same(list));
            expect(probe.count(_listKey), countsBefore[_listKey]);
            for (final id in _staticIds) {
              expect(tester.widget(_button(id)), same(before[id]));
              expect(
                probe.count(Key('workspace-nav-$id')),
                countsBefore[Key('workspace-nav-$id')],
              );
            }
            for (final id in _timedIds) {
              expect(tester.widget(_button(id)), isNot(same(before[id])));
              expect(
                probe.count(Key('workspace-nav-$id')),
                greaterThan(countsBefore[Key('workspace-nav-$id')]!),
              );
            }
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('minimal cached badges and selections refresh from new data', (
    tester,
  ) async {
    final fixture = await _NavigationFixture.create();
    await tester.pumpWidget(fixture.host());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('expedition-active-count')), findsNothing);

    await fixture.accept('deck', [
      {
        'api_id': 2,
        'api_mission': [
          1,
          5,
          fixture.now.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
        ],
      },
    ]);
    await tester.pump();
    _expectBadge('expedition-active-count', '①');
    final activeButton = tester.widget(_button('expedition'));
    await fixture.tick(tester, seconds: 10);
    expect(tester.widget(_button('expedition')), same(activeButton));

    await tester.tap(_button('fleet'));
    await tester.pumpAndSettle();
    expect(fixture.selections, [1]);
    expect(_buttonBackground(tester, 'fleet'), const Color(0xff2b2c22));
    expect(_buttonBackground(tester, 'game'), Colors.transparent);
    _expectBadge('expedition-active-count', '①');

    await fixture.accept('deck', [
      {
        'api_id': 2,
        'api_mission': [0, 0, 0],
      },
    ]);
    await tester.pump();
    expect(find.byKey(const Key('expedition-active-count')), findsNothing);
    expect(_buttonBackground(tester, 'fleet'), const Color(0xff2b2c22));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hidden minimal navigation resumes with current deadline counts', (
    tester,
  ) async {
    final fixture = await _NavigationFixture.create();
    await fixture.seedActiveTimers();
    final probe = _BuildProbe()..attach();
    await tester.pumpWidget(fixture.host());
    await tester.pumpAndSettle();
    _expectBadge('expedition-active-count', '②');
    _expectBadge('construction-completion-count', '①');
    _expectBadge('repair-active-count', '②');

    fixture.visible.value = false;
    await tester.pump();
    final countsBefore = Map<Key, int>.from(probe.counts);
    final listBefore = tester.widget(find.byKey(_listKey));
    final buttonsBefore = {
      for (final id in [..._staticIds, ..._timedIds])
        id: tester.widget(_button(id)),
    };
    await fixture.tick(tester, seconds: 20);

    expect(tester.widget(find.byKey(_listKey)), same(listBefore));
    for (final entry in buttonsBefore.entries) {
      expect(tester.widget(_button(entry.key)), same(entry.value));
    }
    for (final key in countsBefore.keys) {
      expect(probe.count(key), countsBefore[key], reason: '$key ticked hidden');
    }

    // Resume without advancing time: overdue counts must be current immediately.
    fixture.visible.value = true;
    await tester.pump();
    _expectBadge('expedition-active-count', '①');
    _expectBadge('construction-completion-count', '②');
    _expectBadge('repair-active-count', '①');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'HD horizontal minimal navigation keeps compact geometry on ticks',
    (tester) async {
      final fixture = await _NavigationFixture.create();
      await fixture.layout.setHdEnabled(true);
      await fixture.layout.setWorkspaceMenuPosition('bottom');
      await fixture.seedActiveTimers();
      final probe = _BuildProbe()..attach();
      await tester.pumpWidget(fixture.host(hd: true));
      await tester.pumpAndSettle();
      final navigation = find.byType(WorkspaceNavigation);
      expect(tester.widget<WorkspaceNavigation>(navigation).hd, isTrue);
      expect(fixture.layout.workspaceMenuHorizontal, isTrue);
      final navigationRect = tester.getRect(navigation);
      expect(navigationRect.size, const Size(760, 41));
      final listBefore = tester.widget(find.byKey(_listKey));
      final staticBefore = {
        for (final id in _staticIds) id: tester.widget(_button(id)),
      };
      final rectsBefore = {
        for (final id in [..._staticIds, ..._timedIds])
          id: tester.getRect(_button(id)),
      };
      final countsBefore = Map<Key, int>.from(probe.counts);
      await fixture.tick(tester, seconds: 10);
      expect(tester.widget(find.byKey(_listKey)), same(listBefore));
      for (final key in countsBefore.keys) {
        expect(probe.count(key), countsBefore[key]);
      }
      await fixture.tick(tester, seconds: 2);
      _expectBadge('expedition-active-count', '①');
      _expectBadge('construction-completion-count', '②');
      _expectBadge('repair-active-count', '①');
      expect(tester.getRect(navigation), navigationRect);
      expect(tester.widget(find.byKey(_listKey)), same(listBefore));
      for (final entry in rectsBefore.entries) {
        expect(tester.getRect(_button(entry.key)), entry.value);
      }
      for (final entry in staticBefore.entries) {
        expect(tester.widget(_button(entry.key)), same(entry.value));
      }
      await tester.tap(_button('construction'));
      await tester.pumpAndSettle();
      expect(fixture.selections, [4]);
      expect(
        _buttonBackground(tester, 'construction'),
        const Color(0xff2b2c22),
      );
      _expectBadge('construction-completion-count', '②');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('minimal navigation still reorders and taps after quiet ticks', (
    tester,
  ) async {
    final fixture = await _NavigationFixture.create();
    await tester.pumpWidget(fixture.host());
    await tester.pumpAndSettle();
    await fixture.tick(tester, seconds: 10);

    final game = _button('game');
    final fleet = _button('fleet');
    final gameItem = find.byKey(const Key('workspace-nav-item-game'));
    final before = tester.getRect(gameItem);
    final gesture = await tester.startGesture(tester.getCenter(game));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    expect(
      find.ancestor(of: gameItem, matching: find.byType(ReorderableListView)),
      findsNothing,
    );
    expect(tester.getRect(gameItem), before);
    await gesture.moveBy(Offset(0, before.height * .85));
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(fixture.layout.workspaceMenuOrder.take(2), ['fleet', 'game']);
    expect(fixture.selections, isEmpty);
    expect(tester.getTopLeft(fleet).dy, lessThan(tester.getTopLeft(game).dy));
    await tester.tap(fleet);
    await tester.pumpAndSettle();
    expect(fixture.selections, [1]);
    expect(_buttonBackground(tester, 'fleet'), const Color(0xff2b2c22));
    await tester.tap(game);
    await tester.pumpAndSettle();
    expect(fixture.selections, [1, 0]);
    expect(_buttonBackground(tester, 'game'), const Color(0xff2b2c22));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
