import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('debug and release builds use the 1.0.9 beta2 version contract', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(
      pubspec,
      contains(RegExp(r'^version: 1\.0\.9-beta\.2\+22\r?$', multiLine: true)),
    );
  });
}
