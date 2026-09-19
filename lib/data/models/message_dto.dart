// lib/data/models/message_dto.dart

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
  // ============================================================
  // 1. ПОЛЯ — ТОЧНО КАК В JSON
  // ============================================================

  /// Уникальный ID сообщения (UUID).
  ///
  /// У ассистентских сообщений совпадает с ID ответа в формате
  /// Responses (`resp_<uuid>`) без префикса — используется для
  /// повторного чтения, фидбэка и источников.
  final String id;

  /// Текст сообщения.
  ///
  /// В JSON называется `content`. Хранится как `text` — так удобнее
  /// в домене (не путать с `content`-массивами в других API).
  final String text;

  /// `true` — сообщение от пользователя, `false` — от AI.
  ///
  /// В JSON — поле `role: "user" | "assistant"`.
  final bool isFromUser;

  /// Время создания сообщения.
  ///
  /// В JSON — `created_at` (ISO-8601, строкой).
  final DateTime timestamp;

  /// Имена файлов, которые использовал ассистент при генерации ответа.
  ///
  /// **Формат:** `["накладная.pdf", "договор.pdf (частично)"]` — массив строк.
  /// Если ответ не использовал файлов — пустой массив `[]`.
  ///
  /// **Частично обрезанный документ** помечается суффиксом
  /// `" (частично)"` — см. README `document_chat`, раздел
  /// «Контекстное окно» → «Обрезка документа».
  ///
  /// **Важно:** это `List<String>`, а не `List<Map>`. README
  /// дважды подтверждает: `sources` = `[filename]`.
  final List<String>? sources;

  /// Оценка пользователя для ассистентского сообщения.
  ///
  /// Формат: `{"vote": 1 | -1 | null, "comment": "..." | null}`
  /// или `null`, если оценки нет.
  ///
  /// Для сообщений пользователя — всегда `null`.
  final Map<String, dynamic>? feedback;

  /// ID агента, который ответил (только для сообщений AI).
  ///
  /// **В README не упоминается.** Возможно, бэкенд присылает его
  /// в каких-то случаях; возможно — нет. Парсим как `String?` —
  /// безопасно: если поля нет, будет `null`.
  ///
  /// Используется в `Message` для контекста, но UI его не показывает.
  final String? agentId;

  /// ID сессии (чата) на бэкенде (только для сообщений AI).
  ///
  /// **В README не упоминается.** См. комментарий к [agentId].
  final String? sessionId;

  // ============================================================
  // 2. КОНСТРУКТОР
  // ============================================================

  const MessageDto({
    required this.id,
    required this.text,
    required this.isFromUser,
    required this.timestamp,
    this.sources,
    this.feedback,
    this.agentId,
    this.sessionId,
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

    // --- Sources: массив строк ---
    // Сервер присылает `["накладная.pdf"]`. Парсим через `cast<String>()` —
    // если сервер вдруг пришлёт `List<Map>`, это упадёт с явной ошибкой,
    // а не молча деградирует.
    final List<String>? sources = (json['sources'] as List?)?.cast<String>();

    return MessageDto(
      id: id,
      text: text,
      isFromUser: isFromUser,
      timestamp: timestamp,
      sources: sources,
      feedback: json['feedback'] as Map<String, dynamic>?,
      agentId: json['agentId'] as String?,
      sessionId: json['sessionId'] as String?,
    );
  }

  // ============================================================
  // 4. ОТЛАДКА
  // ============================================================

  @override
  String toString() {
    return 'MessageDto(id: $id, isFromUser: $isFromUser, '
        'textLength: ${text.length}, sources: $sources)';
  }
}
