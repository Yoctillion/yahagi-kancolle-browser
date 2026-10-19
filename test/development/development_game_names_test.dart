import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/development/development_repository.dart';
import 'package:yahagi_kancolle_browser/src/development/equipment_development_page.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/localization/game_name_localizations.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_kc3_bundle.dart';

void main() {
  late ShipSubtitleKc3Bundle bundle;
  setUpAll(() {
    bundle = ShipSubtitleKc3Bundle.fromJsonString(
      File(ShipSubtitleKc3Bundle.bundledAsset).readAsStringSync(),
    );
  });
  for (final language in ['en', 'ko']) {
    testWidgets(
      'development output, current flagship and pool use $language names',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1300, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        late String ship;
        late String equipment;
        late String type;
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) =>
                GameNameLocalizationScope(bundle: bundle, child: child!),
            home: Builder(
              builder: (context) {
                final names = gameNames(context);
                ship = names.shipName('赤城', shipId: 83);
                equipment = names.equipmentName('九七式艦攻');
                type = names.equipmentTypeName('艦上攻撃機', typeId: 8);
                return Scaffold(
                  body: EquipmentDevelopmentPage(
                    state: _state,
                    repository: DevelopmentRepository(
                      loadString: (_) async => jsonEncode(_snapshot),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(equipment, isNot('九七式艦攻'));
        expect(type, isNot('艦上攻撃機'));
        expect(find.text(equipment), findsOneWidget);
        expect(find.text(type), findsOneWidget);
        expect(find.textContaining(ship), findsWidgets);
        expect(find.textContaining('赤城'), findsNothing);
        await tester.tap(find.byKey(const Key('development-secretary-picker')));
        await tester.pumpAndSettle();
        expect(find.textContaining(ship), findsWidgets);
        expect(find.textContaining('赤城'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

const _state = GameState(
  hasPortData: true,
  ships: {1: OwnedShip(id: 1, masterId: 83, level: 1)},
  fleets: [
    Fleet(id: 1, name: 'First fleet', shipIds: [1]),
  ],
  masterShips: {83: MasterShip(id: 83, name: '赤城', shipTypeId: 11)},
  masterSlotItems: {
    16: MasterSlotItem(id: 16, name: '九七式艦攻', type: [3, 5, 8, 8]),
  },
  masterSlotItemTypes: {8: '艦上攻撃機'},
);
final _snapshot = {
  'schema_version': 1,
  'generated_at': '2026-10-19T00:00:00.000Z',
  'source': {
    'repository': 'https://example.invalid',
    'commit': 'test',
    'hashes': {'pool': 'test'},
  },
  'summary': {
    'pool_count': 1,
    'selectable_pool_count': 1,
    'equipment_count': 1,
    'negative_pool_count': 0,
    'minimum_resource_pool_count': 0,
  },
  'equipment': [
    {
      'id': 16,
      'name': '九七式艦攻',
      'names': {'zh': '九七式舰攻', 'zh_Hant': '九七式艦攻', 'ja': '九七式艦攻'},
      'type_id': 8,
      'icon_id': 8,
      'minimum_resources': [10, 10, 10, 10],
    },
  ],
  'pools': [
    {
      'pool_key': 'carrier-akagi#3',
      'name': 'carrier-akagi',
      'labels': {'zh': '空母系-赤城', 'zh_Hant': '空母系-赤城', 'ja': '空母系-赤城'},
      'descriptions': {'zh': '赤城', 'zh_Hant': '赤城', 'ja': '赤城'},
      'pool_id': 3,
      'ship_ids': [83],
      'drop_rates': {'16': 1},
      'criteria': {
        'ship_types': [],
        'class_types': [],
        'ship_names': [],
        'ship_ids': [],
        'excluded_ship_ids': [],
      },
    },
  ],
  'secretaries': [
    {'ship_id': 83, 'pool_key': 'carrier-akagi#3'},
  ],
};
