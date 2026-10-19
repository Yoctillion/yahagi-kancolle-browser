import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/bridge/native_game_capture_script.dart';

void main() {
  const required = [
    'YAHAGI_GAME_DECODED_JS',
    'YAHAGI_GAME_START2_JSON',
    'YAHAGI_REAL_MOD_ZIP',
    'YAHAGI_REAL_VOICE_MOD_ZIP',
  ];
  final missing = required
      .where((key) => (Platform.environment[key] ?? '').isEmpty)
      .toList();
  test(
    'real game startup and port consumers use original mod coordinates',
    () {
      final temporary = Directory.systemTemp.createTempSync(
        'yahagi-real-game-consumer-',
      );
      try {
        final capture = File('${temporary.path}/capture.js')
          ..writeAsStringSync(nativeGameCaptureScript);
        final result = Process.runSync('node', [
          'test/fixtures/game_mod_coordinate_game_consumer_test.cjs',
          'android/app/src/main/kotlin/app/yahagi/kancollebrowser/mods/GameModCoordinateScript.kt',
          capture.path,
        ]);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(result.stdout, contains('6 scenarios passed'));
        expect(result.stdout, contains('31 actual PNGs'));
      } finally {
        temporary.deleteSync(recursive: true);
      }
    },
    skip: missing.isEmpty
        ? false
        : 'Optional local fixtures: ${missing.join(', ')}',
  );
}
