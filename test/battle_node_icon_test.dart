import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_models.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_node_icon.dart';

const _friendArrow = Color(0xff4aa8ff);
const _enemyArrow = Color(0xffff5d4d);
const _battleFill = Color(0xffa8281f);
const _nightFill = Color(0xff6d4bd8);

void main() {
  Future<void> pumpIcon(WidgetTester tester, BattleContext context) =>
      tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(child: BattleNodeIcon(nodeContext: context)),
          ),
        ),
      );

  RenderObject painterOf(WidgetTester tester) => tester.renderObject(
    find.descendant(
      of: find.byType(BattleNodeIcon),
      matching: find.byType(CustomPaint),
    ),
  );

  testWidgets('long press reveals the node type the icon stands for', (
    tester,
  ) async {
    await pumpIcon(tester, const BattleContext(eventId: 4, eventKind: 4));

    await tester.longPress(find.byType(BattleNodeIcon));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('航空战'), findsOneWidget);
  });

  testWidgets('air battle draws both sides arrows, air raid only the enemy', (
    tester,
  ) async {
    await pumpIcon(tester, const BattleContext(eventId: 4, eventKind: 4));
    expect(
      painterOf(tester),
      paints
        ..path(color: _enemyArrow)
        ..path(color: _enemyArrow)
        ..path(color: _friendArrow)
        ..path(color: _friendArrow),
    );

    await pumpIcon(tester, const BattleContext(eventId: 4, eventKind: 6));
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
    await pumpIcon(tester, const BattleContext(eventId: 5, eventKind: 2));

    expect(
      painterOf(tester),
      paints
        ..path(color: _enemyArrow)
        ..path(color: _enemyArrow)
        ..circle(color: _nightFill),
    );
  });

  group('submarine battle', () {
    const submarine = BattleContext(
      eventId: 4,
      eventKind: 1,
      nodeTypeOverride: '潜艇战',
    );

    testWidgets('shows the anti-sub ring without the air raid arrow', (
      tester,
    ) async {
      await pumpIcon(tester, submarine);

      expect(
        painterOf(tester),
        paints
          ..circle(color: _battleFill)
          ..circle(color: _friendArrow),
      );
      expect(painterOf(tester), paintsExactlyCountTimes(#drawPath, 0));
    });

    testWidgets('anti-sub air raid keeps its arrow over the same ring', (
      tester,
    ) async {
      await pumpIcon(
        tester,
        const BattleContext(eventId: 4, colorNo: 15, nodeTypeOverride: '潜艇战'),
      );

      expect(
        painterOf(tester),
        paints
          ..circle(color: _battleFill)
          ..circle(color: _friendArrow)
          ..path(color: _enemyArrow),
      );
    });

    testWidgets('a night submarine battle keeps the night fill', (
      tester,
    ) async {
      await pumpIcon(
        tester,
        const BattleContext(eventId: 4, eventKind: 2, nodeTypeOverride: '潜艇战'),
      );

      expect(
        painterOf(tester),
        paints
          ..circle(color: _nightFill)
          ..circle(color: _friendArrow),
      );
    });
  });
}
