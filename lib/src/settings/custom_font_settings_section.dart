import '../theme/app_palette.dart';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yahagi_kancolle_browser/l10n/app_localizations.dart';

import '../theme/custom_font_controller.dart';
import 'settings_ui_helpers.dart';

class CustomFontSettingsSection extends StatefulWidget {
  const CustomFontSettingsSection({
    super.key,
    required this.controller,
    required this.fallbackFonts,
  });

  final CustomFontController controller;
  final List<String> fallbackFonts;

  @override
  State<CustomFontSettingsSection> createState() =>
      _CustomFontSettingsSectionState();
}

class _CustomFontSettingsSectionState extends State<CustomFontSettingsSection> {
  bool _working = false;
  String? _error;

  Future<void> _importFont() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final font = await widget.controller.importForPreview();
      if (!mounted || font == null) return;
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            _FontPreviewDialog(controller: widget.controller, font: font),
      );
    } catch (error) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(
          () => _error = switch (error) {
            PlatformException(code: 'font_too_large') =>
              l10n.customFontTooLarge,
            MissingPluginException() => l10n.customFontUnsupported,
            PlatformException(code: 'unsupported_platform') =>
              l10n.customFontUnsupported,
            _ => l10n.customFontImportFailed,
          },
        );
      }
    } finally {
      await widget.controller.discardPreview();
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _restoreDefault() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await widget.controller.restoreDefault();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = AppLocalizations.of(context)!.customFontSaveFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final enabled = !_working && !widget.controller.busy;
        final currentFont =
            widget.controller.selectedFont?.name ?? l10n.customFontDefault;
        final importIcon = widget.controller.busy
            ? SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: appOnAccentColor(context, Color(0xff332914)),
                ),
              )
            : const Icon(Icons.file_upload_outlined, size: 18);
        final restoreStyle = OutlinedButton.styleFrom(
          foregroundColor: appColor(context, const Color(0xffd4a85f)),
          minimumSize: const Size(36, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        );
        final importStyle = FilledButton.styleFrom(
          backgroundColor: appColor(context, const Color(0xffd4a85f)),
          foregroundColor: appOnAccentColor(context, const Color(0xff332914)),
          minimumSize: const Size(36, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        );
        final canRestore = enabled && widget.controller.selectedFont != null;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.customFontTitle,
                            style: appTextStyle(
                              context,
                              SettingsTileTypography.title,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Tooltip(
                            message: currentFont,
                            child: Text(
                              currentFont,
                              key: const Key('settings-custom-font-current'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: appTextStyle(
                                context,
                                SettingsTileTypography.description,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Tooltip(
                      message: l10n.customFontRestore,
                      child: constraints.maxWidth >= 520
                          ? OutlinedButton.icon(
                              key: const Key('settings-custom-font-restore'),
                              onPressed: canRestore ? _restoreDefault : null,
                              style: restoreStyle,
                              icon: const Icon(Icons.restore, size: 18),
                              label: Text(l10n.customFontRestore),
                            )
                          : OutlinedButton(
                              key: const Key('settings-custom-font-restore'),
                              onPressed: canRestore ? _restoreDefault : null,
                              style: restoreStyle,
                              child: const Icon(Icons.restore, size: 18),
                            ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message:
                          '${l10n.customFontImport}\n${l10n.customFontDescription}',
                      child: constraints.maxWidth >= 520
                          ? FilledButton.icon(
                              key: const Key('settings-custom-font-import'),
                              onPressed: enabled ? _importFont : null,
                              style: importStyle,
                              icon: importIcon,
                              label: Text(l10n.customFontImport),
                            )
                          : FilledButton(
                              key: const Key('settings-custom-font-import'),
                              onPressed: enabled ? _importFont : null,
                              style: importStyle,
                              child: importIcon,
                            ),
                    ),
                  ],
                ),
                if (_error case final error?) ...[
                  const SizedBox(height: 8),
                  Text(
                    error,
                    key: const Key('settings-custom-font-error'),
                    style: appTextStyle(
                      context,
                      TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FontPreviewDialog extends StatefulWidget {
  const _FontPreviewDialog({required this.controller, required this.font});

  final CustomFontController controller;
  final CustomFontDescriptor font;

  @override
  State<_FontPreviewDialog> createState() => _FontPreviewDialogState();
}

class _FontPreviewDialogState extends State<_FontPreviewDialog> {
  bool _saving = false;
  bool _saveFailed = false;
  bool _limitReached = false;
  bool _requested = false;
  bool _rendering = false;
  bool _previewFailed = false;
  ui.Image? _image;
  double _previewScale = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_requested) {
      _requested = true;
      unawaited(_renderPreview());
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  String _sample(AppLocalizations l10n) =>
      '${l10n.customFontPreviewSample}\n0123456789\nAa Bb Cc Xx Yy Zz';

  Future<void> _renderPreview() async {
    if (_rendering) return;
    final media = MediaQuery.of(context);
    final fontSize = media.textScaler.scale(18).clamp(12.0, 72.0);
    final scale = media.devicePixelRatio
        .clamp(1.0, 2.0)
        .clamp(1.0, 72 / fontSize);
    final width = ((media.size.width - 128).clamp(160, 480) * scale)
        .round()
        .clamp(160, 1024);
    final text = _sample(AppLocalizations.of(context)!);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final color =
        Theme.of(context).textTheme.bodyLarge?.color ?? const Color(0xffe5eef5);
    setState(() {
      _rendering = true;
      _previewFailed = false;
    });
    try {
      final bytes = await widget.controller.renderPreview(
        text: text,
        width: width,
        fontSize: fontSize * scale,
        locale: locale,
        color: color.toARGB32(),
      );
      if (!mounted) return;
      final image = await _decodePreview(bytes);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = image;
        _previewScale = scale;
        _rendering = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _rendering = false;
          _previewFailed = true;
        });
      }
    }
  }

  // Inspect dimensions before allocating decoded pixels, and keep ownership out
  // of the global ImageCache so closing a dialog releases its single image.
  Future<ui.Image> _decodePreview(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 3 * 1024 * 1024) {
      throw const FormatException('Invalid font preview size');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width <= 0 ||
          descriptor.width > 1024 ||
          descriptor.height <= 0 ||
          descriptor.height > 512 ||
          descriptor.width * descriptor.height > 524288) {
        throw const FormatException('Invalid font preview dimensions');
      }
      codec = await descriptor.instantiateCodec();
      return (await codec.getNextFrame()).image;
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  Future<void> _apply() async {
    setState(() {
      _saving = true;
      _saveFailed = false;
      _limitReached = false;
    });
    try {
      await widget.controller.applyPreview();
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _limitReached = error is CustomFontLoadLimitException;
          _saveFailed = !_limitReached;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        key: const Key('custom-font-preview-dialog'),
        scrollable: true,
        title: Text(l10n.customFontPreviewTitle),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.font.name),
            const SizedBox(height: 16),
            if (_image case final image?)
              Semantics(
                label: _sample(l10n),
                image: true,
                child: RawImage(
                  key: const Key('custom-font-preview-sample'),
                  image: image,
                  width: image.width / _previewScale,
                  height: image.height / _previewScale,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.low,
                ),
              )
            else if (_previewFailed) ...[
              Text(
                l10n.customFontPreviewFailed,
                key: const Key('custom-font-preview-render-error'),
                style: appTextStyle(
                  context,
                  TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              TextButton(
                key: const Key('custom-font-preview-retry'),
                onPressed: _renderPreview,
                child: Text(l10n.customFontPreviewRetry),
              ),
            ] else
              const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              ),
            const SizedBox(height: 16),
            Text(
              l10n.customFontPreviewNote,
              style: appTextStyle(context, SettingsTileTypography.description),
            ),
            if (_saveFailed || _limitReached) ...[
              const SizedBox(height: 8),
              Text(
                _limitReached
                    ? l10n.customFontLoadLimit
                    : l10n.customFontSaveFailed,
                key: const Key('custom-font-preview-error'),
                style: appTextStyle(
                  context,
                  TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            key: const Key('custom-font-preview-cancel'),
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('custom-font-preview-apply'),
            onPressed: _saving || _image == null ? null : _apply,
            child: Text(l10n.customFontApply),
          ),
        ],
      ),
    );
  }
}
