import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('app.yahagi.kancollebrowser/mod_manager');

/// Existing mod UI fixtures use a fake repository but create the real optional
/// portrait controller. Supply only that controller's empty platform snapshot.
void mockGameModPortraitPlatform() {
  SharedPreferences.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        if (call.method == 'portraitSnapshot') {
          return {'token': 'test-empty', 'resources': <Object>[]};
        }
        throw MissingPluginException('Unexpected test method: ${call.method}');
      });
}

void clearGameModPortraitPlatformMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null);
}
