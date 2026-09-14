// lib/domain/models/attachment.dart

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

  /// Локальный ID — генерируется на клиенте сразу при выборе файла.
  ///
  /// Нужен, чтобы UI мог отслеживать конкретное вложение до того,
  /// как сервер присвоит свой ID. После загрузки сохраняется: UI уже
  /// мог запомнить его для анимаций/отслеживания.
  final String localId;

  /// ID файла на сервере (`file-<uuid>`).
  ///
  /// `null`, пока загрузка не прошла успешно.
  /// Появляется в ответе `POST /v1/files`.
  final String? remoteId;

  // ============================================================
  // 2. ДАННЫЕ О ФАЙЛЕ
  // ============================================================

  /// Имя файла как его видит пользователь («накладная.pdf»).
  final String fileName;

  /// MIME-тип (`application/pdf`, `image/jpeg`, ...).
  final String mimeType;

  /// Размер файла в байтах.
  final int sizeBytes;

  /// Путь к файлу на устройстве.
  ///
  /// Хранится **строкой**, а не `File`, чтобы домен не зависел от `dart:io`.
  /// UI сам делает `File(localPath)`, когда нужно показать превью.
  final String localPath;

  // ============================================================
  // 3. КЛАССИФИКАЦИЯ
  // ============================================================

  /// Тип вложения — для выбора способа отображения в UI.
  final AttachmentKind kind;

  // ============================================================
  // 4. СОСТОЯНИЕ
  // ============================================================

  /// Текущее состояние загрузки/обработки.
  final AttachmentStatus status;

  /// Текст ошибки, если [status] == [AttachmentStatus.failed].
  final String? errorMessage;

  /// Прогресс загрузки: 0.0..1.0.
  ///
  /// Пока не отслеживается (`0.0`), но поле уже есть — пригодится,
  /// когда добавим прогресс-бар через `dio`.
  final double uploadProgress;

  // ============================================================
  // 5. СВЯЗЬ С ЧАТОМ
  // ============================================================

  /// ID чата, к которому привязан файл.
  ///
  /// Если задан — бэкенд автоматически подставит файл в последующие
  /// вопросы этого чата (см. README `document_chat`).
  /// `null`, если файл загружен без привязки к чату.
  final String? conversationId;

  // ============================================================
  // МАРКЕР ДЛЯ copyWith
  // ============================================================

  /// Специальный объект-маркер: «это поле не было передано в copyWith».
  ///
  /// Нужен, чтобы отличать `copyWith()` (не трогать поле)
  /// от `copyWith(field: null)` (явно обнулить поле).
  static const _unset = Object();

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

  /// Создать вложение сразу после выбора файла пользователем.
  ///
  /// Статус — [AttachmentStatus.pending]: файл выбран, но загрузка
  /// ещё не началась. UI показывает превью и ждёт «Отправить».
  ///
  /// [kind] вычисляется здесь из [mimeType], чтобы UI не занимался
  /// этой логикой. Если MIME неизвестен — `AttachmentKind.other`.
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

  /// Файл успешно загружен и готов к использованию.
  ///
  /// Только в этом состоянии `remoteId` можно передавать в `input_file`.
  bool get isUploaded => remoteId != null && status == AttachmentStatus.done;

  /// Загрузка или обработка упала.
  bool get isFailed => status == AttachmentStatus.failed;

  /// Файл в процессе: ещё не готов, но и не упал.
  ///
  /// UI использует для показа спиннера и блокировки удаления.
  bool get isInProgress =>
      status == AttachmentStatus.pending ||
      status == AttachmentStatus.uploading ||
      status == AttachmentStatus.processing;

  /// Это изображение? UI покажет миниатюру.
  bool get isImage => kind == AttachmentKind.image;

  /// Это PDF? UI покажет иконку + имя файла.
  bool get isPdf => kind == AttachmentKind.pdf;

  // ============================================================
  // 8. КОПИРОВАНИЕ (immutable-паттерн)
  // ============================================================

  /// Создать копию с изменёнными полями.
  ///
  /// Nullable-поля ([remoteId], [errorMessage], [conversationId])
  /// используют маркер [_unset], чтобы отличать «не передали»
  /// от «передали null для сброса».
  Attachment copyWith({
    String? localId,
    Object? remoteId = _unset,
    String? fileName,
    String? mimeType,
    int? sizeBytes,
    String? localPath,
    AttachmentKind? kind,
    AttachmentStatus? status,
    Object? errorMessage = _unset,
    double? uploadProgress,
    Object? conversationId = _unset,
  }) {
    return Attachment(
      localId: localId ?? this.localId,
      remoteId: identical(remoteId, _unset)
          ? this.remoteId
          : remoteId as String?,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      localPath: localPath ?? this.localPath,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      conversationId: identical(conversationId, _unset)
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
// ПРИВАТНЫЕ ХЕЛПЕРЫ
// ============================================================

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
