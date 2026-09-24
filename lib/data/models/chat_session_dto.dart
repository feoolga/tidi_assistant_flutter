// lib/data/models/chat_session_dto.dart

/// DTO для сессии чата — точно соответствует JSON-ответу бэкенда.
///
/// Используется только для парсинга данных, НЕ содержит бизнес-логики.
class ChatSessionDto {
  final String id;
  final String? title;

  /// Дата создания — может быть `null`, если бэкенд прислал
  /// невалидное значение (см. [_parseDateOrNull]).
  final DateTime? createdAt;

  /// Дата последнего обновления — может быть `null` по той же причине.
  final DateTime? updatedAt;

  const ChatSessionDto({
    required this.id,
    this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Создает DTO из JSON-ответа бэкенда.
  ///
  /// **Почему даты парсятся через [_parseDateOrNull]:**
  ///
  /// Бэкенд в редких случаях может вернуть `created_at`/`updated_at`
  /// в неожиданном формате:
  /// - `null` (миграция, потеря данных);
  /// - число (Unix-time вместо ISO-8601);
  /// - невалидную ISO-строку (`"2026-13-45T00:00:00"`).
  ///
  /// Прямой `as String` + `DateTime.parse` на таких значениях
  /// **падает с `TypeError` или `FormatException`** — и весь список
  /// чатов не парсится из-за одного «плохого» элемента. Пользователь
  /// видит «Произошла непредвиденная ошибка» вместо списка чатов.
  ///
  /// [_parseDateOrNull] возвращает `null` в таких случаях. UI покажет
  /// «дата неизвестна» — честнее, чем подставлять `DateTime.now()`,
  /// который выглядел бы как реальная дата и путал пользователя.
  factory ChatSessionDto.fromJson(Map<String, dynamic> json) {
    return ChatSessionDto(
      id: json['id'].toString(), // Бэкенд может вернуть число
      title: json['title'] as String?,
      createdAt: _parseDateOrNull(json['created_at']),
      updatedAt: _parseDateOrNull(json['updated_at']),
    );
  }

  // ============================================================
  // ПРИВАТНЫЕ ХЕЛПЕРЫ
  // ============================================================

  /// Устойчивый парсинг даты из JSON.
  ///
  /// Возвращает `DateTime` или `null`:
  /// - если значение — валидная ISO-8601 строка, парсим её;
  /// - иначе (`null`, число, пустая строка, невалидный ISO) — `null`.
  ///
  /// **Почему не бросаем:** DTO — слой данных. Он должен быть
  /// устойчив к неидеальному ответу сервера. «Что делать с плохой
  /// датой» — не его ответственность. UI сам решит, показать
  /// «дата неизвестна» или вообще ничего.
  ///
  /// **Почему `dynamic`, а не `Object?`:** `json['key']` возвращает
  /// `dynamic` (парсер JSON — динамический по природе). Здесь
  /// `dynamic` оправдан — это **граница** между нетипизированным
  /// JSON и типизированным Dart.
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
}
