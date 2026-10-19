import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/fleet/game_mod_portraits.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_controller.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_models.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_page.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_strings.dart';

import 'game_mods_controller_test.dart' show FakeGameModsPort;
import 'support/game_mod_portrait_platform_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(mockGameModPortraitPlatform);
  tearDown(clearGameModPortraitPlatformMock);

  testWidgets('interface portrait sync is enabled by default', (tester) async {
    final controller = GameModsController(port: FakeGameModsPort());
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GameModsPage(controller: controller)),
      ),
    );
    final toggle = find.byKey(const Key('game-mods-portrait-sync'));
    expect(toggle, findsOneWidget);
    expect(tester.widget<Switch>(toggle).value, isTrue);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  test('initialization awaits independent portrait preferences', () async {
    final portraits = _FakePortraits()..initializeGate = Completer<void>();
    final controller = GameModsController(
      port: FakeGameModsPort(),
      portraits: portraits,
    );
    addTearDown(portraits.dispose);
    addTearDown(controller.dispose);
    final initializing = controller.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(portraits.initializeCalls, 1);
    expect(controller.loading, isTrue);
    portraits.initializeGate!.complete();
    await initializing;
    await controller.initialize();
    expect(portraits.initializeCalls, 1);
    expect(controller.loading, isFalse);
    expect(controller.supported, isTrue);
  });

  test(
    'optional portrait API errors do not disable game mod management',
    () async {
      final portraits = _FakePortraits()..failInitialization = true;
      final controller = GameModsController(
        port: FakeGameModsPort(),
        portraits: portraits,
      );
      addTearDown(portraits.dispose);
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.supported, isTrue);
      expect(controller.canEdit, isTrue);
      expect(controller.errorCode, isNull);
      controller.setMaster(false);
      await controller.flushDraft();
      expect(controller.status.draft.master, isFalse);
    },
  );

  test(
    'sync notifications are forwarded without editing mod choices',
    () async {
      final portraits = _FakePortraits();
      final port = FakeGameModsPort();
      final controller = GameModsController(port: port, portraits: portraits);
      addTearDown(portraits.dispose);
      await controller.initialize();
      final original = controller.status.draft;
      var notifications = 0;
      controller.addListener(() => notifications++);
      await portraits.setEnabled(false);
      expect(notifications, greaterThan(0));
      expect(controller.status.draft.sameAs(original), isTrue);
      expect(controller.status.pending, isFalse);
      expect(port.saved, isEmpty);
      expect(port.applyCalls, 0);
      controller.dispose();
      expect(portraits.disposed, isFalse);
      final before = notifications;
      await portraits.setEnabled(true);
      expect(
        notifications,
        before,
        reason: 'Injected controller stays reusable',
      );
    },
  );

  for (final outcome in ['success', 'failed', 'throws', 'status-throws']) {
    test('apply refreshes final portraits after $outcome', () async {
      final events = <String>[];
      final port = _ApplyPort(events, outcome);
      final portraits = _FakePortraits()
        ..onRefresh = () => events.add('portraits');
      final controller = GameModsController(port: port, portraits: portraits);
      addTearDown(portraits.dispose);
      addTearDown(controller.dispose);
      await controller.initialize();
      events.clear();
      port.applying = true;
      controller.setMaster(false);
      await controller.flushDraft();
      await controller.apply();
      expect(events, ['apply', 'status', 'portraits']);
      expect(portraits.refreshCalls, 1);
      expect(controller.busy, isFalse);
      expect(controller.supported, isTrue);
      if (outcome == 'success') {
        expect(controller.errorCode, isNull);
        expect(controller.status.applied.master, isFalse);
      } else {
        expect(controller.errorCode, isNotNull);
      }
    });
  }

  test(
    'portrait refresh failures preserve a successful apply result',
    () async {
      final portraits = _FakePortraits()..failRefresh = true;
      final controller = GameModsController(
        port: FakeGameModsPort(),
        portraits: portraits,
      );
      addTearDown(portraits.dispose);
      addTearDown(controller.dispose);
      await controller.initialize();
      controller.setMaster(false);
      await controller.apply();
      expect(portraits.refreshCalls, 1);
      expect(controller.lastApplyResult, GameModsApplyResult.noGame);
      expect(controller.errorCode, isNull);
      expect(controller.status.applied.master, isFalse);
    },
  );

  for (final locale in const [
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    Locale('ja'),
    Locale('en'),
    Locale('ko'),
  ]) {
    for (final layout in const [
      (size: Size(360, 760), scale: 1.6),
      (size: Size(720, 832), scale: 1.0),
    ]) {
      testWidgets(
        'sync is readable and immediate in $locale at ${layout.size.width}px/${layout.scale}x',
        (tester) async {
          final portraits = _FakePortraits();
          final port = FakeGameModsPort();
          final controller = GameModsController(
            port: port,
            portraits: portraits,
          );
          final s = GameModsStrings(locale);
          await _pumpSyncPage(
            tester,
            controller,
            portraits,
            locale: locale,
            size: layout.size,
            scale: layout.scale,
          );
          final toggle = find.byKey(const Key('game-mods-portrait-sync'));
          await tester.ensureVisible(toggle);
          await tester.pumpAndSettle();
          expect(toggle.hitTestable(), findsOneWidget);
          final bounds = tester.getRect(toggle);
          expect(bounds.width, greaterThanOrEqualTo(44));
          expect(bounds.height, greaterThanOrEqualTo(44));
          expect(bounds.right, lessThanOrEqualTo(layout.size.width));
          for (final text in [s.syncPortraits, s.syncPortraitsHint]) {
            final finder = find.text(text);
            expect(finder, findsOneWidget);
            final paragraph = tester.renderObject<RenderParagraph>(finder);
            expect(paragraph.didExceedMaxLines, isFalse);
            expect(
              paragraph.getMaxIntrinsicHeight(paragraph.size.width),
              lessThanOrEqualTo(paragraph.size.height + .1),
            );
            final rect = tester.getRect(finder);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(bounds.left));
          }
          final original = controller.status.draft;
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          expect(tester.widget<Switch>(toggle).value, isFalse);
          expect(portraits.selections, [false]);
          expect(controller.status.draft.sameAs(original), isTrue);
          expect(port.saved, isEmpty);
          expect(port.applyCalls, 0);
          expect(controller.status.pending, isFalse);
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          expect(tester.widget<Switch>(toggle).value, isTrue);
          expect(portraits.selections, [false, true]);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('saving locks only sync and failure remains retryable', (
    tester,
  ) async {
    final portraits = _FakePortraits()
      ..saveGate = Completer<void>()
      ..failSave = true;
    final port = FakeGameModsPort();
    final controller = GameModsController(port: port, portraits: portraits);
    const s = GameModsStrings(Locale('zh'));
    await _pumpSyncPage(tester, controller, portraits);
    final toggle = find.byKey(const Key('game-mods-portrait-sync'));
    await tester.tap(toggle);
    await tester.pump();
    expect(tester.widget<Switch>(toggle).onChanged, isNull);
    expect(
      tester
          .widget<Switch>(find.byKey(const Key('game-mods-master')))
          .onChanged,
      isNotNull,
    );
    portraits.saveGate!.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(toggle).value, isTrue);
    expect(tester.widget<Switch>(toggle).onChanged, isNotNull);
    expect(find.text(s.syncPortraitsSaveFailed), findsOneWidget);
    expect(find.text(s.reason('save_failed')), findsNothing);
    expect(controller.errorCode, isNull);
    portraits.failSave = false;
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(toggle).value, isFalse);
    expect(find.text(s.syncPortraitsSaveFailed), findsNothing);
    expect(port.saved, isEmpty);
    expect(port.applyCalls, 0);
  });
}

Future<void> _pumpSyncPage(
  WidgetTester tester,
  GameModsController controller,
  _FakePortraits portraits, {
  Locale locale = const Locale('zh'),
  Size size = const Size(720, 832),
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    portraits.dispose();
  });
  await controller.initialize();
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: [locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(body: GameModsPage(controller: controller)),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

class _FakePortraits extends GameModPortraitController {
  bool enabledValue = true, savingValue = false;
  String? errorValue;
  bool failInitialization = false, failSave = false, failRefresh = false;
  bool disposed = false;
  int initializeCalls = 0, refreshCalls = 0;
  final selections = <bool>[];
  Completer<void>? initializeGate, saveGate;
  VoidCallback? onRefresh;

  @override
  bool get enabled => enabledValue;
  @override
  bool get saving => savingValue;
  @override
  String? get errorCode => errorValue;
  @override
  Future<void> initialize() async {
    initializeCalls++;
    await initializeGate?.future;
    if (failInitialization) throw MissingPluginException();
  }

  @override
  Future<void> refresh() async {
    refreshCalls++;
    onRefresh?.call();
    if (failRefresh) throw MissingPluginException();
  }

  @override
  Future<void> setEnabled(bool value) async {
    selections.add(value);
    savingValue = true;
    notifyListeners();
    await saveGate?.future;
    if (failSave) {
      errorValue = 'portrait_sync_save_failed';
    } else {
      enabledValue = value;
      errorValue = null;
    }
    savingValue = false;
    notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _ApplyPort extends FakeGameModsPort {
  _ApplyPort(this.events, this.outcome);
  final List<String> events;
  final String outcome;
  bool applying = false;

  @override
  Future<GameModsApplyResult> applyAndReload() async {
    events.add('apply');
    if (outcome == 'throws') throw PlatformException(code: 'reload_failed');
    if (outcome == 'failed') return GameModsApplyResult.failed;
    return super.applyAndReload();
  }

  @override
  Future<GameModsStatus> status() async {
    events.add('status');
    if (applying && outcome == 'status-throws') {
      throw PlatformException(code: 'status_unavailable');
    }
    return super.status();
  }
}
