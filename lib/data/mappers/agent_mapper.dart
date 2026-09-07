// lib/data/mappers/agent_mapper.dart

import '../../domain/models/agent.dart';
import '../models/agent_dto.dart';

/// Маппер для преобразования AgentDto в доменную модель Agent.
///
/// Отвечает за:
/// - Преобразование данных из формата бэкенда в формат приложения
/// - Применение бизнес-правил (например, если нет имени — использовать ID)
/// - Обеспечение целостности данных
class AgentMapper {
  /// Преобразует DTO в доменную модель.
  static Agent toDomain(AgentDto dto) {
    return Agent(
      id: dto.id,
      // Если имя не пришло — используем ID
      name: dto.name ?? dto.id,
      description: dto.description,
      capabilities: dto.capabilities ?? [], // null → пустой список
      routable: dto.routable ?? true, // если не указано — разрешаем роутинг
      transport: dto.transport,
    );
  }
}
