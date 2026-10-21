import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/theme/app_palette.dart';
import 'package:yahagi_kancolle_browser/src/theme/app_theme.dart';

void main() {
  test('original dark palette preserves every source color and alpha', () {
    const palette = AppPalette(AppThemeMode.dark);
    for (final color in <Color>[
      const Color(0xff0a1823),
      const Color(0xff142735),
      const Color(0xffd4a85f),
      const Color(0xff8197a5),
      const Color(0xffd33d17),
      const Color(0x4d83d5c8),
      Colors.white70,
      Colors.transparent,
    ]) {
      expect(palette.color(color), color);
    }
  });

  test('approved light themes map surfaces, text and accent independently', () {
    const sea = AppPalette(AppThemeMode.seaSalt);
    const sky = AppPalette(AppThemeMode.skyBlue);
    expect(sea.color(const Color(0xff0a1823)), const Color(0xffeaf2f2));
    expect(sky.color(const Color(0xff0a1823)), const Color(0xffedf2fa));
    expect(sea.color(const Color(0xff142735)), const Color(0xfffcfefe));
    expect(sky.color(const Color(0xff142735)), const Color(0xfffdfdff));
    expect(sea.color(const Color(0xffd4a85f)), const Color(0xff14666e));
    expect(sky.color(const Color(0xffd4a85f)), const Color(0xff355fa8));
    expect(sea.color(Colors.white), const Color(0xff203b43));
    expect(sky.color(Colors.white), const Color(0xff273954));
    expect(sea.color(const Color(0xff8197a5)), const Color(0xff526e77));
    expect(sky.color(const Color(0xff8197a5)), const Color(0xff566882));
  });

  test('semantic hues and transparent overlays survive light adaptation', () {
    for (final mode in [AppThemeMode.seaSalt, AppThemeMode.skyBlue]) {
      final palette = AppPalette(mode);
      expect(palette.color(Colors.transparent), Colors.transparent);
      expect(palette.color(Colors.black38), Colors.black38);
      final red = palette.color(const Color(0xffd33d17));
      final green = palette.color(const Color(0xff29a634));
      final orange = palette.color(const Color(0xfff57c00));
      final yellow = palette.color(const Color(0xffffc940));
      expect(red.r, greaterThan(red.g));
      expect(green.g, greaterThan(green.r));
      expect(orange, isNot(yellow));
      expect(red, isNot(orange));
      final translucent = palette.color(const Color(0x4d83d5c8));
      expect(translucent.a, closeTo(0x4d / 255, 0.00001));
    }
  });

  test('all source color literals preserve alpha and map idempotently', () {
    final colors = <Color>{};
    final pattern = RegExp(r'Color\(0x([0-9a-fA-F]{8})\)');
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      for (final match in pattern.allMatches(file.readAsStringSync())) {
        colors.add(Color(int.parse(match.group(1)!, radix: 16)));
      }
    }
    expect(colors.length, greaterThan(150));
    for (final mode in AppThemeMode.values) {
      final palette = AppPalette(mode);
      for (final source in colors) {
        final target = palette.color(source);
        expect(target.a, source.a, reason: '$mode $source');
        expect(palette.color(target), target, reason: '$mode $source');
        if (mode == AppThemeMode.dark) expect(target, same(source));
      }
    }
  });

  test(
    'light UI text has sufficient contrast and repeated mapping is stable',
    () {
      for (final mode in [AppThemeMode.seaSalt, AppThemeMode.skyBlue]) {
        final p = AppPalette(mode);
        for (final pair in [
          (p.foreground, p.surface),
          (p.muted, p.inner),
          (p.muted, p.raised),
          (p.muted, p.accentSurface),
          (p.accent, p.accentSurface),
          (p.success, p.successSurface),
          (p.info, p.infoSurface),
          (p.warning, p.warningSurface),
          (p.orange, p.orangeSurface),
          (p.error, p.errorSurface),
          (p.gold, p.goldSurface),
        ]) {
          final a = pair.$1.computeLuminance();
          final b = pair.$2.computeLuminance();
          final ratio =
              (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05);
          expect(ratio, greaterThanOrEqualTo(4.5), reason: '$mode $pair');
          expect(p.color(pair.$1), pair.$1);
          expect(p.color(pair.$2), pair.$2);
        }
      }
    },
  );

  test('theme changes preserve typography and standard widget dimensions', () {
    final dark = createAppTheme(mode: AppThemeMode.dark, fontFamily: 'Example');
    for (final mode in [AppThemeMode.seaSalt, AppThemeMode.skyBlue]) {
      final theme = createAppTheme(mode: mode, fontFamily: 'Example');
      expect(
        theme.textTheme.bodyMedium?.fontSize,
        dark.textTheme.bodyMedium?.fontSize,
      );
      expect(
        theme.textTheme.bodyMedium?.fontWeight,
        dark.textTheme.bodyMedium?.fontWeight,
      );
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Example');
      expect(theme.visualDensity, dark.visualDensity);
      expect(theme.materialTapTargetSize, dark.materialTapTargetSize);
      expect(theme.brightness, Brightness.light);
    }
  });

  test('light themes do not inherit unreadable dark legacy control colors', () {
    for (final mode in [AppThemeMode.seaSalt, AppThemeMode.skyBlue]) {
      final palette = AppPalette(mode);
      final theme = createAppTheme(mode: mode);
      for (final foreground in [theme.hintColor, theme.unselectedWidgetColor]) {
        final visible = Color.alphaBlend(foreground, palette.surface);
        final contrast =
            (palette.surface.computeLuminance() + .05) /
            (visible.computeLuminance() + .05);
        expect(
          contrast,
          greaterThanOrEqualTo(4.5),
          reason: '$mode $foreground',
        );
      }
    }
  });

  testWidgets('switching palettes keeps child state and layout intact', (
    tester,
  ) async {
    final mode = ValueNotifier(AppThemeMode.dark);
    addTearDown(mode.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<AppThemeMode>(
        valueListenable: mode,
        builder: (context, value, child) => MaterialApp(
          theme: createAppTheme(mode: value),
          home: const Scaffold(body: _StatefulProbe()),
        ),
      ),
    );
    final initialState = tester.state(find.byType(_StatefulProbe));
    final initialRect = tester.getRect(find.byKey(const Key('theme-probe')));
    for (final value in [
      AppThemeMode.seaSalt,
      AppThemeMode.skyBlue,
      AppThemeMode.dark,
    ]) {
      mode.value = value;
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(_StatefulProbe)), same(initialState));
      expect(tester.getRect(find.byKey(const Key('theme-probe'))), initialRect);
      final box = tester.widget<ColoredBox>(
        find.byKey(const Key('theme-probe')),
      );
      expect(box.color, AppPalette(value).color(const Color(0xff142735)));
      expect(tester.takeException(), isNull);
    }
  });
}

class _StatefulProbe extends StatefulWidget {
  const _StatefulProbe();
  @override
  State<_StatefulProbe> createState() => _StatefulProbeState();
}

class _StatefulProbeState extends State<_StatefulProbe> {
  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const Key('theme-probe'),
    color: appColor(context, const Color(0xff142735)),
    child: const SizedBox(width: 170, height: 90),
  );
}
