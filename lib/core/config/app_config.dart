// lib/core/config/app_config.dart

import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Конфигурация приложения.
///
/// Здесь хранятся все настройки в одном месте.
/// Если нужно поменять URL сервера или таймауты - меняем только здесь.
class AppConfig {
  // ============================================================
  // 1. БАЗОВЫЙ URL СЕРВЕРА
  // ============================================================

  // ---- 1. БАЗОВЫЙ URL ----
  static String get baseUrl {
    final url = dotenv.env['API_URL'];
    if (url == null || url.isEmpty) {
      throw Exception('API_URL не задан в .env файле');
    }
    return url;
  }

  // ============================================================
  // 2. ПОЛЬЗОВАТЕЛЬ (пока временно)
  // ============================================================

  // ---- 2. ID ПОЛЬЗОВАТЕЛЯ ----
  static String get userId {
    final id = dotenv.env['USER_ID'];
    if (id == null || id.isEmpty) {
      throw Exception('USER_ID не задан в .env файле');
    }
    return id;
  }

  // ============================================================
  // 3. ТАЙМАУТЫ
  // ============================================================

  /// Таймаут для обычных запросов (10 секунд)
  static const Duration timeout = Duration(seconds: 10);

  /// Таймаут для стримов (дольше, так как ответ может идти долго)
  static const Duration streamTimeout = Duration(seconds: 60);

  /// Таймаут для загрузки файлов.
  ///
  /// Отдельный и очень длинный, потому что бэкенд (`document_chat`)
  /// синхронно прогоняет файл через MinerU (OCR + разбор в markdown).
  /// По README бэкендера — `MINERU_TIMEOUT_SECONDS=600` по умолчанию.
  /// Ставим те же 10 минут, чтобы наш таймаут не сработал раньше серверного.
  static const Duration uploadTimeout = Duration(minutes: 10);

  // ============================================================
  // 4. ЗАГОЛОВКИ ПО УМОЛЧАНИЮ
  // ============================================================

  /// Заголовки, которые отправляются с каждым запросом
  static const Map<String, String> defaultHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  /// Заголовки для стримов (SSE)
  static const Map<String, String> streamHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'text/event-stream',
  };

  // ============================================================
  // 5. ЛИМИТЫ ФАЙЛОВ (валидация на клиенте)
  // ============================================================

  /// Максимальный размер одного файла.
  /// Совпадает с лимитом бэкенда: файл больше 25 МБ → 413.
  /// Проверяем локально, чтобы не гонять зря многомегабайтные запросы.
  static const int maxFileSizeBytes = 25 * 1024 * 1024; // 25 МБ

  /// Максимальное количество файлов в одном сообщении.
  ///
  /// Бэкендер (`document_chat`) настраивает через `MAX_ATTACHED_FILES`
  /// (1 или 5 в зависимости от модели). Ставим 5 — если реальный деплой
  /// использует 1, поменяем здесь одно число.
  static const int maxAttachedFiles = 5;

  /// Разрешённые MIME-типы для загрузки.
  ///
  /// Используем для клиентской валидации и для отображения корректного
  /// типа в UI (иконка PDF / превью картинки).
  ///
  /// ВАЖНО: MIME не всегда приходит из `file_picker` корректно —
  /// иногда там `application/octet-stream`. Поэтому есть ещё список
  /// расширений ниже, и валидация идёт по обоим.
  static const Set<String> allowedMimeTypes = {
    // PDF
    'application/pdf',
    // Изображения (то, что реально поддерживает Android-галерея)
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/webp',
  };

  /// Разрешённые расширения файлов.
  ///
  /// Нужны для `file_picker` — он фильтрует по расширениям, а не по MIME.
  /// Держим синхронно с `allowedMimeTypes`: если добавили MIME,
  /// добавьте и расширение, и наоборот.
  static const List<String> allowedFileExtensions = [
    'pdf',
    'jpg',
    'jpeg',
    'png',
    'webp',
  ];

  /// Человекочитаемое описание разрешённых форматов — для сообщений об ошибке.
  static const String allowedFormatsDescription = 'PDF, JPG, PNG, WebP';
}
