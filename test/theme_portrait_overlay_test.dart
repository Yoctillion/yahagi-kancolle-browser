import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_status_visuals.dart';
import 'package:yahagi_kancolle_browser/src/settings/battle_status_effect_settings.dart';
import 'package:yahagi_kancolle_browser/src/theme/app_palette.dart';
import 'package:yahagi_kancolle_browser/src/theme/app_theme.dart';

void main() {
  testWidgets(
    'morale sparkles retain their light over ship artwork in every theme',
    (tester) async {
      for (final mode in AppThemeMode.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: createAppTheme(mode: mode),
            home: const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 160,
                  height: 64,
                  child: ColoredBox(
                    color: Color(0xff102030),
                    child: ShipMoraleMark(
                      shipId: 1,
                      value: 60,
                      sparklePulse: AlwaysStoppedAnimation(.25),
                      sparkleMode: MoraleSparkleMode.steady,
                      showTextBadge: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final stars = tester.widgetList<Icon>(
          find.descendant(
            of: find.byKey(const Key('fleet-morale-stars-1')),
            matching: find.byType(Icon),
          ),
        );
        expect(stars, hasLength(6));
        for (final star in stars) {
          expect(star.color, const Color(0xfffff7a4), reason: mode.name);
          expect(star.shadows!.first.color, Colors.white, reason: mode.name);
          expect(
            star.shadows!.last.color,
            const Color(0xffffcf3f),
            reason: mode.name,
          );
        }
        expect(tester.takeException(), isNull);
      }
    },
  );
}
