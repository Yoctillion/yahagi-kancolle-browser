import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_controller.dart';
import 'package:yahagi_kancolle_browser/src/battle/live_battle_card.dart';
import 'package:yahagi_kancolle_browser/src/battle/prediction/battle_prediction_executor.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_reducer.dart';

import 'fixtures/kcsapi_fixtures.dart';

const _warningKey = Key('battle-unconfirmed-warning');

void main() {
  for (final language in ['zh', 'en', 'ja']) {
    testWidgets('first captured battle parse error is visible in $language', (
      tester,
    ) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      controller.accept(
        kcsapiEvent('/kcsapi/api_req_sortie/battle', null, sequence: 901),
      );
      await controller.idle;
      expect(controller.current, isNull);
      expect(controller.lastError, isNotNull);

      final locale = Locale(language);
      await _mount(tester, controller, locale: locale);

      expect(find.byKey(_warningKey), findsOneWidget);
      expect(
        find.text(lookupAppLocalizations(locale).battlePredictionUnconfirmed),
        findsOneWidget,
      );
      expect(
        find.text(controller.lastError!),
        findsNothing,
        reason: 'Internal parser diagnostics must not replace localized UI.',
      );
    });
  }

  testWidgets('ordinary empty waiting state has no warning', (tester) async {
    final controller = _controller();
    addTearDown(controller.dispose);

    await _mount(tester, controller);

    expect(controller.isPredictionConfirmed, isTrue);
    expect(find.byKey(_warningKey), findsNothing);
    expect(
      find.text(
        lookupAppLocalizations(const Locale('en')).waitingForSortieData,
      ),
      findsOneWidget,
    );
  });

  testWidgets('empty partial battle still shows an unconfirmed warning', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    // A captured battle without a live fleet snapshot is an unconfirmed
    // partial session, even when no exception was thrown.
    controller.accept(dayBattleEvent);
    await controller.idle;
    expect(controller.current, isNotNull);
    expect(controller.current!.friendShips, isEmpty);
    expect(controller.isPredictionConfirmed, isFalse);

    await _mount(tester, controller);

    expect(find.byKey(_warningKey), findsOneWidget);
  });

  testWidgets('collapsed card reveals a retained error when expanded', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    controller.accept(
      kcsapiEvent('/kcsapi/api_req_sortie/battle', null, sequence: 901),
    );
    await controller.idle;

    await _mount(tester, controller, collapsed: true);
    expect(find.byKey(_warningKey), findsNothing);
    await _mount(tester, controller);

    expect(find.byKey(_warningKey), findsOneWidget);
  });

  testWidgets('successful port and battle recovery remove the old error', (
    tester,
  ) async {
    final reducer = GameStateReducer();
    var state = reducer.reduce(GameState.empty, start2Event);
    state = reducer.reduce(state, portEvent);
    final controller = _controller(state: state);
    addTearDown(controller.dispose);
    controller.accept(
      kcsapiEvent('/kcsapi/api_req_sortie/battle', null, sequence: 901),
    );
    await controller.idle;
    await _mount(tester, controller);
    expect(find.byKey(_warningKey), findsOneWidget);

    controller.accept(portEvent);
    await controller.idle;
    await tester.pump();
    await tester.pump();
    expect(controller.lastError, isNull);
    expect(find.byKey(_warningKey), findsNothing);

    controller
      ..accept(mapStartEvent)
      ..accept(dayBattleEvent);
    await controller.idle;
    await tester.pump();
    await tester.pump();

    expect(controller.current!.friendMain.first.currentHp, 18);
    expect(controller.isPredictionConfirmed, isTrue);
    expect(find.byKey(_warningKey), findsNothing);
  });
}

BattleController _controller({GameState state = GameState.empty}) =>
    BattleController(
      gameState: () => state,
      predictionExecutor: const ImmediateBattlePredictionExecutor(),
    );

Future<void> _mount(
  WidgetTester tester,
  BattleController controller, {
  Locale locale = const Locale('en'),
  bool collapsed = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: LiveBattleCard(
            controller: controller,
            collapsed: collapsed,
            onToggleCollapse: () {},
            showEnemyPortraits: false,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
