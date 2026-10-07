import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:yahagi_kancolle_browser/src/kcwiki_report/kcwiki_report_request.dart';
import 'package:yahagi_kancolle_browser/src/kcwiki_report/kcwiki_report_transport.dart';

void main() {
  test(
    'total deadline cancels a response that never ends without closing client',
    () {
      fakeAsync((clock) {
        final client = _ControlledClient();
        final transport = HttpKcwikiReportTransport(
          client: client,
          baseUri: Uri.parse('https://example.test'),
          timeout: const Duration(seconds: 8),
        );
        KcwikiTransportResult? result;
        transport.send(_request()).then((value) => result = value);
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 9));
        expect(result?.failure, KcwikiTransportFailure.timeout);
        expect(client.aborted, 1);
        expect(client.cancelled, 1);
        expect(client.closed, isFalse);
        expect(
          client.requests,
          hasLength(1),
          reason: 'POST must not be retried',
        );
        transport.close();
      });
    },
  );

  test('slow response chunks do not renew the total deadline', () {
    fakeAsync((clock) {
      final client = _ControlledClient();
      final transport = HttpKcwikiReportTransport(
        client: client,
        baseUri: Uri.parse('https://example.test'),
        timeout: const Duration(seconds: 8),
      );
      KcwikiTransportResult? result;
      transport.send(_request()).then((value) => result = value);
      clock.flushMicrotasks();
      for (var i = 0; i < 8; i++) {
        client.body.add([1]);
        clock.elapse(const Duration(seconds: 1));
      }
      expect(result?.failure, KcwikiTransportFailure.timeout);
      expect(client.cancelled, 1);
      transport.close();
    });
  });

  test('late headers are cancelled after timeout and cannot succeed later', () {
    fakeAsync((clock) {
      final client = _ControlledClient()..holdHeaders = true;
      final transport = HttpKcwikiReportTransport(
        client: client,
        baseUri: Uri.parse('https://example.test'),
        timeout: const Duration(seconds: 8),
      );
      final results = <KcwikiTransportResult>[];
      transport.send(_request()).then(results.add);
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 9));
      expect(results.single.failure, KcwikiTransportFailure.timeout);
      expect(client.aborted, 1);
      client.headers.complete(http.StreamedResponse(client.body.stream, 204));
      clock.flushMicrotasks();
      expect(client.cancelled, 1);
      expect(results, hasLength(1));
      transport.close();
    });
  });

  test('closing transport completes active body and late-header requests', () {
    fakeAsync((clock) {
      for (final holdHeaders in [false, true]) {
        final client = _ControlledClient()..holdHeaders = holdHeaders;
        final transport = HttpKcwikiReportTransport(
          client: client,
          baseUri: Uri.parse('https://example.test'),
        );
        KcwikiTransportResult? result;
        transport.send(_request()).then((value) => result = value);
        clock.flushMicrotasks();
        transport.close();
        clock.flushMicrotasks();
        expect(result?.failure, KcwikiTransportFailure.network);
        expect(client.aborted, 1);
        if (holdHeaders) {
          client.headers.complete(
            http.StreamedResponse(client.body.stream, 204),
          );
          clock.flushMicrotasks();
        }
        expect(client.cancelled, 1);
      }
    });
  });

  test('completed response releases its deadline and accepts only 2xx', () {
    fakeAsync((clock) {
      for (final status in [200, 204, 400, 503]) {
        final client = _ControlledClient()..statusCode = status;
        final transport = HttpKcwikiReportTransport(
          client: client,
          baseUri: Uri.parse('https://example.test'),
        );
        KcwikiTransportResult? result;
        transport.send(_request()).then((value) => result = value);
        clock.flushMicrotasks();
        client.body.add([1, 2]);
        client.body.close();
        clock.flushMicrotasks();
        expect(result?.accepted, status < 300);
        expect(result?.statusCode, status);
        expect(clock.nonPeriodicTimerCount, 0);
        clock.elapse(const Duration(seconds: 9));
        expect(client.aborted, 0);
        transport.close();
      }
    });
  });

  test('cleartext endpoint never receives a report', () async {
    final client = _RecordingClient();
    final transport = HttpKcwikiReportTransport(
      client: client,
      baseUri: Uri.parse('http://example.test:17027'),
    );
    addTearDown(transport.close);

    final result = await transport.send(
      KcwikiReportRequest.form(
        KcwikiReportModule.quest,
        const <String, Object?>{},
      ),
    );
    expect(result.accepted, isFalse);
    expect(client.requests, isEmpty);
  });

  test('quest uses form encoding and battle uses JSON', () async {
    final client = _RecordingClient();
    final transport = HttpKcwikiReportTransport(
      client: client,
      baseUri: Uri.parse('https://example.test:17027'),
    );
    addTearDown(transport.close);

    await transport.send(
      KcwikiReportRequest.form(KcwikiReportModule.quest, <String, Object?>{
        'current': 101,
        'after': <int>[301],
      }),
    );
    await transport.send(
      KcwikiReportRequest.json(KcwikiReportModule.battle, <String, Object?>{
        'data': <String, Object?>{},
      }),
    );

    expect(client.requests[0].url.path, '/api/report/quest');
    expect(
      client.requests[0].headers['content-type'],
      contains('application/x-www-form-urlencoded'),
    );
    expect(client.requests[0].body, contains('after%5B0%5D=301'));
    expect(client.requests[1].url.path, '/api/report/battle');
    expect(
      client.requests[1].headers['content-type'],
      contains('application/json'),
    );
    expect(jsonDecode(client.requests[1].body), <String, Object?>{
      'data': <String, Object?>{},
    });
  });

  test('non-2xx response is reported as rejected', () async {
    final transport = HttpKcwikiReportTransport(
      client: _RecordingClient(statusCode: 503),
      baseUri: Uri.parse('https://example.test:17027'),
    );
    addTearDown(transport.close);

    final result = await transport.send(
      KcwikiReportRequest.form(
        KcwikiReportModule.quest,
        const <String, Object?>{},
      ),
    );

    expect(result.accepted, isFalse);
    expect(result.statusCode, 503);
  });

  test('oversized body is rejected before opening the network', () async {
    final client = _RecordingClient();
    final transport = HttpKcwikiReportTransport(
      client: client,
      baseUri: Uri.parse('https://example.test:17027'),
      maxBodyBytes: 10,
    );
    addTearDown(transport.close);

    final result = await transport.send(
      KcwikiReportRequest.json(KcwikiReportModule.battle, <String, Object?>{
        'data': 'long payload',
      }),
    );

    expect(result.accepted, isFalse);
    expect(result.failure, KcwikiTransportFailure.bodyTooLarge);
    expect(client.requests, isEmpty);
  });

  test('request timeout becomes an isolated failure', () async {
    final transport = HttpKcwikiReportTransport(
      client: _RecordingClient(block: true),
      baseUri: Uri.parse('https://example.test:17027'),
      timeout: const Duration(milliseconds: 1),
    );
    addTearDown(transport.close);

    final result = await transport.send(
      KcwikiReportRequest.form(
        KcwikiReportModule.quest,
        const <String, Object?>{},
      ),
    );

    expect(result.accepted, isFalse);
    expect(result.failure, KcwikiTransportFailure.timeout);
  });
}

KcwikiReportRequest _request() => KcwikiReportRequest.form(
  KcwikiReportModule.quest,
  const <String, Object?>{},
);

final class _ControlledClient extends http.BaseClient {
  _ControlledClient() {
    body = StreamController<List<int>>(
      onCancel: () {
        cancelled++;
      },
    );
  }
  late final StreamController<List<int>> body;
  final headers = Completer<http.StreamedResponse>();
  final requests = <http.BaseRequest>[];
  bool holdHeaders = false;
  int statusCode = 204;
  int aborted = 0;
  int cancelled = 0;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (request is http.Abortable) {
      request.abortTrigger?.then((_) {
        aborted++;
      });
    }
    if (holdHeaders) return headers.future;
    return http.StreamedResponse(body.stream, statusCode);
  }

  @override
  void close() {
    closed = true;
  }
}

final class _RecordingClient extends http.BaseClient {
  _RecordingClient({this.statusCode = 204, this.block = false});

  final int statusCode;
  final bool block;
  final List<http.Request> requests = <http.Request>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final materialized = request as http.Request;
    requests.add(materialized);
    if (block) await Completer<void>().future;
    return http.StreamedResponse(const Stream<List<int>>.empty(), statusCode);
  }
}
