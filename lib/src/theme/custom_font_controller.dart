import 'package:flutter/foundation.dart';

import 'custom_font_file_loader.dart';
import 'custom_font_port.dart';
import 'custom_font_store.dart';

export 'custom_font_descriptor.dart';
export 'custom_font_file_loader.dart' show CustomFontLoadLimitException;
export 'custom_font_port.dart';
export 'custom_font_store.dart';

typedef CustomFontLoader = Future<void> Function(CustomFontDescriptor font);

final class CustomFontController extends ChangeNotifier {
  CustomFontController._(this._store, this._port, this._loader);

  static Future<CustomFontController> load({
    CustomFontStore? store,
    CustomFontPort? port,
    CustomFontLoader? loader,
  }) async {
    final controller = CustomFontController._(
      store ?? const SharedPreferencesCustomFontStore(),
      port ?? const MethodChannelCustomFontPort(),
      loader ?? CustomFontFileLoader().load,
    );
    CustomFontDescriptor? saved;
    try {
      saved = await controller._store.load();
      if (saved != null) {
        await controller._ensureLoaded(saved);
        controller._selectedFont = saved;
      }
      controller._cleanupAllowed = true;
    } catch (_) {
      // A missing/corrupt font must not prevent the application from starting.
      try {
        await controller._store.save(null);
        controller._cleanupAllowed = true;
      } catch (_) {}
      await controller._removeUnused([saved]);
    }
    final Object maintenance = controller._port;
    if (controller._cleanupAllowed &&
        maintenance is CustomFontMaintenancePort) {
      try {
        final selectedId = controller._selectedFont?.id;
        await maintenance.pruneFonts({?selectedId});
      } catch (_) {
        // Interrupted-import cleanup must not prevent loading a saved font.
      }
    }
    return controller;
  }

  final CustomFontStore _store;
  final CustomFontPort _port;
  final CustomFontLoader _loader;
  // Font registration survives file cleanup, but is repeated on every startup.
  final Set<String> _loadedIds = {};
  CustomFontDescriptor? _selectedFont;
  CustomFontDescriptor? _previewFont;
  // Failed startup storage can hide the durable selection from runtime state.
  bool _cleanupAllowed = false;
  bool _busy = false;
  bool _disposed = false;

  CustomFontDescriptor? get selectedFont => _selectedFont;
  CustomFontDescriptor? get previewFont => _previewFont;
  String? get fontFamily => _selectedFont?.fontFamily;
  bool get busy => _busy;

  Future<Uint8List> renderPreview({
    required String text,
    required int width,
    required double fontSize,
    required String locale,
    required int color,
  }) async {
    final font = _previewFont;
    if (_disposed || font == null) {
      throw StateError('No custom font is staged for preview');
    }
    final Object port = _port;
    if (port is! CustomFontPreviewPort) {
      throw UnsupportedError('Font preview is unavailable on this platform');
    }
    return port.renderPreview(
      font,
      text: text,
      width: width,
      fontSize: fontSize,
      locale: locale,
      color: color,
    );
  }

  Future<CustomFontDescriptor?> importForPreview() async {
    if (_busy || _disposed) return null;
    _setBusy(true);
    CustomFontDescriptor? imported;
    try {
      imported = await _port.importFont();
      if (imported == null) return null;
      if (_disposed) {
        await _removeUnused([imported]);
        return null;
      }
      final previous = _previewFont;
      _previewFont = imported;
      _notify();
      await _removeUnused([previous]);
      return imported;
    } catch (_) {
      await _removeUnused([imported]);
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> applyPreview() async {
    final preview = _previewFont;
    if (_busy || _disposed || preview == null) return;
    _setBusy(true);
    try {
      await _ensureLoaded(preview);
      await _store.save(preview);
      _cleanupAllowed = true;
      final previous = _selectedFont;
      _selectedFont = preview;
      _previewFont = null;
      _notify();
      await _removeUnused([previous]);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> discardPreview() async {
    if (_busy || _disposed || _previewFont == null) return;
    _setBusy(true);
    try {
      final previous = _previewFont;
      _previewFont = null;
      _notify();
      await _removeUnused([previous]);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> restoreDefault() async {
    if (_busy || _disposed) return;
    _setBusy(true);
    try {
      await _store.save(null);
      _cleanupAllowed = true;
      final previous = [_selectedFont, _previewFont];
      _selectedFont = null;
      _previewFont = null;
      _notify();
      await _removeUnused(previous);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _ensureLoaded(CustomFontDescriptor font) async {
    if (_loadedIds.contains(font.id)) return;
    if (_loadedIds.length >= CustomFontFileLoader.maxRegisteredFonts) {
      throw const CustomFontLoadLimitException();
    }
    await _loader(font);
    _loadedIds.add(font.id);
  }

  Future<void> _removeUnused(Iterable<CustomFontDescriptor?> fonts) async {
    if (!_cleanupAllowed) return;
    final ids = fonts
        .whereType<CustomFontDescriptor>()
        .map((font) => font.id)
        .toSet();
    for (final id in ids) {
      if (id == _selectedFont?.id || id == _previewFont?.id) continue;
      try {
        await _port.removeFont(id);
      } catch (_) {
        // Cleanup cannot invalidate an already persisted selection.
      }
    }
  }

  void _setBusy(bool value) {
    _busy = value;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
