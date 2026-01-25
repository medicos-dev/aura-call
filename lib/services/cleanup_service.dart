import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service to periodically cleanup abandoned signals
/// This runs from the app for free tier Supabase
/// For Pro tier, use pg_cron in the database instead
class CleanupService {
  static final CleanupService _instance = CleanupService._internal();
  factory CleanupService() => _instance;
  CleanupService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  Timer? _cleanupTimer;
  bool _isRunning = false;

  /// Start the cleanup service
  /// Runs every 20 minutes in background
  void start() {
    if (_isRunning) return;
    _isRunning = true;

    // Run immediately on start
    _runCleanup();

    // Then run every 20 minutes
    _cleanupTimer = Timer.periodic(
      const Duration(minutes: 20),
      (_) => _runCleanup(),
    );

    debugPrint('[CleanupService] Started - running every 20 minutes');
  }

  /// Stop the cleanup service
  void stop() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _isRunning = false;
    debugPrint('[CleanupService] Stopped');
  }

  /// Run the cleanup
  Future<void> _runCleanup() async {
    try {
      debugPrint('[CleanupService] Running cleanup...');

      // Call the RPC function
      final result = await _supabase.rpc('run_signal_cleanup');

      if (result != null) {
        debugPrint('[CleanupService] Cleanup complete:');
        debugPrint('  Before: ${result['before']} signals');
        debugPrint('  Deleted: ${result['deleted']} signals');
        debugPrint('  After: ${result['after']} signals');
      }
    } catch (e) {
      debugPrint('[CleanupService] Error: $e');
      // Don't rethrow - we don't want to crash the app
    }
  }

  /// Manual cleanup trigger (can be called from settings)
  Future<Map<String, dynamic>?> runManualCleanup() async {
    try {
      final result = await _supabase.rpc('run_signal_cleanup');
      return result as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[CleanupService] Manual cleanup error: $e');
      return null;
    }
  }
}
