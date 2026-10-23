import 'package:flutter/services.dart';

import 'ship_subtitle_catalog.dart';
import 'ship_subtitle_settings.dart';

const shipSubtitleChannel = MethodChannel(
  'app.yahagi.kancollebrowser/ship_subtitles',
);

abstract interface class ShipSubtitlePort {
  set onPositionChanged(void Function(double x, double y)? callback);
  Future<bool> isSupported();
  Future<void> configure({
    required bool enabled,
    required ShipSubtitleFontSize fontSize,
    required bool locked,
    required double x,
    required double y,
  });
  Future<void> setCatalog(ShipSubtitleCatalog catalog);
  Future<void> setShips(List<Map<String, Object?>> ships);
  void dispose();
}

final class MethodChannelShipSubtitlePort implements ShipSubtitlePort {
  MethodChannelShipSubtitlePort({this.channel = shipSubtitleChannel}) {
    channel.setMethodCallHandler(_onMethodCall);
  }

  final MethodChannel channel;
  @override
  void Function(double x, double y)? onPositionChanged;
  bool _disposed = false;

  Future<void> _onMethodCall(MethodCall call) async {
    if (_disposed || call.method != 'positionChanged') return;
    final value = call.arguments;
    if (value is! Map) return;
    final x = value['x'];
    final y = value['y'];
    if (x is! num ||
        y is! num ||
        !x.isFinite ||
        !y.isFinite ||
        x < 0 ||
        x > 1 ||
        y < 0 ||
        y > 1) {
      return;
    }
    onPositionChanged?.call(x.toDouble(), y.toDouble());
  }

  @override
  Future<bool> isSupported() async {
    if (_disposed) return false;
    return await channel.invokeMethod<bool>('isSupported') ?? false;
  }

  @override
  Future<void> configure({
    required bool enabled,
    required ShipSubtitleFontSize fontSize,
    required bool locked,
    required double x,
    required double y,
  }) async {
    if (_disposed) return;
    await channel.invokeMethod<void>('configure', {
      'enabled': enabled,
      'fontSize': fontSize.wireName,
      'locked': locked,
      'x': x,
      'y': y,
    });
  }

  @override
  Future<void> setCatalog(ShipSubtitleCatalog catalog) async {
    if (_disposed) return;
    await channel.invokeMethod<void>('setCatalog', {
      'version': catalog.version,
      'quotes': catalog.quotes,
    });
  }

  @override
  Future<void> setShips(List<Map<String, Object?>> ships) async {
    if (_disposed) return;
    await channel.invokeMethod<void>('setShips', {'ships': ships});
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    onPositionChanged = null;
    channel.setMethodCallHandler(null);
  }
}
