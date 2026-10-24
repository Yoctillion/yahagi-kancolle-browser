/// iOS-specific entry point for Yahagi KanColle Browser.
///
/// This file is the iOS build target entry (configured via Xcode
/// FLUTTER_TARGET=lib/main_ios.dart). It runs the shared [runYahagi] startup
/// and injects iOS-specific components through [YahagiStartupHooks]:
///
/// - [IOSGameWebView] as the game surface (with lifecycle audio, AudioContext
///   tracking, WKWebView compatibility)
/// - [RawDataServerController] for developer-mode master data extraction
/// - Developer mode easter egg (7-tap on settings nav)
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'main.dart';
import 'src/bridge/captured_api_event.dart';
import 'src/browser/game_resource_cache_channel.dart';
import 'src/browser/game_resource_cache_store.dart';
import 'src/capture/raw_data_server_controller.dart';
import 'src/game_state/game_api_event_pipeline.dart';
import 'src/ios_game_webview.dart';
import 'src/localization/ui_locale.dart';
import 'src/settings/background_game_retention_controller.dart';
import 'src/settings/game_mouse_wheel_settings.dart';
import 'src/settings/layout_settings_controller.dart';
import 'src/settings/raw_data_section.dart';
import 'src/widgets/top_notice.dart';

// TEMP startup diagnostics: surface where startup stops instead of leaving
// the white launch screen.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final errors = <String>[];
  FlutterError.onError = (details) {
    errors.add(
      'FlutterError: ${details.exceptionAsString()}\n${details.stack}',
    );
    FlutterError.presentError(details);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    errors.add('Async: $error\n$stack');
    return true;
  };
  ErrorWidget.builder = (details) => Material(
    color: const Color(0xff400000),
    child: SingleChildScrollView(
      child: Text(
        'Build error: ${details.exceptionAsString()}\n${details.stack}',
        style: const TextStyle(color: Colors.white, fontSize: 10),
      ),
    ),
  );
  var finished = false;
  Timer(const Duration(seconds: 12), () {
    if (finished) return;
    runApp(
      _StartupDiagnosticApp(
        'Startup still running after 12s\nstage: $yahagiStartupStage\n\n'
        '${errors.join('\n\n')}',
      ),
    );
  });
  try {
    await runYahagi(hooks: _IOSStartupHooks());
  } catch (error, stack) {
    runApp(
      _StartupDiagnosticApp(
        'Startup failed\nstage: $yahagiStartupStage\n$error\n$stack\n\n'
        '${errors.join('\n\n')}',
      ),
    );
  } finally {
    finished = true;
  }
}

class _StartupDiagnosticApp extends StatelessWidget {
  const _StartupDiagnosticApp(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      backgroundColor: const Color(0xff101820),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            message,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
      ),
    ),
  );
}

final class _IOSStartupHooks extends YahagiStartupHooks {
  final _rawDataServerController = RawDataServerController();
  int _settingsTapCount = 0;
  Timer? _settingsTapResetTimer;

  @override
  GameResourceCachePort get gameResourceCachePort =>
      const _IosDisabledGameResourceCachePort();

  @override
  late final List<GameApiEventConsumer> extraEventConsumers = [
    _IOSRawDataConsumer(_rawDataServerController),
  ];

  @override
  Widget Function(YahagiApp app) get gameSurfaceBuilder => _buildGameSurface;

  @override
  late final List<Widget> additionalDataSections = [
    ListenableBuilder(
      listenable: _rawDataServerController,
      builder: (context, _) => _rawDataServerController.developerMode
          ? _buildDeveloperSection()
          : const SizedBox.shrink(),
    ),
  ];

  @override
  void Function(BuildContext context) get onSettingsNavTap => _onSettingsNavTap;

  @override
  Future<void> adjustSettings({
    required LayoutSettingsController layoutSettingsController,
    required BackgroundGameRetentionController
    backgroundGameRetentionController,
    required GameMouseWheelSettingsController gameMouseWheelSettingsController,
  }) async {
    // Persist the initial locale so UI localization and the settings selection
    // stay in sync from the first launch.
    if (layoutSettingsController.localeCode == null) {
      await layoutSettingsController.setLocaleCode(
        uiLocaleStorageCode(WidgetsBinding.instance.platformDispatcher.locale),
      );
    }
    if (backgroundGameRetentionController.enabled) {
      await backgroundGameRetentionController.setEnabled(false);
    }
    if (gameMouseWheelSettingsController.enabled) {
      await gameMouseWheelSettingsController.setEnabled(false);
    }
  }

  Widget _buildGameSurface(YahagiApp app) => IOSGameWebView(
    key: const GlobalObjectKey('yahagi_game_webview'),
    networkSettingsController: app.networkSettingsController,
    safetySettingsController: app.safetySettingsController,
    controller: app.controller,
    browserController: app.browserController,
    captureModeController: app.captureModeController,
    audioController: app.audioController,
    toolbarController: app.toolbarController,
    gameCaptureController: app.gameCaptureController,
    frameRateSettingsController: app.gameFrameRateSettingsController,
  );

  Widget _buildDeveloperSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 24),
      const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text(
          '开发者选项 (Developer Options)',
          style: TextStyle(
            color: Color(0xffd4a85f),
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
      Material(
        color: const Color(0xff142735),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ListTileTheme(
          data: const ListTileThemeData(
            contentPadding: EdgeInsets.symmetric(horizontal: 16),
            minLeadingWidth: 0,
          ),
          child: RawDataSection(controller: _rawDataServerController),
        ),
      ),
    ],
  );

  void _onSettingsNavTap(BuildContext context) {
    _settingsTapResetTimer?.cancel();
    _settingsTapCount++;
    _settingsTapResetTimer = Timer(const Duration(milliseconds: 1500), () {
      _settingsTapCount = 0;
    });

    if (_settingsTapCount >= 7) {
      _settingsTapCount = 0;
      _settingsTapResetTimer?.cancel();
      if (!_rawDataServerController.developerMode) {
        _rawDataServerController.setDeveloperMode(true);
        HapticFeedback.mediumImpact();
        if (context.mounted) {
          TopNotice.show(
            context,
            message: '已开启开发者模式',
            tone: TopNoticeTone.success,
          );
        }
      } else {
        HapticFeedback.lightImpact();
        if (context.mounted) {
          TopNotice.show(context, message: '当前已处于开发者模式');
        }
      }
    }
  }
}

final class _IOSRawDataConsumer implements GameApiEventConsumer {
  _IOSRawDataConsumer(this._controller);

  final RawDataServerController _controller;

  @override
  bool supportsPath(String path) => path.contains('/api_start2/getData');

  @override
  void accept(CapturedApiEvent event) {
    if (_controller.developerMode) {
      _controller.saveRawMasterData(event.responseBody);
    }
  }

  @override
  Future<void> get idle => Future.value();
}

final class _IosDisabledGameResourceCachePort implements GameResourceCachePort {
  const _IosDisabledGameResourceCachePort();

  @override
  Future<bool> configure(GameResourceCacheMode mode) async => true;

  @override
  Future<GameResourceCacheStatus> status() async =>
      GameResourceCacheStatus.empty;

  @override
  Future<bool> setManifest(
    GameResourceManifest manifest, {
    bool Function()? shouldContinue,
  }) async => false;

  @override
  Future<bool> startDownload({bool allowMetered = false}) async => false;

  @override
  Future<bool> pauseDownload() async => false;

  @override
  Future<GameResourceCacheStatus> checkIntegrity() async =>
      GameResourceCacheStatus.empty;

  @override
  Future<bool> repair({bool allowMetered = false}) async => false;

  @override
  Future<bool> clear() async => false;
}
