// lib/models/agent.dart

/// Модель агента - представляет ИИ-ассистента на бэкенде
class Agent {
  /// Уникальный идентификатор агента (например, "epoz", "techdocs")
  final String id;
  
  /// Человекочитаемое имя агента (например, "ЕПоЗ", "Техническая документация")
  final String name;
  
  /// Описание агента (для будущего использования)
  final String? description;

  const Agent({
    required this.id,
    required this.name,
    this.description,
  });

  /// Создание агента из JSON (с бэкенда)
  factory Agent.fromJson(Map<String, dynamic> json) {
    return Agent(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
    );
  }

  /// Преобразование агента в JSON (для отправки на бэкенд)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (description != null) 'description': description,
    };
  }

  /// Статический маппинг ID агента в человеческое имя (для быстрого доступа)
  static const Map<String, String> defaultNames = {
    'epoz': 'ЕПоЗ',
    'tech_rag': 'Техническая документация',
    'ocr': 'OCR',
    'chat': 'AI Ассистент',
  };

  /// Получить человеческое имя по ID агента
  static String getNameById(String agentId) {
    return defaultNames[agentId] ?? 'AI Ассистент';
  }
}