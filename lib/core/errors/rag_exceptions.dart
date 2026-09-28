// lib/core/errors/rag_exceptions.dart

import 'app_exception.dart';

/// Ошибки, связанные с RAG-сценарием.
///
/// RAG-сценарий — это создание **пользовательских наборов документов**
/// (RAG-наборов) с последующим использованием их в диалоге с
/// `agentic_rag`-агентом. Это **отдельный bounded context**, поэтому
/// у него **свои** бизнес-правила и **свои** ошибки.
///
/// **Почему отдельный класс, а не `FileException`/`BusinessException`:**
/// - Лимиты RAG отличаются от лимитов `document_chat`:
///   файл — 200 МБ (не 25 МБ), общий размер набора — 20 ГБ.
/// - Доменные состояния RAG (`empty`/`ingesting`/`ready`/`failed`)
///   не имеют аналогов в других сценариях.
/// - Специфические сущности: «набор», «документ в наборе»,
///   «иконка набора».
/// - Сообщения для пользователя должны быть **про RAG**:
///   «Не удалось создать RAG-набор», а не «Не удалось загрузить файл».
///
/// **Где используется:**
/// - `RagRepository` — при разборе ответов от `/v1/platform/rags`;
/// - `ErrorHandler.handleRagCreation` / `ErrorHandler.handleRagUpload` —
///   единая точка превращения ошибок в контексте RAG;
/// - UI — показывает `userMessage`, логирует `code` и `technicalDetails`.
///
/// **Все ошибки — `AppException`.** Это значит, что `ErrorHandler`
/// пропускает их как есть, не оборачивая в `UnknownException`.
class RagException extends AppException {
  const RagException({
    required super.code,
    required super.userMessage,
    super.technicalDetails,
    super.originalError,
  });

  // ============================================================
  // 1. ЛИМИТЫ И ДОМЕННЫЕ ПРАВИЛА
  // ============================================================

  /// Достигнут лимит RAG-наборов на владельца.
  ///
  /// Бэкенд устанавливает лимит **50 наборов** на владельца
  /// (см. `INGEST_RAG_MAX_SETS_PER_OWNER` в конфиге ingestion-сервиса).
  /// При попытке создать 51-й — `POST /v1/platform/rags` вернёт `409`
  /// (или `400`), а мы превратим это в эту ошибку.
  ///
  /// **Что делать пользователю:** удалить ненужные наборы и создать
  /// новый. UI может предложить перейти в список RAG-наборов.
  factory RagException.limitReached({int? max}) {
    final limitText = max != null ? ' ($max)' : '';
    return RagException(
      code: 'RAG_LIMIT_REACHED',
      userMessage:
          'Достигнут лимит RAG-наборов$limitText. '
          'Удалите ненужные и попробуйте снова.',
      technicalDetails: max != null ? 'Max sets per owner: $max' : null,
    );
  }

  /// Превышен общий размер набора.
  ///
  /// Бэкенд ограничивает **суммарный размер всех документов набора**
  /// в **20 ГБ** (`INGEST_RAG_MAX_BYTES_PER_SET`). Проверка
  /// **накопительная** — то есть 20 ГБ нельзя превысить и за несколько
  /// запросов загрузки.
  ///
  /// **Почему отдельно от `FileException.tooLarge`:**
  /// там — про **один** файл (25 МБ у `document_chat`, 200 МБ у RAG),
  /// здесь — про **сумму** всех файлов набора.
  ///
  /// [currentBytes] — текущий размер набора (если бэкенд прислал).
  /// [maxBytes] — предельный размер (если бэкенд прислал).
  factory RagException.sizeLimitReached({int? currentBytes, int? maxBytes}) {
    // Форматируем размеры в человекочитаемый вид, если они есть.
    final currentGb = currentBytes != null
        ? (currentBytes / 1024 / 1024 / 1024).toStringAsFixed(1)
        : null;
    final maxGb = maxBytes != null
        ? (maxBytes / 1024 / 1024 / 1024).toStringAsFixed(1)
        : null;

    // Формируем сообщение по частям — если есть цифры, показываем их.
    final String userMessage;
    if (currentGb != null && maxGb != null) {
      userMessage =
          'Превышен общий размер набора ($maxGb ГБ). '
          'Сейчас в наборе: $currentGb ГБ.';
    } else if (maxGb != null) {
      userMessage = 'Превышен общий размер набора ($maxGb ГБ).';
    } else {
      userMessage = 'Превышен общий размер набора.';
    }

    return RagException(
      code: 'RAG_SIZE_LIMIT_REACHED',
      userMessage: userMessage,
      technicalDetails: currentBytes != null || maxBytes != null
          ? 'Current: $currentBytes bytes, max: $maxBytes bytes'
          : null,
    );
  }

  /// Набор ещё не готов к использованию.
  ///
  /// Возникает при попытке начать диалог с RAG-агентом, когда
  /// `status` набора — `empty` или `ingesting` (документы ещё
  /// обрабатываются воркером).
  ///
  /// **Что делать пользователю:** подождать. UI может показать
  /// прогресс-бар и кнопку «Обновить».
  ///
  /// [ragId] — ID набора (для логирования).
  /// [status] — текущий статус набора (`empty`/`ingesting`/`failed`).
  factory RagException.notReady({
    required String ragId,
    required String status,
  }) {
    // Разные сообщения для разных статусов — точнее для пользователя.
    final String userMessage;
    switch (status) {
      case 'empty':
        userMessage =
            'В RAG-наборе пока нет документов. Загрузите хотя бы один файл.';
        break;
      case 'ingesting':
        userMessage = 'RAG-набор ещё обрабатывается. Подождите немного.';
        break;
      case 'failed':
        userMessage =
            'RAG-набор не удалось обработать. '
            'Проверьте документы и попробуйте создать новый.';
        break;
      default:
        userMessage = 'RAG-набор ещё не готов к использованию.';
    }

    return RagException(
      code: 'RAG_NOT_READY',
      userMessage: userMessage,
      technicalDetails: 'RAG set "$ragId" is not ready (status: "$status")',
    );
  }

  /// RAG-набор не найден, удалён или принадлежит другому пользователю.
  ///
  /// Бэкенд **не различает** «не существует» и «чужой» — оба случая
  /// возвращают `404`, потому что подтверждать существование чужих
  /// ресурсов — утечка информации.
  ///
  /// **Что делать пользователю:** если он точно знал про набор —
  /// возможно, набор удалили. UI может предложить вернуться к списку.
  factory RagException.notFound(String ragId) {
    return RagException(
      code: 'RAG_NOT_FOUND',
      userMessage: 'RAG-набор не найден или был удалён.',
      technicalDetails: 'RAG set with id "$ragId" not found',
    );
  }

  // ============================================================
  // 2. СОЗДАНИЕ НАБОРА
  // ============================================================

  /// Не удалось создать RAG-набор.
  ///
  /// Fallback для любых ошибок при `POST /v1/platform/rags`, которые
  /// не подошли под [limitReached] или [notFound].
  ///
  /// **Что делать пользователю:** попробовать позже.
  factory RagException.createFailed([Object? error]) {
    return RagException(
      code: 'RAG_CREATE_FAILED',
      userMessage: 'Не удалось создать RAG-набор. Попробуйте позже.',
      technicalDetails: error?.toString(),
      originalError: error,
    );
  }

  // ============================================================
  // 3. ЗАГРУЗКА ДОКУМЕНТОВ
  // ============================================================

  /// Не удалось загрузить документы в RAG-набор.
  ///
  /// **Особый случай.** Загрузка документов **не атомарна**: файлы
  /// пишутся по очереди, каждый со своим коммитом. Если 5-й файл упал —
  /// первые 4 **остаются принятыми**, а фронт получает только ошибку
  /// (см. README ingestion-сервиса). Значит:
  ///
  /// - после ошибки надо **перечитать** `GET .../documents`;
  /// - сообщение должно быть **про частичную** загрузку, если мы знаем,
  ///   сколько успело пройти.
  ///
  /// [accepted] — сколько файлов успело приняться (если известно).
  /// [failed] — сколько не прошло (если известно).
  /// [error] — оригинальная ошибка (для `technicalDetails`).
  factory RagException.uploadFailed({
    int? accepted,
    int? failed,
    Object? error,
  }) {
    final String userMessage;
    if (accepted != null && failed != null) {
      userMessage =
          'Часть файлов не загружена. Принято: $accepted, отклонено: $failed.';
    } else if (accepted != null && accepted > 0) {
      userMessage =
          'Не удалось загрузить документы. Принято: $accepted. '
          'Проверьте список файлов в наборе.';
    } else {
      userMessage = 'Не удалось загрузить документы в RAG-набор.';
    }

    return RagException(
      code: 'RAG_UPLOAD_FAILED',
      userMessage: userMessage,
      technicalDetails: error?.toString(),
      originalError: error,
    );
  }

  /// Файл больше допустимого размера для RAG-набора.
  ///
  /// Лимит одного файла в RAG — **200 МБ** (`INGEST_ARCHIVE_MAX_FILE_SIZE`).
  /// Это **сильно больше**, чем 25 МБ у `document_chat`, поэтому
  /// отдельная фабрика — чтобы не путать сообщения.
  ///
  /// Бэкенд при `413` возвращает **только текст** (`error.message`),
  /// **без** полей `actual_bytes`/`max_bytes` (в отличие от
  /// `document_chat`, где эти поля есть). Поэтому фабрика принимает
  /// опциональный [serverMessage] и не пытается показать точные цифры,
  /// если их нет.
  ///
  /// **Почему не парсим `message` для извлечения размера:** формат
  /// сообщения — зона ответственности бэкенда, может меняться.
  /// Свой лимит мы **знаем** (`AppConfig.ragMaxFileSize`), поэтому
  /// показываем его в сообщении.
  factory RagException.fileTooLarge({String? serverMessage, int? maxBytes}) {
    final maxMb = maxBytes != null
        ? (maxBytes / 1024 / 1024).toStringAsFixed(0)
        : null;
    final limitText = maxMb != null ? ' (максимум $maxMb МБ)' : '';

    return RagException(
      code: 'RAG_FILE_TOO_LARGE',
      userMessage: 'Файл слишком большой$limitText.',
      technicalDetails: serverMessage ?? 'Server returned HTTP 413',
    );
  }

  /// Формат файла не поддерживается RAG-сервисом.
  ///
  /// Возможные причины: `415 Unsupported Media Type` от бэкенда,
  /// либо клиентская валидация перед отправкой.
  ///
  /// **Какие форматы поддерживаются:** см. README ingestion-сервиса —
  /// PDF, DOCX, TXT, MD и другие (точный список уточняется).
  factory RagException.unsupportedFormat({required String mimeType}) {
    return RagException(
      code: 'RAG_UNSUPPORTED_FORMAT',
      userMessage: 'Формат файла не поддерживается для RAG-набора.',
      technicalDetails: 'Unsupported MIME type: $mimeType',
    );
  }

  /// Слишком много файлов в одном запросе на загрузку.
  ///
  /// **Это клиентский лимит, не серверный.** Бэкенд не устанавливает
  /// максимум на количество файлов в одном `POST .../documents`, но
  /// **рекомендует грузить пачками по 5–10** (см. ответ бэкендера:
  /// «запрос не атомарный, ошибка на середине оставляет первые файлы
  /// принятыми»). Наш лимит — `AppConfig.ragMaxFilesPerBatch`.
  ///
  /// **Почему такой лимит нужен:**
  /// - Уменьшает «ущерб» от частичной загрузки: чем меньше пачка,
  ///   тем понятнее, что успело пройти.
  /// - Упрощает UI: можно показать прогресс «3 из 10» по-человечески.
  factory RagException.tooManyFilesInBatch({
    required int actual,
    required int max,
  }) {
    return RagException(
      code: 'RAG_TOO_MANY_FILES_IN_BATCH',
      userMessage:
          'За один раз можно загрузить не более $max файлов. Выбрано: $actual.',
      technicalDetails:
          'Attempted to upload $actual files, max per batch: $max',
    );
  }

  // ============================================================
  // 4. ИКОНКА НАБОРА
  // ============================================================

  /// Иконка набора превышает допустимый размер (512 КБ).
  ///
  /// Лимит берётся из настроек ingestion-сервиса, но клиент проверяет
  /// его **до** отправки, чтобы не гонять зря большой файл.
  factory RagException.iconTooLarge({
    required int sizeBytes,
    required int maxBytes,
  }) {
    final sizeKb = (sizeBytes / 1024).toStringAsFixed(0);
    final maxKb = (maxBytes / 1024).toStringAsFixed(0);

    return RagException(
      code: 'RAG_ICON_TOO_LARGE',
      userMessage: 'Иконка слишком большая ($sizeKb КБ). Максимум — $maxKb КБ.',
      technicalDetails: 'Icon size: $sizeBytes bytes, max: $maxBytes bytes',
    );
  }

  /// Формат иконки не поддерживается.
  ///
  /// Разрешены: PNG, JPEG, WebP. SVG **не принимается** — иконка
  /// отдаётся с того же origin, что и фронт, а SVG является
  /// исполняемым документом (см. README ingestion-сервиса).
  factory RagException.iconUnsupportedFormat({required String mimeType}) {
    return RagException(
      code: 'RAG_ICON_UNSUPPORTED_FORMAT',
      userMessage:
          'Формат иконки не поддерживается. Разрешены: PNG, JPEG, WebP.',
      technicalDetails: 'Unsupported icon MIME type: $mimeType',
    );
  }
}
