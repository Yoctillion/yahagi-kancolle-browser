import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/src/account/account_session.dart';
import 'package:yahagi_kancolle_browser/src/fleet/dashboard_card.dart';
import 'package:yahagi_kancolle_browser/src/fleet/expedition_summary_card.dart';
import 'package:yahagi_kancolle_browser/src/expedition/expedition_check_card.dart';
import 'package:yahagi_kancolle_browser/src/expedition/expedition_selection_store.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_store.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_reducer.dart';
import 'package:yahagi_kancolle_browser/src/layout/panel_style.dart';
import 'package:yahagi_kancolle_browser/src/layout/flat_style.dart';
import 'package:yahagi_kancolle_browser/src/layout/flat_text_toggle.dart';
import 'package:yahagi_kancolle_browser/src/layout/flat_underline_tabs.dart';

import 'fixtures/kcsapi_fixtures.dart';

void main() {
  setUp(() {
    AccountSession.shared.selectMember(1001);
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'switching accounts restores that accounts expedition selection',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'account.1001.expedition.selected_mission.fleet_2': 105,
        'account.2002.expedition.selected_mission.fleet_2': 112,
      });
      final controller = GameStateController();
      addTearDown(controller.dispose);
      controller
        ..accept(start2Event)
        ..accept(portEvent);
      await controller.idle;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ExpeditionCheckContent(
              controller: controller,
              onOpenDetails: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('expedition-mission-name')))
            .data,
        startsWith('A6'),
      );
      AccountSession.shared.selectMember(2002);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('expedition-mission-name')))
            .data,
        startsWith('B3'),
      );
    },
  );
  testWidgets('首页远征检查按舰队恢复上次选择的 A6', (tester) async {
    final controller = GameStateController();
    final store = _MemoryExpeditionSelectionStore(<int, int>{1: 112, 2: 105});
    addTearDown(controller.dispose);
    controller
      ..accept(start2Event)
      ..accept(portEvent)
      ..accept(slotItemEvent);
    await controller.idle;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ExpeditionCheckContent(
            controller: controller,
            onOpenDetails: (_) {},
            selectionStore: store,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const Key('expedition-mission-name')))
          .data,
      startsWith('A6'),
    );

    await tester.tap(find.byKey(const Key('expedition-fleet-1')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const Key('expedition-mission-name')))
          .data,
      startsWith('B3'),
    );
    await tester.tap(find.byKey(const Key('expedition-fleet-2')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const Key('expedition-mission-name')))
          .data,
      startsWith('A6'),
    );

    await tester.tap(find.byKey(const Key('expedition-mission-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('expedition-mission-option-2')));
    await tester.pumpAndSettle();
    expect(store.values[2], 2);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ExpeditionCheckContent(
            controller: controller,
            onOpenDetails: (_) {},
            selectionStore: store,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const Key('expedition-mission-name')))
          .data,
      startsWith('2'),
    );
  });

  testWidgets('详细卡片无大发开关并在条件末尾始终显示提醒', (tester) async {
    final controller = GameStateController();
    addTearDown(controller.dispose);
    controller
      ..accept(start2Event)
      ..accept(portEvent)
      ..accept(slotItemEvent);
    await controller.idle;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ExpeditionCheckContent(
            controller: controller,
            onOpenDetails: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('详细'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('expedition-daihatsu-optimization-switch')),
      findsNothing,
    );
    expect(find.text('尽量装满大发'), findsNothing);
    expect(find.text('尽可能多的大发动艇或特大发动艇'), findsOneWidget);
  });

  group('极简档扁平化', () {
    Future<void> pumpFlat(
      WidgetTester tester, {
      required PanelStyle style,
      String languageCode = 'en',
      double width = 190,
      ExpeditionSelectionStore? selectionStore,
    }) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = GameStateController();
      addTearDown(controller.dispose);
      controller
        ..accept(start2Event)
        ..accept(portEvent)
        ..accept(slotItemEvent);
      await controller.idle;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(languageCode),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: PanelStyleScope(
                style: style,
                child: ExpeditionCheckContent(
                  controller: controller,
                  onOpenDetails: (_) {},
                  selectionStore: selectionStore,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder inCheck(Finder matching) => find.descendant(
      of: find.byType(ExpeditionCheckContent),
      matching: matching,
    );

    int decoratedBoxes(WidgetTester tester) {
      var count = 0;
      for (final box in tester.widgetList<DecoratedBox>(
        inCheck(find.byType(DecoratedBox)),
      )) {
        final decoration = box.decoration;
        if (decoration is! BoxDecoration ||
            decoration.color != null ||
            decoration.borderRadius != null) {
          count++;
          continue;
        }
        final border = decoration.border;
        if (border != null &&
            !(border is Border &&
                border.top == BorderSide.none &&
                border.left == BorderSide.none &&
                border.right == BorderSide.none &&
                border.bottom.width == 2 &&
                [
                  flatAccentColor,
                  Colors.transparent,
                ].contains(border.bottom.color))) {
          count++;
        }
      }
      for (final material in tester.widgetList<Material>(
        inCheck(find.byType(Material)),
      )) {
        if (material.color != null && material.color != Colors.transparent) {
          count++;
        }
      }
      return count;
    }

    Future<void> openDetailedGreat(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('expedition-mode-detailed')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('expedition-success-great')));
      await tester.pumpAndSettle();
    }

    testWidgets('flat 下检查模式除选中底线外不含底色、圆角或方框', (tester) async {
      await pumpFlat(tester, style: PanelStyle.flat);
      expect(decoratedBoxes(tester), 0);
      await openDetailedGreat(tester);
      expect(decoratedBoxes(tester), 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('flat 下约 190 宽、英文、1.3 倍字号无溢出', (tester) async {
      await pumpFlat(tester, style: PanelStyle.flat);
      await openDetailedGreat(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('flat 下模式切换是无底色文字，选中金色、未选灰色', (tester) async {
      await pumpFlat(tester, style: PanelStyle.flat, languageCode: 'zh');
      Color colorOf(String label) =>
          tester.widget<Text>(find.text(label)).style!.color!;
      expect(colorOf('简洁'), const Color(0xffd4a85f));
      expect(colorOf('详细'), const Color(0xff8197a5));
      expect(tester.widget<Text>(find.text('简洁')).style!.fontSize, 10.5);
    });

    testWidgets('非 flat 仍保留方块装饰', (tester) async {
      await pumpFlat(tester, style: PanelStyle.card, width: 420);
      expect(decoratedBoxes(tester), greaterThan(0));
      final group = find.byKey(const Key('expedition-fleet-segments'));
      expect(tester.widget(group), isA<Container>());
      expect(tester.getSize(group).height, 26);
      expect(find.byType(FlatUnderlineTabs), findsNothing);
    });

    for (final width in [300.0, 190.0]) {
      testWidgets('flat 舰队切换等分整行并保留各队远征选择 ($width)', (tester) async {
        final store = _MemoryExpeditionSelectionStore({1: 112, 2: 105});
        await pumpFlat(
          tester,
          style: PanelStyle.flat,
          width: width,
          selectionStore: store,
        );
        final group = find.byKey(const Key('expedition-fleet-segments'));
        expect(tester.widget(group), isA<FlatUnderlineTabs>());
        final groupRect = tester.getRect(group);
        expect(groupRect.width, width);
        expect(groupRect.height, 22);
        for (final id in [1, 2]) {
          final rect = tester.getRect(find.byKey(Key('expedition-fleet-$id')));
          expect(rect.width, closeTo(groupRect.width / 2, 0.01));
          expect(
            rect.left,
            closeTo(groupRect.left + (id - 1) * groupRect.width / 2, 0.01),
          );
          expect(rect.top, groupRect.top);
        }
        Color lineColor(int id) =>
            ((tester
                                .widget<DecoratedBox>(
                                  find.descendant(
                                    of: find.byKey(Key('expedition-fleet-$id')),
                                    matching: find.byType(DecoratedBox),
                                  ),
                                )
                                .decoration
                            as BoxDecoration)
                        .border!
                    as Border)
                .bottom
                .color;
        String missionName() => tester
            .widget<Text>(find.byKey(const Key('expedition-mission-name')))
            .data!;
        expect(lineColor(1), Colors.transparent);
        expect(lineColor(2), flatAccentColor);
        expect(missionName(), startsWith('A6'));
        await tester.tap(find.byKey(const Key('expedition-fleet-1')));
        await tester.pumpAndSettle();
        expect(lineColor(1), flatAccentColor);
        expect(lineColor(2), Colors.transparent);
        expect(missionName(), startsWith('B3'));
        await tester.tap(find.byKey(const Key('expedition-fleet-2')));
        await tester.pumpAndSettle();
        expect(lineColor(2), flatAccentColor);
        expect(missionName(), startsWith('A6'));
        for (final key in [
          'expedition-mode-segments',
          'expedition-success-segments',
        ]) {
          expect(tester.widget(find.byKey(Key(key))), isA<FlatTextToggle>());
        }
        expect(store.values, {1: 112, 2: 105});
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('首页远征检查默认选择远征 1', (tester) async {
    final controller = GameStateController();
    addTearDown(controller.dispose);
    controller
      ..accept(start2Event)
      ..accept(portEvent)
      ..accept(slotItemEvent);
    await controller.idle;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ExpeditionSummaryCard(
            controller: controller,
            collapsed: false,
            onToggleCollapse: () {},
            onOpenExpedition: () {},
            onOpenExpeditionCheck: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('expedition-mode-check')));
    await tester.pump();

    expect(find.byKey(const Key('expedition-mission-picker')), findsOneWidget);
    expect(find.textContaining('1 ·'), findsOneWidget);
  });

  testWidgets('远征检查默认状态不绘制独有边框', (tester) async {
    final controller = GameStateController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ExpeditionSummaryCard(
          controller: controller,
          collapsed: false,
          onToggleCollapse: () {},
          onOpenExpedition: () {},
          onOpenExpeditionCheck: (_) {},
        ),
      ),
    );

    expect(
      tester.widget<DashboardCard>(find.byType(DashboardCard)).borderColor,
      isNull,
    );
  });

  testWidgets('首页卡片具有折叠箭头、模式切换和独立详情页按钮', (tester) async {
    final controller = GameStateController();
    addTearDown(controller.dispose);
    var collapsed = false;
    var opened = false;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: SizedBox(
              width: 420,
              child: ExpeditionSummaryCard(
                controller: controller,
                collapsed: collapsed,
                onToggleCollapse: () => setState(() => collapsed = !collapsed),
                onOpenExpedition: () {},
                onOpenExpeditionCheck: (_) => opened = true,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('expedition-mode-check')));
    await tester.pump();

    expect(find.text('远征简报'), findsOneWidget);
    expect(find.text('进度'), findsOneWidget);
    expect(find.text('检查'), findsOneWidget);
    expect(find.text('简洁'), findsOneWidget);
    expect(find.text('详细'), findsOneWidget);
    expect(find.text('成功'), findsOneWidget);
    expect(find.text('大成功'), findsOneWidget);

    for (final label in <String>['简洁', '详细', '成功', '大成功']) {
      final text = tester.widget<Text>(find.text(label));
      expect(text.style?.fontSize, 10);
      expect(text.style?.fontWeight, FontWeight.w700);
    }
    for (final key in <String>[
      'expedition-mode-segments',
      'expedition-success-segments',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget);
    }

    await tester.tap(find.byKey(const Key('expedition-status-text')));
    expect(opened, isTrue);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('expedition-status-text')), findsNothing);
  });

  testWidgets('真实母港规模不会让远征卡片无限分配内存', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = _largePortState();
    final controller = GameStateController(
      gameStateStore: _StaticGameStateStore(state),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: ExpeditionSummaryCard(
              controller: controller,
              collapsed: false,
              onToggleCollapse: () {},
              onOpenExpedition: () {},
              onOpenExpeditionCheck: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('expedition-mode-check')));
    await tester.pump();

    expect(find.text('远征简报'), findsOneWidget);
    expect(find.textContaining('常规检查'), findsOneWidget);

    await tester.tap(find.text('详细'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('预计收入'), findsOneWidget);
    expect(find.text('远征条件'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('远征检查卡片在标准手机宽度下切换大成功无溢出', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = GameStateController();
    addTearDown(controller.dispose);
    controller
      ..accept(start2Event)
      ..accept(portEvent)
      ..accept(slotItemEvent);
    await controller.idle;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 412,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ExpeditionSummaryCard(
                controller: controller,
                collapsed: false,
                onToggleCollapse: () {},
                onOpenExpedition: () {},
                onOpenExpeditionCheck: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('expedition-mode-check')));
    await tester.pump();
    final fleetGroup = find.byKey(const Key('expedition-fleet-segments'));
    expect(fleetGroup, findsOneWidget);
    final fleetLabels = find.descendant(
      of: fleetGroup,
      matching: find.byType(Text),
    );
    expect(fleetLabels, findsWidgets);
    for (final text in tester.widgetList<Text>(fleetLabels)) {
      expect(text.style?.fontSize, 10);
      expect(text.style?.fontWeight, FontWeight.w700);
    }
    final missionTexts = tester.widgetList<Text>(
      find.byKey(const Key('expedition-mission-name')),
    );
    expect(missionTexts, isNotEmpty);
    expect(missionTexts.every((text) => text.style?.fontSize == 12), isTrue);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('expedition-status-text')))
          .style
          ?.fontSize,
      12,
    );
    await tester.tap(find.text('大成功'));
    await tester.pumpAndSettle();
    expect(find.textContaining('大成功：未通过 ('), findsNothing);
    expect(find.text('大成功：未通过'), findsOneWidget);
    await tester.tap(find.text('详细'));
    await tester.pump();
    expect(find.byKey(const Key('expedition-status-text')), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('长舰队名在手机宽度下自动缩小为单行', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final reducer = GameStateReducer();
    var state = reducer.reduce(GameState.empty, start2Event);
    state = reducer.reduce(state, portEvent);
    state = reducer.reduce(state, slotItemEvent);
    final secondFleet = state.fleets.firstWhere((fleet) => fleet.id == 2);
    state = state.copyWith(
      fleets: <Fleet>[
        Fleet(id: 2, name: '第十一驱逐舰队', shipIds: secondFleet.shipIds),
        for (final fleet in state.fleets)
          if (fleet.id != 2) fleet,
      ],
    );
    final controller = GameStateController(
      gameStateStore: _StaticGameStateStore(state),
    );
    addTearDown(controller.dispose);
    await controller.idle;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 412,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ExpeditionSummaryCard(
                controller: controller,
                collapsed: false,
                onToggleCollapse: () {},
                onOpenExpedition: () {},
                onOpenExpeditionCheck: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('expedition-mode-check')));
    await tester.pump();

    final nameText = tester.widget<Text>(find.text('第十一驱逐舰队'));
    expect(nameText.maxLines, 1);
    expect(nameText.softWrap, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄卡片的远征名称与常规检查统一使用紧凑自适应字号', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = GameStateController();
    addTearDown(controller.dispose);
    controller
      ..accept(start2Event)
      ..accept(portEvent)
      ..accept(slotItemEvent);
    await controller.idle;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: ExpeditionSummaryCard(
              controller: controller,
              collapsed: false,
              onToggleCollapse: () {},
              onOpenExpedition: () {},
              onOpenExpeditionCheck: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('expedition-mode-check')));
    await tester.pump();

    final missionTexts = tester.widgetList<Text>(
      find.byKey(const Key('expedition-mission-name')),
    );
    expect(missionTexts, isNotEmpty);
    expect(missionTexts.every((text) => text.style?.fontSize == 11), isTrue);
    expect(missionTexts.every((text) => text.maxLines == 1), isTrue);

    final status = tester.widget<Text>(
      find.byKey(const Key('expedition-status-text')),
    );
    expect(status.style?.fontSize, 11);
    expect(status.maxLines, 1);
    expect(tester.takeException(), isNull);
  });
}

final class _MemoryExpeditionSelectionStore
    implements ExpeditionSelectionStore {
  _MemoryExpeditionSelectionStore(this.values);

  final Map<int, int> values;

  @override
  Future<int?> loadMissionId(int fleetId) async => values[fleetId];

  @override
  Future<void> saveMissionId(int fleetId, int missionId) async {
    values[fleetId] = missionId;
  }
}

class _StaticGameStateStore extends GameStateStore {
  _StaticGameStateStore(this.value);
  final GameState value;
  @override
  Future<GameState> load() async => value;
}

GameState _largePortState() {
  final masters = <int, MasterShip>{};
  final ships = <int, OwnedShip>{};
  final slots = <int, OwnedSlotItem>{};
  var slotId = 1;
  for (var index = 1; index <= 279; index++) {
    final masterId = 1000 + index;
    masters[masterId] = MasterShip(
      id: masterId,
      name: '舰船$index',
      shipTypeId: index == 1 ? 3 : 2,
      maxFuel: 20,
      maxAmmo: 20,
      slotCount: 8,
    );
    final shipSlots = <int>[];
    for (var slot = 0; slot < 8; slot++) {
      slots[slotId] = OwnedSlotItem(id: slotId, masterId: 1);
      shipSlots.add(slotId++);
    }
    ships[index] = OwnedShip(
      id: index,
      masterId: masterId,
      level: 80,
      currentFuel: 20,
      currentAmmo: 20,
      slotIds: shipSlots,
    );
  }
  return GameState(
    masterShips: masters,
    ships: ships,
    slotItems: slots,
    fleets: const <Fleet>[
      Fleet(id: 2, name: '第2舰队', shipIds: <int>[1, 2, 3, 4, 5, 6]),
    ],
    hasPortData: true,
    hasMasterData: true,
  );
}
