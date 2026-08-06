import 'package:flutter/material.dart';

/// Global [GlobalKey] for [ScaffoldMessengerState], used by non-UI code (e.g.
/// tunnel start/stop callbacks running without a [BuildContext]) to surface
/// errors as snackbars. Pulled out of `main.dart` so it can be imported
/// without creating an import cycle between UI and `AppState`.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
