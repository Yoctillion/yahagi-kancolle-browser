import 'dart:async';

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
import 'package:yahagi_kancolle_browser/src/game_webview.dart';
import 'package:yahagi_kancolle_browser/src/prototype_status_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/network_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/network_settings_store.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_controller.dart';
import 'package:yahagi_kancolle_browser/src/settings/safety_settings_store.dart';

void main() {
  late _WebViewPlatform platform;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    platform = _WebViewPlatform();
    WebViewPlatform.instance = platform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(gameFrameReloadMethodChannelName),
          (_) async => null,
        );
  });

  Future<_Fixture> pump(WidgetTester tester) async {
    final fixture = await _Fixture.create();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      fixture.dispose();
    });
    await tester.pumpWidget(MaterialApp(home: fixture.view));
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    expect(platform.controller.loads, hasLength(1));
    return fixture;
  }

  testWidgets(
    'platform navigation without callbacks times out and really retries',
    (tester) async {
      await pump(tester);
      await tester.pump(const Duration(seconds: 46));
      expect(find.byKey(const Key('game-webview-page-reload')), findsOneWidget);
      await tester.tap(find.byKey(const Key('game-webview-page-reload')));
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }
      expect(platform.controller.reloads, 1);
    },
  );

  testWidgets('platform main frame error survives a late finish callback', (
    tester,
  ) async {
    await pump(tester);
    platform.delegate.started('https://game.example/');
    platform.delegate.error(
      const WebResourceError(
        errorCode: -2,
        description: 'private error text',
        isForMainFrame: true,
      ),
    );
    await tester.pump();
    platform.delegate.finished('https://game.example/');
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(find.byKey(const Key('game-webview-page-reload')), findsOneWidget);
  });

  testWidgets(
    'platform old main page error cannot hide the current ready page',
    (tester) async {
      await pump(tester);
      platform.delegate.started('https://game.example/old');
      platform.delegate.started('https://game.example/current');
      platform.delegate.finished('https://game.example/current');
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }
      platform.delegate.error(
        const WebResourceError(
          errorCode: -2,
          description: 'old document error',
          isForMainFrame: true,
          url: 'https://game.example/old',
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('game-webview-page-reload')), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('platform child resource error keeps a usable login visible', (
    tester,
  ) async {
    await pump(tester);
    platform.delegate.started(
      'https://accounts.dmm.com/service/login/password',
    );
    platform.delegate.error(
      const WebResourceError(
        errorCode: -2,
        description: 'image unavailable',
        isForMainFrame: false,
      ),
    );
    platform.delegate.finished(
      'https://accounts.dmm.com/service/login/password',
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const Key('game-webview-page-reload')), findsNothing);
  });

  testWidgets('platform body pending does not finish the game load', (
    tester,
  ) async {
    await pump(tester);
    platform.controller.presentation = 'pending';
    platform.delegate.started('https://play.games.dmm.com/game/kancolle');
    platform.delegate.finished('https://play.games.dmm.com/game/kancolle');
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 46));
    expect(find.byKey(const Key('game-webview-page-reload')), findsOneWidget);
  });

  testWidgets('platform body disappearing after readiness has a new deadline', (
    tester,
  ) async {
    await pump(tester);
    platform.controller.presentation = 'game';
    platform.delegate.started('https://play.games.dmm.com/game/kancolle');
    platform.delegate.finished('https://play.games.dmm.com/game/kancolle');
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    expect(find.byType(CircularProgressIndicator), findsNothing);
    platform.controller.presentation = 'pending';
    platform.controller.channels['YahagiPresentation']!.onMessageReceived(
      const JavaScriptMessage(message: 'pending'),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 46));
    expect(find.byKey(const Key('game-webview-page-reload')), findsOneWidget);
  });

  testWidgets('platform main page HTTP error is retryable', (tester) async {
    await pump(tester);
    platform.delegate.started('https://game.example/');
    platform.delegate.httpError?.call(
      HttpResponseError(
        request: WebResourceRequest(uri: Uri.parse('https://game.example/')),
        response: const WebResourceResponse(uri: null, statusCode: 503),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('game-webview-page-reload')), findsOneWidget);
  });

  testWidgets('platform late page command response cannot hide a usable page', (
    tester,
  ) async {
    platform.controllerReply = Completer<void>();
    await pump(tester);
    platform.delegate.started('https://game.example/');
    platform.delegate.finished('https://game.example/');
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(seconds: 11));
    expect(find.byKey(const Key('game-webview-page-reload')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    platform.controllerReply!.complete();
    await tester.pump();
  });

  testWidgets(
    'platform presentation message during a probe schedules a fresh read',
    (tester) async {
      await pump(tester);
      final old = Completer<Object>();
      platform.controller.probe = old;
      platform.delegate.started('https://game.example/');
      platform.delegate.finished('https://game.example/');
      await tester.pump();
      platform.controller.channels['YahagiPresentation']!.onMessageReceived(
        const JavaScriptMessage(message: 'game'),
      );
      platform.controller.presentation = 'game';
      platform.controller.probe = null;
      old.complete('pending');
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('platform deadline pauses until the app resumes', (tester) async {
    await pump(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 2));
    expect(find.byKey(const Key('game-webview-page-reload')), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 46));
    expect(find.byKey(const Key('game-webview-page-reload')), findsOneWidget);
  });

  testWidgets('platform new document discards the old presentation result', (
    tester,
  ) async {
    await pump(tester);
    final old = Completer<Object>();
    platform.controller.probe = old;
    platform.delegate.started('https://game.example/old');
    platform.delegate.finished('https://game.example/old');
    await tester.pump();
    platform.delegate.started('https://game.example/current');
    old.complete('game');
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    platform.controller.probe = null;
    platform.controller.presentation = 'web';
    platform.delegate.finished('https://game.example/current');
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

class _WebViewPlatform extends WebViewPlatform {
  late _Controller controller;
  late _Delegate delegate;
  Completer<void>? controllerReply;
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => controller = _Controller(params)..loadReply = controllerReply;
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
  int reloads = 0;
  String presentation = 'web';
  Completer<Object>? probe;
  Completer<void>? loadReply;
  final Map<String, JavaScriptChannelParams> channels = {};
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setBackgroundColor(Color color) async {}
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
    await loadReply?.future;
  }

  @override
  Future<void> reload() async {
    reloads++;
  }

  @override
  Future<void> runJavaScript(String script) async {}
  @override
  Future<Object> runJavaScriptReturningResult(String script) async =>
      probe == null ? presentation : probe!.future;
  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {}
}

class _Delegate extends PlatformNavigationDelegate {
  _Delegate(super.params) : super.implementation();
  late PageEventCallback started;
  late PageEventCallback finished;
  late WebResourceErrorCallback error;
  HttpResponseErrorCallback? httpError;
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
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {
    error = callback;
  }

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback callback) async {
    httpError = callback;
  }
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
  final browser = GameBrowserController(
    homeUri: Uri.parse('https://game.example/'),
  );
  final toolbar = GameToolbarController();
  final capture = GameCaptureController();
  static Future<_Fixture> create() async => _Fixture(
    NetworkSettingsController(store: _NetworkStore()),
    await SafetySettingsController.load(MemorySafetySettingsStore()),
    await CaptureModeController.load(SharedPreferencesCaptureModeStore()),
    await GameAudioController.load(SharedPreferencesGameAudioStore()),
  );
  Widget get view => GameWebView(
    networkSettingsController: network,
    safetySettingsController: safety,
    controller: status,
    browserController: browser,
    captureModeController: captureMode,
    audioController: audio,
    toolbarController: toolbar,
    gameCaptureController: capture,
    startupOrchestratorFactory: () => _Startup(),
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

class _Startup implements GameSurfaceStartupOrchestrator {
  @override
  Future<GameSurfaceNetworkResult> applyNetworkSettings() async =>
      const GameSurfaceNetworkResult.success();
  @override
  Future<void> runCaptureStartup({
    required Future<void> Function() waitForSurface,
    required bool Function() isActive,
    required Future<void> Function() navigate,
  }) async {
    await waitForSurface();
    if (isActive()) await navigate();
  }

  @override
  Future<void> prepareCapture() async {}
  @override
  Future<void> attachAudioPortOnce() async {}
  @override
  Future<bool> attachFrameRatePlatformPort() async => false;
  @override
  void dispose() {}
}
