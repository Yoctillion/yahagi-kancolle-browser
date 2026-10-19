import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_catalog.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_catalog_store.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_language.dart';
import 'package:yahagi_kancolle_browser/src/subtitles/ship_subtitle_update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Korean catalog store can load its offline bundle without a loose JSON file',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'subtitle-ko-bundled-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final catalog = await FileShipSubtitleCatalogStore.inDirectory(
        directory,
        language: ShipSubtitleLanguage.korean,
      ).loadBestAvailable();
      expect(catalog.quoteCount, greaterThan(17000));
      expect(catalog.quotes['1']?['1'], contains('무츠키'));
    },
  );

  test('single-language Korean source uses its pinned KC3 file', () async {
    final directory = await Directory.systemTemp.createTemp('subtitle-ko-');
    addTearDown(() => directory.delete(recursive: true));
    final current = ShipSubtitleCatalog(
      version: '20260701000000',
      quotes: {
        '1': {'1': '이전 자막'},
      },
    );
    final store = FileShipSubtitleCatalogStore(
      cacheFile: File('${directory.path}/ko-kr.json'),
      bundledReader: () async => current.toJsonString(),
    );
    final urls = <Uri>[];
    const sha = '6fed2aac44a1ca95f2892bb1af93a6bc0e60b667';
    final result = await ShipSubtitleUpdateService(
      language: ShipSubtitleLanguage.korean,
      store: store,
      client: MockClient((request) async {
        urls.add(request.url);
        return http.Response(
          jsonEncode(
            request.url.host == 'api.github.com'
                ? [
                    {
                      'sha': sha,
                      'commit': {
                        'committer': {'date': '2026-10-17T02:31:18Z'},
                      },
                    },
                  ]
                : {
                    '1': {'Intro': '제독님, 출격 준비가 되었습니다!'},
                  },
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    ).checkAndUpdate(current: current);
    expect(
      result,
      isA<ShipSubtitleUpdated>(),
      reason: result is ShipSubtitleUpdateFailed ? '${result.error}' : null,
    );
    expect(urls.first.queryParameters['path'], 'data/kr/quotes.json');
    expect(urls.last.path, '/KC3Kai/kc3-translations/$sha/data/kr/quotes.json');
    expect(
      (await store.loadBestAvailable()).quotes['1']?['1'],
      '제독님, 출격 준비가 되었습니다!',
    );
  });
}
