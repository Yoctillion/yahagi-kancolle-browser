import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/battle/battle_contact.dart';
import 'package:yahagi_kancolle_browser/src/fleet/equipment_type_icon.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';

const _slotItems = <int, MasterSlotItem>{
  54: MasterSlotItem(
    id: 54,
    name: '彩雲',
    accuracy: 2,
    type: <int>[5, 7, 9, 9, 0],
  ),
  102: MasterSlotItem(
    id: 102,
    name: '九八式水上偵察機(夜偵)',
    accuracy: 3,
    type: <int>[5, 7, 10, 50, 0],
  ),
};

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  ),
);

Finder _inSide(String side, Finder matching) => find.descendant(
  of: find.byKey(Key('contact-plane-$side')),
  matching: matching,
);

void main() {
  test('day contact multiplier follows plane accuracy', () {
    expect(dayContactPercent(0), 112);
    expect(dayContactPercent(1), 112);
    expect(dayContactPercent(2), 117);
    expect(dayContactPercent(3), 120);
    expect(dayContactPercent(5), 120);
  });

  test('night contact power bonus follows plane accuracy', () {
    expect(nightContactPowerBonus(0), 5);
    expect(nightContactPowerBonus(1), 5);
    expect(nightContactPowerBonus(2), 7);
    expect(nightContactPowerBonus(3), 9);
  });

  testWidgets('marks show icon and percent per side', (tester) async {
    await _pump(
      tester,
      const ContactPlaneMarks(
        friendPlaneId: 54,
        enemyPlaneId: 102,
        slotItems: _slotItems,
        night: false,
      ),
    );
    expect(_inSide('friend', find.text('117%')), findsOneWidget);
    expect(_inSide('enemy', find.text('120%')), findsOneWidget);
    expect(find.byType(EquipmentTypeIconImage), findsNWidgets(2));
    final friendIcon = tester.widget<EquipmentTypeIconImage>(
      _inSide('friend', find.byType(EquipmentTypeIconImage)),
    );
    expect(friendIcon.iconId, 9);
  });

  testWidgets('only enemy contact renders one side', (tester) async {
    await _pump(
      tester,
      const ContactPlaneMarks(
        friendPlaneId: -1,
        enemyPlaneId: 102,
        slotItems: _slotItems,
        night: false,
      ),
    );
    expect(find.byKey(const Key('contact-plane-friend')), findsNothing);
    expect(find.byKey(const Key('contact-plane-enemy')), findsOneWidget);
  });

  testWidgets('no contact renders nothing', (tester) async {
    await _pump(
      tester,
      const ContactPlaneMarks(
        friendPlaneId: -1,
        enemyPlaneId: -1,
        slotItems: _slotItems,
        night: false,
      ),
    );
    expect(find.byType(EquipmentTypeIconImage), findsNothing);
  });

  testWidgets('unknown plane falls back to base multiplier', (tester) async {
    await _pump(
      tester,
      const ContactPlaneMarks(
        friendPlaneId: 999,
        enemyPlaneId: -1,
        slotItems: _slotItems,
        night: false,
      ),
    );
    expect(_inSide('friend', find.text('112%')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap shows detail line', (tester) async {
    await _pump(
      tester,
      const ContactPlaneMarks(
        friendPlaneId: 54,
        enemyPlaneId: -1,
        slotItems: _slotItems,
        night: false,
      ),
    );
    await tester.tap(find.byKey(const Key('contact-plane-marks')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('×1.17', findRichText: true), findsOneWidget);
    expect(find.textContaining('彩雲', findRichText: true), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('night marks show power bonus', (tester) async {
    await _pump(
      tester,
      const ContactPlaneMarks(
        friendPlaneId: 54,
        enemyPlaneId: -1,
        slotItems: _slotItems,
        night: true,
      ),
    );
    expect(_inSide('friend', find.text('+7')), findsOneWidget);
  });
}
