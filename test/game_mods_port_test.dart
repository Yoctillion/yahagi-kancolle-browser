import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_models.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_port.dart';
import 'package:yahagi_kancolle_browser/src/toolbox/game_mods/game_mods_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.yahagi.kancollebrowser/mod_manager');
  const port = MethodChannelGameModsPort();
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'capabilities' => {'supported': true},
            'pickAndPreflightArchive' => null,
            'applyAndReload' => {'result': 'blocked'},
            'status' => {'packages': [], 'sessionId': 8},
            _ => null,
          };
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test('channel sends explicit config, token, and package contracts', () async {
    expect((await port.capabilities()).supported, isTrue);
    expect(await port.pickAndPreflightArchive(), isNull);
    await port.saveDraft(
      const GameModsConfig(
        master: true,
        order: ['one'],
        enabledPackages: {'one'},
        enabledResources: {'resource'},
      ),
    );
    await port.commitImport('token');
    await port.discardImport('other');
    await port.removePackage('one');
    await port.resetAll();
    expect(await port.applyAndReload(), GameModsApplyResult.blocked);
    expect((await port.status()).sessionId, 8);
    expect(calls.firstWhere((c) => c.method == 'saveDraft').arguments, {
      'config': {
        'master': true,
        'order': ['one'],
        'enabledPackages': ['one'],
        'enabledResources': ['resource'],
      },
    });
    expect(calls.firstWhere((c) => c.method == 'commitImport').arguments, {
      'token': 'token',
    });
    expect(calls.firstWhere((c) => c.method == 'discardImport').arguments, {
      'token': 'other',
    });
    expect(calls.firstWhere((c) => c.method == 'removePackage').arguments, {
      'id': 'one',
    });
  });
  test('cancel uses the draft-only native cancellation contract', () async {
    await port.cancelChanges();

    expect(calls.map((call) => call.method), ['cancelChanges']);
    expect(calls.single.arguments, isNull);
  });
  test('five locales explain coordinate locks with localized reasons', () {
    final labels = [
      for (final locale in const [
        Locale('zh'),
        Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        Locale('ja'),
        Locale('en'),
        Locale('ko'),
      ])
        GameModsStrings(locale).reason('coordinates_unsupported'),
    ];
    expect(labels.toSet().length, 5);
    expect(labels[3], contains('coordinates'));
    expect(GameModsStrings(const Locale('zh', 'TW')).title, '魔改管理');
  });
  test('archive paths are detail data rather than primary resource labels', () {
    final s = GameModsStrings(const Locale('en'));
    final resource = GameModResource.fromMap({
      'id': 'x',
      'path': 'kcs2/img/unknown/file.png',
      'label': 'kcs2/img/unknown/file.png',
      'kind': 'image',
      'supported': true,
    });
    expect(s.resourceLabel(resource, 1), 'Image resources 1');
    final ship = GameModResource.fromMap({
      'id': 's',
      'path': 'kcs2/resources/ship/full/0001_hash.png',
      'label': '0001 · full',
      'kind': 'ship',
      'supported': true,
    });
    expect(s.resourceLabel(ship, 1), '0001 · Full portrait');
    final background = GameModResource.fromMap({
      'id': 'bg',
      'path': 'kcs2/img/port/port_background.png',
      'label': 'kcs2/img/port/port_background.png',
      'kind': 'image',
      'supported': true,
    });
    expect(s.resourceLabel(background, 1), 'Home port background');
  });
}
