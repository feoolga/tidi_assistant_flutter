// lib/models/agent.dart

class Agent {
  final String id;
  final String name;

  /// Описание агента (используется для роутинга)
  final String? description;

  /// Список умений агента
  final List<String>? capabilities;

  /// Можно ли выбрать автоматически
  final bool? routable;

  /// Тип транспорта: "contract", "external", "ocr", "cognitum"
  final String? transport;

  const Agent({
    required this.id,
    required this.name,
    this.description,
    this.capabilities,
    this.routable,
    this.transport,
  });

  /// Создание агента из JSON (с бэкенда)
  factory Agent.fromJson(Map<String, dynamic> json) {
    return Agent(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      capabilities: (json['capabilities'] as List?)?.cast<String>(),
      routable: json['routable'] as bool?,
      transport: json['transport'] as String?,
    );
  }

  /// Вспомогательный метод: проверяет, умеет ли агент что-то
  bool hasCapability(String capability) {
    return capabilities?.contains(capability) ?? false;
  }
}
