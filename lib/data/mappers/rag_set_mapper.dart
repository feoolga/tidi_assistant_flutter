// lib/data/mappers/rag_set_mapper.dart

import '../../core/logger/app_logger.dart';
import '../../domain/models/rag_config.dart';
import '../../domain/models/rag_set.dart';
import '../../domain/models/rag_status.dart';
import '../models/documents_counts_dto.dart';
import '../models/rag_config_dto.dart';
import '../models/rag_set_dto.dart';

/// Маппер `RagSetDto` → `RagSet`.
///
/// **Ответственность:**
/// - превратить `status` (строка) в `RagStatus` (enum);
/// - превратить вложенные DTO (`documents`, `config`) в доменные
///   объекты (`DocumentsCounts`, `RagConfig`);
/// - применить fallback для опциональных полей (`createdAt`,
///   `updatedAt`, `chunksTotal`, отсутствующих вложенных объектов).
///
/// **Что НЕ делает:**
/// - не парсит JSON (это `RagSetDto.fromJson`);
/// - не ходит в сеть (это `RagRepository`, D3);
/// - не решает, что показать пользователю (это UI, D8).
///
/// **Вложенные мапперы — внутри.** `DocumentsCounts` и `RagConfig` —
/// **простые** объекты (4 поля каждый), не используются **пока**
/// в других эндпойнтах. Отдельные мапперы для них — **преждевременно**.
/// Если в будущем понадобятся — вынесем.
class RagSetMapper {
  // ============================================================
  // 1. ПУБЛИЧНЫЙ API
  // ============================================================

  /// Преобразовать DTO в доменную модель.
  ///
  /// **Что делаем:**
  /// 1. Парсим `status` (строка → enum). Падаем при незнакомом
  ///    или `null`.
  /// 2. Мапим вложенные объекты:
  ///    - `documents` (DTO) → `DocumentsCounts` (домен);
  ///    - `config` (DTO) → `RagConfig` (домен).
  /// 3. Применяем fallback для опциональных полей.
  ///
  /// **Бросает:**
  /// - [ArgumentError] — если `status` незнакомый **или** `null`.
  ///   Это **ошибка контракта** с бэкендом: сервер прислал статус,
  ///   которого нет в нашем enum, или не прислал вообще. Лучше
  ///   **упасть** громко, чем молча искажать данные.
  static RagSet toDomain(RagSetDto dto) {
    final status = _parseStatus(dto.status);
    final documentsCounts = _mapDocumentsCounts(dto.documents);
    final config = _mapConfig(dto.config);
    final createdAt = _resolveDate(dto.createdAt, dto.id, 'created_at');
    final updatedAt = _resolveDate(dto.updatedAt, dto.id, 'updated_at');
    final chunksTotal = dto.chunksTotal ?? 0;

    return RagSet(
      id: dto.id,
      name: dto.name,
      description: dto.description,
      status: status,
      documentsCounts: documentsCounts,
      chunksTotal: chunksTotal,
      hasPending: dto.hasPending,
      hasIcon: dto.hasIcon,
      config: config,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  // ============================================================
  // 2. ПАРСИНГ STATUS
  // ============================================================

  /// Превратить строковый статус в [RagStatus].
  ///
  /// Ожидаемые значения (см. README ingestion-сервиса):
  /// - `"empty"` → [RagStatus.empty];
  /// - `"ingesting"` → [RagStatus.ingesting];
  /// - `"ready"` → [RagStatus.ready];
  /// - `"failed"` → [RagStatus.failed].
  ///
  /// **`null` — тоже ошибка.** В `RagSetDto` поле `status`
  /// **опциональное** (DTO не падает), но в **домене** `status` —
  /// **обязательное**. Значит, **маппер** — та точка, где мы
  /// **решаем**: если `null` — это **ошибка контракта**, падаем.
  ///
  /// **При незнакомом значении — `ArgumentError`.** Как и в
  /// `RagDocumentMapper`: молчаливое искажение хуже падения.
  static RagStatus _parseStatus(String? status) {
    switch (status) {
      case 'empty':
        return RagStatus.empty;
      case 'ingesting':
        return RagStatus.ingesting;
      case 'ready':
        return RagStatus.ready;
      case 'failed':
        return RagStatus.failed;
      case null:
        AppLogger.warning(
          'RagSetMapper: status отсутствует. '
          'Ожидались: empty, ingesting, ready, failed.',
        );
        throw ArgumentError.notNull('status');
      default:
        AppLogger.warning(
          'RagSetMapper: незнакомый status "$status". '
          'Ожидались: empty, ingesting, ready, failed.',
        );
        throw ArgumentError.value(
          status,
          'status',
          'Незнакомый статус RAG-набора. '
              'Допустимые: empty, ingesting, ready, failed.',
        );
    }
  }

  // ============================================================
  // 3. ВЛОЖЕННЫЕ ОБЪЕКТЫ
  // ============================================================

  /// Мапит `DocumentsCountsDto` → `DocumentsCounts`.
  ///
  /// **Если `dto == null`** — возвращает пустой `DocumentsCounts()`
  /// (все нули). Почему: отсутствие счётчиков **не** критично,
  /// дефолт «нет документов» — разумен.
  ///
  /// **Почему не отдельный маппер.** `DocumentsCounts` — простой
  /// объект (4 поля), пока не используется в других эндпойнтах.
  /// Отдельный маппер — преждевременно.
  static DocumentsCounts _mapDocumentsCounts(DocumentsCountsDto? dto) {
    if (dto == null) {
      return const DocumentsCounts();
    }
    return DocumentsCounts(
      total: dto.total,
      ready: dto.ready,
      failed: dto.failed,
      pending: dto.pending,
    );
  }

  /// Мапит `RagConfigDto` → `RagConfig`.
  ///
  /// **Если `dto == null`** — возвращает дефолтный `RagConfig()`
  /// (temperature: 0.3, topK: 5, scoreThreshold: 0.4, prompt: null).
  /// Почему: дефолты **известны** и совпадают с бэкендом. Разумно.
  ///
  /// **Дефолты на уровне полей** (`dto.temperature ?? 0.3`) — если
  /// конкретное поле не пришло, но остальные есть. Например, сервер
  /// прислал `config` с `topK`, но без `temperature` — берём `0.3`.
  ///
  /// **Про `assert`-проверки `RagConfig`.** Конструктор `RagConfig`
  /// проверяет диапазоны (`temperature ∈ [0, 1]`, `topK ∈ [1, 10]`,
  /// `scoreThreshold ∈ [0, 1]`). Если сервер прислал **невалидное**
  /// (например, `temperature: 5.0`) — `assert` **упадёт** в дебаге.
  /// Это **правильно**: сервер **обязан** присылать валидные значения.
  /// В проде `assert` **отключён**, значение **примется** и **уйдёт**
  /// в API — сервер вернёт `400`.
  static RagConfig _mapConfig(RagConfigDto? dto) {
    if (dto == null) {
      return const RagConfig();
    }
    return RagConfig(
      prompt: dto.prompt,
      temperature: dto.temperature ?? 0.3,
      topK: dto.topK ?? 5,
      scoreThreshold: dto.scoreThreshold ?? 0.4,
    );
  }

  // ============================================================
  // 4. FALLBACK — ДАТЫ
  // ============================================================

  /// Разрешить дату с fallback на Unix epoch.
  ///
  /// Если `value == null` — возвращает `DateTime.utc(1970, 1, 1)`
  /// и **логирует**.
  ///
  /// **Почему Unix epoch, а не `DateTime.now()`.** `now()` выглядел
  /// бы как реальная дата — пользователь **не понял бы**, что
  /// дата неизвестна. `1970-01-01` — **классический** маркер.
  ///
  /// **Почему `DateTime.utc`, а не `DateTime.fromMillisecondsSinceEpoch`.**
  /// `utc` **не зависит** от локального часового пояса — в тестах
  /// это **важно**.
  ///
  /// **Почему параметры `fieldName` и `ragId`.** Чтобы в логе было
  /// **видно**, какое поле и **для какого** набора пропало. Полезно
  /// при отладке.
  static DateTime _resolveDate(
    DateTime? value,
    String ragId,
    String fieldName,
  ) {
    if (value != null) return value;

    AppLogger.warning(
      'RagSetMapper: $fieldName отсутствует для набора $ragId, '
      'использую Unix epoch (1970-01-01 UTC).',
    );
    return DateTime.utc(1970, 1, 1);
  }
}
