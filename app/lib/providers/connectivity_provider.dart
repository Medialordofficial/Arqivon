import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Watches network connectivity and exposes whether the device is offline.
class ConnectivityNotifier extends Notifier<bool> {
  StreamSubscription<List<ConnectivityResult>>? _sub;

  @override
  bool build() {
    _sub?.cancel();
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      state = results.contains(ConnectivityResult.none);
    });
    ref.onDispose(() => _sub?.cancel());

    // Assume online until proven otherwise.
    _checkNow();
    return false;
  }

  Future<void> _checkNow() async {
    final results = await Connectivity().checkConnectivity();
    state = results.contains(ConnectivityResult.none);
  }
}

/// `true` when the device has no network at all.
final isOfflineProvider =
    NotifierProvider<ConnectivityNotifier, bool>(ConnectivityNotifier.new);
