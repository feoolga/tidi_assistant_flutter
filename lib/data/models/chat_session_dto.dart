// lib/data/models/chat_session_dto.dart

import '../../core/utils/json_parsing.dart';

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
      createdAt: parseDateOrNull(json['created_at']),
      updatedAt: parseDateOrNull(json['updated_at']),
    );
  }
}
