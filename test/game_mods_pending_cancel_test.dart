import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_controller.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_page.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_strings.dart';

import 'game_mods_controller_test.dart' show FakeGameModsPort;
import 'support/game_mod_portrait_platform_mock.dart';

void main() {
  setUp(mockGameModPortraitPlatform);
  tearDown(clearGameModPortraitPlatformMock);

  testWidgets('package switch is right of resources and priority', (
    tester,
  ) async {
    final controller = await _page(tester);
    final details = find.byKey(const Key('game-mods-details-a'));
    await tester.ensureVisible(details);
    await tester.pumpAndSettle();
    final toggle = find.byKey(const Key('game-mods-package-a'));
    expect(
      tester.getRect(details).right,
      lessThanOrEqualTo(tester.getRect(toggle).left),
    );
    expect(controller.status.pending, isFalse);
  });

  testWidgets('staged deletion turns card red and footer cancel restores it', (
    tester,
  ) async {
    final port = FakeGameModsPort();
    final controller = await _page(tester, port: port);
    final card = find.byKey(const Key('game-mods-card-b'));
    await tester.ensureVisible(find.byKey(const Key('game-mods-details-b')));
    await tester.pumpAndSettle();
    final before = tester.widget<Container>(card).decoration as BoxDecoration;
    await tester.tap(find.byKey(const Key('game-mods-details-b')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('game-mods-remove-b')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    final removing = tester.widget<Container>(card).decoration as BoxDecoration;
    expect(removing.color!.r, greaterThan(removing.color!.g));
    expect(
      (removing.border! as Border).top.color.r,
      greaterThan((removing.border! as Border).top.color.g),
    );
    expect(find.text('Removal pending'), findsOneWidget);
    expect(
      tester
          .widget<Switch>(find.byKey(const Key('game-mods-package-b')))
          .onChanged,
      isNull,
    );
    expect(port.applyCalls, 0);
    final cancel = find.byKey(const Key('game-mods-cancel'));
    final apply = find.byKey(const Key('game-mods-apply'));
    expect(tester.getRect(cancel).right, lessThan(tester.getRect(apply).left));
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(controller.status.pending, isFalse);
    expect(controller.status.packages.every((p) => !p.pendingRemoval), isTrue);
    expect(find.text('Removal pending'), findsNothing);
    final restored = tester.widget<Container>(card).decoration as BoxDecoration;
    expect(restored.color, before.color);
    expect(
      tester.widget<Switch>(find.byKey(const Key('game-mods-package-b'))).value,
      isTrue,
    );
    expect(port.applyCalls, 0);
    expect(tester.widget<OutlinedButton>(cancel).onPressed, isNull);
  });

  testWidgets(
    'removing from enabled filter returns to all so the red card stays visible',
    (tester) async {
      await _page(tester);
      final enabled = find.widgetWithText(FilterChip, 'Enabled 2');
      await tester.ensureVisible(enabled);
      await tester.tap(enabled);
      final details = find.byKey(const Key('game-mods-details-b'));
      await tester.ensureVisible(details);
      await tester.pumpAndSettle();
      await tester.tap(details);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('game-mods-remove-b')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('game-mods-card-b')), findsOneWidget);
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'All 2'))
            .selected,
        isTrue,
      );
    },
  );

  for (final locale in const [
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    Locale('ja'),
    Locale('en'),
    Locale('ko'),
  ]) {
    testWidgets(
      'cancel remains left of apply at 360px and large text in $locale',
      (tester) async {
        final controller = await _page(tester, locale: locale, narrow: true);
        controller.setMaster(false);
        await tester.pumpAndSettle();
        final cancel = find.byKey(const Key('game-mods-cancel'));
        final apply = find.byKey(const Key('game-mods-apply'));
        expect(
          tester.getRect(cancel).right,
          lessThan(tester.getRect(apply).left),
        );
        expect(tester.getSize(cancel).height, greaterThanOrEqualTo(44));
        expect(tester.getSize(apply).height, greaterThanOrEqualTo(44));
        expect(tester.getRect(apply).right, lessThanOrEqualTo(360));
        expect(
          find.descendant(
            of: cancel,
            matching: find.text(GameModsStrings(locale).cancel),
          ),
          findsOneWidget,
        );
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(controller.status.draft.master, isTrue);
        expect(controller.status.pending, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<GameModsController> _page(
  WidgetTester tester, {
  FakeGameModsPort? port,
  Locale locale = const Locale('en'),
  bool narrow = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(narrow ? 360 : 1050, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final controller = GameModsController(port: port ?? FakeGameModsPort());
  await controller.initialize();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: const [
        Locale('zh'),
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        Locale('ja'),
        Locale('en'),
        Locale('ko'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(narrow ? 1.6 : 1)),
        child: child!,
      ),
      home: Scaffold(body: GameModsPage(controller: controller)),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}
