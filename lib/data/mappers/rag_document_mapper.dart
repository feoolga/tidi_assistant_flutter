// lib/data/mappers/rag_document_mapper.dart

import '../../core/logger/app_logger.dart';
import '../../domain/models/rag_document.dart';
import '../../domain/models/rag_document_status.dart';
import '../models/rag_document_dto.dart';

/// Маппер `RagDocumentDto` → `RagDocument`.
///
/// **Ответственность:**
/// - превратить `status` (строка) в `RagDocumentStatus` (enum);
/// - применить fallback для опциональных полей (`sizeBytes`,
///   `createdAt`, `chunksCount`);
/// - залогировать **аномалии** (отсутствующие поля, незнакомый статус).
///
/// **Что НЕ делает:**
/// - не парсит JSON (это `RagDocumentDto.fromJson`);
/// - не ходит в сеть (это репозиторий, D3);
/// - не решает, что показать пользователю (это UI, D8).
///
/// **Граница слоёв.** Это **последний** рубеж перед доменом. Здесь
/// мы **впервые** работаем с **доменными** типами (`RagDocument`,
/// `RagDocumentStatus`). До этого — только с DTO и строками.
class RagDocumentMapper {
  // ============================================================
  // 1. ПУБЛИЧНЫЙ API
  // ============================================================

  /// Преобразовать DTO в доменную модель.
  ///
  /// **Что делаем:**
  /// 1. Парсим `status` (строка → enum). Падаем при незнакомом.
  /// 2. Применяем fallback:
  ///    - `sizeBytes: dto.sizeBytes ?? 0` + warning при `null`;
  ///    - `createdAt: dto.createdAt ?? DateTime(0)` + warning при `null`;
  ///    - `chunksCount: dto.chunksCount ?? 0` (без warning — норма).
  /// 3. Пробрасываем `error` и `duplicateOf` как есть.
  ///
  /// **Бросает:**
  /// - [ArgumentError] — если `status` незнакомый. Это **ошибка
  ///   контракта** с бэкендом: сервер прислал статус, которого
  ///   нет в нашем enum. Лучше **упасть** громко, чем молча
  ///   искажать данные.
  ///
  /// **Почему не fallback в `failed`/`pending`.** Молчаливое
  /// искажение хуже явного падения: пользователь увидит «документ
  /// упал», хотя на самом деле «незнакомый статус». Падение
  /// **через ErrorHandler** превратится в понятную ошибку UI.
  static RagDocument toDomain(RagDocumentDto dto) {
    final status = _parseStatus(dto.status);
    final sizeBytes = _resolveSizeBytes(dto);
    final createdAt = _resolveCreatedAt(dto);
    final chunksCount = dto.chunksCount ?? 0;

    return RagDocument(
      id: dto.id,
      filename: dto.filename,
      sizeBytes: sizeBytes,
      createdAt: createdAt,
      status: status,
      chunksCount: chunksCount,
      error: dto.error,
      duplicateOf: dto.duplicateOf,
    );
  }

  // ============================================================
  // 2. ПАРСИНГ STATUS
  // ============================================================

  /// Превратить строковый статус в [RagDocumentStatus].
  ///
  /// Ожидаемые значения (см. README ingestion-сервиса, схему БД):
  /// - `"pending"` → [RagDocumentStatus.pending];
  /// - `"processing"` → [RagDocumentStatus.processing];
  /// - `"success"` → [RagDocumentStatus.success];
  /// - `"failed"` → [RagDocumentStatus.failed].
  ///
  /// **При незнакомом значении — `ArgumentError`.** Это **ошибка
  /// контракта**: сервер добавил новый статус, которого мы не
  /// знаем. Лучше **упасть** сейчас, чем показывать непонятное
  /// состояние пользователю.
  ///
  /// **Логируем** перед падением — чтобы в логе было видно,
  /// **какой** именно статус пришёл и **для какого** документа.
  ///
  /// **Почему `switch` с exhaustive.** Dart 3 требует, чтобы
  /// `switch` по enum был **исчерпывающим** — если мы забудем
  /// обработать какое-то значение, компилятор **скажет**.
  /// Здесь мы **проверяем строку**, но всё равно — используем
  /// `switch` с `default` для **явного** отлова незнакомых.
  static RagDocumentStatus _parseStatus(String status) {
    switch (status) {
      case 'pending':
        return RagDocumentStatus.pending;
      case 'processing':
        return RagDocumentStatus.processing;
      case 'success':
        return RagDocumentStatus.success;
      case 'failed':
        return RagDocumentStatus.failed;
      default:
        // Логируем перед падением — чтобы в логе было видно,
        // что именно пришло. `dto.id` тут недоступен (метод
        // статический, без контекста), поэтому пишем только статус.
        AppLogger.warning(
          'RagDocumentMapper: незнакомый status "$status". '
          'Ожидались: pending, processing, success, failed.',
        );
        throw ArgumentError.value(
          status,
          'status',
          'Незнакомый статус документа RAG. '
              'Допустимые: pending, processing, success, failed.',
        );
    }
  }

  // ============================================================
  // 3. FALLBACK — sizeBytes
  // ============================================================

  /// Разрешить `sizeBytes` с fallback.
  ///
  /// Если `dto.sizeBytes == null` — ставим `0` и **логируем**.
  ///
  /// **Почему `0`, а не `throw`.** В ответе `POST .../documents`
  /// поле `size_bytes` **может не приходить** (см. README
  /// ingestion-сервиса, пример ответа). Падать **нельзя** —
  /// потеряем **весь** документ из-за одного поля.
  ///
  /// **Почему логируем.** Если `size_bytes` **массово** пропадает,
  /// это может быть **баг бэкенда**. Warning в логе — **сигнал**.
  static int _resolveSizeBytes(RagDocumentDto dto) {
    if (dto.sizeBytes != null) return dto.sizeBytes!;

    AppLogger.warning(
      'RagDocumentMapper: size_bytes отсутствует для документа ${dto.id}, '
      'использую 0.',
    );
    return 0;
  }

  // ============================================================
  // 4. FALLBACK — createdAt
  // ============================================================

  /// Разрешить `createdAt` с fallback.
  ///
  /// Если `dto.createdAt == null` — ставим **эпоху**
  /// (`DateTime(0)` = 1970-01-01 00:00:00 UTC) и **логируем**.
  ///
  /// **Почему `DateTime(0)`, а не `DateTime.now()`.**
  /// `now()` **выглядел бы** как реальная дата — пользователь
  /// **не понял бы**, что дата неизвестна. `DateTime(0)` — это
  /// **классический** маркер «неизвестно». UI может его
  /// распознать (`date.year == 1970`) или просто показать
  /// «01.01.1970» — странно, но **видно**.
  ///
  /// **Почему не `throw`.** По аналогии с `sizeBytes`: дата
  /// **может** не прийти, это **известно**. Падать нельзя.
  static DateTime _resolveCreatedAt(RagDocumentDto dto) {
    if (dto.createdAt != null) return dto.createdAt!;

    AppLogger.warning(
      'RagDocumentMapper: created_at отсутствует для документа ${dto.id}, '
      'использую эпоху (1970-01-01).',
    );
    // Unix epoch (1970-01-01 00:00:00 UTC) — классический маркер
    // «неизвестная дата». Используем `DateTime.utc`, а не
    // `DateTime.fromMillisecondsSinceEpoch(0)`, чтобы результат
    // не зависел от локального часового пояса — в тестах это
    // важно.
    return DateTime.utc(1970, 1, 1);
  }
}
