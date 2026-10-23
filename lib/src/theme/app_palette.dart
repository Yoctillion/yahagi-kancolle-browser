import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Maps the existing UI paint colors without changing widget geometry or assets.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette(this.mode);

  factory AppPalette.forMode(AppThemeMode mode) => AppPalette(mode);

  final AppThemeMode mode;
  static final _colorCache = <AppThemeMode, Map<int, Color>>{};
  bool get isDark => mode == AppThemeMode.dark;
  bool get _sea => mode == AppThemeMode.seaSalt;
  Brightness get brightness => isDark ? Brightness.dark : Brightness.light;

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ??
      const AppPalette(AppThemeMode.dark);

  Color get background =>
      isDark ? const Color(0xff0a1823) : _light(0xffeaf2f2, 0xffedf2fa);
  Color get surface =>
      isDark ? const Color(0xff142735) : _light(0xfffcfefe, 0xfffdfdff);
  Color get chrome =>
      isDark ? const Color(0xff122431) : _light(0xfff9fcfc, 0xfff9fbff);
  Color get navigation =>
      isDark ? const Color(0xff0c1c27) : _light(0xfff2f8f7, 0xfff3f6fc);
  Color get inner =>
      isDark ? const Color(0xff102331) : _light(0xffedf4f4, 0xffeef3fb);
  Color get raised =>
      isDark ? const Color(0xff1c3547) : _light(0xffe1ecec, 0xffe0e8f5);
  Color get border =>
      isDark ? const Color(0xff294052) : _light(0xffccdcdd, 0xffced9eb);
  Color get strongBorder =>
      isDark ? const Color(0xff4c6b84) : _light(0xffa8c4c6, 0xffafc2df);
  Color get foreground =>
      isDark ? const Color(0xffdce6eb) : _light(0xff203b43, 0xff273954);
  Color get muted =>
      isDark ? const Color(0xff8197a5) : _light(0xff526e77, 0xff566882);
  Color get accent =>
      isDark ? const Color(0xffd4a85f) : _light(0xff14666e, 0xff355fa8);
  Color get accentSurface =>
      isDark ? const Color(0xff3c3323) : _light(0xffdceeed, 0xffe0eafb);
  Color get accentBorder =>
      isDark ? const Color(0xff927440) : _light(0xff89b4b6, 0xff99b3df);
  Color get success =>
      isDark ? const Color(0xff65d493) : _light(0xff216d4f, 0xff2c735a);
  Color get successSurface =>
      isDark ? const Color(0xff183e38) : _light(0xffe2f0e8, 0xffe4f2e9);
  Color get info =>
      isDark ? const Color(0xff84c0dc) : _light(0xff256780, 0xff355fa8);
  Color get infoSurface =>
      isDark ? const Color(0xff1b3549) : _light(0xffe1eef4, 0xffe0eafb);
  Color get gold => const Color(0xff805c1a);
  Color get goldSurface => const Color(0xfff4ead3);
  Color get warning => _light(0xff8a5715, 0xff875b17);
  Color get warningSurface => _light(0xfff7ead3, 0xfffaedcf);
  Color get orange => _light(0xffa64a1c, 0xffa04c21);
  Color get orangeSurface => _light(0xfff8e7dc, 0xfffbe9df);
  Color get error => _light(0xffaf3834, 0xffae3e4c);
  Color get errorSurface => _light(0xfffbeae7, 0xfffce9ed);
  Color get purple => const Color(0xff70539b);
  Color get purpleSurface => const Color(0xffeee7f7);

  Color _light(int sea, int sky) => Color(_sea ? sea : sky);

  /// Dark mode is an exact identity mapping, including opacity and custom hues.
  Color color(Color source) {
    if (isDark || source.a == 0) return source;
    final rgb = source.toARGB32() & 0x00ffffff;
    // Keep shadows, barriers and game placeholders black.
    if (rgb == 0) return source;
    final cache = _colorCache.putIfAbsent(mode, () => <int, Color>{});
    if (cache.length > 1024) cache.clear();
    final target = cache.putIfAbsent(rgb, () => _mapped(rgb));
    return source.a == 1 ? target : target.withValues(alpha: source.a);
  }

  Color adapt(Color source) => color(source);

  Color _mapped(int rgb) {
    // Mapping is idempotent when a shared style is adapted again by its caller.
    for (final color in <Color>[
      background,
      surface,
      chrome,
      navigation,
      inner,
      raised,
      border,
      strongBorder,
      foreground,
      muted,
      accent,
      accentSurface,
      accentBorder,
      success,
      successSurface,
      info,
      infoSurface,
      gold,
      goldSurface,
      warning,
      warningSurface,
      orange,
      orangeSurface,
      error,
      errorSurface,
      purple,
      purpleSurface,
    ]) {
      if ((color.toARGB32() & 0x00ffffff) == rgb) return color;
    }
    return switch (rgb) {
      0x081521 || 0x081923 || 0x0a1823 || 0x0b1720 || 0x07121b => background,
      0x142735 => surface,
      0x122431 || 0x122531 => chrome,
      0x0c1c27 || 0x0b202d || 0x0b1d29 || 0x0c1d29 || 0x0d1d28 => navigation,
      0x0d1a26 ||
      0x0d1d29 ||
      0x102331 ||
      0x10212e ||
      0x102532 ||
      0x102936 ||
      0x102a38 ||
      0x102431 ||
      0x101d27 => inner,
      0x172a38 ||
      0x1c3547 ||
      0x1a3447 ||
      0x163247 ||
      0x263f4d ||
      0x263e4d ||
      0x203746 => raised,
      0x294052 || 0x315064 || 0x385064 || 0x294657 || 0x284354 => border,
      0x4c6b84 || 0x456174 => strongBorder,
      0xd4a85f || 0xe0b25c || 0xe0ad4f || 0xd8ad60 || 0xffdc88 => accent,
      0x8a6628 ||
      0x5b4829 ||
      0x4a3b21 ||
      0x2b2c22 ||
      0x3c3323 ||
      0x403923 ||
      0x514123 => accentSurface,
      0x8197a5 ||
      0x9fb3bf ||
      0x8fa8b6 ||
      0xa9bac4 ||
      0x9db2bf ||
      0x8ba2af ||
      0xa6bdc8 ||
      0x8fa5b2 ||
      0x93aab8 ||
      0x526776 ||
      0x4a5c68 ||
      0x71818b ||
      0x9cb0ba => muted,
      0xffffff ||
      0xdce6eb ||
      0xecf3f5 ||
      0xe1e9ed ||
      0xedf2f4 ||
      0xeef6f8 ||
      0xf2f7f9 ||
      0xc7d5dc ||
      0xdbe5eb => foreground,
      0x29a634 ||
      0x4caf50 ||
      0x65d493 ||
      0x65cba6 ||
      0x64caa4 ||
      0x6fd3a9 ||
      0x7ccca3 ||
      0x87da61 => success,
      0x183e38 || 0x183631 || 0x16463e || 0x1b3c35 => successSurface,
      0x70c7bc || 0x83d5c8 || 0x80c8bd || 0x5daea6 || 0x69d2cf => accent,
      0xffc940 ||
      0xffc95c ||
      0xffc85a ||
      0xffc861 ||
      0xffcf67 ||
      0xefbd58 ||
      0xffd268 => gold,
      0xf57c00 || 0xff9800 || 0xe58c4f => orange,
      0xd33d17 ||
      0xe73939 ||
      0xef6f6c ||
      0xff6f68 ||
      0xff8b88 ||
      0xff8c78 ||
      0xffb4a9 ||
      0xffaaa4 => error,
      0x5a2528 || 0x3a292b || 0x642b2c || 0x472c2c => errorSurface,
      _ => _fallback(Color(0xff000000 | rgb)),
    };
  }

  Color _fallback(Color source) {
    final hsl = HSLColor.fromColor(source);
    final hue = hsl.hue;
    final saturation = hsl.saturation;
    final lightness = hsl.lightness;
    // Blue-grey neutrals form the original surfaces, dividers and text.
    if (saturation < .18 || (hue >= 190 && hue <= 235 && saturation < .65)) {
      if (lightness < .11) return background;
      if (lightness < .19) return inner;
      if (lightness < .26) return raised;
      if (lightness < .38) return border;
      if (lightness < .75) return muted;
      return foreground;
    }
    if (hue < 20 || hue >= 345) {
      return lightness < .27 ? errorSurface : error;
    }
    if (hue < 40) return lightness < .28 ? orangeSurface : orange;
    if (hue < 75) return lightness < .32 ? goldSurface : gold;
    if (hue < 170) return lightness < .28 ? successSurface : success;
    if (hue < 195) return lightness < .28 ? accentSurface : accent;
    if (hue < 255) return lightness < .28 ? infoSurface : info;
    return lightness < .3 ? purpleSurface : purple;
  }

  @override
  AppPalette copyWith({AppThemeMode? mode}) => AppPalette(mode ?? this.mode);

  @override
  AppPalette lerp(covariant AppPalette? other, double t) =>
      other == null || t < .5 ? this : other;
}

T appColor<T extends Color?>(BuildContext context, T source) =>
    source == null ? source : AppPalette.of(context).color(source) as T;

/// Text/icons on a solid accent button need a light foreground in light modes.
T appOnAccentColor<T extends Color?>(BuildContext context, T source) {
  if (source == null) return source;
  final palette = AppPalette.of(context);
  return (palette.isDark ? source : palette.surface.withValues(alpha: source.a))
      as T;
}

List<Color> appColors(BuildContext context, List<Color> colors) =>
    colors.map(AppPalette.of(context).color).toList(growable: false);

T appTextStyle<T extends TextStyle?>(BuildContext context, T style) {
  if (style == null) return style;
  if (AppPalette.of(context).isDark) return style;
  return style.copyWith(
        color: appColor(context, style.color),
        backgroundColor: appColor(context, style.backgroundColor),
        decorationColor: appColor(context, style.decorationColor),
      )
      as T;
}

/// Rich text keeps a style on every span, so each span in the tree is adapted.
InlineSpan appTextSpan(BuildContext context, InlineSpan span) {
  if (AppPalette.of(context).isDark || span is! TextSpan) return span;
  return TextSpan(
    text: span.text,
    style: appTextStyle(context, span.style),
    children: span.children
        ?.map((child) => appTextSpan(context, child))
        .toList(growable: false),
    recognizer: span.recognizer,
    mouseCursor: span.mouseCursor,
    onEnter: span.onEnter,
    onExit: span.onExit,
    semanticsLabel: span.semanticsLabel,
    locale: span.locale,
    spellOut: span.spellOut,
  );
}

ThemeData createAppTheme({
  required AppThemeMode mode,
  String? fontFamily,
  List<String>? fontFamilyFallback,
}) {
  final palette = AppPalette(mode);
  final original = ThemeData(
    brightness: Brightness.dark,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xffd4a85f),
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: const Color(0xff0a1823),
    useMaterial3: true,
  );
  if (palette.isDark) {
    return original.copyWith(extensions: <ThemeExtension<dynamic>>[palette]);
  }
  return original.copyWith(
    brightness: Brightness.light,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: palette.accent,
          brightness: Brightness.light,
        ).copyWith(
          primary: palette.accent,
          onPrimary: palette.surface,
          primaryContainer: palette.accentSurface,
          onPrimaryContainer: palette.accent,
          surface: palette.surface,
          onSurface: palette.foreground,
          onSurfaceVariant: palette.muted,
          surfaceContainerHighest: palette.raised,
          outline: palette.strongBorder,
          outlineVariant: palette.border,
          error: palette.error,
          onError: palette.surface,
          errorContainer: palette.errorSurface,
          onErrorContainer: palette.error,
        ),
    scaffoldBackgroundColor: palette.background,
    canvasColor: palette.surface,
    cardColor: palette.surface,
    dividerColor: palette.border,
    disabledColor: palette.muted,
    hintColor: palette.muted,
    unselectedWidgetColor: palette.muted,
    textTheme: original.textTheme.apply(
      bodyColor: palette.foreground,
      displayColor: palette.foreground,
    ),
    primaryTextTheme: original.primaryTextTheme.apply(
      bodyColor: palette.foreground,
      displayColor: palette.foreground,
    ),
    iconTheme: original.iconTheme.copyWith(color: palette.muted),
    primaryIconTheme: original.primaryIconTheme.copyWith(color: palette.accent),
    appBarTheme: original.appBarTheme.copyWith(
      backgroundColor: palette.chrome,
      foregroundColor: palette.foreground,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: original.dialogTheme.copyWith(
      backgroundColor: palette.surface,
    ),
    popupMenuTheme: original.popupMenuTheme.copyWith(color: palette.surface),
    bottomSheetTheme: original.bottomSheetTheme.copyWith(
      backgroundColor: palette.surface,
    ),
    textSelectionTheme: original.textSelectionTheme.copyWith(
      cursorColor: palette.accent,
      selectionColor: palette.accent.withValues(alpha: .25),
      selectionHandleColor: palette.accent,
    ),
    extensions: <ThemeExtension<dynamic>>[palette],
  );
}
