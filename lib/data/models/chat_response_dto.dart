// lib/data/models/chat_response_dto.dart

/// DTO (Data Transfer Object) для ответа от сервера.
///
/// Эта модель используется ТОЛЬКО для работы с данными.
/// Она не знает про UI и про бизнес-логику.
///
/// Откуда приходит: из SSE-потока от Master-роутера.
/// Куда идет: в Repository, где преобразуется в Message для UI.
class ChatResponseDto {
  // ============================================================
  // 1. ПОЛЯ
  // ============================================================

  /// ID ответа (например, "chatcmpl-1e6b7ee7-...")
  /// Приходит от сервера в поле "id"
  final String id;

  /// Модель/агент, который ответил (например, "epoz" или "auto")
  /// Приходит от сервера в поле "model"
  final String model;

  /// ID чата (conversation_id), если был передан в запросе
  /// Приходит от сервера в поле "conversation_id"
  final String? conversationId;

  /// Полный текст ответа (собранный из всех токенов)
  final String content;

  // ============================================================
  // 2. КОНСТРУКТОР
  // ============================================================

  const ChatResponseDto({
    required this.id,
    required this.model,
    this.conversationId,
    required this.content,
  });

  // ============================================================
  // 3. ФАБРИЧНЫЙ МЕТОД (пока заглушка)
  // ============================================================

  /// Создает DTO из JSON-объекта, полученного из SSE-потока.
  ///
  /// ВНИМАНИЕ! Этот метод пока НЕ ПОЛНЫЙ.
  /// Он будет использоваться в Repository для парсинга каждого чанка.
  ///
  /// Сейчас мы просто создаем структуру.
  /// Полную реализацию напишем на следующем шаге.
  factory ChatResponseDto.fromJson(Map<String, dynamic> json) {
    return ChatResponseDto(
      id: json['id']?.toString() ?? '',
      model: json['model']?.toString() ?? 'auto',
      conversationId: json['conversation_id']?.toString(),
      content: '', // Пока пусто, будем собирать из токенов
    );
  }

  // ============================================================
  // 4. ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ
  // ============================================================

  @override
  String toString() {
    return 'ChatResponseDto(id: $id, model: $model, conversationId: $conversationId, contentLength: ${content.length})';
  }
}
