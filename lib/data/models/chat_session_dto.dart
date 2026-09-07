// lib/data/models/chat_session_dto.dart

/// DTO для сессии чата — точно соответствует JSON-ответу бэкенда.
///
/// Используется только для парсинга данных, НЕ содержит бизнес-логики.
class ChatSessionDto {
  final String id;
  final String? title;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ChatSessionDto({
    required this.id,
    this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Создает DTO из JSON-ответа бэкенда.
  factory ChatSessionDto.fromJson(Map<String, dynamic> json) {
    return ChatSessionDto(
      id: json['id'].toString(), // Бэкенд может вернуть число
      title: json['title'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
