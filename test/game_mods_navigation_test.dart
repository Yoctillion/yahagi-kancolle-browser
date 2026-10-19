import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/toolbox_mode.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/toolbox_mode_tabs.dart';

void main() {
  test('mods has its own toolbox mode before other tools', () {
    final names = ToolboxMode.values.map((e) => e.name).toList();
    expect(names, contains('mods'));
    expect(names.indexOf('mods'), lessThan(names.indexOf('other')));
  });
  testWidgets('narrow toolbox scrolls to the independent mod entry', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(300, 90);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ToolboxMode? picked;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: ToolboxModeTabs(
            mode: ToolboxMode.export,
            compact: true,
            onChanged: (mode) => picked = mode,
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('toolbox-tab-mods')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('toolbox-tab-mods')));
    await tester.tap(find.byKey(const Key('toolbox-tab-mods')));
    expect(picked?.name, 'mods');
    expect(tester.takeException(), isNull);
  });
}
