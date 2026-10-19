import 'package:flutter/widgets.dart';

import '../subtitles/ship_subtitle_catalog_controller.dart';
import '../subtitles/ship_subtitle_kc3_bundle.dart';
import 'game_name_catalog.dart';

/// Display-only names. Without the app's resource scope, preserve raw labels.
GameNameCatalog gameNames(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<_GameNameData>()?.names ??
    GameNameCatalog(
      locale: Localizations.maybeLocaleOf(context) ?? const Locale('zh'),
    );

/// Lives above the Navigator so dialogs and drawers share the same dictionary.
class GameNameLocalizationScope extends StatefulWidget {
  const GameNameLocalizationScope({
    super.key,
    this.controller,
    this.bundle,
    required this.child,
  });

  final ShipSubtitleCatalogController? controller;
  final ShipSubtitleKc3Bundle? bundle;
  final Widget child;

  @override
  State<GameNameLocalizationScope> createState() =>
      _GameNameLocalizationScopeState();
}

class _GameNameLocalizationScopeState extends State<GameNameLocalizationScope> {
  Locale? _locale;
  ShipSubtitleKc3Bundle? _bundle;
  GameNameCatalog? _names;

  Widget _content(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context) ?? const Locale('zh');
    // CJK labels deliberately stay original, so dictionary updates do not
    // invalidate their widgets or retain indexes they will never use.
    final bundle = switch (locale.languageCode) {
      'en' || 'ko' => widget.controller?.kc3Bundle ?? widget.bundle,
      _ => null,
    };
    if (_names == null || _locale != locale || !identical(_bundle, bundle)) {
      _locale = locale;
      _bundle = bundle;
      _names = GameNameCatalog(locale: locale, bundle: bundle);
    }
    return _GameNameData(names: _names!, child: widget.child);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return controller == null
        ? _content(context)
        : AnimatedBuilder(
            animation: controller,
            builder: (context, _) => _content(context),
          );
  }
}

class _GameNameData extends InheritedWidget {
  const _GameNameData({required this.names, required super.child});
  final GameNameCatalog names;

  @override
  bool updateShouldNotify(_GameNameData oldWidget) =>
      !identical(names, oldWidget.names);
}
