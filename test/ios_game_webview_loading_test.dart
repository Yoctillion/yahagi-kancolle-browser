import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:yahagi_kancolle_browser/src/audio/game_audio_controller.dart';
import 'package:yahagi_kancolle_browser/src/audio/game_audio_store.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_browser_controller.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_frame_reload_port.dart';
import 'package:yahagi_kancolle_browser/src/browser/game_toolbar_controller.dart';
import 'package:yahagi_kancolle_browser/src/capture/capture_mode_controller.dart';
import 'package:yahagi_kancolle_browser/src/capture/capture_mode_store.dart';
import 'package:yahagi_kancolle_browser/src/capture/game_capture_controller.dart';
import 'package:yahagi_kancolle_browser/src/ios_game_webview.dart';
import 'package:yahagi_kancolle_browser/src/prototype_status_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/network_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/network_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_store.dart';

const _gameUrl = 'https://play.games.dmm.com/game/kancolle';

void main() {
  late _WebViewPlatform platform;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    platform = _WebViewPlatform();
    WebViewPlatform.instance = platform;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in [
      gameFrameReloadMethodChannelName,
      'app.webview/fixed_canvas_scaling',
      'app.yahagi.kancollebrowser/game_capture',
      'app.yahagi.kancollebrowser/game_audio',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => null,
      );
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('app.yahagi.kancollebrowser/network_proxy'),
      (_) async => <String, Object>{
        'success': true,
        'code': 'ok',
        'message': '',
        'elapsedMs': 0,
      },
    );
  });

  Future<void> pump(WidgetTester tester) async {
    final fixture = await _Fixture.create();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      fixture.dispose();
    });
    await tester.pumpWidget(MaterialApp(home: fixture.view));
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    expect(platform.controller.loads, hasLength(1));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
  }

  final overlay = find.byType(CircularProgressIndicator);

  testWidgets('game frame on a parsed document reveals before page finish', (
    tester,
  ) async {
    await pump(tester);
    platform.controller
      ..documentReady = true
      ..presentation = 'game';
    platform.delegate.started(_gameUrl);
    await settle(tester);
    expect(overlay, findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);
    expect(overlay, findsNothing);
  });

  testWidgets(
    'pending game frame reveals on the runtime presentation message',
    (tester) async {
      await pump(tester);
      platform.controller
        ..documentReady = true
        ..presentation = 'pending';
      platform.delegate.started(_gameUrl);
      await tester.pump(const Duration(milliseconds: 600));
      await settle(tester);
      expect(overlay, findsOneWidget);

      platform.controller.presentation = 'game';
      platform.controller.channels['YahagiPresentation']!.onMessageReceived(
        const JavaScriptMessage(message: 'game'),
      );
      await settle(tester);
      expect(overlay, findsNothing);
    },
  );

  testWidgets('initial blank document keeps the overlay before the deadline', (
    tester,
  ) async {
    await pump(tester);
    platform.controller.presentation = 'web';
    platform.delegate.started(_gameUrl);
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    expect(overlay, findsOneWidget);
  });

  testWidgets('a page that never finishes is revealed at the deadline', (
    tester,
  ) async {
    await pump(tester);
    platform.delegate.started(_gameUrl);
    await tester.pump(const Duration(seconds: 15));
    await settle(tester);
    expect(overlay, findsNothing);
  });

  testWidgets('page finish reveals even when page scripts are rejected', (
    tester,
  ) async {
    await pump(tester);
    platform.controller
      ..rejectScripts = true
      ..presentation = 'game';
    platform.delegate.started(_gameUrl);
    await settle(tester);
    platform.delegate.finished(_gameUrl);
    await settle(tester);
    expect(overlay, findsNothing);
  });
}

class _WebViewPlatform extends WebViewPlatform {
  late _Controller controller;
  late _Delegate delegate;
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => controller = _Controller(params);
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => delegate = _Delegate(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _View(params);
}

class _Controller extends PlatformWebViewController {
  _Controller(super.params) : super.implementation();
  final List<Uri> loads = [];
  String presentation = 'web';
  bool documentReady = false;
  bool rejectScripts = false;
  final Map<String, JavaScriptChannelParams> channels = {};
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setBackgroundColor(Color color) async {}
  @override
  Future<void> setUserAgent(String? userAgent) async {}
  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    channels[params.name] = params;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}
  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    loads.add(params.uri);
  }

  @override
  Future<void> runJavaScript(String script) async {
    if (rejectScripts) throw PlatformException(code: 'js');
  }

  @override
  Future<Object> runJavaScriptReturningResult(String script) async {
    if (script.contains('__yahagiIOSDocumentReady')) {
      return documentReady ? '__yahagiIOSDocumentReady' : '';
    }
    return presentation;
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {}
}

class _Delegate extends PlatformNavigationDelegate {
  _Delegate(super.params) : super.implementation();
  late PageEventCallback started;
  late PageEventCallback finished;
  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {}
  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async {
    started = callback;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    finished = callback;
  }

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {}
}

class _View extends PlatformWebViewWidget {
  _View(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class _Fixture {
  _Fixture(this.network, this.safety, this.captureMode, this.audio);
  final NetworkSettingsController network;
  final SafetySettingsController safety;
  final CaptureModeController captureMode;
  final GameAudioController audio;
  final status = PrototypeStatusController();
  final browser = GameBrowserController(homeUri: Uri.parse(_gameUrl));
  final toolbar = GameToolbarController();
  final capture = GameCaptureController();
  static Future<_Fixture> create() async => _Fixture(
    NetworkSettingsController(store: _NetworkStore()),
    await SafetySettingsController.load(MemorySafetySettingsStore()),
    await CaptureModeController.load(SharedPreferencesCaptureModeStore()),
    await GameAudioController.load(SharedPreferencesGameAudioStore()),
  );
  Widget get view => IOSGameWebView(
    networkSettingsController: network,
    safetySettingsController: safety,
    controller: status,
    browserController: browser,
    captureModeController: captureMode,
    audioController: audio,
    toolbarController: toolbar,
    gameCaptureController: capture,
  );
  void dispose() {
    network.dispose();
    safety.dispose();
    captureMode.dispose();
    audio.dispose();
    status.dispose();
    browser.dispose();
    toolbar.dispose();
    capture.dispose();
  }
}

class _NetworkStore implements NetworkSettingsStore {
  @override
  Future<NetworkSettings> loadSettings() async => const NetworkSettings();
  @override
  Future<void> saveSettings(NetworkSettings settings) async {}
}
