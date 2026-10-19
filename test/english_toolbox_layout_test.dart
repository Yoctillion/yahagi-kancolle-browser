import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_models.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_pills.dart';
import 'package:yahagi_kancolle_browser/src/battle/land_base_raid_panel.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/sortie_map_query/enemy_catalog.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/sortie_map_query/sortie_enemy_details.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/sortie_map_query/sortie_map_models.dart';

import 'enemy_catalog_test.dart' show enemyCatalogFixture;

Future<void> _openEnemyDialog(
  WidgetTester tester, {
  required Size size,
  required double scale,
  bool longValues = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final rawCatalog = longValues
      ? enemyCatalogFixture
            .replaceFirst('"speed": "低速"', '"speed": "陸上"')
            .replaceFirst('"range": "中"', '"range": "超長+"')
      : enemyCatalogFixture;
  final catalog = EnemyCatalogData.fromJsonString(rawCatalog);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSortieEnemyDetails(
              context,
              entry: const EnemyShipEntry(
                id: 1523,
                nameJa: '軽母ヌ級elite(艦載機黒)',
                nameZh: null,
              ),
              state: GameState.empty,
              catalog: catalog,
            ),
            child: const Text('Open enemy details'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open enemy details'));
  await tester.pumpAndSettle();
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('English long enemy values remain complete at scale $scale', (
      tester,
    ) async {
      await _openEnemyDialog(
        tester,
        size: const Size(320, 700),
        scale: scale,
        longValues: true,
      );
      for (final value in ['Land-based', 'Very long+']) {
        final text = find.text(value);
        expect(text, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(text);
        expect(paragraph.didExceedMaxLines, isFalse, reason: value);
        expect(
          paragraph.size.width + 0.001,
          greaterThanOrEqualTo(paragraph.getMaxIntrinsicWidth(double.infinity)),
          reason: '$value must be laid out without cutting off characters',
        );
        final cell = find
            .ancestor(of: text, matching: find.byType(Column))
            .first;
        final cellRect = tester.getRect(cell);
        final paintedRect = Rect.fromPoints(
          paragraph.localToGlobal(Offset.zero),
          paragraph.localToGlobal(paragraph.size.bottomRight(Offset.zero)),
        );
        expect(paintedRect.left, greaterThanOrEqualTo(cellRect.left - 0.01));
        expect(paintedRect.right, lessThanOrEqualTo(cellRect.right + 0.01));
        expect(paintedRect.top, greaterThanOrEqualTo(cellRect.top - 0.01));
        expect(paintedRect.bottom, lessThanOrEqualTo(cellRect.bottom + 0.01));
      }
      expect(find.text('軽母ヌ級elite(艦載機黒)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('English air raid fits 260 px at text scale $scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const Scaffold(
            body: SizedBox(
              width: 260,
              child: LandBaseRaidPanel(
                result: LandBaseRaidResult(
                  areaId: 47,
                  airSuperiority: '丧失',
                  bases: [
                    LandBaseRaidSnapshot(
                      baseId: 1,
                      name: '第一基地航空队',
                      currentHp: 200,
                      maxHp: 200,
                      damage: 0,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Air raid on base'), findsOneWidget);
      expect(find.text('第一基地航空隊'), findsOneWidget);
      final label = find.text('Air control: Air control lost');
      expect(label, findsOneWidget);
      final pill = find.byType(AirSuperiorityPill);
      expect(
        tester.getSize(label).height,
        lessThanOrEqualTo(tester.getSize(pill).height),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('English battle header fits 196 px at text scale $scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const Scaffold(
            body: SizedBox(
              width: 196,
              child: AdaptiveBattleHeader(
                nodeLabel: '节点 123',
                enemyName: '深海原名艦隊',
                enemyStyle: TextStyle(fontSize: 13),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Sortie node 123'), findsOneWidget);
      expect(find.text('深海原名艦隊'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in const [Size(320, 700), Size(800, 600), Size(700, 320)]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('English enemy details fit $size at text scale $scale', (
        tester,
      ) async {
        await _openEnemyDialog(tester, size: size, scale: scale);
        expect(find.text('Aircraft capacity'), findsOneWidget);
        expect(find.text('Slow'), findsOneWidget);
        expect(find.text('Medium'), findsOneWidget);
        expect(find.text('軽母ヌ級elite(艦載機黒)'), findsOneWidget);
        expect(find.text('軽空母'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('5inch単装砲'));
        await tester.pump();
        expect(find.text('5inch単装砲'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
