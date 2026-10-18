// lib/data/models/message_dto.dart

import '../../domain/models/message_source.dart';

/// DTO для сообщения — точно соответствует JSON-ответу бэкенда.
///
/// Источник формата: README `document_chat`, раздел
/// `GET /v1/platform/conversations/{id}/messages`:
///
/// ```json
/// {
///   "id": "9c858901-...",
///   "role": "user" | "assistant",
///   "content": "...",
///   "sources": ["накладная.pdf"],
///   "created_at": "2026-08-03T12:00:00",
///   "feedback": {"vote": 1, "comment": "точно"} | null
/// }
/// ```
///
/// Используется только для парсинга данных, НЕ содержит бизнес-логики.
class MessageDto {
  // 1. ПОЛЯ
  final String id;
  final String text;
  final bool isFromUser;
  final DateTime timestamp;
  final List<MessageSource>? sources;
  final Map<String, dynamic>? feedback;
  final String? agentId;
  final String? sessionId;

  /// Статус сообщения — из поля `status` ответа сервера.
  ///
  /// Возможные значения (по README Agentic RAG и реальному ответу сервера):
  /// - `"ok"` — сообщение успешно обработано;
  /// - `"failed"` — генерация упала (например, `client_disconnected`
  ///   при обрыве SSE-стрима);
  /// - `"pending"` — сообщение ещё обрабатывается (обычно не приходит
  ///   в `GET .../messages`, но на всякий случай парсим как есть).
  ///
  /// `null` — если поле не пришло (например, `document_chat` может
  /// не присылать `status` в истории — у него своя схема).
  ///
  /// **Почему `String?`, а не enum.** DTO — зеркало JSON. Превращение
  /// в доменный enum — работа маппера (D2), не DTO. DTO **не решает**,
  /// что считать «успехом», — он просто **хранит** то, что пришло.
  final String? status;

  /// Текст ошибки — из поля `error` ответа сервера.
  ///
  /// Например, `"client_disconnected"` — сервер прервал генерацию,
  /// потому что клиент отвалился. Или `null`, если ошибки нет.
  ///
  /// `null` — если поля нет или оно `null`.
  final String? error;

  const MessageDto({
    required this.id,
    required this.text,
    required this.isFromUser,
    required this.timestamp,
    this.sources,
    this.feedback,
    this.agentId,
    this.sessionId,
    this.status,
    this.error,
  });

  // ============================================================
  // 3. ПАРСИНГ
  // ============================================================

  /// Создаёт DTO из JSON-ответа бэкенда.
  ///
  /// Поддерживает разные форматы (на случай эволюции API):
  /// - `role` / `isFromUser` — автор сообщения;
  /// - `content` / `text` — текст сообщения;
  /// - `created_at` / `timestamp` — время создания.
  ///
  /// Обязательные поля (в новых версиях API): `id`, `role`, `content`,
  /// `created_at`. Если чего-то не хватает — используем fallback.
  factory MessageDto.fromJson(Map<String, dynamic> json) {
    // --- Определяем автора ---
    // Сначала смотрим `role` (актуальный формат README).
    // Fallback на `isFromUser` — на случай старого API.
    final bool isFromUser;
    if (json.containsKey('role')) {
      isFromUser = json['role'] == 'user';
    } else if (json.containsKey('isFromUser')) {
      isFromUser = json['isFromUser'] as bool? ?? false;
    } else {
      isFromUser = false;
    }

    // --- Получаем текст ---
    // `content` — актуальный формат. Fallback на `text` — старый.
    final String text =
        json['content'] as String? ?? json['text'] as String? ?? '';

    // --- Получаем время ---
    // `created_at` — актуальный формат. Fallback на `timestamp` — старый.
    final String timestampStr =
        json['created_at'] as String? ?? json['timestamp'] as String? ?? '';
    final DateTime timestamp = timestampStr.isNotEmpty
        ? DateTime.parse(timestampStr)
        : DateTime.now();

    // --- Получаем ID ---
    // ID может прийти числом (в старом API) — приводим к строке.
    // Если ID нет — генерируем временный (для отображения в UI).
    final String id =
        json['id']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();

    // --- Sources: два формата ---
    //
    // Формат A (`document_chat`): `["file.pdf", "другой.pdf (частично)"]` —
    // массив строк, только имена.
    //
    // Формат B (`agentic_rag`): `[{"order": 1, "chunk_id": "...",
    // "document_id": "...", "chunk_index": 0, "filename": "..."}]` —
    // массив объектов с метаданными.
    //
    // Приводим к единому `List<MessageSource>`. Пустой список `[]`
    // превращается в пустой `List<MessageSource>` — не `null`.
    final List<MessageSource>? sources = _parseSources(json['sources']);

    return MessageDto(
      id: id,
      text: text,
      isFromUser: isFromUser,
      timestamp: timestamp,
      sources: sources,
      feedback: json['feedback'] as Map<String, dynamic>?,
      agentId: json['agentId'] as String?,
      sessionId: json['sessionId'] as String?,
      // --- НОВОЕ ---
      status: json['status'] as String?,
      error: json['error'] as String?,
    );
  }

  /// Парсит sources из JSON — поддерживает два формата.
  ///
  /// Возвращает `null`, если поле отсутствует или не массив.
  /// Возвращает пустой список, если массив пуст.
  static List<MessageSource>? _parseSources(dynamic value) {
    if (value is! List) return null;
    if (value.isEmpty) return const [];

    final result = <MessageSource>[];
    for (final item in value) {
      if (item is String) {
        // Формат A (`document_chat`): просто имя.
        result.add(MessageSource.fromFilename(item));
      } else if (item is Map<String, dynamic>) {
        // Формат B (`agentic_rag`): объект с полями.
        final filename = item['filename'] as String?;
        if (filename == null || filename.isEmpty) {
          // Без filename source бессмысленный — пропускаем.
          continue;
        }
        result.add(
          MessageSource(
            order: item['order'] as int?,
            chunkId: item['chunk_id'] as String?,
            documentId: item['document_id'] as String?,
            chunkIndex: item['chunk_index'] as int?,
            filename: filename,
          ),
        );
      }
      // Игнорируем всё остальное (числа, булевы, вложенные массивы).
    }
    return result;
  }

  // ============================================================
  // 4. ОТЛАДКА
  // ============================================================

  @override
  String toString() {
    return 'MessageDto(id: $id, isFromUser: $isFromUser, '
        'textLength: ${text.length}, sources: $sources, '
        'status: $status, error: $error)';
  }
}
