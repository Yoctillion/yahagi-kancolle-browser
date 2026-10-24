import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('debug and release builds use the 1.0.9 beta6 version contract', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(
      pubspec,
      contains(RegExp(r'^version: 1\.0\.9-beta\.6\+26\r?$', multiLine: true)),
    );
  });
}
