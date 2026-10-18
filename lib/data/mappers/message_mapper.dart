// lib/data/mappers/message_mapper.dart

import '../../core/logger/app_logger.dart';
import '../../domain/models/message.dart';
import '../../domain/models/message_status.dart';
import '../models/message_dto.dart';

/// Маппер для преобразования MessageDto в доменную модель Message.
///
/// Отвечает за:
/// - Преобразование данных из формата бэкенда в формат приложения.
/// - **Перевод `status` (String) → `MessageStatus` (enum).**
/// - Обеспечение целостности данных.
class MessageMapper {
  /// Преобразует DTO в доменную модель.
  ///
  /// **Что делаем:**
  /// 1. Парсим `status` (строка → enum). Незнакомое значение —
  ///    fallback в `MessageStatus.ok` + warning в логе.
  /// 2. Пробрасываем `error` из DTO в `errorMessage` домена
  ///    (переименование «на границе»: DTO — зеркало JSON, домен —
  ///    смысловое имя).
  /// 3. Остальные поля — как есть.
  static Message toDomain(MessageDto dto) {
    return Message(
      id: dto.id,
      text: dto.text,
      isFromUser: dto.isFromUser,
      timestamp: dto.timestamp,
      agentId: dto.agentId,
      sessionId: dto.sessionId,
      sources: dto.sources,
      feedback: dto.feedback,
      status: _parseStatus(dto.status),
      errorMessage: dto.error,
    );
  }

  // ============================================================
  // ПРИВАТНЫЕ ХЕЛПЕРЫ
  // ============================================================

  /// Превратить строковый статус в [MessageStatus].
  ///
  /// Ожидаемые значения (см. README Agentic RAG, раздел
  /// `GET .../messages`):
  /// - `"ok"` → [MessageStatus.ok];
  /// - `"failed"` → [MessageStatus.failed];
  /// - `"pending"` → [MessageStatus.pending].
  ///
  /// **`null` → `MessageStatus.ok`.** Это **безопасный дефолт**:
  /// `document_chat` **не** присылает `status` (у него своя схема) —
  /// все его сообщения по факту `ok`. Для `agentic_rag` `status`
  /// **всегда** приходит, но и здесь `null` не сломает.
  ///
  /// **Незнакомое значение → `MessageStatus.ok` + warning.** Возможно,
  /// бекендер добавил новый статус (например, `"cancelled"`) — мы
  /// **не** падаем и **не** теряем сообщение, но **сигналим** в лог.
  /// Если такое начнёт повторяться — увидим и добавим case.
  static MessageStatus _parseStatus(String? raw) {
    switch (raw) {
      case 'ok':
        return MessageStatus.ok;
      case 'failed':
        return MessageStatus.failed;
      case 'pending':
        return MessageStatus.pending;
      case null:
        // Сервер не прислал status — это нормально для document_chat
        // и безопасно для agentic_rag.
        return MessageStatus.ok;
      default:
        // Незнакомый статус — логируем, но не роняем.
        AppLogger.warning(
          'MessageMapper: незнакомый status "$raw". '
          'Ожидались: ok, failed, pending. Использую "ok".',
        );
        return MessageStatus.ok;
    }
  }
}
