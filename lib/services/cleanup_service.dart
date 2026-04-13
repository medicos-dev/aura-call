import 'dart:async';
import 'package:flutter/foundation.dart';

class CleanupService {
  static final CleanupService _instance = CleanupService._internal();
  factory CleanupService() => _instance;
  CleanupService._internal();

  void start() {
    debugPrint('[CleanupService] Dummy mode started');
  }

  void stop() {
    debugPrint('[CleanupService] Dummy mode stopped');
  }

  Future<Map<String, dynamic>?> runManualCleanup() async {
    return {'before': 0, 'deleted': 0, 'after': 0};
  }
}
