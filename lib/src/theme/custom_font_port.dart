import 'package:flutter/services.dart';

import 'custom_font_descriptor.dart';

export 'custom_font_descriptor.dart';

abstract interface class CustomFontPort {
  Future<CustomFontDescriptor?> importFont();
  Future<void> removeFont(String id);
}

/// Optional startup cleanup for files left by an interrupted preview/import.
abstract interface class CustomFontMaintenancePort {
  Future<void> pruneFonts(Set<String> ids);
}

/// Produces a temporary image instead of registering a preview font in Flutter.
abstract interface class CustomFontPreviewPort {
  Future<Uint8List> renderPreview(
    CustomFontDescriptor font, {
    required String text,
    required int width,
    required double fontSize,
    required String locale,
    required int color,
  });
}

final class MethodChannelCustomFontPort
    implements
        CustomFontPort,
        CustomFontMaintenancePort,
        CustomFontPreviewPort {
  const MethodChannelCustomFontPort([
    this.channel = const MethodChannel(
      'app.yahagi.kancollebrowser/custom_fonts',
    ),
  ]);

  final MethodChannel channel;

  @override
  Future<CustomFontDescriptor?> importFont() async {
    final value = await channel.invokeMethod<Object?>('importFont');
    return value == null ? null : CustomFontDescriptor.fromMap(value);
  }

  @override
  Future<void> removeFont(String id) =>
      channel.invokeMethod<void>('removeFont', {'id': id});

  @override
  Future<void> pruneFonts(Set<String> ids) =>
      channel.invokeMethod<void>('pruneFonts', {'ids': ids.toList()});

  @override
  Future<Uint8List> renderPreview(
    CustomFontDescriptor font, {
    required String text,
    required int width,
    required double fontSize,
    required String locale,
    required int color,
  }) async {
    final bytes = await channel.invokeMethod<Object?>('renderPreview', {
      'id': font.id,
      'text': text,
      'width': width,
      'fontSize': fontSize,
      'locale': locale,
      'color': color,
    });
    if (bytes is! Uint8List ||
        bytes.isEmpty ||
        bytes.length > 3 * 1024 * 1024) {
      throw const FormatException('Invalid font preview image');
    }
    return bytes;
  }
}
