// lib/data/models/rag_config_dto.dart

import '../../core/utils/json_parsing.dart';

/// DTO конфигурации RAG-набора — **зеркало JSON** от бэкенда.
///
/// Соответствует полю `config` в ответе `GET /v1/platform/rags/{id}`:
/// ```json
/// "config": {"prompt": null, "temperature": 0.3, "top_k": 5,
///            "score_threshold": 0.4}
/// ```
///
/// **Что такое DTO.** Точное отражение JSON. Не знает про домен,
/// про `RagConfig` (доменный класс), про валидацию. Только
/// «прочитал JSON → разложил по полям».
///
/// **Что делает маппер (D2.4).** Превращает этот DTO в доменный
/// `RagConfig` — с `assert`-проверками диапазонов, с дефолтами.
///
/// **Про имена полей.** В JSON — `snake_case` (`top_k`,
/// `score_threshold`). В DTO — `camelCase` (`topK`,
/// `scoreThreshold`). Соответствие — в `fromJson`.
///
/// **Про обязательность.** Все четыре поля **опциональны** —
/// если сервер их не прислал, маппер поставит **дефолты**
/// (`temperature: 0.3`, `topK: 5`, `scoreThreshold: 0.4`,
/// `prompt: null`). Это **правильно**: конфиг без части полей —
/// не критично, применим дефолт.
class RagConfigDto {
  // ============================================================
  // 1. ПОЛЯ — ТОЧНО КАК В JSON
  // ============================================================

  /// Дополнительные инструкции для LLM. Может быть `null`.
  final String? prompt;

  /// «Температура» генерации. Может быть `null`, если сервер
  /// не прислал — маппер поставит дефолт `0.3`.
  final double? temperature;

  /// Сколько фрагментов поднимать из индекса. Может быть `null`.
  final int? topK;

  /// Порог косинусного сходства. Может быть `null`.
  final double? scoreThreshold;

  // ============================================================
  // 2. КОНСТРУКТОР
  // ============================================================

  const RagConfigDto({
    this.prompt,
    this.temperature,
    this.topK,
    this.scoreThreshold,
  });

  // ============================================================
  // 3. ПАРСИНГ ИЗ JSON
  // ============================================================

  /// Создаёт DTO из JSON-объекта `config`.
  ///
  /// **Все поля — опциональные.** Если поле не пришло — `null`,
  /// маппер поставит дефолт. Это **правильно** для конфига:
  /// отсутствие поля — не ошибка, а «применить дефолт».
  ///
  /// **Обрати внимание:** `temperature` и `scoreThreshold` в JSON —
  /// числа (`double`). Но Dart **может** получить `int`, если сервер
  /// прислал `1` вместо `1.0`. Поэтому используем `_parseDoubleOrNull`.
  factory RagConfigDto.fromJson(Map<String, dynamic> json) {
    return RagConfigDto(
      prompt: json['prompt'] as String?,
      temperature: parseDoubleOrNull(json['temperature']),
      topK: json['top_k'] as int?,
      scoreThreshold: parseDoubleOrNull(json['score_threshold']),
    );
  }

  // ============================================================
  // 4. ОТЛАДКА
  // ============================================================

  @override
  String toString() {
    return 'RagConfigDto(prompt: ${prompt == null ? "null" : "${prompt!.length} chars"}, '
        'temperature: $temperature, topK: $topK, '
        'scoreThreshold: $scoreThreshold)';
  }
}
