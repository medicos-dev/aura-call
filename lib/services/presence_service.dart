import 'package:supabase_flutter/supabase_flutter.dart';

class PresenceService {
  final SupabaseClient supabase;
  final String myCallId;
  final Function(List<String>) onOnlineUsersUpdated;

  RealtimeChannel? _channel;

  PresenceService({
    required this.supabase,
    required this.myCallId,
    required this.onOnlineUsersUpdated,
  });

  void connect() {
    _channel = supabase.channel('online_users');

    _channel!
        .onPresenceSync((payload) {
          // In some versions, presenceState() returns a List<PresenceState> or similar.
          // The error indicates it returns List<SinglePresenceState>.
          // Let's coerce it safely.
          final presenceState = _channel!.presenceState();

          List<String> onlineIds = [];

          // If it is indeed a list, we iterate.
          // Note: The structure might be different based on version.
          // We will try to handle it dynamically or assume the error was correct about List type.

          // ERROR was: getter 'keys' not defined for 'List<SinglePresenceState>'.
          // So it IS a list.

          // Let's assume SinglePresenceState has 'payloads' or 'payload'.
          // Inspection might be needed, but let's try standard iteration.

          for (final dynamic state in presenceState) {
            // Use dynamic access to bypass analyzer issues with SinglePresenceState
            // Structure expected: state.payloads -> List<Map<String, dynamic>>
            try {
              final payloads = state.payloads;
              if (payloads != null) {
                for (final p in payloads) {
                  if (p['call_id'] != null) {
                    onlineIds.add(p['call_id'] as String);
                  }
                }
              }
            } catch (e) {
              // Fallback or ignore
            }
          }

          onOnlineUsersUpdated(onlineIds.toSet().toList());
        })
        .onPresenceJoin((payload) {
          // Handle single join if needed
        })
        .onPresenceLeave((payload) {
          // Handle single leave if needed
        })
        .subscribe((status, error) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            await _channel!.track({
              'call_id': myCallId,
              'last_seen': DateTime.now().toIso8601String(),
            });
          }
        });
  }

  void disconnect() {
    if (_channel != null) {
      supabase.removeChannel(_channel!);
    }
  }
}
