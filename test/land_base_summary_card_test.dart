import 'package:yahagi_kancolle_browser/src/layout/panel_style.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/src/layout/flat_empty_text.dart';
import 'package:yahagi_kancolle_browser/src/layout/hd_bottom_strip.dart';
import 'package:yahagi_kancolle_browser/src/settings/battle_status_effect_settings.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/fleet/fleet_ship_status_capsule.dart';
import 'package:yahagi_kancolle_browser/src/fleet/land_base_summary_card.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_status_visuals.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state_controller.dart';

import 'fixtures/kcsapi_fixtures.dart';

void main() {
  testWidgets('flat 下区域切换为文字切换', (tester) async {
    final controller = await _controllerWithLandBases(selectedAreaBaseCount: 2);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PanelStyleScope(
            style: PanelStyle.flat,
            child: SizedBox(
              width: 600,
              child: _CardHarness(controller: controller),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final switcher = find.byKey(const Key('land-base-area-switcher'));
    expect(switcher, findsOneWidget);
    for (final box in tester.widgetList<DecoratedBox>(
      find.descendant(of: switcher, matching: find.byType(DecoratedBox)),
    )) {
      final d = box.decoration;
      expect(
        d is BoxDecoration && (d.color != null || d.border != null),
        isFalse,
      );
    }
    final selector = find.byKey(const Key('land-base-area-selector-62'));
    await tester.tap(selector);
    await tester.pumpAndSettle();
    final selected = tester.widget<Text>(
      find.descendant(of: selector, matching: find.byType(Text)),
    );
    expect(selected.style?.color, const Color(0xffd4a85f));
  });

  testWidgets('HD land bases follow bottom span and reflow live', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final controller = await _controllerWithLandBases(selectedAreaBaseCount: 3);
    final layout = await LayoutSettingsController.load(
      SharedPreferencesLayoutSettingsStore(),
    );
    addTearDown(controller.dispose);
    addTearDown(layout.dispose);
    await layout.setHdSplit(false);
    await layout.setHdModule('wide', 'land_base');
    for (final width in [665.0, 780.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              height: 300,
              child: HdBottomStrip(
                controller: layout,
                moduleBuilder: (_) => SingleChildScrollView(
                  child: LandBaseSummaryCard(
                    controller: controller,
                    collapsed: false,
                    onToggleCollapse: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('land-base-area-selector-62')));
      await tester.pumpAndSettle();
      for (final columns in [1, 2, 3, 2]) {
        await layout.setHdModuleSpan('land_base', columns);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('land-base-area-selector-62')));
        await tester.pumpAndSettle();
        final rows = find.byType(LandBaseAirGroupRow);
        expect(rows, findsNWidgets(3));
        final rects = [for (var i = 0; i < 3; i++) tester.getRect(rows.at(i))];
        for (var i = 0; i < 3; i++) {
          expect(
            rects[i].top,
            closeTo(rects[(i ~/ columns) * columns].top, .1),
          );
          if (i % columns > 0) {
            expect(rects[i].left, greaterThan(rects[i - 1].right));
          }
          if (i >= columns) {
            expect(rects[i].top, greaterThan(rects[i - columns].top));
          }
        }
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets(
    'land base options retain HP and fatigue and reclaim image width',
    (tester) async {
      final base = _base(currentHp: 48, conditions: [3, 1, 1, 1]);
      for (final width in [280.0, 360.0, 560.0]) {
        for (var mask = 0; mask < 16; mask++) {
          final keys = ['portrait', 'bars', 'airPower', 'range'];
          final fields = {
            for (var i = 0; i < 4; i++)
              if ((mask & (1 << i)) != 0) keys[i],
          };
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: width,
                  child: LandBaseAirGroupRow(
                    state: _state(base),
                    base: base,
                    visible: fields,
                  ),
                ),
              ),
            ),
          );
          expect(
            find.byKey(const Key('land-base-hp-value-62-1')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('land-base-fatigue-face-62-1')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('land-base-portrait-62-1')),
            fields.contains('portrait') ? findsOneWidget : findsNothing,
          );
          expect(
            find.byKey(const Key('land-base-hp-meter-62-1')),
            fields.contains('bars') ? findsOneWidget : findsNothing,
          );
          expect(
            find.byKey(const Key('land-base-air-power-chip-62-1')),
            fields.contains('airPower') ? findsOneWidget : findsNothing,
          );
          expect(
            find.byKey(const Key('land-base-range-chip-62-1')),
            fields.contains('range') ? findsOneWidget : findsNothing,
          );
          for (var id = 1; id <= 4; id++) {
            expect(
              find.byKey(Key('land-base-slot-count-62-1-$id')),
              findsOneWidget,
            );
          }
          if (!fields.contains('portrait')) {
            expect(find.byType(ShipHpFrame), findsNothing);
          }
          expect(tester.takeException(), isNull, reason: '$width $mask');
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'damage frames only the portrait and never creates a fatigue face',
    (tester) async {
      await tester.pumpWidget(
        _row(base: _base(currentHp: 48, conditions: const <int>[1, 1, 1, 1])),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.byKey(const Key('land-base-portrait-hp-frame-62-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('land-base-row-hp-frame-62-1')),
        findsNothing,
      );
      expect(find.byKey(const Key('land-base-hp-meter-62-1')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('land-base-status-column-62-1')),
          matching: find.byType(DamagePulseBuilder),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const Key('land-base-fatigue-face-62-1')),
        findsNothing,
      );
    },
  );

  for (final entry in <int, String>{2: 'yellow', 3: 'red'}.entries) {
    testWidgets('${entry.value} fatigue face sits at portrait top-right', (
      tester,
    ) async {
      await tester.pumpWidget(
        _row(
          base: _base(currentHp: 200, conditions: <int>[1, entry.key, 1, 1]),
        ),
      );

      final portrait = tester.getRect(
        find.byKey(const Key('land-base-portrait-62-1')),
      );
      final face = tester.getRect(
        find.byKey(const Key('land-base-fatigue-face-62-1')),
      );
      expect(face.top, closeTo(portrait.top, 0.1));
      expect(face.right, closeTo(portrait.right - 4, 0.1));
    });
  }

  testWidgets('renders four slots including missing planes and relocation', (
    tester,
  ) async {
    await tester.pumpWidget(
      _row(
        base: _base(
          currentHp: 152,
          conditions: const <int>[1, 2, 3, 1],
          states: const <int>[1, 1, 2, 0],
          counts: const <int>[18, 12, 0, 0],
        ),
      ),
    );

    for (var id = 1; id <= 4; id++) {
      expect(find.byKey(Key('land-base-slot-62-1-$id')), findsOneWidget);
    }
    expect(find.text('18'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(
      find.byKey(const Key('land-base-slot-relocating-62-1-3')),
      findsOneWidget,
    );

    final slot = tester.getRect(find.byKey(const Key('land-base-slot-62-1-1')));
    final icon = tester.getRect(
      find.byKey(const Key('land-base-slot-icon-62-1-1')),
    );
    final count = tester.getRect(
      find.byKey(const Key('land-base-slot-count-62-1-1')),
    );
    expect(icon.width, greaterThan(16));
    expect(icon.height, greaterThan(16));
    expect(slot.right - count.right, inInclusiveRange(2, 4));
    expect(count.top - slot.top, inInclusiveRange(2, 4));
    expect(count.top, lessThan(icon.bottom));
  });

  testWidgets('ordinary phone window keeps slot count at eight pixels', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      _row(
        width: 390,
        base: _base(currentHp: 200, conditions: const <int>[1, 1, 1, 1]),
      ),
    );

    final count = find.descendant(
      of: find.byKey(const Key('land-base-slot-count-62-1-1')),
      matching: find.byType(Text),
    );
    expect(tester.widget<Text>(count).style?.fontSize, 8);
  });

  testWidgets('near-square large window enlarges only the slot count', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(673, 841);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      _row(base: _base(currentHp: 200, conditions: const <int>[1, 1, 1, 1])),
    );

    final count = find.descendant(
      of: find.byKey(const Key('land-base-slot-count-62-1-1')),
      matching: find.byType(Text),
    );
    expect(tester.widget<Text>(count).style?.fontSize, 10);
  });

  testWidgets('action kind three is retreat and four is rest', (tester) async {
    await tester.pumpWidget(
      _row(
        base: _base(
          currentHp: 200,
          conditions: const <int>[1, 1, 1, 1],
          actionKind: 3,
        ),
      ),
    );

    var actionChip = find.byKey(const Key('land-base-action-chip-62-1'));
    var actionText = find.descendant(
      of: actionChip,
      matching: find.byType(Text),
    );
    expect(find.text('退避'), findsOneWidget);
    expect(find.text('休息'), findsNothing);
    expect(
      tester.widget<Text>(actionText).style?.color,
      const Color(0xff9ca8b2),
    );

    await tester.pumpWidget(
      _row(
        base: _base(
          currentHp: 200,
          conditions: const <int>[1, 1, 1, 1],
          actionKind: 4,
        ),
      ),
    );

    actionChip = find.byKey(const Key('land-base-action-chip-62-1'));
    actionText = find.descendant(of: actionChip, matching: find.byType(Text));
    expect(find.text('休息'), findsOneWidget);
    expect(find.text('退避'), findsNothing);
    expect(
      tester.widget<Text>(actionText).style?.color,
      const Color(0xff70c697),
    );
  });

  testWidgets('land base info chips match the home ship badge sizing', (
    tester,
  ) async {
    final base = _base(currentHp: 200, conditions: const <int>[1, 1, 1, 1]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const MiniBadge(
                key: Key('ship-badge-size-reference'),
                text: '参照',
                color: Color(0xffa9bac4),
              ),
              SizedBox(
                width: 640,
                child: LandBaseAirGroupRow(state: _state(base), base: base),
              ),
            ],
          ),
        ),
      ),
    );

    final reference = find.byKey(const Key('ship-badge-size-reference'));
    final referenceHeight = tester.getSize(reference).height;
    for (final key in const <Key>[
      Key('land-base-name-62-1'),
      Key('land-base-action-chip-62-1'),
      Key('land-base-air-power-chip-62-1'),
    ]) {
      final chip = find.byKey(key);
      final text = find.descendant(of: chip, matching: find.byType(Text));
      expect(tester.getSize(chip).height, closeTo(referenceHeight, 0.1));
      expect(tester.widget<Text>(text).style?.fontSize, 8);
    }
  });

  testWidgets(
    'ordinary landscape width uses a compact header without overflow',
    (tester) async {
      await tester.pumpWidget(
        _row(
          width: 470,
          base: _base(currentHp: 200, conditions: const <int>[1, 1, 1, 1]),
        ),
      );

      expect(tester.takeException(), isNull);

      final name = tester.getRect(find.byKey(const Key('land-base-name-62-1')));
      final airPower = tester.getRect(
        find.byKey(const Key('land-base-air-power-chip-62-1')),
      );
      final action = tester.getRect(
        find.byKey(const Key('land-base-action-chip-62-1')),
      );
      final range = tester.getRect(
        find.byKey(const Key('land-base-range-chip-62-1')),
      );
      final portrait = tester.getRect(
        find.byKey(const Key('land-base-portrait-62-1')),
      );

      expect(action.center.dy, closeTo(name.center.dy, 0.1));
      expect(airPower.center.dy, closeTo(name.center.dy, 0.1));
      expect(range.center.dy, closeTo(name.center.dy, 0.1));
      expect(portrait.top, greaterThan(name.bottom));
      expect(portrait.size, const Size(68, 32));

      final hpValue = tester.getRect(
        find.byKey(const Key('land-base-hp-value-62-1')),
      );
      final hpText = find.descendant(
        of: find.byKey(const Key('land-base-hp-value-62-1')),
        matching: find.byType(Text),
      );
      final hpMeter = tester.getRect(
        find.byKey(const Key('land-base-hp-meter-62-1')),
      );
      expect(tester.widget<Text>(hpText).style?.fontSize, 11);
      expect(hpMeter.top - hpValue.bottom, closeTo(3, 0.1));
      expect(hpMeter.left, closeTo(hpValue.left, 0.1));
      expect(hpMeter.height, closeTo(7.2, 0.1));

      final hpIcon = tester.widget<Icon>(
        find.byKey(const Key('land-base-hp-icon-62-1')),
      );
      expect(hpIcon.color, const Color(0xffef5a5a));
      expect(hpIcon.size, 10);

      expect(name.height, closeTo(action.height, 0.1));
      expect(name.top, closeTo(action.top, 0.1));
      expect(name.width, lessThan(100));
      expect(action.left - name.right, closeTo(4, 0.1));
      final nameContainer = find.descendant(
        of: find.byKey(const Key('land-base-name-62-1')),
        matching: find.byType(Container),
      );
      expect(
        tester.widget<Container>(nameContainer).decoration,
        isA<BoxDecoration>(),
      );

      final slots = <Rect>[
        for (var id = 1; id <= 4; id++)
          tester.getRect(find.byKey(Key('land-base-slot-62-1-$id'))),
      ];
      for (final slot in slots) {
        expect(slot.width, lessThanOrEqualTo(38));
      }
      for (var index = 1; index < slots.length; index++) {
        expect(slots[index].left - slots[index - 1].right, closeTo(2, 0.1));
      }
    },
  );

  testWidgets('very narrow dashboard column shrinks slots without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _row(
        // The row's horizontal padding leaves the 217.8 px content width
        // reported by the iPhone 17 Pro overflow.
        width: 229.8,
        base: _base(currentHp: 200, conditions: const <int>[1, 1, 1, 1]),
      ),
    );

    expect(tester.takeException(), isNull);

    final slots = <Rect>[
      for (var id = 1; id <= 4; id++)
        tester.getRect(find.byKey(Key('land-base-slot-62-1-$id'))),
    ];
    for (final slot in slots) {
      expect(slot.width, inExclusiveRange(0, 20));
      expect(
        slot.right,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const Key('land-base-row-62-1'))).right,
        ),
      );
    }
  });

  testWidgets('single-column spare width expands hp toward right slots', (
    tester,
  ) async {
    await tester.pumpWidget(
      _row(
        width: 640,
        base: _base(currentHp: 200, conditions: const <int>[1, 1, 1, 1]),
      ),
    );

    final row = tester.getRect(find.byKey(const Key('land-base-row-62-1')));
    final status = tester.getRect(
      find.byKey(const Key('land-base-status-column-62-1')),
    );
    final squadrons = tester.getRect(
      find.byKey(const Key('land-base-squadron-strip-62-1')),
    );

    expect(status.width, greaterThan(150));
    expect(squadrons.left - status.right, closeTo(7, 0.1));
    expect(row.right - squadrons.right, closeTo(7.2, 0.1));
  });

  testWidgets('card switches areas and collapses without a details panel', (
    tester,
  ) async {
    final controller = await _controllerWithLandBases();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_card(controller));
    await tester.pump();

    expect(find.text('[6] 中部海域'), findsNothing);
    expect(find.text('其他海域基地'), findsOneWidget);
    expect(find.text('第一基地航空队'), findsNothing);

    await tester.tap(find.byKey(const Key('land-base-area-selector-62')));
    await tester.pump();
    expect(find.text('[62] 反击！第三十一战队的战斗'), findsNothing);
    expect(find.text('第一基地航空队'), findsOneWidget);
    expect(find.text('其他海域基地'), findsNothing);

    await tester.tap(find.byKey(const Key('land-base-collapse-button')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(LandBaseAirGroupRow), findsNothing);
    expect(find.text('点击航空队查看装备详情'), findsNothing);
  });

  testWidgets('area heading omits the land base count', (tester) async {
    final controller = await _controllerWithLandBases(selectedAreaBaseCount: 2);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_card(controller));
    await tester.tap(find.byKey(const Key('land-base-area-selector-62')));
    await tester.pump();

    expect(find.text('2 支航空队'), findsNothing);
  });

  testWidgets('expanded foldable width arranges three bases in a 2x2 grid', (
    tester,
  ) async {
    final controller = await _controllerWithLandBases(selectedAreaBaseCount: 3);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_card(controller, width: 760));
    await tester.tap(find.byKey(const Key('land-base-area-selector-62')));
    await tester.pump();

    final first = tester.getRect(find.byKey(const Key('land-base-row-62-1')));
    final second = tester.getRect(find.byKey(const Key('land-base-row-62-2')));
    final third = tester.getRect(find.byKey(const Key('land-base-row-62-3')));

    expect(first.top, closeTo(second.top, 0.1));
    expect(second.left, greaterThan(first.right));
    expect(third.left, closeTo(first.left, 0.1));
    expect(third.top, greaterThan(first.bottom));
    expect(third.width, closeTo(first.width, 0.1));
    expect(third.right, lessThan(second.right));
    expect(
      tester
          .getRect(find.byKey(const Key('land-base-status-column-62-1')))
          .width,
      closeTo(68, 0.1),
    );
  });

  testWidgets('ordinary width keeps land bases in one column', (tester) async {
    final controller = await _controllerWithLandBases(selectedAreaBaseCount: 3);
    addTearDown(controller.dispose);

    await tester.pumpWidget(_card(controller, width: 600));
    await tester.tap(find.byKey(const Key('land-base-area-selector-62')));
    await tester.pump();

    final first = tester.getRect(find.byKey(const Key('land-base-row-62-1')));
    final second = tester.getRect(find.byKey(const Key('land-base-row-62-2')));
    final third = tester.getRect(find.byKey(const Key('land-base-row-62-3')));

    expect(second.left, closeTo(first.left, 0.1));
    expect(second.top, greaterThan(first.bottom));
    expect(third.left, closeTo(first.left, 0.1));
    expect(third.top, greaterThan(second.bottom));
  });
  testWidgets('flat scope drops tile fills but keeps every land base item', (
    tester,
  ) async {
    final base = _base(currentHp: 150, conditions: const <int>[60, 1, 1, 1]);
    await tester.pumpWidget(_flatRow(base: base, width: 200));

    expect(tester.takeException(), isNull);
    final row = find.byKey(const Key('land-base-row-62-1'));
    // 受损脉冲的辉光不是底色块，单独排除。
    final pulseGlows = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(DamagePulseBuilder),
            matching: find.byType(DecoratedBox),
          ),
        )
        .toSet();
    final filled = tester
        .widgetList<DecoratedBox>(
          find.descendant(of: row, matching: find.byType(DecoratedBox)),
        )
        .where((box) {
          final decoration = box.decoration;
          return !pulseGlows.contains(box) &&
              decoration is BoxDecoration &&
              decoration.shape == BoxShape.rectangle &&
              (decoration.color != null ||
                  decoration.borderRadius != null ||
                  decoration.boxShadow != null);
        });
    expect(filled, isEmpty);
    expect(find.text('第一基地航空队'), findsOneWidget);
    for (final key in const <String>[
      'land-base-action-chip-62-1',
      'land-base-air-power-chip-62-1',
      'land-base-range-chip-62-1',
      'land-base-hp-value-62-1',
      'land-base-hp-meter-62-1',
      'land-base-portrait-62-1',
      'land-base-squadron-strip-62-1',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
    expect(find.textContaining('150/200'), findsOneWidget);
    for (final key in const <String>[
      'land-base-status-column-62-1',
      'land-base-fatigue-face-62-1',
      'land-base-portrait-hp-frame-62-1',
    ]) {
      expect(find.byKey(Key(key)), findsNothing, reason: key);
    }
    expect(
      tester
          .widget<Text>(find.byKey(const Key('land-base-air-power-chip-62-1')))
          .style
          ?.fontSize,
      11,
    );
    for (var id = 1; id <= 4; id++) {
      expect(find.byKey(Key('land-base-slot-62-1-$id')), findsOneWidget);
    }
  });

  group('flat 中队格版式', () {
    // 测试字体每字 1em，与真机字形尺寸偏差大；行高与等宽验收用应用实际的中文字体量。
    setUpAll(() async {
      await (FontLoader(
        _appFont,
      )..addFont(rootBundle.load('assets/fonts/HarmonyOS_Sans_SC.ttf'))).load();
    });

    testWidgets('flat 下宽 190 时四格等宽、无溢出且整行高度 <=40', (tester) async {
      final base = _base(currentHp: 150, conditions: const <int>[1, 1, 1, 1]);
      tester.view.physicalSize = const Size(190, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _flatRow(
          base: base,
          width: 190,
          visible: const <String>{'bars', 'airPower', 'range'},
        ),
      );

      expect(tester.takeException(), isNull);
      final widths = <double>[
        for (var id = 1; id <= 4; id++)
          tester.getSize(find.byKey(Key('land-base-slot-62-1-$id'))).width,
      ];
      for (final width in widths) {
        expect(width, closeTo(widths.first, 0.01));
      }
      expect(
        tester.getSize(find.byKey(const Key('land-base-slot-62-1-1'))).height,
        18,
      );
      expect(
        tester.getSize(find.byKey(const Key('land-base-row-62-1'))).height,
        lessThanOrEqualTo(40),
      );

      await tester.pumpWidget(
        _flatRow(
          base: base,
          width: 190,
          textScaler: const TextScaler.linear(1.3),
          visible: const <String>{'bars', 'airPower', 'range'},
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('flat 下头像铺在两行底下，不增加整行高度', (tester) async {
      final base = _base(currentHp: 150, conditions: const <int>[1, 1, 1, 1]);
      await tester.pumpWidget(
        _flatRow(
          base: base,
          width: 190,
          visible: const <String>{'bars', 'airPower', 'range'},
        ),
      );
      final row = find.byKey(const Key('land-base-row-62-1'));
      final withoutPortrait = tester.getSize(row).height;
      expect(find.byKey(const Key('land-base-portrait-62-1')), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('land-base-name-62-1')))
            .style
            ?.shadows,
        isNull,
      );

      await tester.pumpWidget(_flatRow(base: base, width: 190));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('land-base-portrait-62-1')), findsOneWidget);
      expect(tester.getSize(row).height, withoutPortrait);
      for (final key in const <String>[
        'land-base-action-chip-62-1',
        'land-base-name-62-1',
        'land-base-air-power-chip-62-1',
        'land-base-slot-count-62-1-1',
      ]) {
        expect(
          tester.widget<Text>(find.byKey(Key(key))).style?.shadows,
          const <Shadow>[Shadow(color: Colors.black, blurRadius: 3)],
          reason: key,
        );
      }
    });
  });

  testWidgets('flat 下基地 HP 只在已知且受损时显示', (tester) async {
    for (final currentHp in const <int?>[200, null]) {
      final base = _base(
        currentHp: currentHp,
        conditions: const <int>[1, 1, 1, 1],
      );
      await tester.pumpWidget(_flatRow(base: base, width: 200));
      expect(
        find.byKey(const Key('land-base-hp-value-62-1')),
        findsNothing,
        reason: '$currentHp',
      );
      expect(find.byKey(const Key('land-base-hp-meter-62-1')), findsNothing);
    }

    final damaged = _base(currentHp: 90, conditions: const <int>[1, 1, 1, 1]);
    await tester.pumpWidget(
      _flatRow(
        base: damaged,
        width: 200,
        visible: const <String>{'airPower', 'range'},
      ),
    );
    expect(find.byKey(const Key('land-base-hp-value-62-1')), findsOneWidget);
    expect(find.byKey(const Key('land-base-hp-icon-62-1')), findsOneWidget);
    expect(find.text('90/200'), findsOneWidget);
    expect(find.byKey(const Key('land-base-hp-meter-62-1')), findsNothing);
  });

  testWidgets('flat 下受损脉冲跟随 damagePulseMode', (tester) async {
    final base = _base(currentHp: 40, conditions: const <int>[1, 1, 1, 1]);
    final hpValue = find.byKey(const Key('land-base-hp-value-62-1'));
    final pulse = find.descendant(
      of: hpValue,
      matching: find.byType(DamagePulseBuilder),
    );
    final glow = find.descendant(
      of: hpValue,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            (widget.decoration as BoxDecoration).boxShadow != null,
      ),
    );
    for (final visible in const <Set<String>>[
      <String>{'bars', 'airPower', 'range'},
      <String>{'airPower', 'range'},
    ]) {
      await tester.pumpWidget(
        _flatRow(base: base, width: 200, visible: visible),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(pulse, findsOneWidget, reason: '$visible');
      expect(glow, findsOneWidget, reason: '$visible');

      await tester.pumpWidget(
        _flatRow(
          base: base,
          width: 200,
          visible: visible,
          damagePulseMode: DamagePulseFilter.off,
        ),
      );
      expect(hpValue, findsOneWidget);
      expect(pulse, findsNothing, reason: '$visible');
      expect(glow, findsNothing, reason: '$visible');
    }
  });

  testWidgets('flat 下熟练度、疲劳下划线与未满搭载数', (tester) async {
    final base = _base(
      currentHp: 200,
      conditions: const <int>[1, 2, 3, 1],
      counts: const <int>[18, 18, 18, 12],
    );
    await tester.pumpWidget(
      _flatRow(
        base: base,
        state: _state(base, proficiencies: const <int>[7, 0, 3, 0]),
        width: 200,
      ),
    );

    expect(tester.takeException(), isNull);
    for (final entry in const <int, bool>{
      1: true,
      2: false,
      3: true,
      4: false,
    }.entries) {
      expect(
        find.byKey(Key('land-base-slot-proficiency-62-1-${entry.key}')),
        entry.value ? findsOneWidget : findsNothing,
        reason: 'squadron ${entry.key}',
      );
    }

    Decoration? decorationOf(int id) => tester
        .widget<Container>(find.byKey(Key('land-base-slot-62-1-$id')))
        .decoration;
    expect(decorationOf(1), isNull);
    expect(decorationOf(4), isNull);
    for (final entry in const <int, Color>{
      2: Color(0xffe7ad45),
      3: Color(0xffef5a5a),
    }.entries) {
      final decoration = decorationOf(entry.key) as BoxDecoration;
      final border = decoration.border as Border;
      expect(border.bottom.width, 2);
      expect(border.bottom.color, entry.value);
      expect(border.top, BorderSide.none);
      expect(decoration.color, isNull);
      expect(decoration.borderRadius, isNull);
      expect(decoration.boxShadow, isNull);
    }

    Color? countColor(int id) => tester
        .widget<Text>(find.byKey(Key('land-base-slot-count-62-1-$id')))
        .style
        ?.color;
    expect(countColor(4), const Color(0xffff8b78));
    expect(countColor(1), const Color(0xffe8f1f5));
  });

  testWidgets('flat 空态使用 FlatEmptyText', (tester) async {
    final controller = GameStateController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PanelStyleScope(
            style: PanelStyle.flat,
            child: SizedBox(
              width: 200,
              child: _CardHarness(controller: controller),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FlatEmptyText), findsOneWidget);
  });
}

const _appFont = 'HarmonyOS_Sans_SC';

Widget _flatRow({
  required LandBaseState base,
  GameState? state,
  required double width,
  Set<String> visible = const <String>{'portrait', 'bars', 'airPower', 'range'},
  TextScaler textScaler = TextScaler.noScaling,
  DamagePulseFilter damagePulseMode = DamagePulseFilter.all,
}) => MaterialApp(
  theme: ThemeData(fontFamily: _appFont),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: textScaler),
    child: child!,
  ),
  home: Scaffold(
    body: PanelStyleScope(
      style: PanelStyle.flat,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: LandBaseAirGroupRow(
            state: state ?? _state(base),
            base: base,
            visible: visible,
            damagePulseMode: damagePulseMode,
          ),
        ),
      ),
    ),
  ),
);

LandBaseState _base({
  required int? currentHp,
  required List<int> conditions,
  int actionKind = 1,
  List<int> states = const <int>[1, 1, 1, 1],
  List<int> counts = const <int>[18, 18, 18, 18],
}) => LandBaseState(
  areaId: 62,
  baseId: 1,
  name: '第一基地航空队',
  actionKind: actionKind,
  distanceBase: 7,
  maxHp: 200,
  currentHp: currentHp,
  squadrons: <LandBaseSquadronState>[
    for (var index = 0; index < 4; index++)
      LandBaseSquadronState(
        squadronId: index + 1,
        state: states[index],
        slotItemId: 1001 + index,
        currentCount: counts[index],
        maxCount: 18,
        condition: conditions[index],
      ),
  ],
);

Widget _row({required LandBaseState base, double width = 640}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: width,
      child: LandBaseAirGroupRow(state: _state(base), base: base),
    ),
  ),
);

GameState _state(
  LandBaseState base, {
  List<int> proficiencies = const <int>[0, 0, 0, 0],
}) => GameState(
  serverOrigin: 'https://example.test',
  landBases: <LandBaseState>[base],
  masterSlotItems: <int, MasterSlotItem>{
    for (var index = 0; index < 4; index++)
      201 + index: MasterSlotItem(
        id: 201 + index,
        name: '陆航装备${index + 1}',
        antiAir: 10,
        type: const <int>[0, 0, 6, 6],
      ),
  },
  slotItems: <int, OwnedSlotItem>{
    for (var index = 0; index < 4; index++)
      1001 + index: OwnedSlotItem(
        id: 1001 + index,
        masterId: 201 + index,
        proficiency: proficiencies[index],
      ),
  },
);

Future<GameStateController> _controllerWithLandBases({
  int selectedAreaBaseCount = 1,
}) async {
  final controller = GameStateController();
  controller
    ..accept(
      kcsapiEvent('/kcsapi/api_start2/getData', <String, Object?>{
        'api_mst_stype': const <Object?>[],
        'api_mst_ship': const <Object?>[],
        'api_mst_maparea': <Object?>[
          <String, Object?>{'api_id': 6, 'api_name': '中部海域'},
          <String, Object?>{'api_id': 62, 'api_name': '反击！第三十一战队的战斗'},
        ],
      }),
    )
    ..accept(
      kcsapiEvent('/kcsapi/api_get_member/mapinfo', <String, Object?>{
        'api_map_info': const <Object?>[],
        'api_air_base': <Object?>[
          <String, Object?>{
            'api_area_id': 6,
            'api_rid': 1,
            'api_name': '其他海域基地',
          },
          <String, Object?>{
            'api_area_id': 62,
            'api_rid': 1,
            'api_name': '第一基地航空队',
          },
          for (var baseId = 2; baseId <= selectedAreaBaseCount; baseId++)
            <String, Object?>{
              'api_area_id': 62,
              'api_rid': baseId,
              'api_name': baseId == 2 ? '第二基地航空队' : '第三基地航空队',
            },
        ],
      }),
    );
  await controller.idle;
  return controller;
}

Widget _card(GameStateController controller, {double? width}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: width,
      child: _CardHarness(controller: controller),
    ),
  ),
);

class _CardHarness extends StatefulWidget {
  const _CardHarness({required this.controller});

  final GameStateController controller;

  @override
  State<_CardHarness> createState() => _CardHarnessState();
}

class _CardHarnessState extends State<_CardHarness> {
  var _collapsed = false;

  @override
  Widget build(BuildContext context) => LandBaseSummaryCard(
    controller: widget.controller,
    collapsed: _collapsed,
    onToggleCollapse: () => setState(() => _collapsed = !_collapsed),
  );
}
