// lib/data/mappers/message_mapper.dart

import '../../core/logger/app_logger.dart';
import '../../domain/models/message.dart';
import '../../domain/models/message_status.dart';
import '../models/message_dto.dart';

/// Маппер `MessageDto` → `Message`.
///
/// **Ответственность:**
/// - превратить `status` (строка) в `MessageStatus` (enum);
/// - подставить `DateTime.now()` для `timestamp`, если сервер
///   не прислал дату (или прислал невалидную);
/// - переименовать `error` → `errorMessage` (граница слоёв:
///   в DTO — зеркало JSON, в домене — смысловое имя).
///
/// **Что НЕ делает:**
/// - не парсит JSON (это `MessageDto.fromJson`);
/// - не ходит в сеть (это `ChatRepository`);
/// - не решает, что показать пользователю (это UI).
class MessageMapper {
  /// Преобразовать DTO в доменную модель.
  ///
  /// **Про `timestamp`.** В DTO — `DateTime?` (может быть `null`, если
  /// сервер не прислал `created_at` или прислал невалидное). В домене —
  /// **non-null**. Подставляем `DateTime.now()` — осознанный fallback:
  /// лучше показать «сейчас», чем уронить весь список сообщений
  /// из-за одной кривой даты. Альтернатива (`DateTime(0)` = 1970)
  /// пугает пользователя — для чата это плохо.
  ///
  /// **Про `status`.** См. `_parseStatus`. `null` и незнакомые значения
  /// → `MessageStatus.ok` — безопасный дефолт.
  static Message toDomain(MessageDto dto) {
    return Message(
      id: dto.id,
      text: dto.text,
      isFromUser: dto.isFromUser,
      timestamp: dto.timestamp ?? DateTime.now(),
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
  /// Ожидаемые значения: `"ok"`, `"failed"`, `"pending"`.
  ///
  /// **`null` → `MessageStatus.ok`.** Это **безопасный дефолт**:
  /// `document_chat` **не** присылает `status` в истории — все его
  /// сообщения по факту `ok`. Для `agentic_rag` `status` **всегда**
  /// приходит, но и здесь `null` не сломает.
  ///
  /// **Незнакомое значение → `MessageStatus.ok` + warning.** Возможно,
  /// бэкендер добавил новый статус (например, `"cancelled"`) — мы
  /// **не** падаем и **не** теряем сообщение, но **сигналим** в лог.
  /// Если такое начнёт повторяться — увидим и добавим `case`.
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
