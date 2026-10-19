import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_catalog.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_port.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/ship-subtitles');
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'isSupported' ? true : null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'sends lightweight configuration separately from complete data',
    () async {
      final port = MethodChannelShipSubtitlePort(channel: channel);
      addTearDown(port.dispose);
      expect(await port.isSupported(), isTrue);
      await port.configure(
        enabled: true,
        fontSize: ShipSubtitleFontSize.large,
        locked: true,
        x: .3,
        y: .7,
      );
      await port.setCatalog(
        ShipSubtitleCatalog(
          version: '2026101805',
          quotes: {
            '1': {'1': '睦月，出击！'},
          },
        ),
      );
      await port.setShips([
        {'id': 1, 'fileName': 'secret', 'name': '睦月'},
      ]);
      final config = calls.firstWhere((call) => call.method == 'configure');
      expect(config.arguments, {
        'enabled': true,
        'fontSize': 'large',
        'locked': true,
        'x': .3,
        'y': .7,
      });
      expect((config.arguments as Map).containsKey('quotes'), isFalse);
      expect(
        calls.firstWhere((call) => call.method == 'setCatalog').arguments,
        {
          'version': '2026101805',
          'quotes': {
            '1': {'1': '睦月，出击！'},
          },
        },
      );
    },
  );

  test(
    'position callbacks accept only finite normalized coordinates',
    () async {
      final port = MethodChannelShipSubtitlePort(channel: channel);
      addTearDown(port.dispose);
      final positions = <List<double>>[];
      port.onPositionChanged = (x, y) => positions.add([x, y]);
      Future<void> send(Object? arguments) async {
        final completion = Completer<void>();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              channel.name,
              const StandardMethodCodec().encodeMethodCall(
                MethodCall('positionChanged', arguments),
              ),
              (_) => completion.complete(),
            );
        await completion.future;
      }

      await send({'x': .2, 'y': .8});
      await send({'x': -1, 'y': .8});
      await send({'x': double.nan, 'y': .8});
      await send({'x': .5, 'y': 2});
      expect(positions, [
        [.2, .8],
      ]);
    },
  );
}
