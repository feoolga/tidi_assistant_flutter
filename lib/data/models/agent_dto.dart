// lib/data/models/agent_dto.dart

/// DTO для агента — точно соответствует JSON-ответу бэкенда.
///
/// Используется только для парсинга данных, НЕ содержит бизнес-логики.
class AgentDto {
  final String id;
  final String? name;
  final String? description;
  final List<String>? capabilities;
  final bool? routable;
  final String? transport;

  const AgentDto({
    required this.id,
    this.name,
    this.description,
    this.capabilities,
    this.routable,
    this.transport,
  });

  /// Создает DTO из JSON-ответа бэкенда
  ///
  /// Поддерживает оба формата:
  /// - Новый формат OpenAI: {"id": "...", "object": "model", ...}
  /// - Старый формат: {"id": "...", "name": "...", ...}
  factory AgentDto.fromJson(Map<String, dynamic> json) {
    final String id = json['id'] as String;

    // В новом формате имя может быть в поле 'id' или 'name'
    String? name;
    if (json.containsKey('name') && json['name'] != null) {
      name = json['name'] as String;
    }
    // Если name нет — оставляем null (маппер потом возьмет id)

    return AgentDto(
      id: id,
      name: name,
      description: json['description'] as String?,
      capabilities: (json['capabilities'] as List?)?.cast<String>(),
      routable: json['routable'] as bool? ?? true,
      transport: json['transport'] as String?,
    );
  }
}
