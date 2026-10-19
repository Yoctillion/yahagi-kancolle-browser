import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yahagi_kancolle_browser/src/fleet/game_mod_portraits.dart';
import 'package:yahagi_kancolle_browser/src/fleet/ship_portrait.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';

void main() {
  final directory = Platform.environment['GAME_MOD_PORTRAIT_FIXTURE_DIR'];
  final characterDirectory =
      Platform.environment['GAME_MOD_CHARACTER_PORTRAIT_FIXTURE_DIR'];
  testWidgets(
    'three actual packages resolve and render wide, square and detail avatars',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(700, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final port = _RealPort(directory!);
      final controller = GameModPortraitController(port: port);
      await controller.initialize();
      addTearDown(controller.dispose);
      const ships = [
        MasterShip(
          id: 607,
          name: 'I-47',
          shipTypeId: 13,
          portraitVersion: '1',
          portraitFileName: 'tciiyagxjjpu',
        ),
        MasterShip(
          id: 426,
          name: 'Fubuki',
          shipTypeId: 2,
          portraitVersion: '1',
          portraitFileName: 'rtkekdbkqrkg',
        ),
        MasterShip(
          id: 735,
          name: 'Lexington',
          shipTypeId: 11,
          portraitVersion: '1',
          portraitFileName: 'xngurirfszwi',
        ),
      ];
      final prepared = await tester.runAsync(
        () => Future.wait(ships.map(controller.resolve)),
      );
      expect(prepared!.every((p) => p != null), isTrue);
      expect(prepared.map((p) => p!.layout), [
        GameModPortraitLayout.full,
        GameModPortraitLayout.banner,
        GameModPortraitLayout.banner,
      ]);
      // Full-only I-47 uses the same fixed top-left square as every other full
      // resource. The 256px output is a thumbnail, not a per-ship composition.
      await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(prepared.first!.bytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 256);
        expect(frame.image.height, 256);
        frame.image.dispose();
        codec.dispose();
      });
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: GameModPortraitScope(
            controller: controller,
            child: Scaffold(
              backgroundColor: const Color(0xff091923),
              body: RepaintBoundary(
                key: boundaryKey,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Applied mods / 96x56 / 80x80 / 120x100',
                        style: TextStyle(color: Colors.white),
                      ),
                      for (final ship in ships)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 90,
                                child: Text(
                                  ship.name,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              for (final size in [
                                const Size(96, 56),
                                const Size(80, 80),
                                const Size(120, 100),
                              ])
                                Padding(
                                  padding: const EdgeInsets.only(right: 20),
                                  child: ShipPortrait(
                                    ship: ship,
                                    serverOrigin: 'https://example.test',
                                    width: size.width,
                                    height: size.height,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final context = tester.element(find.byType(Scaffold));
        await Future.wait(
          tester
              .widgetList<Image>(find.byType(Image))
              .map((widget) => precacheImage(widget.image, context)),
        );
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('game-mod-portrait')), findsNWidgets(9));
      expect(tester.takeException(), isNull);
      final boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final render = await boundary.toImage(pixelRatio: 2);
        final bytes = await render.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$directory/portrait-preview.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        for (var index = 0; index < ships.length; index++) {
          await File(
            '$directory/${ships[index].id}-prepared.png',
          ).writeAsBytes(prepared[index]!.bytes);
        }
        render.dispose();
      });
      await controller.setEnabled(false);
      // Do not mount official network images for this fixture-only export.
      expect(controller.enabled, isFalse);
      expect(await controller.resolve(ships.first), isNull);
    },
    skip: directory == null,
  );

  testWidgets(
    'actual Verniy and Zuikaku character canvases keep their complete faces',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(700, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final port = _CharacterPort(characterDirectory!);
      final controller = GameModPortraitController(port: port);
      await controller.initialize();
      addTearDown(controller.dispose);
      const ships = [
        MasterShip(
          id: 147,
          name: 'Верный',
          shipTypeId: 2,
          portraitVersion: '1',
        ),
        MasterShip(
          id: 467,
          name: '瑞鶴改二甲',
          shipTypeId: 18,
          portraitVersion: '1',
        ),
      ];
      final prepared = await tester.runAsync(
        () => Future.wait(ships.map(controller.resolve)),
      );
      expect(prepared, everyElement(isNotNull));
      expect(
        prepared!.map((portrait) => portrait!.layout),
        everyElement(GameModPortraitLayout.characterFull),
      );
      for (var index = 0; index < ships.length; index++) {
        final source = image.decodePng(
          File('$characterDirectory/${port.files[index]}').readAsBytesSync(),
        )!;
        expect((source.width, source.height), (431, 645));
        // These real character canvases have faces right of the old x=0 crop.
        // The fixed character_full template is the top-centred 194px square;
        // this specification uses literal coordinates, independent of ship ID.
        final expected = image.copyResize(
          image.copyCrop(source, x: 119, y: 0, width: 194, height: 194),
          width: 256,
          height: 256,
        );
        final actual = image.decodePng(prepared[index]!.bytes)!;
        expect((actual.width, actual.height), (256, 256));
        final actualPixels = sha256.convert(actual.getBytes()).toString();
        expect(actualPixels, sha256.convert(expected.getBytes()).toString());
        final oldFragment = image.copyResize(
          image.copyCrop(source, x: 0, y: 0, width: 194, height: 194),
          width: 256,
          height: 256,
        );
        expect(
          actualPixels,
          isNot(sha256.convert(oldFragment.getBytes()).toString()),
        );
      }
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: GameModPortraitScope(
            controller: controller,
            child: Scaffold(
              backgroundColor: const Color(0xff091923),
              body: RepaintBoundary(
                key: boundaryKey,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'character_full / 96x56 / 80x80 / 120x100',
                        style: TextStyle(color: Colors.white),
                      ),
                      for (final ship in ships)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 90,
                                child: Text(
                                  ship.name,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              for (final size in [
                                const Size(96, 56),
                                const Size(80, 80),
                                const Size(120, 100),
                              ])
                                Padding(
                                  padding: const EdgeInsets.only(right: 20),
                                  child: ShipPortrait(
                                    ship: ship,
                                    serverOrigin: 'https://example.test',
                                    width: size.width,
                                    height: size.height,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final context = tester.element(find.byType(Scaffold));
        await Future.wait(
          tester
              .widgetList<Image>(find.byType(Image))
              .map((widget) => precacheImage(widget.image, context)),
        );
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('game-mod-portrait')), findsNWidgets(6));
      expect(tester.takeException(), isNull);
      final boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final render = await boundary.toImage(pixelRatio: 2);
        final bytes = await render.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$characterDirectory/character-portrait-preview.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        for (var index = 0; index < ships.length; index++) {
          await File(
            '$characterDirectory/${ships[index].id}-prepared.png',
          ).writeAsBytes(prepared[index]!.bytes);
        }
        render.dispose();
      });
      await controller.setEnabled(false);
      expect(controller.enabled, isFalse);
      for (final ship in ships) {
        expect(await controller.resolve(ship), isNull);
      }
    },
    skip: characterDirectory == null,
  );
}

class _RealPort implements GameModPortraitPort {
  _RealPort(this.directory);
  final String directory;
  @override
  Future<GameModPortraitSnapshot> snapshot() async =>
      GameModPortraitSnapshot.fromMap({
        'token': 'actual-three-packages',
        'resources': [
          {
            'id': 'i47',
            'path': 'kcs2/resources/ship/full/0607_4674_tciiyagxjjpu.png',
          },
          {'id': 'fubuki', 'path': 'kcs2/resources/ship/banner/0426_4278.png'},
          {
            'id': 'lexington',
            'path': 'kcs2/resources/ship/banner/0735_8629.png',
          },
        ],
      });
  @override
  Future<Uint8List?> read({
    required String token,
    required String resourceId,
  }) => File('$directory/$resourceId.png').readAsBytes();
  @override
  void setChangedHandler(VoidCallback? handler) {}
}

class _CharacterPort implements GameModPortraitPort {
  _CharacterPort(this.directory);
  final String directory;
  final files = const ['0147_9741.png', '0467_8845.png'];

  @override
  Future<GameModPortraitSnapshot> snapshot() async =>
      GameModPortraitSnapshot.fromMap({
        'token': 'actual-character-canvas-regression',
        'resources': [
          for (final file in files)
            {'id': file, 'path': 'kcs2/resources/ship/character_full/$file'},
        ],
      });

  @override
  Future<Uint8List?> read({
    required String token,
    required String resourceId,
  }) => File('$directory/$resourceId').readAsBytes();

  @override
  void setChangedHandler(VoidCallback? handler) {}
}
