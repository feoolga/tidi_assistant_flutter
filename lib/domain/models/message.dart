// lib/models/message.dart

/// Модель сообщения в чате.
/// Используется как для сообщений пользователя, так и для ответов AI.
class Message {
  // ============================================================
  // 1. ОСНОВНЫЕ ПОЛЯ (обязательные)
  // ============================================================

  /// Уникальный ID сообщения (генерируется на клиенте или приходит с сервера)
  final String id;

  /// Текст сообщения (собранный из токенов для AI, или введённый пользователем)
  final String text;

  /// true — сообщение от пользователя, false — от AI
  final bool isFromUser;

  /// Время отправки/получения сообщения
  final DateTime timestamp;

  // ============================================================
  // 2. ДОПОЛНИТЕЛЬНЫЕ ПОЛЯ (опциональные)
  // ============================================================

  /// ID агента, который ответил (только для сообщений AI)
  final String? agentId;

  /// ID сессии (чата) на бэкенде (только для сообщений AI)
  final String? sessionId;

  // ============================================================
  // 3. ПОЛЯ ДЛЯ БУДУЩЕГО (пока не используются, но модель готова)
  // ============================================================

  /// Источники, на которые ссылался AI (для RAG-ответов)
  final List<Map<String, dynamic>>? sources;

  /// Оценка/фидбэк от пользователя (лайк/дизлайк)
  final Map<String, dynamic>? feedback;

  // ============================================================
  // 4. КОНСТРУКТОРЫ
  // ============================================================

  /// Основной конструктор — все поля обязательны (кроме опциональных)
  const Message({
    required this.id,
    required this.text,
    required this.isFromUser,
    required this.timestamp,
    this.agentId,
    this.sessionId,
    this.sources,
    this.feedback,
  });

  // ------------------------------------------------------------
  // 4.1. Создание сообщения из JSON (для загрузки истории)
  // ------------------------------------------------------------

  /// Используется, когда мы получаем готовые сообщения от сервера
  /// (например, GET /agents/{agent_id}/sessions/{session_id}/messages)
  factory Message.fromJson(Map<String, dynamic> json) {
    // --- Определяем автора ---
    // Приоритет 1: поле 'role' (приходит от бэкенда)
    // Приоритет 2: поле 'isFromUser' (используется в некоторых API)
    // Приоритет 3: по умолчанию false (сообщение от AI)
    bool isFromUser;
    if (json.containsKey('role')) {
      isFromUser = json['role'] == 'user';
    } else if (json.containsKey('isFromUser')) {
      isFromUser = json['isFromUser'] as bool? ?? false;
    } else {
      isFromUser = false;
    }

    // --- Получаем текст ---
    // Приоритет 1: поле 'content' (стандарт бэкенда)
    // Приоритет 2: поле 'text' (для обратной совместимости)
    final String text =
        json['content'] as String? ?? json['text'] as String? ?? '';

    // --- Получаем время ---
    // Приоритет 1: поле 'created_at' (стандарт бэкенда)
    // Приоритет 2: поле 'timestamp' (для обратной совместимости)
    final String timestampStr =
        json['created_at'] as String? ?? json['timestamp'] as String? ?? '';
    final DateTime timestamp = timestampStr.isNotEmpty
        ? DateTime.parse(timestampStr)
        : DateTime.now();

    // --- Получаем ID ---
    // Если ID нет — генерируем на основе времени
    final String id =
        json['id']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();

    return Message(
      id: id,
      text: text,
      isFromUser: isFromUser,
      timestamp: timestamp,
      agentId: json['agentId'] as String?,
      sessionId: json['sessionId'] as String?,
      sources: json['sources'] as List<Map<String, dynamic>>?,
      feedback: json['feedback'] as Map<String, dynamic>?,
    );
  }

  // ------------------------------------------------------------
  // 4.2. Создание сообщения из SSE-потока (НОВОЕ!)
  // ------------------------------------------------------------

  /// Используется, когда мы собираем сообщение из токенов SSE-потока.
  ///
  /// Пример использования:
  /// ```dart
  /// String fullText = '';
  /// String? messageId;
  /// String? agentId;
  /// String? sessionId;
  ///
  /// // ... собираем токены в fullText ...
  ///
  /// final message = Message.fromStream(
  ///   text: fullText,
  ///   agentId: agentId,
  ///   sessionId: sessionId,
  ///   messageId: messageId,
  /// );
  /// ```
  factory Message.fromStream({
    required String text,
    String? agentId,
    String? sessionId,
    String? messageId,
    bool isFromUser = false, // по умолчанию — сообщение от AI
    List<Map<String, dynamic>>? sources,
  }) {
    return Message(
      id: messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      isFromUser: isFromUser,
      timestamp: DateTime.now(),
      agentId: agentId,
      sessionId: sessionId,
      sources: sources,
    );
  }

  // ------------------------------------------------------------
  // 4.3. Создание сообщения пользователя (УДОБНЫЙ МЕТОД)
  // ------------------------------------------------------------

  /// Удобный конструктор для быстрого создания сообщения пользователя.
  /// Используется в ChatScreen при отправке сообщения.
  factory Message.fromUser({required String text, String? id}) {
    return Message(
      id: id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      isFromUser: true,
      timestamp: DateTime.now(),
    );
  }

  // ------------------------------------------------------------
  // 4.4. Создание сообщения AI (УДОБНЫЙ МЕТОД)
  // ------------------------------------------------------------

  /// Удобный конструктор для быстрого создания ответа AI.
  factory Message.fromAI({
    required String text,
    String? id,
    String? agentId,
    String? sessionId,
    List<Map<String, dynamic>>? sources,
  }) {
    return Message(
      id: id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      isFromUser: false,
      timestamp: DateTime.now(),
      agentId: agentId,
      sessionId: sessionId,
      sources: sources,
    );
  }

  // ============================================================
  // 5. СЕРИАЛИЗАЦИЯ (преобразование обратно в JSON)
  // ============================================================

  /// Преобразует сообщение в JSON для отправки на бэкенд
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'isFromUser': isFromUser,
      'timestamp': timestamp.toIso8601String(),
      if (agentId != null) 'agentId': agentId,
      if (sessionId != null) 'sessionId': sessionId,
      if (sources != null) 'sources': sources,
      if (feedback != null) 'feedback': feedback,
    };
  }

  // ============================================================
  // 6. ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ
  // ============================================================

  /// Создаёт копию сообщения с изменёнными полями (immutable подход)
  Message copyWith({
    String? id,
    String? text,
    bool? isFromUser,
    DateTime? timestamp,
    String? agentId,
    String? sessionId,
    List<Map<String, dynamic>>? sources,
    Map<String, dynamic>? feedback,
  }) {
    return Message(
      id: id ?? this.id,
      text: text ?? this.text,
      isFromUser: isFromUser ?? this.isFromUser,
      timestamp: timestamp ?? this.timestamp,
      agentId: agentId ?? this.agentId,
      sessionId: sessionId ?? this.sessionId,
      sources: sources ?? this.sources,
      feedback: feedback ?? this.feedback,
    );
  }

  // ============================================================
  // 7. ОТЛАДКА
  // ============================================================

  @override
  String toString() {
    final preview = text.length > 20 ? '${text.substring(0, 20)}...' : text;
    return 'Message(id: $id, text: "$preview", isFromUser: $isFromUser, agentId: $agentId, sessionId: $sessionId)';
  }
}
