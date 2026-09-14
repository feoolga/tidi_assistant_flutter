// lib/core/errors/file_exceptions.dart

import 'app_exception.dart';

/// Ошибки, связанные с работой с файлами.
///
/// Покрывают все ситуации, которые могут возникнуть при выборе,
/// валидации, загрузке и обработке вложений:
/// - файл слишком большой;
/// - формат не поддерживается;
/// - слишком много файлов;
/// - загрузка упала (сеть, сервер);
/// - сервер не смог обработать документ (MinerU);
/// - файл ещё обрабатывается на сервере;
/// - не удалось открыть файл при выборе.
///
/// Все ошибки превращаются в `FileException` и попадают в `ErrorHandler`,
/// который дальше показывает `userMessage` пользователю.
class FileException extends AppException {
  const FileException({
    required super.code,
    required super.userMessage,
    super.technicalDetails,
    super.originalError,
  });

  // ============================================================
  // 1. ВАЛИДАЦИЯ НА КЛИЕНТЕ (до отправки)
  // ============================================================

  /// Файл больше допустимого размера.
  ///
  /// Проверяется локально перед загрузкой — чтобы не гонять
  /// многомегабайтный запрос и не ждать отказа от сервера.
  ///
  /// В сообщении показываем **реальные** цифры: сколько есть и сколько можно.
  /// Это понятнее абстрактного «слишком большой».
  factory FileException.tooLarge({
    required int sizeBytes,
    required int maxBytes,
  }) {
    final sizeMb = (sizeBytes / 1024 / 1024).toStringAsFixed(1);
    final maxMb = (maxBytes / 1024 / 1024).toStringAsFixed(0);

    return FileException(
      code: 'FILE_TOO_LARGE',
      userMessage: 'Файл слишком большой ($sizeMb МБ). Максимум — $maxMb МБ.',
      technicalDetails:
          'File size: $sizeBytes bytes, max allowed: $maxBytes bytes',
    );
  }

  /// Формат файла не поддерживается.
  ///
  /// Срабатывает, если `file_picker` вернул файл с расширением или MIME,
  /// которого нет в `AppConfig.allowedFileExtensions` / `allowedMimeTypes`.
  factory FileException.unsupportedFormat({required String mimeType}) {
    return FileException(
      code: 'FILE_UNSUPPORTED_FORMAT',
      userMessage: 'Формат не поддерживается. Разрешены: PDF, JPG, PNG.',
      technicalDetails: 'Unsupported MIME type: $mimeType',
    );
  }

  /// Слишком много файлов в одном сообщении.
  ///
  /// Лимит берётся из `AppConfig.maxAttachedFiles`,
  /// который должен совпадать с настройкой бэкенда (`MAX_ATTACHED_FILES`).
  factory FileException.tooManyFiles({required int actual, required int max}) {
    return FileException(
      code: 'FILE_TOO_MANY',
      userMessage: 'Можно приложить не более $max файлов. У вас — $actual.',
      technicalDetails: 'Attempted to attach $actual files, max: $max',
    );
  }

  // ============================================================
  // 2. ЗАГРУЗКА (запрос к серверу)
  // ============================================================

  /// Загрузка файла не удалась.
  ///
  /// Сеть, таймаут, 5xx от сервера — всё сюда.
  /// Пользователь видит дружелюбное сообщение, разработчик — детали.
  factory FileException.uploadFailed([Object? error]) {
    return FileException(
      code: 'FILE_UPLOAD_FAILED',
      userMessage:
          'Не удалось загрузить файл. Проверьте соединение и попробуйте ещё раз.',
      technicalDetails: error?.toString(),
      originalError: error,
    );
  }

  /// Сервер не смог обработать файл (MinerU упал).
  ///
  /// Бэкенд отвечает `502` с текстом ошибки в `status_details`.
  /// Мы этот текст пробрасываем в `technicalDetails`, а пользователю
  /// показываем общее сообщение — детали MinerU ему не нужны.
  factory FileException.processingFailed([String? details]) {
    return FileException(
      code: 'FILE_PROCESSING_FAILED',
      userMessage: 'Не удалось обработать документ. Попробуйте другой файл.',
      technicalDetails: details,
    );
  }

  /// Файл ещё обрабатывается на сервере.
  ///
  /// Бэкенд возвращает `400` при попытке использовать файл,
  /// у которого `processing_status != "done"`. Это редкий кейс —
  /// обычно загрузка синхронная, но подстрахуемся.
  factory FileException.notReady() {
    return FileException(
      code: 'FILE_NOT_READY',
      userMessage:
          'Файл ещё обрабатывается. Подождите немного и попробуйте снова.',
    );
  }

  // ============================================================
  // 3. ЛОКАЛЬНЫЕ ОПЕРАЦИИ (выбор файла, чтение)
  // ============================================================

  /// Не удалось выбрать или открыть файл.
  ///
  /// Например, `file_picker` вернул `null` (пользователь отменил),
  /// или не хватило прав на чтение. Это не критичная ошибка —
  /// пользователь просто ничего не прикрепил.
  factory FileException.pickFailed([Object? error]) {
    return FileException(
      code: 'FILE_PICK_FAILED',
      userMessage: 'Не удалось открыть файл.',
      technicalDetails: error?.toString(),
      originalError: error,
    );
  }
}
