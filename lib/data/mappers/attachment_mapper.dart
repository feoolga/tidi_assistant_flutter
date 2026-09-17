// lib/data/mappers/attachment_mapper.dart

import '../../domain/models/attachment.dart';
import '../models/attachment_dto.dart';

/// Маппер для преобразования [AttachmentDto] в доменную модель [Attachment].
///
/// Отвечает за:
/// - перевод Unix-времени (`created_at`) в `DateTime` (если понадобится);
/// - перевод `processing_status` (String) в [AttachmentStatus] (enum);
/// - определение `mimeType` по имени файла (в ответе сервера MIME не приходит);
/// - определение [AttachmentKind] по MIME — через общий хелпер
///   [attachmentKindFromMime] из домена;
/// - подготовку `errorMessage` — только если файл реально упал;
/// - установку `uploadProgress = 1.0` (раз сервер ответил — файл загружен).
///
/// ВАЖНО: локальные поля ([Attachment.localId] и [Attachment.localPath])
/// не приходят с сервера — их должен передать вызывающий код
/// ([AttachmentRepository]), у которого есть локальный `Attachment`
/// до момента загрузки. Маппер не генерирует их сам: `localId`
/// должен совпадать с тем, что уже используется в UI.
class AttachmentMapper {
  /// Преобразует DTO в доменную модель.
  ///
  /// [localId] — тот же `localId`, что был присвоен вложению при выборе
  /// файла пользователем. Сохраняем его, чтобы UI не потерял связь
  /// между «до загрузки» и «после загрузки».
  ///
  /// [localPath] — путь к файлу на устройстве. Нужен для превью.
  static Attachment toDomain(
    AttachmentDto dto, {
    required String localId,
    required String localPath,
  }) {
    // 1. Определяем MIME по имени файла.
    //    В ответе сервера MIME-тип не приходит — только filename.
    final mimeType = attachmentMimeTypeFromFilename(dto.filename);

    // 2. Определяем доменный статус — из processing_status,
    //    а НЕ из status. См. README бэкендера: status — сведённое
    //    OpenAI-значение (uploaded/processed/error), processing_status —
    //    точное внутреннее (pending/processing/done/failed).
    final status = _statusFromProcessingStatus(dto.processingStatus);

    // 3. errorMessage заполняем ТОЛЬКО если файл упал.
    //    Если statusDetails есть, но статус done — значит, сервер
    //    прислал «повисший» текст ошибки, и мы его игнорируем:
    //    домен должен быть консистентным, errorMessage != null → ошибка.
    final errorMessage = status == AttachmentStatus.failed
        ? dto.statusDetails
        : null;

    return Attachment(
      localId: localId,
      remoteId: dto.id,
      fileName: dto.filename,
      mimeType: mimeType,
      sizeBytes: dto.bytes,
      localPath: localPath,
      kind: attachmentKindFromMime(mimeType),
      status: status,
      errorMessage: errorMessage,
      // Файл уже загружен — сервер ответил. Значит, прогресс = 100%.
      uploadProgress: 1.0,
      conversationId: dto.conversationId,
    );
  }

  // ============================================================
  // ПРИВАТНЫЕ ХЕЛПЕРЫ
  // ============================================================

  /// Перевести `processing_status` (строка от сервера) в [AttachmentStatus].
  ///
  /// Соответствие — по README бэкендера:
  /// - `pending`    → [AttachmentStatus.pending]
  /// - `processing` → [AttachmentStatus.processing]
  /// - `done`       → [AttachmentStatus.done]
  /// - `failed`     → [AttachmentStatus.failed]
  ///
  /// `uploading` от сервера никогда не приходит — это чисто клиентский
  /// статус (байты летят на сервер). Если сервер ответил — значит,
  /// uploading уже пройден.
  ///
  /// Неизвестное значение → [AttachmentStatus.failed] — безопасный дефолт:
  /// лучше показать ошибку, чем притвориться, что файл готов.
  static AttachmentStatus _statusFromProcessingStatus(String value) {
    switch (value) {
      case 'pending':
        return AttachmentStatus.pending;
      case 'processing':
        return AttachmentStatus.processing;
      case 'done':
        return AttachmentStatus.done;
      case 'failed':
        return AttachmentStatus.failed;
      default:
        // Неизвестный статус — считаем failed. Молчать нельзя:
        // файл в неизвестном состоянии, лучше явная ошибка в UI.
        return AttachmentStatus.failed;
    }
  }
}
