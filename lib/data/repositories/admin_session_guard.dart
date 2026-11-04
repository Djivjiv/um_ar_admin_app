import 'dart:async';

import 'package:flutter/widgets.dart';

/// Runs [check] every [interval] while the app is open, and again whenever it
/// returns to the foreground.
class AdminSessionGuard with WidgetsBindingObserver {
  static const interval = Duration(minutes: 10);

  final Future<Object?> Function() check;
  Timer? _timer;

  AdminSessionGuard({required this.check});

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(interval, (_) => check());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) check();
  }
}
