// lib/data/models/rag_document_dto.dart

/// DTO документа RAG-набора — **зеркало JSON** от бэкенда.
///
/// Соответствует элементу из:
/// - `POST /v1/platform/rags/{id}/documents` (ответ `202`);
/// - `GET  /v1/platform/rags/{id}/documents`.
///
/// **Что такое DTO (ещё раз).** Это **объект для передачи данных** —
/// точное отражение JSON. Он **не знает** про домен, про `enum`,
/// про бизнес-логику. Только «прочитал JSON → разложил по полям».
///
/// **Что делает маппер (D2.3).** Превращает этот DTO в доменный
/// `RagDocument`:
/// - парсит `status` (строка) в `RagDocumentStatus` (enum);
/// - парсит `created_at` (строка ISO-8601) в `DateTime`;
/// - применяет fallback для опциональных полей.
///
/// **Про имена полей.** В JSON — `snake_case` (`size_bytes`,
/// `chunks_count`, `duplicate_of`). В DTO — `camelCase`
/// (`sizeBytes`, `chunksCount`, `duplicateOf`). Соответствие —
/// в `fromJson`.
///
/// **Про обязательность полей.**
///
/// **Обязательные:**
/// - `id` — есть **всегда**, без него документ не имеет смысла;
/// - `filename` — есть **всегда**, без него что показывать в UI?;
/// - `status` — есть **всегда**, это состояние обработки.
///
/// **Опциональные:**
/// - `size_bytes` — **не** приходит в ответе `POST .../documents`
///   (см. пример в README ingestion-сервиса);
/// - `created_at` — в схеме БД явного `created_at` нет, только
///   `updated_at`. Возможно, приходит под другим именем или не приходит;
/// - `chunks_count` — для `pending`/`processing` может быть `0`
///   или отсутствовать;
/// - `error` — только при `status: failed`;
/// - `duplicate_of` — только для дубликатов.
///
/// **Почему не падаем на опциональных.** Если упадём — потеряем
/// **весь** документ из-за **одного** поля. Маппер сам решит,
/// что показать при отсутствии данных.
class RagDocumentDto {
  // ============================================================
  // 1. ПОЛЯ — ТОЧНО КАК В JSON
  // ============================================================

  /// ID документа в наборе (UUID, генерируется на бэкенде).
  final String id;

  /// Имя файла — как его видит пользователь.
  final String filename;

  /// Статус обработки — **строкой**, как приходит с сервера.
  ///
  /// Ожидаемые значения: `"pending"`, `"processing"`, `"success"`,
  /// `"failed"`. **Превращение в `RagDocumentStatus`** — работа
  /// маппера (D2.3). В DTO храним строкой, потому что DTO — зеркало
  /// JSON, а JSON **не знает** про enum.
  final String status;

  /// Размер файла в байтах. Может быть `null`, если сервер не прислал.
  final int? sizeBytes;

  /// Когда документ создан. Может быть `null`, если сервер не прислал
  /// или прислал невалидную дату.
  final DateTime? createdAt;

  /// Сколько чанков документ породил. Может быть `null` или `0` для
  /// документов, обработка которых не завершена.
  final int? chunksCount;

  /// Текст ошибки — только при `status: "failed"`. Иначе `null`.
  final String? error;

  /// ID «старшего» документа, если текущий — дубликат.
  ///
  /// `null` — обычный документ. `!= null` — дубликат.
  /// Подробности — в комментарии к доменному `RagDocument.duplicateOf`.
  final String? duplicateOf;

  // ============================================================
  // 2. КОНСТРУКТОР
  // ============================================================

  const RagDocumentDto({
    required this.id,
    required this.filename,
    required this.status,
    this.sizeBytes,
    this.createdAt,
    this.chunksCount,
    this.error,
    this.duplicateOf,
  });

  // ============================================================
  // 3. ПАРСИНГ ИЗ JSON
  // ============================================================

  /// Создаёт DTO из JSON-ответа бэкенда.
  ///
  /// **Обязательные поля** (`id`, `filename`, `status`) приводятся
  /// через `as String` — если сервер их не пришлёт, **упадёт**
  /// с `TypeError`. Это **правильно**: клиент не должен **молча**
  /// работать с невалидным ответом. Лучше **явная** ошибка, чем
  /// непонятный баг в UI.
  ///
  /// **Опциональные поля** — через `as T?`. Отсутствие → `null`.
  ///
  /// **Даты** — через [_parseDateOrNull] (см. `ChatSessionDto`).
  /// Это **устойчивый** парсер: невалидная строка → `null`,
  /// а не падение с `FormatException`.
  factory RagDocumentDto.fromJson(Map<String, dynamic> json) {
    return RagDocumentDto(
      id: json['id'] as String,
      filename: json['filename'] as String,
      status: json['status'] as String,
      sizeBytes: json['size_bytes'] as int?,
      createdAt: _parseDateOrNull(json['created_at']),
      chunksCount: json['chunks_count'] as int?,
      error: json['error'] as String?,
      duplicateOf: json['duplicate_of'] as String?,
    );
  }

  // ============================================================
  // 4. ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ
  // ============================================================

  /// Устойчивый парсинг даты из JSON.
  ///
  /// Возвращает `DateTime` или `null`:
  /// - если значение — валидная ISO-8601 строка, парсим её;
  /// - иначе (`null`, число, пустая строка, невалидный ISO) — `null`.
  ///
  /// **Почему не бросаем:** DTO — слой данных. Он должен быть
  /// устойчив к неидеальному ответу сервера. «Что делать с плохой
  /// датой» — не его ответственность. Маппер сам решит, показать
  /// «дата неизвестна» или подставить `DateTime.now()`.
  ///
  /// **Копия из `ChatSessionDto`.** Пока дублирование «двух копий» —
  /// терпимо. Если появится третий такой же метод — вынесем в общий
  /// util `lib/core/utils/json_parsing.dart`.
  ///
  /// **Почему `dynamic`, а не `Object?`:** `json['key']` возвращает
  /// `dynamic` — это **граница** между нетипизированным JSON
  /// и типизированным Dart. Здесь `dynamic` оправдан.
  static DateTime? _parseDateOrNull(dynamic value) {
    if (value is String && value.isNotEmpty) {
      try {
        return DateTime.parse(value);
      } on FormatException {
        // Строка есть, но не ISO-8601.
        return null;
      }
    }
    // null, число, пустая строка — невалидные значения.
    return null;
  }

  // ============================================================
  // 5. ОТЛАДКА
  // ============================================================

  @override
  String toString() {
    return 'RagDocumentDto(id: $id, filename: "$filename", '
        'status: $status, sizeBytes: $sizeBytes)';
  }
}
