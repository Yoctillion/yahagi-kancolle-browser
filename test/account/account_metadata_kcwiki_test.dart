import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:yahagi_kancolle_browser/src/account/account_session.dart';
import 'package:yahagi_kancolle_browser/src/bridge/captured_api_event.dart';
import 'package:yahagi_kancolle_browser/src/game_state/game_state.dart';
import 'package:yahagi_kancolle_browser/src/kcwiki_report/kcwiki_report_collector.dart';
import 'package:yahagi_kancolle_browser/src/kcwiki_report/kcwiki_report_consumer.dart';
import 'package:yahagi_kancolle_browser/src/kcwiki_report/kcwiki_report_dispatcher.dart';
import 'package:yahagi_kancolle_browser/src/kcwiki_report/kcwiki_report_request.dart';
import 'package:yahagi_kancolle_browser/src/kcwiki_report/kcwiki_report_settings.dart';
import 'package:yahagi_kancolle_browser/src/kcwiki_report/kcwiki_report_transport.dart';

class MemoryTransport implements KcwikiReportTransport {
  MemoryTransport(this.sent);
  final List<KcwikiReportRequest> sent;
  @override
  Future<KcwikiTransportResult> send(KcwikiReportRequest request) async {
    sent.add(request);
    return const KcwikiTransportResult.accepted(statusCode: 200);
  }

  @override
  void close() {}
}

CapturedApiEvent event(String path, Map<String, Object?> data) {
  final envelope = <String, Object?>{'api_result': 1, 'api_data': data};
  return CapturedApiEvent(
    path: path,
    responseBody: jsonEncode(envelope),
    decodedEnvelope: envelope,
    source: CaptureSource.manual,
    capturedAt: DateTime.utc(2026, 9, 30),
  );
}

void main() {
  test(
    'audit: same-member port flushes final battle just like next-node',
    () async {
      Future<int> run(bool viaPort) async {
        final sent = <KcwikiReportRequest>[];
        final session = AccountSession(initialMemberId: 1);
        final settings = await KcwikiReportController.load(
          MemoryKcwikiReportSettingsStore(true),
        );
        final dispatcher = KcwikiReportDispatcher(
          transportFactory: () => MemoryTransport(sent),
        );
        final consumer = KcwikiReportConsumer(
          controller: settings,
          collector: KcwikiReportCollector(),
          dispatcher: dispatcher,
          gameState: () => const GameState(memberId: 1),
          waitForGameState: () async {},
          accountSession: session,
        );
        Future<void> dispatch(CapturedApiEvent input) async {
          session.accept(input);
          consumer.accept(input);
          await consumer.idle;
        }

        await dispatch(
          event('/kcsapi/api_req_map/start', {
            'api_maparea_id': 3,
            'api_mapinfo_no': 2,
            'api_no': 1,
          }),
        );
        await dispatch(
          event('/kcsapi/api_req_sortie/battle', {
            'api_ship_ke': [1501],
            'api_e_nowhps': [20],
            'api_e_maxhps': [20],
          }),
        );
        await dispatch(
          event('/kcsapi/api_req_sortie/battleresult', {'api_win_rank': 'S'}),
        );
        await dispatch(
          viaPort
              ? event('/kcsapi/api_port/port', {
                  'api_basic': {'api_member_id': 1, 'api_nickname': 'same'},
                })
              : event('/kcsapi/api_req_map/next', {
                  'api_maparea_id': 3,
                  'api_mapinfo_no': 2,
                  'api_no': 2,
                }),
        );
        final count = sent
            .where((r) => r.module == KcwikiReportModule.battle)
            .length;
        consumer.dispose();
        settings.dispose();
        session.dispose();
        return count;
      }

      final port = await run(true), next = await run(false);
      expect(port, 1);
      expect(next, 1);
    },
  );
}
