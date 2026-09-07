// lib/data/mappers/chat_session_mapper.dart

import '../../domain/models/chat_session.dart';
import '../models/chat_session_dto.dart';

/// Маппер для преобразования ChatSessionDto в доменную модель ChatSession.
///
/// Отвечает за:
/// - Преобразование данных из формата бэкенда в формат приложения
/// - Добавление контекстной информации (agentId)
/// - Обеспечение целостности данных
class ChatSessionMapper {
  /// Преобразует DTO в доменную модель.
  ///
  /// [agentId] — ID агента, к которому относится сессия (берется из контекста запроса)
  static ChatSession toDomain(ChatSessionDto dto, String agentId) {
    return ChatSession(
      id: dto.id,
      agentId: agentId,
      title: dto.title,
      createdAt: dto.createdAt,
      updatedAt: dto.updatedAt,
    );
  }
}
