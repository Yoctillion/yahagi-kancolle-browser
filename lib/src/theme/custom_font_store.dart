import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'custom_font_descriptor.dart';

abstract interface class CustomFontStore {
  Future<CustomFontDescriptor?> load();
  Future<void> save(CustomFontDescriptor? font);
}

final class SharedPreferencesCustomFontStore implements CustomFontStore {
  const SharedPreferencesCustomFontStore();

  static const _key = 'custom_font_selection_v1';

  @override
  Future<CustomFontDescriptor?> load() async {
    final value = (await SharedPreferences.getInstance()).getString(_key);
    return value == null
        ? null
        : CustomFontDescriptor.fromMap(jsonDecode(value));
  }

  @override
  Future<void> save(CustomFontDescriptor? font) async {
    final preferences = await SharedPreferences.getInstance();
    try {
      final saved = font == null
          ? await preferences.remove(_key)
          : await preferences.setString(_key, jsonEncode(font.toMap()));
      if (!saved) {
        throw StateError('Custom font preference was not saved');
      }
    } catch (_) {
      // Legacy SharedPreferences changes its cache before the platform confirms.
      try {
        await preferences.reload();
      } catch (_) {}
      rethrow;
    }
  }
}
