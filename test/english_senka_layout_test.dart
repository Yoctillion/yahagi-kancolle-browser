import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/senka/senka_controller.dart';

import 'senka_page_test.dart'
    as fixture
    show MemorySenkaStore, sampleState, pumpSenka;

void main() {
  for (final size in const [
    Size(320, 900),
    Size(390, 844),
    Size(844, 390),
    Size(1280, 680),
  ]) {
    for (final textScale in [1.0, 1.3]) {
      testWidgets('English Senka pages fit $size at scale $textScale', (
        tester,
      ) async {
        final controller = SenkaController(
          store: fixture.MemorySenkaStore(fixture.sampleState()),
          now: () => DateTime.utc(2026, 8, 10),
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        await fixture.pumpSenka(
          tester,
          controller,
          size,
          locale: const Locale('en'),
          textScale: textScale,
        );
        expect(find.text('Server'), findsOneWidget);
        expect(find.text('横須賀鎮守府'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'English Senka info');
        await tester.ensureVisible(
          find.byKey(const Key('senka-sortie-row-3-2')),
        );
        await tester.ensureVisible(find.byKey(const Key('senka-show-hidden')));
        await tester.tap(find.byKey(const Key('senka-show-hidden')));
        await tester.pump();
        expect(find.byKey(const Key('senka-sortie-row-2-1')), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'English sortie filters',
        );

        await tester.tap(find.byKey(const Key('senka-tab-calendar')));
        await tester.pump();
        expect(find.text('Senka calendar: 2026-8'), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('senka-day-detail')));
        expect(
          tester.takeException(),
          isNull,
          reason: 'English Senka calendar',
        );

        await tester.tap(find.byKey(const Key('senka-tab-calculator')));
        await tester.pump();
        expect(find.text('Target senka'), findsOneWidget);
        expect(find.byKey(const Key('senka-projected-card')), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Tooltip &&
                (widget.message?.startsWith('鎮守府近海（1-5）') ?? false),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull, reason: 'English calculator');
        await tester.ensureVisible(find.text('One-time senka quests'));
        await tester.ensureVisible(
          find.byKey(const Key('senka-calculator-footer')),
        );
        expect(tester.takeException(), isNull, reason: 'English reward groups');
        expect(controller.state.nickname, '矢矧');
        expect(
          controller.state.serverOrigin,
          'https://w01.kancolle-server.com',
        );
      });
    }
  }
}
