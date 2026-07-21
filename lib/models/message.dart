// lib/models/message.dart

class Message {
  final String id;
  final String text;
  final bool isFromUser;
  final DateTime timestamp;
  
  final String? agentId;      // ID агента, который ответил (для сообщений AI)
  final String? sessionId;    // ID сессии (чата) на бэкенде
  
  // Для будущего: источники и фидбэк (пока не используем)
  final List<Map<String, dynamic>>? sources;
  final Map<String, dynamic>? feedback;

  Message({
    required this.id,
    required this.text,
    required this.isFromUser,
    required this.timestamp,
    this.agentId,
    this.sessionId,
    this.sources,
    this.feedback,
  });

  // Преобразование из JSON (с бэкенда)
  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      text: json['text'] as String,
      isFromUser: json['isFromUser'] as bool,
      timestamp: DateTime.parse(json['timestamp'] as String),
      agentId: json['agentId'] as String?,
      sessionId: json['sessionId'] as String?,
      sources: json['sources'] as List<Map<String, dynamic>>?,
      feedback: json['feedback'] as Map<String, dynamic>?,
    );
  }

  // Преобразование в JSON (на бэкенд)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'isFromUser': isFromUser,
      'timestamp': timestamp.toIso8601String(),
      if (agentId != null) 'agentId': agentId,
      if (sessionId != null) 'sessionId': sessionId,
      if (sources != null) 'sources': sources,
      if (feedback != null) 'feedback': feedback,
    };
  }

  // Создание копии с обновленными полями (immutable подход)
  Message copyWith({
    String? id,
    String? text,
    bool? isFromUser,
    DateTime? timestamp,
    String? agentId,
    String? sessionId,
    List<Map<String, dynamic>>? sources,
    Map<String, dynamic>? feedback,
  }) {
    return Message(
      id: id ?? this.id,
      text: text ?? this.text,
      isFromUser: isFromUser ?? this.isFromUser,
      timestamp: timestamp ?? this.timestamp,
      agentId: agentId ?? this.agentId,
      sessionId: sessionId ?? this.sessionId,
      sources: sources ?? this.sources,
      feedback: feedback ?? this.feedback,
    );
  }
}