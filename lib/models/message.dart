class Message {
  final String id;
  final String text;
  final bool isFromUser;
  final DateTime timestamp;

  Message({
    required this.id,
    required this.text,
    required this.isFromUser,
    required this.timestamp,
  });

  // Преобразование из JSON (с бэкенда)
  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      text: json['text'],
      isFromUser: json['isFromUser'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  // Преобразование в JSON (на бэкенд)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'isFromUser': isFromUser,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}