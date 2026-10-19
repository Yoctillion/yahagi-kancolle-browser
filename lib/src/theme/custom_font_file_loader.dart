import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'custom_font_descriptor.dart';

/// Engine font registrations cannot be unloaded before restarting the app.
final class CustomFontLoadLimitException implements Exception {
  const CustomFontLoadLimitException();

  @override
  String toString() => 'Custom font registration limit reached';
}

/// Reads and validates off the UI isolate, retaining only registration totals.
final class CustomFontFileLoader {
  CustomFontFileLoader({this._readFont});

  static const maxRegisteredFonts = 8;
  static const maxFontBytes = 32 * 1024 * 1024;
  static const maxRegisteredBytes = 64 * 1024 * 1024;

  final Future<Uint8List> Function(CustomFontDescriptor font)? _readFont;
  final Set<String> _loadedIds = {};
  int _registeredBytes = 0;

  Future<void> load(CustomFontDescriptor font) async {
    if (_loadedIds.contains(font.id)) return;
    final remainingBytes = maxRegisteredBytes - _registeredBytes;
    if (_loadedIds.length >= maxRegisteredFonts || remainingBytes == 0) {
      throw const CustomFontLoadLimitException();
    }
    final bytes = _readFont == null
        ? await _readInWorker(font, remainingBytes)
        : await _readFont(font);
    if (bytes.length > maxFontBytes) {
      throw const FormatException('Font file size is invalid');
    }
    if (bytes.length > remainingBytes) {
      throw const CustomFontLoadLimitException();
    }
    final loader = FontLoader(font.fontFamily)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    _loadedIds.add(font.id);
    _registeredBytes += bytes.length;
  }
}

Future<Uint8List> _readInWorker(
  CustomFontDescriptor font,
  int remainingBytes,
) => Isolate.run(
  () => readAndValidateCustomFontFile(font, remainingBytes: remainingBytes),
);

/// Worker entry point. The returned bytes are the exact bytes registered.
Future<Uint8List> readAndValidateCustomFontFile(
  CustomFontDescriptor font, {
  int remainingBytes = CustomFontFileLoader.maxRegisteredBytes,
}) async {
  final file = await File(font.path).open();
  late Uint8List bytes;
  try {
    final length = await file.length();
    if (length < 12 || length > CustomFontFileLoader.maxFontBytes) {
      throw const FormatException('Font file size is invalid');
    }
    if (length > remainingBytes) {
      throw const CustomFontLoadLimitException();
    }
    bytes = Uint8List(length);
    var offset = 0;
    while (offset < length) {
      final count = await file.readInto(bytes, offset, length);
      if (count == 0) {
        throw const FormatException('Font file is truncated');
      }
      offset += count;
    }
  } finally {
    await file.close();
  }
  // Flutter can report successful loading after its decoder rejects a font.
  // Native import validates the font and uses its content digest as the ID.
  if (sha256.convert(bytes).toString() != font.id) {
    throw const FormatException('Font file content has changed');
  }
  final data = ByteData.sublistView(bytes);
  final signature = data.getUint32(0);
  if (signature != 0x00010000 && // TrueType
      signature != 0x4f54544f && // OpenType CFF (OTTO)
      signature != 0x74727565) {
    // Apple TrueType (true)
    throw const FormatException('Unsupported font file header');
  }
  final tables = data.getUint16(4);
  if (tables == 0 || 12 + 16 * tables > bytes.length) {
    throw const FormatException('Invalid font table directory');
  }
  for (var index = 0; index < tables; index++) {
    final record = 12 + index * 16;
    final offset = data.getUint32(record + 8);
    final length = data.getUint32(record + 12);
    if (offset > bytes.length || length > bytes.length - offset) {
      throw const FormatException('Font table is truncated');
    }
  }
  return bytes;
}
