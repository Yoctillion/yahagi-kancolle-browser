import 'captured_api_event.dart';

final class CaptureEventSequenceGate {
  final Map<(String?, String?), int> _acceptedSequences = {};

  bool accept(CapturedApiEvent event) {
    if (event.sequence <= 0) return true;
    final scope = (event.captureSessionId, event.captureDocumentId);
    if (event.sequence <= (_acceptedSequences[scope] ?? 0)) return false;
    _acceptedSequences[scope] = event.sequence;
    if (_acceptedSequences.length > 64) {
      _acceptedSequences.remove(_acceptedSequences.keys.first);
    }
    return true;
  }

  void clear() => _acceptedSequences.clear();
}
