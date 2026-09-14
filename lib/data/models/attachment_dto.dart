// lib/data/models/attachment_dto.dart

/// DTO для ответа `POST /v1/files` — соответствует формату
/// OpenAI Files API + нестандартные поля платформы.
///
/// Используется только для парсинга JSON, НЕ содержит бизнес-логики.
///
/// Преобразование в доменную модель [Attachment] выполняет
/// `AttachmentMapper` — он же разбирается с:
/// - конвертацией `created_at` (Unix-время) в `DateTime`;
/// - переводом `processing_status` (String) в `AttachmentStatus` (enum);
/// - вычислением `AttachmentKind` по `filename`/`mime_type`;
/// - разделением `status` (OpenAI) и `processing_status` (внутренний).
class AttachmentDto {
  // ============================================================
  // 1. ПОЛЯ — ТОЧНО КАК В JSON
  // ============================================================

  /// ID файла на сервере: `file-<uuid>`.
  /// Используется в `input_file` при генерации и в путях `/v1/files/{id}`.
  final String id;

  /// Тип объекта — всегда `"file"`. Храним, потому что он в JSON
  /// (нужен для отладки и полноты DTO).
  final String object;

  /// Размер файла в байтах.
  final int bytes;

  /// Unix-время создания файла — **в секундах** (не миллисекундах!).
  ///
  /// В домене превратится в `DateTime` — это делает маппер.
  /// Держим как `int`, чтобы DTO оставался зеркалом JSON.
  final int createdAt;

  /// Имя файла — как его видит пользователь.
  final String filename;

  /// Назначение файла в терминах OpenAI Files API.
  /// Сейчас всегда `"assistants"` — единственное используемое значение.
  final String purpose;

  /// Статус в терминах OpenAI: `uploaded` / `processed` / `error`.
  ///
  /// Это сведённое значение: внутренний конвейер богаче
  /// (см. `processingStatus`). Оставлен для совместимости с OpenAI SDK.
  final String status;

  /// Текст ошибки, если `status == "error"`. Иначе `null`.
  /// Заполняется бэкендом из ошибки MinerU.
  final String? statusDetails;

  /// Внутренний статус конвейера обработки:
  /// `pending` / `processing` / `done` / `failed`.
  ///
  /// Это — «настоящий» статус, который смотрит маппер, чтобы выбрать
  /// [AttachmentStatus] в домене.
  final String processingStatus;

  /// ID чата, к которому привязан файл (если загрузка шла
  /// с `conversation_id`). `null`, если файл не привязан.
  final String? conversationId;

  // ============================================================
  // 2. КОНСТРУКТОР
  // ============================================================

  const AttachmentDto({
    required this.id,
    required this.object,
    required this.bytes,
    required this.createdAt,
    required this.filename,
    required this.purpose,
    required this.status,
    this.statusDetails,
    required this.processingStatus,
    this.conversationId,
  });

  // ============================================================
  // 3. ПАРСИНГ
  // ============================================================

  /// Создаёт DTO из JSON-ответа бэкенда.
  ///
  /// Обязательные поля (`id`, `object`, `bytes`, `created_at`,
  /// `filename`, `purpose`, `status`, `processing_status`) приводятся
  /// напрямую через `as` — если сервер их не пришлёт, упадёт с TypeError.
  /// Это правильно: клиент не должен молча работать с невалидным ответом.
  ///
  /// Опциональные (`status_details`, `conversation_id`) — через `as T?`,
  /// отсутствие превращается в `null`.
  factory AttachmentDto.fromJson(Map<String, dynamic> json) {
    return AttachmentDto(
      id: json['id'] as String,
      object: json['object'] as String,
      bytes: json['bytes'] as int,
      createdAt: json['created_at'] as int,
      filename: json['filename'] as String,
      purpose: json['purpose'] as String,
      status: json['status'] as String,
      statusDetails: json['status_details'] as String?,
      processingStatus: json['processing_status'] as String,
      conversationId: json['conversation_id'] as String?,
    );
  }

  // ============================================================
  // 4. ОТЛАДКА
  // ============================================================

  @override
  String toString() {
    return 'AttachmentDto(id: $id, filename: "$filename", '
        'bytes: $bytes, status: $status, processingStatus: $processingStatus)';
  }
}
