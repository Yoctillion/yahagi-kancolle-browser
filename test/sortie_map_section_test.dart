import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/battle/fcd_map_geometry.dart';
import 'package:yahagi_kancolle_browser/src/battle/sortie_map_progress.dart';
import 'package:yahagi_kancolle_browser/src/battle/sortie_map_section.dart';

void main() {
  final geometry = FcdMapGeometry(
    routes: const {
      0: FcdMapRoute(from: null, to: '1'),
      3: FcdMapRoute(from: '1', to: 'A1'),
      11: FcdMapRoute(from: 'A1', to: 'Z1'),
      17: FcdMapRoute(from: 'Z1', to: 'B'),
      19: FcdMapRoute(from: 'A1', to: 'Z1'),
      25: FcdMapRoute(from: 'A1', to: 'C'),
    },
    spots: const {
      '1': FcdMapSpot(x: 0, y: 60, type: 'start'),
      'A1': FcdMapSpot(x: 90, y: 30, type: ''),
      'Z1': FcdMapSpot(x: 180, y: 60, type: ''),
      'B': FcdMapSpot(x: 270, y: 30, type: ''),
      'C': FcdMapSpot(x: 150, y: 120, type: ''),
    },
  );
  SortieMapProgress progress({
    List<int> routes = const [0, 3, 11],
    bool partial = false,
    int area = 2,
  }) => SortieMapProgress(
    mapAreaId: area,
    mapInfoNo: 5,
    routeIds: routes,
    bossRouteId: 17,
    isPartial: partial,
  );

  Widget app({
    required SortieMapProgress value,
    FcdMapGeometry? map,
    bool expanded = true,
    VoidCallback? toggle,
    String? currentLabel,
    Locale locale = const Locale('zh'),
    double textScale = 1,
  }) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(brightness: Brightness.dark),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: SortieMapSection(
            progress: value,
            geometry: map,
            expanded: expanded,
            onToggleExpanded: toggle ?? () {},
            currentNodeLabel: currentLabel,
          ),
        ),
      ),
    ),
  );

  testWidgets('own collapse control retains sea and current mapped node', (
    tester,
  ) async {
    var expanded = true;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SortieMapSection(
              progress: progress(),
              geometry: geometry,
              expanded: expanded,
              onToggleExpanded: () => setState(() => expanded = !expanded),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('sortie-map-section')), findsOneWidget);
    expect(find.byKey(const Key('sortie-map-body')), findsOneWidget);
    expect(find.text('2-5 · 当前 Z1'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('sortie-map-toggle'))).height,
      greaterThanOrEqualTo(44),
    );
    await tester.tap(find.byKey(const Key('sortie-map-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('sortie-map-body')), findsNothing);
    expect(find.text('海域小地图'), findsOneWidget);
    expect(find.text('2-5 · 当前 Z1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sortie-map-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('sortie-map-body')), findsOneWidget);
  });

  testWidgets(
    'folded section follows progress and does not duplicate markers on rebuild',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          app(value: progress(), map: geometry, expanded: false),
        );
        expect(find.text('2-5 · 当前 Z1'), findsOneWidget);
        final updated = progress(routes: const [0, 3, 11, 17]);
        await tester.pumpWidget(
          app(value: updated, map: geometry, expanded: false),
        );
        expect(find.text('2-5 · 当前 B'), findsOneWidget);
        expect(find.byKey(const Key('sortie-map-body')), findsNothing);
        await tester.pumpWidget(app(value: updated, map: geometry));
        await tester.pumpWidget(app(value: updated, map: geometry));
        expect(find.bySemanticsLabel('B · Boss · 当前 · 已走'), findsOneWidget);
        expect(find.bySemanticsLabel('航段 17 · Z1 → B · 已走'), findsOneWidget);
        expect(find.bySemanticsLabel('Z1 · 已走'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('route and node marks remain without footer controls or legend', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(app(value: progress(), map: geometry));
      expect(find.byKey(const Key('sortie-map-canvas')), findsOneWidget);
      expect(find.bySemanticsLabel('航段 11 · A1 → Z1 · 已走'), findsOneWidget);
      expect(find.bySemanticsLabel('航段 19 · A1 → Z1'), findsOneWidget);
      expect(find.bySemanticsLabel('Z1 · 当前 · 已走'), findsOneWidget);
      expect(find.bySemanticsLabel('B · Boss'), findsOneWidget);
      expect(find.bySemanticsLabel('1 · 起点 · 已走'), findsOneWidget);
      expect(find.text('1 → A1 → Z1'), findsNothing);
      expect(find.text('已走'), findsNothing);
      expect(find.text('当前'), findsNothing);
      expect(find.text('Boss'), findsNothing);
      expect(find.text('放大查看'), findsNothing);
      expect(find.byKey(const Key('sortie-map-enlarge')), findsNothing);
      expect(find.byKey(const Key('sortie-map-dialog')), findsNothing);
      expect(find.byType(InteractiveViewer), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('partial capture includes only captured segment endpoints', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        app(
          value: progress(routes: const [11], partial: true),
          map: geometry,
        ),
      );
      expect(find.text('航迹不完整，仅显示已捕获航段'), findsOneWidget);
      expect(find.text('已捕获'), findsNothing);
      expect(find.text('A1 → Z1'), findsNothing);
      expect(find.bySemanticsLabel('1 · 起点'), findsOneWidget);
      expect(find.bySemanticsLabel('航段 3 · 1 → A1'), findsOneWidget);
      expect(find.bySemanticsLabel('航段 11 · A1 → Z1 · 已走'), findsOneWidget);
      expect(find.bySemanticsLabel('Z1 · 当前 · 已走'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('unknown geometry keeps actual label without fabricated map', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        value: progress(routes: const [45, 62], partial: true, area: 99),
        currentLabel: 'ZZ',
      ),
    );
    expect(find.text('99-5 · 当前 ZZ'), findsOneWidget);
    expect(find.text('该地图未更新'), findsOneWidget);
    expect(find.text('航迹不完整，仅显示已捕获航段'), findsOneWidget);
    expect(find.byKey(const Key('sortie-map-canvas')), findsNothing);
    expect(find.text('航段 45 → 航段 62'), findsNothing);
  });

  testWidgets('unmapped route does not fabricate a current node position', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        app(
          value: progress(routes: const [0, 3, 99]),
          map: geometry,
        ),
      );
      expect(find.text('2-5 · 当前 节点 99'), findsOneWidget);
      expect(find.byKey(const Key('sortie-map-canvas')), findsOneWidget);
      expect(find.text('该地图未更新'), findsOneWidget);
      expect(find.bySemanticsLabel('航段 3 · 1 → A1 · 已走'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Z1 · 当前')), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('empty geometry uses the same fallback as an unknown map', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        value: progress(),
        map: FcdMapGeometry(routes: const {}, spots: const {}),
        currentLabel: 'Z1',
      ),
    );
    expect(find.text('2-5 · 当前 Z1'), findsOneWidget);
    expect(find.text('该地图未更新'), findsOneWidget);
    expect(find.byKey(const Key('sortie-map-canvas')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('folded missing map still shows its update status', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(240, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      app(
        value: progress(routes: const [62], area: 99),
        expanded: false,
        currentLabel: 'ZZ',
        textScale: 1.6,
      ),
    );
    expect(find.text('99-5 · 当前 ZZ'), findsOneWidget);
    expect(find.text('该地图未更新'), findsOneWidget);
    expect(find.byKey(const Key('sortie-map-body')), findsNothing);
    expect(find.byKey(const Key('sortie-map-canvas')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('updated geometry clears the missing route warning', (
    tester,
  ) async {
    final currentProgress = progress(routes: const [0, 3, 99]);
    await tester.pumpWidget(app(value: currentProgress, map: geometry));
    expect(find.text('该地图未更新'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Z1 · 当前')), findsNothing);

    final updated = FcdMapGeometry(
      routes: {
        ...geometry.routes,
        99: const FcdMapRoute(from: 'A1', to: 'Z1'),
      },
      spots: geometry.spots,
    );
    await tester.pumpWidget(app(value: currentProgress, map: updated));
    expect(find.text('该地图未更新'), findsNothing);
    expect(find.text('2-5 · 当前 Z1'), findsOneWidget);
    expect(find.byKey(const Key('sortie-map-canvas')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing history and boss routes also flag incomplete data', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        value: progress(routes: const [0, 99, 3]),
        map: geometry,
      ),
    );
    expect(find.text('2-5 · 当前 A1'), findsOneWidget);
    expect(find.text('该地图未更新'), findsOneWidget);

    await tester.pumpWidget(
      app(
        value: SortieMapProgress(
          mapAreaId: 2,
          mapInfoNo: 5,
          routeIds: const [0, 3],
          bossRouteId: 99,
        ),
        map: geometry,
      ),
    );
    expect(find.text('该地图未更新'), findsOneWidget);
    expect(find.byKey(const Key('sortie-map-canvas')), findsOneWidget);
  });

  for (final (locale, message) in [
    (
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      '此地圖尚未更新',
    ),
    (const Locale('ja'), 'このマップは未更新です'),
  ]) {
    testWidgets('missing map update status is localized for $locale', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(value: progress(area: 99), locale: locale, expanded: false),
      );
      expect(find.text(message), findsOneWidget);
      expect(find.text('该地图未更新'), findsNothing);
      expect(find.byKey(const Key('sortie-map-canvas')), findsNothing);
    });
  }

  testWidgets('current map follows replacement geometry and map identity', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(app(value: progress(), map: geometry));
      expect(find.bySemanticsLabel('Z1 · 当前 · 已走'), findsOneWidget);
      final replacement = FcdMapGeometry(
        routes: const {
          0: FcdMapRoute(from: null, to: '2'),
          3: FcdMapRoute(from: '2', to: 'Q'),
        },
        spots: const {
          '2': FcdMapSpot(x: 0, y: 0, type: 'start'),
          'Q': FcdMapSpot(x: 100, y: 100, type: ''),
        },
      );
      await tester.pumpWidget(
        app(
          value: progress(routes: const [0, 3], area: 3),
          map: replacement,
        ),
      );
      expect(find.text('3-5 · 当前 Q'), findsOneWidget);
      expect(find.bySemanticsLabel('Q · 当前 · 已走'), findsOneWidget);
      expect(find.bySemanticsLabel('航段 3 · 2 → Q · 已走'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Z1')), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  for (final width in [240.0, 280.0, 360.0, 640.0]) {
    testWidgets('section and canvas fit width $width', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(value: progress(), map: geometry));
      expect(tester.takeException(), isNull);
      final canvas = tester.getRect(find.byKey(const Key('sortie-map-canvas')));
      expect(canvas.width, lessThanOrEqualTo(430));
      expect(canvas.width, lessThanOrEqualTo(width - 16));
      expect(canvas.left, greaterThanOrEqualTo(0));
      expect(canvas.right, lessThanOrEqualTo(width));
    });
  }

  testWidgets('large text fits narrow and short landscape layouts', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in [const Size(240, 640), const Size(640, 320)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        app(value: progress(partial: true), map: geometry, textScale: 1.5),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('2-5 · 当前 Z1'), findsOneWidget);
      expect(find.text('航迹不完整，仅显示已捕获航段'), findsOneWidget);
      final canvas = tester.getRect(find.byKey(const Key('sortie-map-canvas')));
      expect(canvas.right, lessThanOrEqualTo(size.width));
      expect(canvas.bottom, lessThanOrEqualTo(size.height));
      expect(
        tester.getSize(find.byKey(const Key('sortie-map-toggle'))).height,
        greaterThanOrEqualTo(44),
      );
    }
  });

  for (final width in [240.0, 280.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('English map header fits $width px at text scale $scale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          app(
            value: progress(),
            map: geometry,
            locale: const Locale('en'),
            textScale: scale,
          ),
        );
        expect(find.text('Map overview'), findsOneWidget);
        expect(find.text('2-5 · Current Z1'), findsOneWidget);
        expect(find.byKey(const Key('sortie-map-canvas')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('minimap labels respect the Japanese translation boundary', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        value: progress(partial: true),
        map: geometry,
        locale: const Locale('ja'),
      ),
    );
    expect(find.text('海域ミニマップ'), findsOneWidget);
    expect(find.text('2-5 · 現在 Z1'), findsOneWidget);
    expect(find.text('航跡は不完全です。取得済み区間のみ表示'), findsOneWidget);
    expect(find.text('拡大表示'), findsNothing);
  });
}
