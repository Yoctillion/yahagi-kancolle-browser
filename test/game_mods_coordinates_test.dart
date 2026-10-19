import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_controller.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_models.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_page.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_strings.dart';

import 'game_mods_controller_test.dart' show FakeGameModsPort;
import 'support/game_mod_portrait_platform_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(mockGameModPortraitPlatform);
  tearDown(clearGameModPortraitPlatformMock);

  test(
    'one logical coordinate resource retains both compatible sources and all field targets',
    () {
      final status = coordinateStatus();
      final coordinate = status.packages.first.resources.first;
      expect(coordinate.sourcePaths, [
        'hack/tciiyagxjjpu.config.ini',
        'hack/tciiyagxjjpu.config.json',
      ]);
      expect(coordinate.targetPaths, [
        'coordinates/ship/607/api_boko_n',
        'coordinates/ship/607/api_boko_d',
      ]);
      expect(
        GameModsStatus.fromMap(
          status.toMap(),
        ).packages.first.resources.first.sourcePaths,
        coordinate.sourcePaths,
      );
      final preflight = GameModsPreflight.fromMap({
        'token': 'x',
        'name': '伊47',
        'sourceFileCount': 4,
        'resourceCount': 3,
        'supportedCount': 3,
        'unsupportedCount': 0,
      });
      expect(preflight.fileCount, 4);
      expect(
        GameModsStrings(const Locale('en')).preflightCounts(preflight),
        '4 files, 3 resources: 3 supported, 0 unsupported',
      );
    },
  );

  test(
    'coordinate selection stays independent from images sharing the same ship group and from voices',
    () async {
      final port = FakeGameModsPort()..current = coordinateStatus();
      final c = GameModsController(port: port);
      addTearDown(c.dispose);
      await c.initialize();
      c.setResourceEnabled('coords', false);
      expect(c.status.draft.enabledResources, {'full', 'damaged', 'voice'});
      c.setResourceEnabled('coords', true);
      c.setResourceEnabled('full', false);
      expect(c.status.draft.enabledResources, {'coords', 'damaged', 'voice'});
      c.setResourcesEnabled(
        c.status.packages.first.resources.where((r) => r.kind == 'ship'),
        false,
      );
      expect(c.status.draft.enabledResources, {'coords', 'voice'});
      await c.flushDraft();
      expect(port.applyCalls, 0);
      expect(c.status.pending, isTrue);
    },
  );

  test(
    'coordinate conflicts resolve per field and allow lower packages to fill missing fields',
    () async {
      final port = FakeGameModsPort()
        ..current = coordinateStatus(conflict: true);
      final c = GameModsController(port: port);
      addTearDown(c.dispose);
      await c.initialize();
      c.movePackage('overlay', -1);
      expect(
        c.status.winners['coordinates/ship/607/api_boko_n'],
        'overlay-coords',
      );
      expect(c.status.winners['coordinates/ship/607/api_boko_d'], 'coords');
      c.setResourceEnabled('overlay-coords', false);
      expect(c.status.winners['coordinates/ship/607/api_boko_n'], 'coords');
      await c.flushDraft();
    },
  );

  for (final operation in ['remove', 'reset']) {
    test(
      '$operation keeps the old applied coordinates and confirmed hits when apply fails',
      () async {
        final port = _FailedCoordinateApplyPort()
          ..current = coordinateStatus(hits: ['coords', 'full']);
        final c = GameModsController(port: port);
        addTearDown(c.dispose);
        await c.initialize();
        if (operation == 'remove') {
          await c.removePackage('pack');
          await c.apply();
        } else {
          await c.resetAll();
          expect(c.lastApplyResult, isNull);
          await c.apply();
        }
        expect(c.lastApplyResult, GameModsApplyResult.failed);
        expect(c.status.pending, isTrue);
        expect(c.status.applied.master, isTrue);
        expect(c.status.hits, {'coords', 'full'});
        expect(
          c.status.activeWinners['coordinates/ship/607/api_boko_n'],
          'coords',
        );
        expect(c.status.writtenCoordinateCount, 1);
        expect(c.status.providedFileCount, 1);
        if (operation == 'reset') expect(c.status.draft.master, isFalse);
      },
    );
  }

  testWidgets(
    'coordinate setup waits for JS confirmation and is not counted as a provided file',
    (tester) async {
      final port = FakeGameModsPort()..current = coordinateStatus();
      final c = GameModsController(port: port);
      await c.initialize();
      await tester.pumpWidget(_app(c));
      await _open(tester);
      expect(
        find.byKey(const Key('game-mods-resource-coords')),
        findsOneWidget,
      );
      expect(find.text('Coordinates · 0607'), findsOneWidget);
      expect(
        find.text('Enabled; waiting for game coordinate confirmation'),
        findsOneWidget,
      );
      expect(find.text('Written to game coordinates'), findsNothing);
      expect(
        find.text('1 complete replacement resource provided'),
        findsNothing,
      );
      port.current = coordinateStatus(hits: ['coords']);
      await c.refresh();
      await tester.pumpAndSettle();
      expect(find.text('Written to game coordinates'), findsOneWidget);
      expect(find.textContaining('1 coordinate group written'), findsWidgets);
      expect(
        find.text('1 complete replacement resource provided'),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('game-mods-resource-coords')));
      await tester.pumpAndSettle();
      expect(c.status.pending, isTrue);
      expect(find.text('Written to game coordinates'), findsOneWidget);
      expect(find.text('Configuration off'), findsOneWidget);
      expect(port.applyCalls, 0);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'coordinate source files share one switch and partial conflicts retain it',
    (tester) async {
      final port = FakeGameModsPort()
        ..current = coordinateStatus(
          conflict: true,
          overlayFirst: true,
          hits: ['coords'],
        );
      final c = GameModsController(port: port);
      await c.initialize();
      await tester.pumpWidget(_app(c));
      await _open(tester);
      expect(find.text('1 of 2 coordinate fields overridden'), findsWidgets);
      expect(find.text('Written to game coordinates'), findsOneWidget);
      expect(find.textContaining('Overlay'), findsWidgets);
      final toggle = tester.widget<Switch>(
        find.byKey(const Key('game-mods-resource-coords')),
      );
      expect(toggle.onChanged, isNotNull);
      await tester.tap(find.text('View coordinate sources'));
      await tester.pumpAndSettle();
      expect(find.text('hack/tciiyagxjjpu.config.ini'), findsOneWidget);
      expect(find.text('hack/tciiyagxjjpu.config.json'), findsOneWidget);
      expect(
        find.byKey(const Key('game-mods-resource-coords')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'unmatched coordinate groups stay locked and failed JS writes have a coordinate-specific status',
    (tester) async {
      final port = FakeGameModsPort()
        ..current = coordinateStatus(unmatched: true);
      final c = GameModsController(port: port);
      await c.initialize();
      await tester.pumpWidget(_app(c));
      await _open(tester);
      final locked = tester.widget<Switch>(
        find.byKey(const Key('game-mods-resource-coords')),
      );
      expect(locked.value, isFalse);
      expect(locked.onChanged, isNull);
      expect(
        find.text(
          'No matching ship image was found for this coordinate configuration',
        ),
        findsWidgets,
      );
      port.current = coordinateStatus(
        failures: {'coords': 'coordinate_apply_failed'},
      );
      await c.refresh();
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Game coordinate update failed; apply again or check the logs',
        ),
        findsWidgets,
      );
      expect(
        find.text('Read failed; subsequent requests use the original'),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  test(
    'five locales explain supported coordinate groups, binding failures and JS confirmation',
    () {
      for (final locale in const [
        Locale('zh'),
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        Locale('ja'),
        Locale('en'),
        Locale('ko'),
      ]) {
        final s = GameModsStrings(locale);
        expect(s.kind('coordinates'), isNot(s.kind('other')));
        expect(s.coordinatesWaiting, isNot(s.coordinatesWritten));
        expect(
          s.reason('coordinate_unmatched'),
          isNot(s.reason('unknown_failure')),
        );
        expect(
          s.reason('invalid_coordinates'),
          isNot(s.reason('unknown_failure')),
        );
        expect(
          s.reason('coordinate_conflict'),
          isNot(s.reason('unknown_failure')),
        );
        expect(
          s.reason('coordinate_metadata_ignored'),
          isNot(s.reason('unknown_failure')),
        );
        expect(
          s.reason('coordinate_unknown_fields_ignored'),
          isNot(s.reason('unknown_failure')),
        );
        expect(
          s.helpBody,
          isNot(
            contains(
              'Resources that depend on coordinates are not supported yet',
            ),
          ),
        );
      }
    },
  );
}

class _FailedCoordinateApplyPort extends FakeGameModsPort {
  @override
  Future<GameModsApplyResult> applyAndReload() async {
    applyCalls++;
    return GameModsApplyResult.failed;
  }
}

Widget _app(GameModsController c) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: Scaffold(body: GameModsPage(controller: c)),
);
Future<void> _open(WidgetTester tester) async {
  final details = find.byKey(const Key('game-mods-details-pack'));
  await tester.scrollUntilVisible(details, 160);
  await tester.ensureVisible(details);
  await tester.pumpAndSettle();
  await tester.tap(details);
  await tester.pumpAndSettle();
}

GameModsStatus coordinateStatus({
  List<String> hits = const [],
  Map<String, String> failures = const {},
  bool conflict = false,
  bool overlayFirst = false,
  bool unmatched = false,
}) {
  final resources = [
    {
      'id': 'coords',
      'path': 'coordinates/ship/607',
      'kind': 'coordinates',
      'label': '0607',
      'groupId': 'ship:0607',
      'sourcePaths': [
        'hack/tciiyagxjjpu.config.ini',
        'hack/tciiyagxjjpu.config.json',
      ],
      'targetPaths': [
        'coordinates/ship/607/api_boko_n',
        'coordinates/ship/607/api_boko_d',
      ],
      'supported': !unmatched,
      if (unmatched) 'reason': 'coordinate_unmatched',
    },
    {
      'id': 'full',
      'path': 'kcs2/resources/ship/full/0607_tciiyagxjjpu.png',
      'kind': 'ship',
      'label': '0607 · full',
      'groupId': 'ship:0607',
      'supported': true,
    },
    {
      'id': 'damaged',
      'path': 'kcs2/resources/ship/full_dmg/0607_tciiyagxjjpu.png',
      'kind': 'ship',
      'label': '0607 · full_dmg',
      'groupId': 'ship:0607',
      'supported': true,
    },
    {
      'id': 'voice',
      'path': 'kcs/sound/kcxngurirfszwi/107404.mp3',
      'kind': 'audio',
      'supported': true,
    },
  ];
  final config = {
    'master': true,
    'order': overlayFirst
        ? ['overlay', 'pack']
        : ['pack', if (conflict) 'overlay'],
    'enabledPackages': ['pack', if (conflict) 'overlay'],
    'enabledResources': [
      'full',
      'damaged',
      'voice',
      if (!unmatched) 'coords',
      if (conflict) 'overlay-coords',
    ],
  };
  final winners = {
    'kcs2/resources/ship/full/0607_tciiyagxjjpu.png': 'full',
    'kcs2/resources/ship/full_dmg/0607_tciiyagxjjpu.png': 'damaged',
    'kcs/sound/kcxngurirfszwi/107404.mp3': 'voice',
    if (!unmatched)
      'coordinates/ship/607/api_boko_n': overlayFirst
          ? 'overlay-coords'
          : 'coords',
    if (!unmatched) 'coordinates/ship/607/api_boko_d': 'coords',
  };
  return GameModsStatus.fromMap({
    'packages': [
      {'id': 'pack', 'name': '伊47', 'resources': resources},
      if (conflict)
        {
          'id': 'overlay',
          'name': 'Overlay',
          'resources': [
            {
              'id': 'overlay-coords',
              'path': 'coordinates/ship/607',
              'kind': 'coordinates',
              'label': '0607',
              'groupId': 'ship:0607',
              'sourcePaths': ['alternate.config.json'],
              'targetPaths': ['coordinates/ship/607/api_boko_n'],
              'supported': true,
            },
          ],
        },
    ],
    'draft': config,
    'applied': config,
    'winners': winners,
    'activeWinners': winners,
    'hits': hits,
    'failures': failures,
    'sessionId': 1,
  });
}
