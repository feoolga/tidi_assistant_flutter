// lib/models/agent.dart

class Agent {
  final String id;
  final String name;
  final String? description;
  final List<String>? capabilities;
  final bool? routable;
  final String? transport;

  const Agent({
    required this.id,
    required this.name,
    this.description,
    this.capabilities,
    this.routable,
    this.transport,
  });

  // ============================================================
  // СТАРЫЙ ФОРМАТ (для обратной совместимости)
  // ============================================================

  factory Agent.fromJson(Map<String, dynamic> json) {
    // Проверяем, в каком формате пришли данные
    // Новый формат OpenAI: {"id": "...", "object": "model", ...}
    // Старый формат: {"id": "...", "name": "...", ...}
    
    final String id = json['id'] as String;
    
    // В новом формате имя может быть в поле 'id' или 'name'
    String name;
    if (json.containsKey('name') && json['name'] != null) {
      name = json['name'] as String;
    } else {
      name = id; // Если имени нет — используем ID
    }
    
    return Agent(
      id: id,
      name: name,
      description: json['description'] as String?,
      capabilities: (json['capabilities'] as List?)?.cast<String>(),
      routable: json['routable'] as bool? ?? true,
      transport: json['transport'] as String?,
    );
  }

  // ============================================================
  // ПРЕОБРАЗОВАНИЕ В JSON
  // ============================================================

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (description != null) 'description': description,
      if (capabilities != null) 'capabilities': capabilities,
      if (routable != null) 'routable': routable,
      if (transport != null) 'transport': transport,
    };
  }

  bool hasCapability(String capability) {
    return capabilities?.contains(capability) ?? false;
  }
}