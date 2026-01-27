class User {
  final String id;
  final String callId; // The 6-char code
  final String displayName;
  final DateTime? lastSeen;

  User({
    required this.id,
    required this.callId,
    required this.displayName,
    this.lastSeen,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      callId: json['call_id'] as String,
      displayName: json['username'] as String? ?? 'Unknown',
      lastSeen:
          json['last_seen'] != null ? DateTime.parse(json['last_seen']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'call_id': callId,
      'username': displayName, // API expects username now
      'last_seen': lastSeen?.toIso8601String(),
    };
  }
}
