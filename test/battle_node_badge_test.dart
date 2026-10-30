import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_models.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_node_badge.dart';

const _friendArrow = Color(0xff4aa8ff);
const _enemyArrow = Color(0xffff5d4d);
const _nightFill = Color(0xff6d4bd8);

void main() {
  Future<void> pumpBadge(WidgetTester tester, BattleContext context) =>
      tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(child: BattleNodeBadge(nodeContext: context)),
          ),
        ),
      );

  RenderObject painterOf(WidgetTester tester) => tester.renderObject(
    find.descendant(
      of: find.byType(BattleNodeBadge),
      matching: find.byKey(const Key('battle-node-badge-mark')),
    ),
  );

  testWidgets('shows the node letter over the mark', (tester) async {
    await pumpBadge(
      tester,
      const BattleContext(eventId: 4, nodeDisplayLabel: 'E'),
    );

    expect(find.text('E'), findsOneWidget);
    expect(
      tester.getCenter(find.text('E')),
      tester.getCenter(find.byType(BattleNodeBadge)),
    );
  });

  testWidgets('a long node name shrinks to stay inside the badge', (
    tester,
  ) async {
    await pumpBadge(
      tester,
      const BattleContext(eventId: 4, nodeDisplayLabel: 'ZZ3'),
    );

    expect(tester.takeException(), isNull);
    final badge = tester.getRect(find.byType(BattleNodeBadge));
    final letter = tester.getRect(find.text('ZZ3'));
    expect(letter.left, greaterThanOrEqualTo(badge.left));
    expect(letter.right, lessThanOrEqualTo(badge.right));
  });

  testWidgets('long press reveals the node type the mark stands for', (
    tester,
  ) async {
    await pumpBadge(
      tester,
      const BattleContext(eventId: 4, eventKind: 4, nodeDisplayLabel: 'E'),
    );

    await tester.longPress(find.byType(BattleNodeBadge));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('航空战'), findsOneWidget);
  });

  testWidgets('air battle draws both sides arrows, air raid only the enemy', (
    tester,
  ) async {
    await pumpBadge(tester, const BattleContext(eventId: 4, eventKind: 4));
    expect(
      painterOf(tester),
      paints
        ..path(color: _enemyArrow)
        ..path(color: _enemyArrow)
        ..path(color: _friendArrow)
        ..path(color: _friendArrow),
    );

    await pumpBadge(tester, const BattleContext(eventId: 4, eventKind: 6));
    expect(
      painterOf(tester),
      paints
        ..path(color: _enemyArrow)
        ..path(color: _enemyArrow),
    );
    expect(painterOf(tester), paintsExactlyCountTimes(#drawPath, 2));
  });

  testWidgets('a night boss keeps the night fill under its horns', (
    tester,
  ) async {
    await pumpBadge(tester, const BattleContext(eventId: 5, eventKind: 2));

    expect(
      painterOf(tester),
      paints
        ..path(color: _enemyArrow)
        ..path(color: _enemyArrow)
        ..circle(color: _nightFill),
    );
  });
}
