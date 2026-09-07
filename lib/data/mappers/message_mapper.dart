// lib/data/mappers/message_mapper.dart

import '../../domain/models/message.dart';
import '../models/message_dto.dart';

/// Маппер для преобразования MessageDto в доменную модель Message.
///
/// Отвечает за:
/// - Преобразование данных из формата бэкенда в формат приложения
/// - Обеспечение целостности данных
class MessageMapper {
  /// Преобразует DTO в доменную модель.
  static Message toDomain(MessageDto dto) {
    return Message(
      id: dto.id,
      text: dto.text,
      isFromUser: dto.isFromUser,
      timestamp: dto.timestamp,
      agentId: dto.agentId,
      sessionId: dto.sessionId,
      sources: dto.sources,
      feedback: dto.feedback,
    );
  }
}
