// lib/data/models/chat_response_dto.dart

/// DTO (Data Transfer Object) для ответа от сервера в формате Responses API.
///
/// Собирается из SSE-событий:
/// - response.created → id, model, conversation_id
/// - response.output_text.delta → content (по кусочкам)
/// - response.completed → финальное состояние
///
/// Эта модель используется ТОЛЬКО для работы с данными.
/// Она не знает про UI и про бизнес-логику.
class ChatResponseDto {
  // ============================================================
  // 1. ПОЛЯ
  // ============================================================

  /// ID ответа (например, "resp_1e6b7ee7-..." или "chatcmpl-...")
  final String id;

  /// Модель/агент, который ответил (например, "epoz" или "auto")
  final String model;

  /// ID чата (conversation_id), если был передан в запросе
  final String? conversationId;

  /// Полный текст ответа (собранный из всех токенов)
  final String content;

  // ============================================================
  // 2. КОНСТРУКТОРЫ
  // ============================================================

  const ChatResponseDto({
    required this.id,
    required this.model,
    this.conversationId,
    required this.content,
  });

  /// Пустой DTO для начала сборки из SSE-потока.
  factory ChatResponseDto.empty() {
    return const ChatResponseDto(
      id: '',
      model: 'auto',
      conversationId: null,
      content: '',
    );
  }

  /// Создаёт копию с обновлёнными полями.
  /// Используется для постепенной сборки ответа из событий.
  ChatResponseDto copyWith({
    String? id,
    String? model,
    String? conversationId,
    String? content,
  }) {
    return ChatResponseDto(
      id: id ?? this.id,
      model: model ?? this.model,
      conversationId: conversationId ?? this.conversationId,
      content: content ?? this.content,
    );
  }

  // ============================================================
  // 3. ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ
  // ============================================================

  @override
  String toString() {
    return 'ChatResponseDto(id: $id, model: $model, conversationId: $conversationId, contentLength: ${content.length})';
  }
}
