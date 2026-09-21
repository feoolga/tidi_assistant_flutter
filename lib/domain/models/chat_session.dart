// lib/domain/models/chat_session.dart

import '../../core/utils/date_format.dart';

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
    final t = title;
    if (t != null && t.isNotEmpty) {
      return t;
    }
    return 'Чат от ${formatShortDate(createdAt)}';
  }
}
