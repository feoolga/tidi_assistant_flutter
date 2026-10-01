// lib/data/models/rag_set_dto.dart

import 'documents_counts_dto.dart';
import 'rag_config_dto.dart';

/// DTO RAG-набора — **зеркало JSON** от бэкенда.
///
/// Соответствует элементу из:
/// - `POST /v1/platform/rags` (ответ `201`);
/// - `GET  /v1/platform/rags` (ответ-список);
/// - `GET  /v1/platform/rags/{id}` (ответ-объект).
///
/// **Что такое DTO.** Точное отражение JSON. Не знает про домен,
/// про `RagSet`, про валидацию.
///
/// **Что делает маппер (D2.4).** Превращает в доменный `RagSet`:
/// - парсит `status` (строка) в `RagStatus` (enum);
/// - парсит даты в `DateTime`;
/// - превращает вложенные DTO в доменные объекты;
/// - применяет fallback для опциональных полей.
///
/// **Про имена полей.** В JSON — `snake_case` (`has_icon`,
/// `chunks_total`, `has_pending`, `created_at`, `updated_at`).
/// В DTO — `camelCase`. Соответствие — в `fromJson`.
///
/// **Про обязательность.**
///
/// **Обязательные:**
/// - `id` — есть **всегда**, без него набор не имеет смысла;
/// - `name` — есть **всегда** (бэкенд требует обязательное поле).
///
/// **Опциональные:**
/// - `description` — может быть `null`;
/// - `status` — **строкой** — может прийти `null` в редких случаях,
///   маппер поставит дефолт `empty`;
/// - `documents` — вложенный объект, может отсутствовать, маппер
///   поставит пустые счётчики;
/// - `config` — вложенный объект, может отсутствовать, маппер
///   поставит дефолтный конфиг;
/// - `created_at` / `updated_at` — даты, могут не парситься;
/// - `chunks_total`, `has_pending`, `has_icon` — с дефолтами.
class RagSetDto {
  // ============================================================
  // 1. ПОЛЯ — ТОЧНО КАК В JSON
  // ============================================================

  /// ID набора (UUID).
  final String id;

  /// Название набора.
  final String name;

  /// Описание (опционально).
  final String? description;

  /// Статус набора **строкой**, как приходит с сервера.
  ///
  /// Ожидаемые значения: `"empty"`, `"ingesting"`, `"ready"`,
  /// `"failed"`. Превращение в `RagStatus` — работа маппера.
  final String? status;

  /// Счётчики документов — вложенный объект.
  ///
  /// `null`, если сервер не прислал. Маппер поставит пустой
  /// `DocumentsCountsDto()`.
  final DocumentsCountsDto? documents;

  /// Общее число чанков по всем документам.
  final int? chunksTotal;

  /// Есть ли документы в незавершённом состоянии?
  ///
  /// **Non-nullable** — дефолт `false`, если сервер не прислал.
  /// Это **источник правды** для остановки polling (см. D5).
  final bool hasPending;

  /// Есть ли у набора иконка?
  ///
  /// **Non-nullable** — дефолт `false`.
  final bool hasIcon;

  /// Конфиг набора — вложенный объект.
  ///
  /// `null`, если сервер не прислал. Маппер поставит дефолтный
  /// `RagConfigDto()`.
  final RagConfigDto? config;

  /// Когда набор создан. Может быть `null` при невалидной дате.
  final DateTime? createdAt;

  /// Когда набор последний раз обновлялся. Может быть `null`.
  final DateTime? updatedAt;

  // ============================================================
  // 2. КОНСТРУКТОР
  // ============================================================

  const RagSetDto({
    required this.id,
    required this.name,
    this.description,
    this.status,
    this.documents,
    this.chunksTotal,
    this.hasPending = false,
    this.hasIcon = false,
    this.config,
    this.createdAt,
    this.updatedAt,
  });

  // ============================================================
  // 3. ПАРСИНГ ИЗ JSON
  // ============================================================

  /// Создаёт DTO из JSON-ответа бэкенда.
  ///
  /// **Обязательные поля** (`id`, `name`) — читаем напрямую,
  /// падаем если сервер их не прислал. Это **правильно**: без
  /// `id`/`name` набор **не имеет смысла**.
  ///
  /// **Вложенные объекты** (`documents`, `config`) — через отдельные
  /// DTO. Если сервер не прислал — `null`, маппер поставит дефолт.
  ///
  /// **Даты** — через [_parseDateOrNull] (см. `ChatDocumentDto`).
  factory RagSetDto.fromJson(Map<String, dynamic> json) {
    return RagSetDto(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      status: json['status'] as String?,
      documents: _parseDocuments(json['documents']),
      chunksTotal: json['chunks_total'] as int?,
      hasPending: json['has_pending'] as bool? ?? false,
      hasIcon: json['has_icon'] as bool? ?? false,
      config: _parseConfig(json['config']),
      createdAt: _parseDateOrNull(json['created_at']),
      updatedAt: _parseDateOrNull(json['updated_at']),
    );
  }

  // ============================================================
  // 4. ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ
  // ============================================================

  /// Парсит вложенный объект `documents` в [DocumentsCountsDto].
  ///
  /// Возвращает `null`, если поле отсутствует или не объект.
  /// **Не бросаем** — маппер поставит пустые счётчики.
  static DocumentsCountsDto? _parseDocuments(dynamic value) {
    if (value is Map<String, dynamic>) {
      return DocumentsCountsDto.fromJson(value);
    }
    return null;
  }

  /// Парсит вложенный объект `config` в [RagConfigDto].
  ///
  /// Возвращает `null`, если поле отсутствует или не объект.
  static RagConfigDto? _parseConfig(dynamic value) {
    if (value is Map<String, dynamic>) {
      return RagConfigDto.fromJson(value);
    }
    return null;
  }

  /// Устойчивый парсинг даты из JSON.
  ///
  /// **Копия из `RagDocumentDto`.** Это уже **третья** копия
  /// (была в `ChatSessionDto`, `RagDocumentDto`, теперь здесь).
  /// **Три копии — сигнал выносить в util.**
  ///
  /// **В D2.4** (или в следующем шаге) **вынесем** в общий
  /// `lib/core/utils/json_parsing.dart` и заменим все три копии.
  /// Пока оставляем здесь, чтобы **не раздувать** этот шаг.
  static DateTime? _parseDateOrNull(dynamic value) {
    if (value is String && value.isNotEmpty) {
      try {
        return DateTime.parse(value);
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  // ============================================================
  // 5. ОТЛАДКА
  // ============================================================

  @override
  String toString() {
    return 'RagSetDto(id: $id, name: "$name", status: $status, '
        'documents: $documents, hasPending: $hasPending, '
        'hasIcon: $hasIcon)';
  }
}
