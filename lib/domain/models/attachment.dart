// lib/domain/models/attachment.dart

import '../../core/utils/copy_with_marker.dart';

/// Тип вложения — используется UI для выбора способа отображения.
///
/// - [image] — показываем миниатюру картинки;
/// - [pdf] — показываем иконку + имя файла;
/// - [other] — fallback, на случай неожиданного MIME (например, DOCX).
enum AttachmentKind { image, pdf, other }

/// Состояние вложения в процессе загрузки/обработки.
///
/// Жизненный цикл:
///   pending → uploading → processing → done
///                                   ↘ failed
///
/// - [pending]    — файл выбран локально, но загрузка ещё не началась;
/// - [uploading]  — байты отправляются на сервер (multipart);
/// - [processing] — сервер обрабатывает файл (MinerU разбирает PDF);
/// - [done]       — файл готов к использованию, есть [Attachment.remoteId];
/// - [failed]     — загрузка или обработка упала, есть [Attachment.errorMessage].
enum AttachmentStatus { pending, uploading, processing, done, failed }

/// Доменная модель вложения.
///
/// Используется для связи файла (PDF/картинки) с сообщением пользователя.
///
/// Модель иммутабельна: все изменения состояния происходят через [copyWith].
/// Она не знает про HTTP, JSON и UI — только о том, что такое вложение
/// и как с ним логически работать.
///
/// Жизненный цикл типичного вложения:
/// 1. `Attachment.fromLocalFile(...)` — сразу после выбора файла
///    пользователем, `status = pending`;
/// 2. `copyWith(status: uploading)` — перед отправкой multipart;
/// 3. `copyWith(status: processing, remoteId: 'file-...')` — сервер принял
///    байты, но ещё не закончил разбор (MinerU);
/// 4. `copyWith(status: done)` — файл готов, `remoteId` можно использовать
///    в `input_file` при отправке сообщения.
///
/// На любой стадии возможен переход в `failed` через
/// `copyWith(status: failed, errorMessage: '...')`.
class Attachment {
  // ============================================================
  // 1. ИДЕНТИФИКАЦИЯ
  // ============================================================

  final String localId;
  final String? remoteId;

  // ============================================================
  // 2. ДАННЫЕ О ФАЙЛЕ
  // ============================================================

  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final String localPath;

  // ============================================================
  // 3. КЛАССИФИКАЦИЯ
  // ============================================================

  final AttachmentKind kind;

  // ============================================================
  // 4. СОСТОЯНИЕ
  // ============================================================

  final AttachmentStatus status;
  final String? errorMessage;
  final double uploadProgress;

  // ============================================================
  // 5. СВЯЗЬ С ЧАТОМ
  // ============================================================

  final String? conversationId;

  // ============================================================
  // 6. КОНСТРУКТОРЫ
  // ============================================================

  const Attachment({
    required this.localId,
    this.remoteId,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.localPath,
    required this.kind,
    this.status = AttachmentStatus.pending,
    this.errorMessage,
    this.uploadProgress = 0.0,
    this.conversationId,
  });

  factory Attachment.fromLocalFile({
    required String localId,
    required String fileName,
    required String mimeType,
    required int sizeBytes,
    required String localPath,
    String? conversationId,
  }) {
    return Attachment(
      localId: localId,
      fileName: fileName,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      localPath: localPath,
      kind: attachmentKindFromMime(mimeType),
      status: AttachmentStatus.pending,
      conversationId: conversationId,
    );
  }

  // ============================================================
  // 7. ВСПОМОГАТЕЛЬНЫЕ ГЕТТЕРЫ
  // ============================================================

  bool get isUploaded => remoteId != null && status == AttachmentStatus.done;

  bool get isFailed => status == AttachmentStatus.failed;

  bool get isInProgress =>
      status == AttachmentStatus.pending ||
      status == AttachmentStatus.uploading ||
      status == AttachmentStatus.processing;

  bool get isImage => kind == AttachmentKind.image;

  bool get isPdf => kind == AttachmentKind.pdf;

  // ============================================================
  // 8. КОПИРОВАНИЕ (immutable-паттерн)
  // ============================================================

  Attachment copyWith({
    String? localId,
    Object? remoteId = copyWithUnset,
    String? fileName,
    String? mimeType,
    int? sizeBytes,
    String? localPath,
    AttachmentKind? kind,
    AttachmentStatus? status,
    Object? errorMessage = copyWithUnset,
    double? uploadProgress,
    Object? conversationId = copyWithUnset,
  }) {
    return Attachment(
      localId: localId ?? this.localId,
      remoteId: isCopyWithUnset(remoteId) ? this.remoteId : remoteId as String?,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      localPath: localPath ?? this.localPath,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      errorMessage: isCopyWithUnset(errorMessage)
          ? this.errorMessage
          : errorMessage as String?,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      conversationId: isCopyWithUnset(conversationId)
          ? this.conversationId
          : conversationId as String?,
    );
  }

  // ============================================================
  // 9. ОТЛАДКА
  // ============================================================

  @override
  String toString() {
    return 'Attachment(localId: $localId, kind: $kind, status: $status, '
        'sizeBytes: $sizeBytes, fileName: "$fileName")';
  }
}

// ============================================================
// ХЕЛПЕРЫ: MIME и kind
// ============================================================

/// Определить MIME-тип по имени файла.
///
/// Публичная функция (не метод класса), потому что используется:
/// - в `AttachmentMapper` — при переводе ответа сервера в домен;
/// - в `ChatNotifier.addAttachment` — при валидации локального файла
///   до загрузки (по `AppConfig.allowedMimeTypes`).
///
/// Смотрим только на расширение: файл либо уже на сервере (маппер),
/// либо только что выбран пользователем (валидация). Оба раза расширение
/// — единственный доступный источник информации о типе.
///
/// Если расширение неизвестно — возвращаем `application/octet-stream`.
/// Валидация по `AppConfig.allowedMimeTypes` отсеет такие файлы
/// до загрузки, так что до сервера они не дойдут.
String attachmentMimeTypeFromFilename(String filename) {
  final lower = filename.toLowerCase();

  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.jpg')) return 'image/jpeg';
  if (lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';

  return 'application/octet-stream';
}

/// Определить [AttachmentKind] по MIME-типу.
///
/// Публичная функция (не метод класса), потому что используется также
/// в `AttachmentMapper` — при переводе ответа сервера в доменную модель.
/// Один источник правды о том, как MIME превращается в [AttachmentKind].
///
/// Возвращает [AttachmentKind.other], если MIME неизвестен —
/// UI покажет нейтральную иконку файла.
AttachmentKind attachmentKindFromMime(String mimeType) {
  if (mimeType.startsWith('image/')) return AttachmentKind.image;
  if (mimeType == 'application/pdf') return AttachmentKind.pdf;
  return AttachmentKind.other;
}
