class CallSignal {
  final String id;
  final String senderId;
  final String receiverId;
  final String type; // 'offer', 'answer', 'ice', 'reject', 'ping'
  final Map<String, dynamic> data;
  final DateTime createdAt;

  CallSignal({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.type,
    required this.data,
    required this.createdAt,
  });

  factory CallSignal.fromJson(Map<String, dynamic> json) {
    return CallSignal(
      id: json['id'] as String,
      senderId: json['sender_id'] as String,
      receiverId: json['receiver_id'] as String,
      type: json['type'] as String,
      data: json['data'] as Map<String, dynamic>,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'type': type,
      'data': data,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
