// lib/data/models/message_dto.dart

import '../../core/utils/json_parsing.dart';
import '../../domain/models/message_source.dart';

/// DTO сообщения — точное отражение JSON от бэкенда.
///
/// Источник формата — `GET /v1/platform/conversations/{id}/messages`.
/// Поля соответствуют ответу `document_chat` и `agentic_rag`
/// (у них немного разные схемы, DTO поддерживает обе).
///
/// **Ответственность.** Только парсинг JSON. Никакой бизнес-логики.
/// Превращение в доменную `Message` — задача `MessageMapper`.
class MessageDto {
  // ============================================================
  // 1. ПОЛЯ
  // ============================================================

  final String id;
  final String text;
  final bool isFromUser;

  /// Время создания сообщения.
  ///
  /// **`null`, если сервер не прислал `created_at` или прислал
  /// невалидное значение.** В домене `Message.timestamp` — non-null;
  /// маппер подставит `DateTime.now()` для отображения. Это осознанный
  /// fallback: лучше показать «сейчас», чем уронить весь список сообщений
  /// из-за одной кривой даты.
  final DateTime? timestamp;

  final List<MessageSource>? sources;
  final Map<String, dynamic>? feedback;
  final String? agentId;
  final String? sessionId;

  /// Статус сообщения из поля `status`.
  ///
  /// Возможные значения: `"ok"`, `"failed"`, `"pending"`.
  /// `null` — если поле не пришло (например, `document_chat`
  /// не присылает `status` в истории).
  ///
  /// **`String?`, а не enum.** DTO — зеркало JSON. Превращение
  /// в `MessageStatus` — задача `MessageMapper`.
  final String? status;

  /// Текст ошибки из поля `error` (например, `"client_disconnected"`).
  /// `null` — если ошибки нет.
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
  // 2. ПАРСИНГ
  // ============================================================

  /// Создать DTO из JSON-ответа бэкенда.
  ///
  /// Поддерживает разные форматы (на случай эволюции API):
  /// - `role` / `isFromUser` — автор сообщения;
  /// - `content` / `text` — текст;
  /// - `created_at` / `timestamp` — время.
  ///
  /// **Про `id`.** Если сервер не прислал `id` — генерируем временный
  /// (по `millisecondsSinceEpoch`). Это компромисс: без `id`
  /// сообщение нельзя ни отредактировать, ни удалить, но **показывать**
  /// в истории можно. TODO: использовать генератор из `message_id.dart`,
  /// когда разберёмся с его контрактом.
  ///
  /// **Про `agentId` / `sessionId`.** В JSON они, вероятно, приходят
  /// как `agent_id` / `session_id` (snake_case — как и все остальные
  /// поля). Сейчас читаем как `agentId` / `sessionId`. При интеграции
  /// с реальным бэкендом — проверить и поправить. Если поле не пришло —
  /// `null`, это нормально.
  factory MessageDto.fromJson(Map<String, dynamic> json) {
    // --- Автор ---
    final bool isFromUser;
    if (json.containsKey('role')) {
      isFromUser = json['role'] == 'user';
    } else if (json.containsKey('isFromUser')) {
      isFromUser = json['isFromUser'] as bool? ?? false;
    } else {
      isFromUser = false;
    }

    // --- Текст ---
    final String text =
        json['content'] as String? ?? json['text'] as String? ?? '';

    // --- Время ---
    //
    // `parseDateOrNull` возвращает `null` при `null`/числе/невалидной
    // ISO-строке. Это устойчиво: одно кривое сообщение не роняет
    // весь список. Fallback на `DateTime.now()` — в `MessageMapper`,
    // не здесь (DTO — зеркало JSON, не должен подставлять «сейчас»).
    final DateTime? timestamp = parseDateOrNull(
      json['created_at'] ?? json['timestamp'],
    );

    // --- ID ---
    final String id =
        json['id']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();

    // --- Sources ---
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
      status: json['status'] as String?,
      error: json['error'] as String?,
    );
  }

  /// Парсит `sources` из JSON — поддерживает два формата.
  ///
  /// - **Формат A** (`document_chat`): массив строк — только имена файлов.
  /// - **Формат B** (`agentic_rag`): массив объектов с метаданными
  ///   (`order`, `chunk_id`, `document_id`, `chunk_index`, `filename`).
  ///
  /// Возвращает `null`, если поле отсутствует или не массив.
  static List<MessageSource>? _parseSources(dynamic value) {
    if (value is! List) return null;
    if (value.isEmpty) return const [];

    final result = <MessageSource>[];
    for (final item in value) {
      if (item is String) {
        result.add(MessageSource.fromFilename(item));
      } else if (item is Map<String, dynamic>) {
        final filename = item['filename'] as String?;
        if (filename == null || filename.isEmpty) continue;
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
    }
    return result;
  }

  // ============================================================
  // 3. ОТЛАДКА
  // ============================================================

  @override
  String toString() {
    return 'MessageDto(id: $id, isFromUser: $isFromUser, '
        'textLength: ${text.length}, timestamp: $timestamp, '
        'sources: $sources, status: $status, error: $error)';
  }
}
