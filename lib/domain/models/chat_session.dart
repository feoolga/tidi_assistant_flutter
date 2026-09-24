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

  /// Дата создания — `null`, если бэкенд прислал невалидное значение.
  ///
  /// UI должен показывать «дата неизвестна» вместо подстановки
  /// `DateTime.now()` — последнее выглядело бы как реальная дата
  /// и путало пользователя.
  final DateTime? createdAt;

  /// Дата последнего обновления — `null` по той же причине.
  ///
  /// Используется для сортировки в `chatsProvider`: чаты с `null`
  /// уходят **в конец** списка (см. сортировку там).
  final DateTime? updatedAt;

  const ChatSession({
    required this.id,
    required this.agentId,
    this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Отображаемое название.
  ///
  /// Приоритет:
  /// 1. `title`, если задан и непустой;
  /// 2. `'Чат от <дата>'`, если `createdAt` известен;
  /// 3. `'Чат (дата неизвестна)'`, если дата отсутствует.
  ///
  /// Третий случай — **честный** fallback: показываем пользователю,
  /// что дата неизвестна, а не подставляем «сейчас» или «эпоху».
  String get displayTitle {
    final t = title;
    if (t != null && t.isNotEmpty) {
      return t;
    }
    final created = createdAt;
    if (created != null) {
      return 'Чат от ${formatShortDate(created)}';
    }
    return 'Чат (дата неизвестна)';
  }
}
