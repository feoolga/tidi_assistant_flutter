// lib/models/chat_session.dart

/// Модель сессии чата — соответствует ответу GET /agents/{agent_id}/sessions
class ChatSession {
  /// ID сессии (число от бэкенда, храним как String)
  final String id;

  /// ID агента, к которому относится сессия
  final String agentId;

  /// Название сессии (может быть null)
  final String? title;

  /// Дата создания
  final DateTime createdAt;

  /// Дата последнего обновления
  final DateTime updatedAt;

  const ChatSession({
    required this.id,
    required this.agentId,
    this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Отображаемое название (если title нет — берем дату)
  String get displayTitle {
    if (title != null && title!.isNotEmpty) {
      return title!;
    }
    return 'Чат от ${_formatDate(createdAt)}';
  }

  /// Создание сессии из JSON (с бэкенда)
  factory ChatSession.fromJson(Map<String, dynamic> json, String agentId) {
    return ChatSession(
      id: json['id'].toString(), // Бэкенд может вернуть число
      agentId: agentId,
      title: json['title'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Форматирование даты для отображения
  static String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }
}
