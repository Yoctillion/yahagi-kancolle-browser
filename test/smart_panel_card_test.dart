import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/fleet/dashboard_card.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/layout/panel_style.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/layout_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/module_display_settings.dart';
import 'package:yahagi_kancolle_browser/src/settings/smart_panel_settings.dart';
import 'package:yahagi_kancolle_browser/src/smart_panel/smart_panel_card.dart';
import 'package:yahagi_kancolle_browser/src/smart_panel/smart_panel_controller.dart';

final _zh = lookupAppLocalizations(const Locale('zh'));

CapturedApiEvent _event(String api) => CapturedApiEvent(
  path: '/kcsapi/$api',
  responseBody: '{"api_result":1,"api_data":{}}',
  source: CaptureSource.manual,
  capturedAt: DateTime(2026, 10, 24),
);

class _EmbedProbe extends StatelessWidget {
  const _EmbedProbe(this.state);

  final SmartPanelState state;

  @override
  Widget build(BuildContext context) =>
      Text('body:${state.name}:${DashboardCardEmbedScope.isEmbedded(context)}');
}

void main() {
  late SmartPanelController controller;

  setUp(() {
    controller = SmartPanelController(
      stateProvider: () => GameState.empty,
      waitForGameState: () async {},
      autoSwitchEnabled: () => true,
    );
  });

  tearDown(() => controller.dispose());

  Future<void> pump(
    WidgetTester tester,
    SmartPanelHeaderStyle style, {
    PanelStyle panel = PanelStyle.card,
    double width = 360,
  }) => tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: PanelStyleScope(
            style: panel,
            child: SmartPanelCard(
              controller: controller,
              collapsed: false,
              onToggleCollapse: () {},
              headerStyle: style,
              stateBody: (context, state) => _EmbedProbe(state),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('body is rendered for the current state inside an embed scope', (
    tester,
  ) async {
    await pump(tester, SmartPanelHeaderStyle.dropdown);
    expect(find.text('body:home:true'), findsOneWidget);
  });

  for (final panel in PanelStyle.values) {
    testWidgets('dropdown pages through states with ‹ › ($panel)', (
      tester,
    ) async {
      await pump(tester, SmartPanelHeaderStyle.dropdown, panel: panel);
      expect(find.text(_zh.smartPanelStateHome), findsOneWidget);

      await tester.tap(find.byKey(const Key('smart-panel-next')));
      await tester.pump();
      expect(controller.state, SmartPanelState.sortieCheck);
      expect(find.text(_zh.smartPanelStateSortieCheck), findsOneWidget);

      await tester.tap(find.byKey(const Key('smart-panel-prev')));
      await tester.tap(find.byKey(const Key('smart-panel-prev')));
      await tester.pump();
      expect(controller.state, SmartPanelState.practice);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('dropdown menu lists every state', (tester) async {
    await pump(tester, SmartPanelHeaderStyle.dropdown);
    await tester.tap(find.byKey(const Key('smart-panel-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_zh.smartPanelStateQuests).last);
    await tester.pumpAndSettle();
    expect(controller.state, SmartPanelState.quests);
  });

  testWidgets('tabs show six labels and select on tap', (tester) async {
    await pump(tester, SmartPanelHeaderStyle.tabs);
    expect(find.text(_zh.smartPanelTitle), findsOneWidget);
    for (final state in SmartPanelState.values) {
      expect(find.byKey(Key('smart-panel-tab-${state.name}')), findsOneWidget);
    }
    await tester.tap(find.byKey(const Key('smart-panel-tab-practice')));
    await tester.pump();
    expect(controller.state, SmartPanelState.practice);
  });

  testWidgets('icons show six buttons and select on tap', (tester) async {
    await pump(tester, SmartPanelHeaderStyle.icons);
    for (final state in SmartPanelState.values) {
      expect(find.byKey(Key('smart-panel-icon-${state.name}')), findsOneWidget);
    }
    await tester.tap(find.byKey(const Key('smart-panel-icon-battle')));
    await tester.pump();
    expect(controller.state, SmartPanelState.battle);
    expect(tester.takeException(), isNull);
  });

  for (final width in const <double>[160, 185, 220, 240]) {
    testWidgets('card-style headers fit at $width dp', (tester) async {
      for (final style in SmartPanelHeaderStyle.values) {
        await pump(tester, style, width: width);
        expect(tester.takeException(), isNull, reason: '$style');
      }
    });
  }

  testWidgets('auto marker shows after auto switch and hides after manual', (
    tester,
  ) async {
    await pump(tester, SmartPanelHeaderStyle.dropdown);
    expect(find.byKey(const Key('smart-panel-auto')), findsNothing);

    controller.accept(_event('api_get_member/questlist'));
    await tester.pump();
    expect(find.byKey(const Key('smart-panel-auto')), findsOneWidget);
    expect(find.text('body:quests:true'), findsOneWidget);

    await tester.tap(find.byKey(const Key('smart-panel-next')));
    await tester.pump();
    expect(find.byKey(const Key('smart-panel-auto')), findsNothing);
  });

  group('settings', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('defaults to dropdown with auto switch on', () async {
      final layout = await LayoutSettingsController.load(
        SharedPreferencesLayoutSettingsStore(),
      );
      expect(layout.smartPanelHeaderStyle, SmartPanelHeaderStyle.dropdown);
      expect(layout.smartPanelAutoSwitch, isTrue);
    });

    test('header style and auto switch persist', () async {
      final layout = await LayoutSettingsController.load(
        SharedPreferencesLayoutSettingsStore(),
      );
      await layout.setSmartPanelHeaderStyle(SmartPanelHeaderStyle.tabs);
      await layout.setSmartPanelAutoSwitch(false);

      final reloaded = await LayoutSettingsController.load(
        SharedPreferencesLayoutSettingsStore(),
      );
      expect(reloaded.smartPanelHeaderStyle, SmartPanelHeaderStyle.tabs);
      expect(reloaded.smartPanelAutoSwitch, isFalse);
    });

    testWidgets('display settings dialog edits both smart panel options', (
      tester,
    ) async {
      final layout = await tester.runAsync(
        () => LayoutSettingsController.load(
          SharedPreferencesLayoutSettingsStore(),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showModuleDisplaySettings(context, layout!, 'smart'),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('smart-header-style-icons')));
      await tester.pump();
      expect(layout!.smartPanelHeaderStyle, SmartPanelHeaderStyle.icons);

      await tester.tap(find.byKey(const Key('smart-auto-switch')));
      await tester.pump();
      expect(layout.smartPanelAutoSwitch, isFalse);
    });
  });
}
