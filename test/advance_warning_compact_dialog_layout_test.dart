import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/account/account_session.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_damage_alert.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/capture/battle_result_warning_overlay.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_controller.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_port.dart';
import 'package:yahagi_kancolle_browser/src/capture/sortie_warning_session.dart';
import 'package:yahagi_kancolle_browser/src/game_state/combat_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/ui_display_size.dart';
import 'package:yahagi_kancolle_browser/src/theme/app_palette.dart';
import 'package:yahagi_kancolle_browser/src/theme/app_theme.dart';

import 'fixtures/kcsapi_fixtures.dart';

const _refreshGame = Key('advanceWarningReloadGame');
const _refreshFrame = Key('advanceWarningReloadFrame');
const _mute = Key('muteCurrentSortieWarning');
const _acknowledge = Key('acknowledgeAdvanceWarning');
const _actionKeys = [_refreshGame, _refreshFrame, _mute, _acknowledge];
Finder get _dialogRouteLayout => find
    .ancestor(
      of: find.byType(AlertDialog),
      matching: find.byType(LayoutBuilder),
    )
    .first;
Finder get _dialogSurface => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.byWidgetPredicate(
    (widget) => widget is Material && widget.type == MaterialType.card,
  ),
);
const _singleShip = [
  _Ship('鵜来', [43]),
];

void main() {
  for (final uiSize in [UiDisplaySize.normal, UiDisplaySize.compact]) {
    testWidgets('$uiSize single ship uses the compact layered arrangement', (
      tester,
    ) async {
      final fixture = await _Fixture.create(tester, uiSize: uiSize);
      await fixture.advance(tester);

      final dialog = tester.getRect(_dialogSurface);
      expect(dialog.width, inInclusiveRange(500, 540));
      expect(dialog.height, lessThanOrEqualTo(340));
      final name = tester.getRect(find.text('鵜来'));
      final equipment = tester.getRect(find.textContaining('应急修理女神 ×1'));
      expect(name.center.dy, closeTo(equipment.center.dy, 3));
      expect(name.right, lessThan(equipment.left));
      expect(find.textContaining('HP'), findsNothing);
      expect(find.textContaining('第1舰队'), findsNothing);
      expect(find.textContaining('2号舰'), findsNothing);
      expect(
        tester.widget<Text>(find.text('鵜来')).style?.fontSize ?? 14,
        greaterThanOrEqualTo(13),
      );

      for (final key in _actionKeys) {
        expect(find.byKey(key).hitTestable(), findsOneWidget);
        expect(
          tester.getSize(find.byKey(key)).height,
          greaterThanOrEqualTo(44),
        );
      }
      final refreshGame = tester.getRect(find.byKey(_refreshGame));
      final refreshFrame = tester.getRect(find.byKey(_refreshFrame));
      final mute = tester.getRect(find.byKey(_mute));
      final acknowledge = tester.getRect(find.byKey(_acknowledge));
      expect(refreshGame.center.dy, closeTo(refreshFrame.center.dy, 1));
      expect(refreshGame.bottom, lessThanOrEqualTo(mute.top));
      expect(refreshFrame.bottom, lessThanOrEqualTo(acknowledge.top));
      expect(mute.center.dy, closeTo(acknowledge.center.dy, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('$uiSize multi-ship danger ordering and colors stay intact', (
      tester,
    ) async {
      final fixture = await _Fixture.create(
        tester,
        uiSize: uiSize,
        ships: const [
          _Ship('鵜来', [42, 43]),
          _Ship('夕立改二', []),
          _Ship('时雨改三', [0]),
          _Ship('夕立改二', [43]),
        ],
      );
      await fixture.advance(tester);

      final missing = find.text('未携带损管');
      final unknown = find.text('损管状态未知，请核对游戏内装备');
      final equipped = find.textContaining('应急修理要员 ×1');
      expect(missing, findsOneWidget);
      expect(unknown, findsOneWidget);
      expect(equipped, findsOneWidget);
      expect(
        tester.getTopLeft(missing).dy,
        lessThan(tester.getTopLeft(unknown).dy),
      );
      expect(
        tester.getTopLeft(unknown).dy,
        lessThan(tester.getTopLeft(equipped).dy),
      );
      expect(tester.widget<Text>(missing).style?.color, Colors.redAccent);
      expect(tester.widget<Text>(unknown).style?.color, Colors.redAccent);
      expect(
        tester.widget<Text>(equipped).style?.color,
        const Color(0xffd4a85f),
      );
      expect(find.textContaining('第1舰队·3号舰'), findsOneWidget);
      expect(find.textContaining('第1舰队·5号舰'), findsOneWidget);
      expect(find.textContaining('第1舰队·2号舰'), findsNothing);
      expect(find.textContaining('第1舰队·4号舰'), findsNothing);
      expect(find.textContaining('HP'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final key in [_refreshGame, _refreshFrame]) {
      testWidgets(
        '$uiSize $key closes before refresh completes and does not mute',
        (tester) async {
          final pending = Completer<void>();
          var gameRefreshes = 0;
          var frameRefreshes = 0;
          final fixture = await _Fixture.create(
            tester,
            uiSize: uiSize,
            onReloadGame: () {
              gameRefreshes++;
              return pending.future;
            },
            onReloadGameFrame: () {
              frameRefreshes++;
              return pending.future;
            },
          );
          await fixture.advance(tester);
          final stateBefore = fixture.state;
          final generationBefore = fixture.session.generation;
          await tester.tap(find.byKey(key));
          await tester.pump();
          expect(pending.isCompleted, isFalse);
          expect(find.byType(AlertDialog), findsNothing);
          expect(gameRefreshes, key == _refreshGame ? 1 : 0);
          expect(frameRefreshes, key == _refreshFrame ? 1 : 0);
          expect(fixture.state, same(stateBefore));
          expect(fixture.session.generation, generationBefore);
          expect(fixture.session.isMuted, isFalse);
          pending.complete();
          await tester.pumpAndSettle();
          await fixture.advance(tester);
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(fixture.session.isMuted, isFalse);
          expect(fixture.state, same(stateBefore));
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final locale in [
      const Locale('zh'),
      const Locale('en'),
      const Locale('ja'),
    ]) {
      for (final viewport in [
        const Size(320, 720),
        const Size(360, 640),
        const Size(740, 320),
      ]) {
        testWidgets(
          '$uiSize $locale $viewport large text stays scrollable and actionable',
          (tester) async {
            final fixture = await _Fixture.create(
              tester,
              uiSize: uiSize,
              locale: locale,
              viewport: viewport,
              textScale: 1.5,
              ships: const [
                _Ship('Very long ship name 时雨改三 しぐれかいさん', [43]),
                _Ship('夕立改二', []),
                _Ship('夕立改二', [0]),
                _Ship('鵜来', [42, 43, 42]),
                _Ship('凉月改', []),
              ],
            );
            await fixture.advance(tester);
            expect(find.byType(AlertDialog), findsOneWidget);
            final dialog = tester.getRect(_dialogSurface);
            expect(dialog.left, greaterThanOrEqualTo(0));
            expect(dialog.right, lessThanOrEqualTo(viewport.width));
            expect(dialog.top, greaterThanOrEqualTo(0));
            expect(dialog.bottom, lessThanOrEqualTo(viewport.height));
            expect(tester.takeException(), isNull);
            final l10n = lookupAppLocalizations(locale);
            expect(find.text(l10n.advanceWarningUnknown), findsOneWidget);
            for (final key in _actionKeys) {
              final action = find.byKey(key);
              expect(action, findsOneWidget);
              await tester.ensureVisible(action);
              await tester.pumpAndSettle();
              expect(
                action.hitTestable(),
                findsOneWidget,
                reason: '$key in $viewport',
              );
              expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
              expect(tester.takeException(), isNull);
            }
            await tester.tap(find.byKey(_acknowledge));
            await tester.pumpAndSettle();
            expect(find.byType(AlertDialog), findsNothing);
            expect(fixture.session.isMuted, isFalse);
            await fixture.advance(tester);
            expect(find.byType(AlertDialog), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    for (final locale in [const Locale('en'), const Locale('ja')]) {
      testWidgets('$uiSize $locale two-times text fits a short landscape', (
        tester,
      ) async {
        final fixture = await _Fixture.create(
          tester,
          uiSize: uiSize,
          locale: locale,
          viewport: const Size(740, 320),
          textScale: 2,
          ships: const [
            _Ship('Very long ship name 时雨改三 しぐれかいさん', [43]),
            _Ship('夕立改二', []),
            _Ship('夕立改二', [0]),
            _Ship('鵜来', [42, 43, 42]),
            _Ship('凉月改', []),
          ],
        );
        await fixture.advance(tester);
        expect(find.byType(AlertDialog), findsOneWidget);
        final surface = tester.getRect(_dialogSurface);
        expect(surface.left, greaterThanOrEqualTo(0));
        expect(surface.right, lessThanOrEqualTo(740));
        expect(surface.top, greaterThanOrEqualTo(0));
        expect(surface.bottom, lessThanOrEqualTo(320));
        expect(
          find.text(lookupAppLocalizations(locale).advanceWarningUnknown),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await _expectActionsReachable(tester);
      });
    }

    testWidgets('$uiSize sea-salt theme preserves narrow unknown warnings', (
      tester,
    ) async {
      final fixture = await _Fixture.create(
        tester,
        uiSize: uiSize,
        themeMode: AppThemeMode.seaSalt,
        viewport: const Size(320, 720),
        textScale: 1.5,
        ships: const [
          _Ship('时雨改三', [0]),
          _Ship('鵜来', [43]),
        ],
      );
      await fixture.advance(tester);
      final unknown = find.text('损管状态未知，请核对游戏内装备');
      final equipped = find.textContaining('应急修理女神 ×1');
      expect(unknown, findsOneWidget);
      expect(equipped, findsOneWidget);
      expect(AppPalette.of(tester.element(unknown)).isDark, isFalse);
      expect(
        tester.widget<Text>(unknown).style?.color,
        appColor<Color>(tester.element(unknown), Colors.redAccent),
      );
      expect(
        tester.widget<Text>(equipped).style?.color,
        appColor(tester.element(equipped), const Color(0xffd4a85f)),
      );
      final surface = tester.getRect(_dialogSurface);
      expect(surface.left, greaterThanOrEqualTo(0));
      expect(surface.right, lessThanOrEqualTo(320));
      expect(surface.top, greaterThanOrEqualTo(0));
      expect(surface.bottom, lessThanOrEqualTo(720));
      expect(tester.takeException(), isNull);
      await _expectActionsReachable(tester);
    });

    for (final key in [_refreshGame, _refreshFrame]) {
      testWidgets(
        '$uiSize $key survives height boundaries and rotation without losing later danger',
        (tester) async {
          final pending = Completer<void>();
          var gameRefreshes = 0;
          var frameRefreshes = 0;
          final fixture = await _Fixture.create(
            tester,
            uiSize: uiSize,
            locale: const Locale('en'),
            textScale: 1.5,
            ships: const [
              _Ship('Very long ship name 时雨改三 しぐれかいさん', [43]),
              _Ship('夕立改二', []),
              _Ship('夕立改二', [0]),
              _Ship('鵜来', [42, 43, 42]),
              _Ship('凉月改', []),
            ],
            onReloadGame: () {
              gameRefreshes++;
              return pending.future;
            },
            onReloadGameFrame: () {
              frameRefreshes++;
              return pending.future;
            },
          );
          await fixture.advance(tester);
          final initialDialog = tester.element(find.byType(AlertDialog));
          for (final viewport in [
            const Size(1100, 850),
            const Size(740, 400),
            const Size(740, 399),
            const Size(740, 320),
            const Size(360, 740),
            const Size(1100, 850),
            const Size(740, 399),
          ]) {
            tester.view.physicalSize = viewport;
            await tester.pumpAndSettle();
            expect(find.byType(AlertDialog), findsOneWidget);
            expect(
              tester.element(find.byType(AlertDialog)),
              same(initialDialog),
            );
            final surface = tester.getRect(_dialogSurface);
            expect(surface.left, greaterThanOrEqualTo(0));
            expect(surface.right, lessThanOrEqualTo(viewport.width));
            expect(surface.top, greaterThanOrEqualTo(0));
            expect(surface.bottom, lessThanOrEqualTo(viewport.height));
            expect(tester.takeException(), isNull);
            await _expectActionsReachable(tester);
          }

          final stateBefore = fixture.state;
          final generationBefore = fixture.session.generation;
          await tester.ensureVisible(find.byKey(key));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(key));
          await tester.pump();
          expect(pending.isCompleted, isFalse);
          expect(find.byType(AlertDialog), findsNothing);
          expect(gameRefreshes, key == _refreshGame ? 1 : 0);
          expect(frameRefreshes, key == _refreshFrame ? 1 : 0);
          expect(fixture.session.isMuted, isFalse);
          expect(fixture.session.generation, generationBefore);
          expect(fixture.state, same(stateBefore));

          await fixture.advance(tester);
          expect(pending.isCompleted, isFalse);
          expect(find.byType(AlertDialog), findsOneWidget);
          final newerDialog = tester.element(find.byType(AlertDialog));
          expect(newerDialog, isNot(same(initialDialog)));
          await _expectActionsReachable(tester);
          pending.complete();
          await tester.pumpAndSettle();
          expect(tester.element(find.byType(AlertDialog)), same(newerDialog));
          expect(fixture.session.isMuted, isFalse);
          expect(fixture.state, same(stateBefore));
          await tester.tap(find.byKey(_acknowledge));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          await fixture.advance(tester);
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(fixture.session.isMuted, isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final key in [_refreshGame, _refreshFrame]) {
      testWidgets(
        '$uiSize $key respects nonzero safe-area and keyboard insets across height boundaries',
        (tester) async {
          const viewPadding = EdgeInsets.fromLTRB(28, 24, 18, 18);
          const viewInsets = EdgeInsets.only(bottom: 96);
          final pendingRefreshes = <Completer<void>>[];
          var gameRefreshes = 0;
          var frameRefreshes = 0;
          final fixture = await _Fixture.create(
            tester,
            uiSize: uiSize,
            locale: const Locale('en'),
            textScale: 2,
            viewPadding: viewPadding,
            viewInsets: viewInsets,
            viewport: const Size(740, 519),
            ships: const [
              _Ship('Very long ship name 时雨改三 しぐれかいさん', [43]),
              _Ship('夕立改二', []),
              _Ship('夕立改二', [0]),
              _Ship('鵜来', [42, 43, 42]),
              _Ship('凉月改', []),
            ],
            onReloadGame: () {
              gameRefreshes++;
              final pending = Completer<void>();
              pendingRefreshes.add(pending);
              return pending.future;
            },
            onReloadGameFrame: () {
              frameRefreshes++;
              final pending = Completer<void>();
              pendingRefreshes.add(pending);
              return pending.future;
            },
          );
          final stateBefore = fixture.state;
          var expectedRefreshes = 0;
          for (final effectiveHeight in [399.0, 400.0]) {
            final viewport = Size(
              740,
              effectiveHeight + viewPadding.top + viewInsets.bottom,
            );
            tester.view.physicalSize = viewport;
            await tester.pumpAndSettle();
            await fixture.advance(tester);
            final generationBefore = fixture.session.generation;
            expect(find.byType(AlertDialog), findsOneWidget);
            expect(
              tester.getSize(_dialogRouteLayout).height,
              effectiveHeight + viewInsets.bottom,
            );
            expect(
              tester.getSize(find.byType(AlertDialog)).height,
              effectiveHeight,
            );
            expect(
              MediaQuery.viewInsetsOf(tester.element(find.byType(AlertDialog))),
              EdgeInsets.zero,
            );
            expect(
              tester.getSize(find.byType(AlertDialog)).width,
              viewport.width - viewPadding.horizontal,
            );
            final surface = tester.getRect(_dialogSurface);
            expect(surface.left, greaterThanOrEqualTo(viewPadding.left));
            expect(
              surface.right,
              lessThanOrEqualTo(viewport.width - viewPadding.right),
            );
            expect(surface.top, greaterThanOrEqualTo(viewPadding.top));
            expect(
              surface.bottom,
              lessThanOrEqualTo(viewport.height - viewInsets.bottom),
            );
            expect(tester.takeException(), isNull);
            await _expectActionsReachable(tester);
            await tester.ensureVisible(find.byKey(key));
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(key));
            await tester.pump();
            expectedRefreshes++;
            expect(pendingRefreshes.length, expectedRefreshes);
            expect(pendingRefreshes.last.isCompleted, isFalse);
            expect(find.byType(AlertDialog), findsNothing);
            expect(gameRefreshes, key == _refreshGame ? expectedRefreshes : 0);
            expect(
              frameRefreshes,
              key == _refreshFrame ? expectedRefreshes : 0,
            );
            expect(fixture.session.isMuted, isFalse);
            expect(fixture.session.generation, generationBefore);
            expect(fixture.state, same(stateBefore));

            await fixture.advance(tester);
            expect(find.byType(AlertDialog), findsOneWidget);
            final newerDialog = tester.element(find.byType(AlertDialog));
            pendingRefreshes.last.complete();
            await tester.pumpAndSettle();
            expect(tester.element(find.byType(AlertDialog)), same(newerDialog));
            await _expectActionsReachable(tester);
            await tester.tap(find.byKey(_acknowledge));
            await tester.pumpAndSettle();
            expect(find.byType(AlertDialog), findsNothing);
            expect(fixture.session.isMuted, isFalse);
          }

          await fixture.advance(tester);
          await tester.ensureVisible(find.byKey(_mute));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(_mute));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(fixture.session.isMuted, isTrue);
          await fixture.advance(tester);
          expect(find.byType(AlertDialog), findsNothing);
          fixture.session.startSortie();
          await fixture.advance(tester);
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(fixture.session.isMuted, isFalse);
          expect(fixture.state, same(stateBefore));
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      '$uiSize tall window with a large keyboard keeps actions reachable',
      (tester) async {
        final fixture = await _Fixture.create(
          tester,
          uiSize: uiSize,
          locale: const Locale('en'),
          viewport: const Size(740, 650),
          textScale: 2,
          viewPadding: const EdgeInsets.fromLTRB(28, 24, 18, 18),
          viewInsets: const EdgeInsets.only(bottom: 350),
          ships: const [
            _Ship('Very long ship name 时雨改三 しぐれかいさん', [43]),
            _Ship('夕立改二', []),
            _Ship('夕立改二', [0]),
            _Ship('鵜来', [42, 43, 42]),
            _Ship('凉月改', []),
          ],
        );
        await fixture.advance(tester);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(tester.getSize(_dialogRouteLayout).height, 626);
        expect(tester.getSize(find.byType(AlertDialog)).height, 276);
        expect(
          MediaQuery.viewInsetsOf(tester.element(find.byType(AlertDialog))),
          EdgeInsets.zero,
        );
        final surface = tester.getRect(_dialogSurface);
        expect(surface.top, greaterThanOrEqualTo(24));
        expect(surface.bottom, lessThanOrEqualTo(300));
        expect(tester.takeException(), isNull);
        await _expectActionsReachable(tester);
      },
    );

    testWidgets(
      '$uiSize keyboard hiding animation keeps the same modal usable',
      (tester) async {
        final pendingRefreshes = <Completer<void>>[];
        var gameRefreshes = 0;
        var frameRefreshes = 0;
        final fixture = await _Fixture.create(
          tester,
          uiSize: uiSize,
          locale: const Locale('en'),
          viewport: const Size(740, 650),
          textScale: 2,
          viewPadding: const EdgeInsets.fromLTRB(28, 24, 18, 18),
          viewInsets: const EdgeInsets.only(bottom: 350),
          ships: const [
            _Ship('Very long ship name 时雨改三 しぐれかいさん', [43]),
            _Ship('夕立改二', []),
            _Ship('夕立改二', [0]),
            _Ship('鵜来', [42, 43, 42]),
            _Ship('凉月改', []),
          ],
          onReloadGame: () {
            gameRefreshes++;
            final pending = Completer<void>();
            pendingRefreshes.add(pending);
            return pending.future;
          },
          onReloadGameFrame: () {
            frameRefreshes++;
            final pending = Completer<void>();
            pendingRefreshes.add(pending);
            return pending.future;
          },
        );
        await fixture.advance(tester);
        final initialDialog = tester.element(find.byType(AlertDialog));
        expect(tester.takeException(), isNull);
        fixture.viewInsets.value = EdgeInsets.zero;
        var elapsedMilliseconds = 0;
        for (final deltaMilliseconds in [0, 16, 34, 50]) {
          elapsedMilliseconds += deltaMilliseconds;
          await tester.pump(Duration(milliseconds: deltaMilliseconds));
          expect(
            tester.takeException(),
            isNull,
            reason: 'Keyboard hiding at ${elapsedMilliseconds}ms',
          );
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(tester.element(find.byType(AlertDialog)), same(initialDialog));
          for (final key in _actionKeys) {
            expect(find.byKey(key), findsOneWidget);
          }
        }
        await tester.pumpAndSettle();
        await _expectActionsReachable(tester);
        for (final key in [_refreshGame, _refreshFrame]) {
          final stateBefore = fixture.state;
          final generationBefore = fixture.session.generation;
          await tester.ensureVisible(find.byKey(key));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(key));
          await tester.pump();
          expect(find.byType(AlertDialog), findsNothing);
          expect(pendingRefreshes.last.isCompleted, isFalse);
          expect(fixture.session.isMuted, isFalse);
          expect(fixture.session.generation, generationBefore);
          expect(fixture.state, same(stateBefore));
          pendingRefreshes.last.complete();
          await tester.pumpAndSettle();
          await fixture.advance(tester);
          expect(find.byType(AlertDialog), findsOneWidget);
          await _expectActionsReachable(tester);
        }
        expect(gameRefreshes, 1);
        expect(frameRefreshes, 1);
        await tester.tap(find.byKey(_acknowledge));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(fixture.session.isMuted, isFalse);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$uiSize open multi-ship warning removes depleted gold details',
      (tester) async {
        final fixture = await _Fixture.create(
          tester,
          uiSize: uiSize,
          ships: const [
            _Ship('鵜来', [42, 43]),
            _Ship('夕立改二', [42]),
            _Ship('时雨改三', [43]),
          ],
        );
        await fixture.advance(tester);
        final initialDialog = tester.element(find.byType(AlertDialog));
        expect(find.text('大破舰娘已携带损管，请确认剩余装备。'), findsOneWidget);
        expect(find.textContaining('携带：'), findsNWidgets(3));

        fixture.state = _state(const [
          _Ship('鵜来', []),
          _Ship('夕立改二', []),
          _Ship('时雨改三', []),
        ]);
        await fixture.advance(tester);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(tester.element(find.byType(AlertDialog)), same(initialDialog));
        expect(find.text('存在未携带损管的大破舰娘！'), findsOneWidget);
        expect(find.text('未携带损管'), findsNWidgets(3));
        expect(find.textContaining('携带：'), findsNothing);
        expect(find.textContaining('应急修理'), findsNothing);
        expect(find.text('大破舰娘已携带损管，请确认剩余装备。'), findsNothing);

        fixture.state = _state(const [
          _Ship('鵜来', [0]),
          _Ship('夕立改二', []),
          _Ship('时雨改三', [0]),
        ]);
        await fixture.advance(tester);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(tester.element(find.byType(AlertDialog)), same(initialDialog));
        expect(find.text('未携带损管'), findsOneWidget);
        final unknown = find.text('损管状态未知，请核对游戏内装备');
        expect(unknown, findsNWidgets(2));
        for (final text in tester.widgetList<Text>(unknown)) {
          expect(text.style?.color, Colors.redAccent);
        }
        expect(find.textContaining('携带：'), findsNothing);
        expect(find.textContaining('应急修理'), findsNothing);
        expect(find.text('大破舰娘已携带损管，请确认剩余装备。'), findsNothing);
        expect(find.text('大破舰已携带损管'), findsNothing);
        await _expectActionsReachable(tester);
        await tester.tap(find.byKey(_acknowledge));
        await tester.pumpAndSettle();
        await fixture.advance(tester);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(unknown, findsNWidgets(2));
        expect(find.textContaining('应急修理'), findsNothing);
        expect(fixture.session.isMuted, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _expectActionsReachable(WidgetTester tester) async {
  for (final key in _actionKeys) {
    final action = find.byKey(key);
    expect(action, findsOneWidget);
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    expect(
      action.hitTestable(),
      findsOneWidget,
      reason:
          '$key bounds=${tester.getRect(action)} scroll=${find.byType(SingleChildScrollView).evaluate().map((element) => tester.getRect(find.byElementPredicate((candidate) => identical(candidate, element)))).toList()}',
    );
    expect(tester.getSize(action).height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
  }
}

class _Ship {
  const _Ship(this.name, this.equipment);
  final String name;
  final List<int> equipment;
}

GameState _state(List<_Ship> specs) => GameState(
  memberId: 1001,
  hasEquipmentInventory: true,
  masterShips: {
    1: const MasterShip(id: 1, name: '旗舰', shipTypeId: 2),
    for (var index = 0; index < specs.length; index++)
      index + 2: MasterShip(
        id: index + 2,
        name: specs[index].name,
        shipTypeId: 2,
      ),
  },
  ships: {
    1: const OwnedShip(id: 1, masterId: 1, level: 99, currentHp: 20, maxHp: 20),
    for (var index = 0; index < specs.length; index++)
      index + 2: OwnedShip(
        id: index + 2,
        masterId: index + 2,
        level: 99,
        currentHp: 5,
        maxHp: 20,
        slotIds: [
          for (var slot = 0; slot < specs[index].equipment.length; slot++)
            1000 + index * 10 + slot,
        ],
      ),
  },
  slotItems: {
    for (var index = 0; index < specs.length; index++)
      for (var slot = 0; slot < specs[index].equipment.length; slot++)
        if (specs[index].equipment[slot] > 0)
          1000 + index * 10 + slot: OwnedSlotItem(
            instanceId: 1000 + index * 10 + slot,
            masterSlotItemId: specs[index].equipment[slot],
          ),
  },
  fleets: [
    Fleet(
      id: 1,
      name: '第一舰队',
      shipIds: [
        1,
        for (var index = 0; index < specs.length; index++) index + 2,
      ],
    ),
  ],
  combatState: const CombatState(sortieFleetId: 1, isActive: true),
);

class _Fixture {
  _Fixture(
    this.account,
    this.capture,
    this.port,
    this.settings,
    this.state,
    EdgeInsets initialViewInsets,
  ) : viewInsets = ValueNotifier(initialViewInsets);
  final AccountSession account;
  final GameCaptureController capture;
  final _CapturePort port;
  final SafetySettingsController settings;
  final SortieWarningSession session = SortieWarningSession();
  final ValueNotifier<EdgeInsets> viewInsets;
  GameState state;
  int sequence = 0;

  static Future<_Fixture> create(
    WidgetTester tester, {
    required UiDisplaySize uiSize,
    List<_Ship> ships = _singleShip,
    Locale locale = const Locale('zh'),
    AppThemeMode themeMode = AppThemeMode.dark,
    Size viewport = const Size(1100, 850),
    double textScale = 1,
    EdgeInsets viewPadding = EdgeInsets.zero,
    EdgeInsets viewInsets = EdgeInsets.zero,
    Future<void> Function()? onReloadGame,
    Future<void> Function()? onReloadGameFrame,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = viewport;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final account = AccountSession(initialMemberId: 1001);
    final capture = GameCaptureController();
    final port = _CapturePort();
    await capture.attach(port, enabled: true);
    final settings = await SafetySettingsController.load(
      MemorySafetySettingsStore(),
    );
    final fixture = _Fixture(
      account,
      capture,
      port,
      settings,
      _state(ships),
      viewInsets,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      fixture.session.dispose();
      fixture.viewInsets.dispose();
      settings.dispose();
      capture.dispose();
      port.dispose();
      account.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: createAppTheme(mode: themeMode),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => ValueListenableBuilder<EdgeInsets>(
          valueListenable: fixture.viewInsets,
          builder: (context, currentInsets, _) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              boldText: true,
              viewPadding: viewPadding,
              viewInsets: currentInsets,
              padding: EdgeInsets.fromLTRB(
                math.max(0, viewPadding.left - currentInsets.left),
                math.max(0, viewPadding.top - currentInsets.top),
                math.max(0, viewPadding.right - currentInsets.right),
                math.max(0, viewPadding.bottom - currentInsets.bottom),
              ),
            ),
            child: child!,
          ),
        ),
        home: Column(
          children: [
            SizedBox(
              height: topHeaderHeight(uiSize),
              child: Center(
                child: SizedBox(
                  height: headerCapsuleHeight(uiSize),
                  child: const Text('顶栏'),
                ),
              ),
            ),
            Expanded(
              child: BattleResultWarningOverlay(
                accountSession: account,
                gameCaptureController: capture,
                warningSession: fixture.session,
                loadSafetyState: () async => fixture.state,
                damageControlStateTrusted: () => true,
                safetySettingsController: settings,
                damageAlertPort: const _AlertPort(),
                onReloadGame: onReloadGame ?? () async {},
                onReloadGameFrame: onReloadGameFrame ?? () async {},
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
    return fixture;
  }

  Future<void> advance(WidgetTester tester) async {
    port.add(
      kcsapiEvent('/kcsapi/api_req_map/next', const {}, sequence: ++sequence),
    );
    await tester.pumpAndSettle();
  }
}

class _AlertPort implements BattleDamageAlertPort {
  const _AlertPort();
  @override
  Future<void> alert(BattleDamageAlertSeverity severity) async {}
}

class _CapturePort implements GameCapturePort {
  final _events = StreamController<CapturedApiEvent>.broadcast(sync: true);
  @override
  Stream<CapturedApiEvent> get events => _events.stream;
  void add(CapturedApiEvent event) => _events.add(event);
  @override
  Future<void> configure({
    required bool enabled,
    required String script,
  }) async {}
  @override
  Future<bool> isSupported() async => true;
  @override
  void dispose() => unawaited(_events.close());
}
