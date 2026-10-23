import 'package:flutter/foundation.dart';

import '../settings/safety_settings_store.dart';

class SortieWarningSession extends ChangeNotifier {
  bool _isActive = false;
  bool _isMuted = false;
  int _generation = 0;
  AdvanceWarningTimingSettings? _timings;

  bool get isActive => _isActive;
  bool get isMuted => _isMuted;
  int get generation => _generation;
  AdvanceWarningTimingSettings? get timings => _timings;

  AdvanceWarningTimingSettings timingsForSortie(
    AdvanceWarningTimingSettings configured,
  ) => _timings ??= configured;

  void startSortie() {
    _timings = null;
    _isActive = true;
    _isMuted = false;
    _generation++;
    notifyListeners();
  }

  void ensureSortie() {
    if (_isActive) return;
    _isActive = true;
    _generation++;
  }

  void endSortie() {
    _timings = null;
    _isActive = false;
    _isMuted = false;
    _generation++;
    notifyListeners();
  }

  void muteCurrentSortie() {
    if (!_isActive || _isMuted) return;
    _isMuted = true;
    notifyListeners();
  }
}
