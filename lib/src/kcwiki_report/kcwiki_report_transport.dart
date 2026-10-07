import 'dart:async';

import 'package:http/http.dart' as http;

import 'kcwiki_report_request.dart';

Uri? configuredKcwikiReportEndpoint() {
  const raw = String.fromEnvironment('KCWIKI_REPORT_BASE_URL');
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

enum KcwikiTransportFailure { bodyTooLarge, timeout, network, rejected }

final class KcwikiTransportResult {
  const KcwikiTransportResult.accepted({required this.statusCode})
    : accepted = true,
      failure = null;

  const KcwikiTransportResult.failed({this.statusCode, required this.failure})
    : accepted = false;

  final bool accepted;
  final int? statusCode;
  final KcwikiTransportFailure? failure;
}

abstract interface class KcwikiReportTransport {
  Future<KcwikiTransportResult> send(KcwikiReportRequest request);

  void close();
}

final class HttpKcwikiReportTransport implements KcwikiReportTransport {
  HttpKcwikiReportTransport({
    required http.Client client,
    required this.baseUri,
    this.timeout = const Duration(seconds: 8),
    this.maxBodyBytes = 2 * 1024 * 1024,
  }) : assert(maxBodyBytes > 0) {
    _client = client;
  }

  late final http.Client _client;
  final Uri baseUri;
  final Duration timeout;
  final int maxBodyBytes;
  bool _closed = false;
  final Set<void Function()> _activeCancellations = {};

  @override
  Future<KcwikiTransportResult> send(KcwikiReportRequest request) async {
    if (_closed) {
      return const KcwikiTransportResult.failed(
        failure: KcwikiTransportFailure.network,
      );
    }
    if (request.byteLength > maxBodyBytes) {
      return const KcwikiTransportResult.failed(
        failure: KcwikiTransportFailure.bodyTooLarge,
      );
    }
    if (baseUri.scheme != 'https' ||
        baseUri.host.isEmpty ||
        baseUri.userInfo.isNotEmpty) {
      return const KcwikiTransportResult.failed(
        failure: KcwikiTransportFailure.network,
      );
    }
    final target = baseUri.resolve(request.module.path);
    final abort = Completer<void>();
    final outbound =
        http.AbortableRequest('POST', target, abortTrigger: abort.future)
          ..headers['content-type'] = request.contentType
          ..followRedirects = false
          ..body = request.encodedBody;

    final completion = Completer<KcwikiTransportResult>();
    StreamSubscription<List<int>>? subscription;
    Timer? deadline;
    late final void Function() cancel;

    void finish(KcwikiTransportResult result, {bool cancelRequest = false}) {
      if (completion.isCompleted) return;
      deadline?.cancel();
      _activeCancellations.remove(cancel);
      if (cancelRequest) {
        if (!abort.isCompleted) abort.complete();
        final active = subscription;
        if (active != null) {
          // Do not let a broken cancellation future keep the report queue busy.
          // The abort trigger also terminates this request in the native client.
          unawaited(active.cancel().catchError((Object _) {}));
        }
      }
      completion.complete(result);
    }

    cancel = () => finish(
      const KcwikiTransportResult.failed(
        failure: KcwikiTransportFailure.network,
      ),
      cancelRequest: true,
    );
    _activeCancellations.add(cancel);
    deadline = Timer(timeout, () {
      finish(
        const KcwikiTransportResult.failed(
          failure: KcwikiTransportFailure.timeout,
        ),
        cancelRequest: true,
      );
    });

    Future<void> consume() async {
      try {
        final response = await _client.send(outbound);
        if (completion.isCompleted) {
          // Injected clients may ignore Abortable. Cancel any late response too.
          await response.stream
              .listen((_) {}, onError: (Object _, StackTrace _) {})
              .cancel();
          return;
        }
        subscription = response.stream.listen(
          (_) {},
          onError: (Object _, StackTrace _) => cancel(),
          onDone: () => finish(
            response.statusCode >= 200 && response.statusCode < 300
                ? KcwikiTransportResult.accepted(
                    statusCode: response.statusCode,
                  )
                : KcwikiTransportResult.failed(
                    statusCode: response.statusCode,
                    failure: KcwikiTransportFailure.rejected,
                  ),
          ),
        );
      } catch (_) {
        cancel();
      }
    }

    unawaited(consume());
    return completion.future;
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    for (final cancel in _activeCancellations.toList()) {
      cancel();
    }
    _client.close();
  }
}
