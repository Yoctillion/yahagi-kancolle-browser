import 'package:flutter/widgets.dart';

import 'diagnostic_event.dart';

DiagnosticLifecycleState? diagnosticLifecycleState(AppLifecycleState? state) =>
    switch (state) {
      AppLifecycleState.resumed => DiagnosticLifecycleState.resumed,
      AppLifecycleState.inactive => DiagnosticLifecycleState.inactive,
      AppLifecycleState.hidden => DiagnosticLifecycleState.hidden,
      AppLifecycleState.paused => DiagnosticLifecycleState.paused,
      AppLifecycleState.detached => DiagnosticLifecycleState.stopped,
      null => null,
    };
