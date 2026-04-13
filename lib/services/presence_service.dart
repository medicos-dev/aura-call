import 'dart:async';

class PresenceService {
  final String myCallId;
  final Function(List<String>) onOnlineUsersUpdated;
  Timer? _timer;

  PresenceService({
    required this.myCallId,
    required this.onOnlineUsersUpdated,
  });

  void connect() {
    // Dummy Presence for UI UI Design Overhaul
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      onOnlineUsersUpdated([
        'MOCK01',
        'MOCK02',
        'MOCK05'
      ]); 
    });
    
    // Immediate mock
    onOnlineUsersUpdated([
      'MOCK01',
      'MOCK02',
    ]);
  }

  void disconnect() {
    _timer?.cancel();
  }
}
