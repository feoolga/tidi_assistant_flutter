// lib/data/models/message_dto.dart

/// DTO для сообщения — точно соответствует JSON-ответу бэкенда.
///
/// Используется только для парсинга данных, НЕ содержит бизнес-логики.
class MessageDto {
  final String id;
  final String text;
  final bool isFromUser;
  final DateTime timestamp;
  final String? agentId;
  final String? sessionId;
  final List<Map<String, dynamic>>? sources;
  final Map<String, dynamic>? feedback;

  const MessageDto({
    required this.id,
    required this.text,
    required this.isFromUser,
    required this.timestamp,
    this.agentId,
    this.sessionId,
    this.sources,
    this.feedback,
  });

  /// Создает DTO из JSON-ответа бэкенда.
  ///
  /// Поддерживает разные форматы:
  /// - Стандартный: {"id": "...", "content": "...", "role": "user", "created_at": "..."}
  /// - Альтернативный: {"id": "...", "text": "...", "isFromUser": true, "timestamp": "..."}
  factory MessageDto.fromJson(Map<String, dynamic> json) {
    // --- Определяем автора ---
    bool isFromUser;
    if (json.containsKey('role')) {
      isFromUser = json['role'] == 'user';
    } else if (json.containsKey('isFromUser')) {
      isFromUser = json['isFromUser'] as bool? ?? false;
    } else {
      isFromUser = false;
    }

    // --- Получаем текст ---
    final String text =
        json['content'] as String? ?? json['text'] as String? ?? '';

    // --- Получаем время ---
    final String timestampStr =
        json['created_at'] as String? ?? json['timestamp'] as String? ?? '';
    final DateTime timestamp = timestampStr.isNotEmpty
        ? DateTime.parse(timestampStr)
        : DateTime.now();

    // --- Получаем ID ---
    final String id =
        json['id']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();

    return MessageDto(
      id: id,
      text: text,
      isFromUser: isFromUser,
      timestamp: timestamp,
      agentId: json['agentId'] as String?,
      sessionId: json['sessionId'] as String?,
      sources: json['sources'] as List<Map<String, dynamic>>?,
      feedback: json['feedback'] as Map<String, dynamic>?,
    );
  }
}
