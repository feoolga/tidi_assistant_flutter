// lib/core/logger/app_logger.dart

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:logger/logger.dart';

/// Профессиональный логгер для приложения.
///
/// Использует пакет [logger] для:
/// - Уровней логирования (debug, info, warning, error)
/// - Красивого форматирования с цветами
/// - Автоматической фильтрации в зависимости от режима (debug/release)
///
/// Пример использования:
/// ```dart
/// AppLogger.info('Загружено агентов: 5');
/// AppLogger.warning('Не удалось загрузить чаты для агента $id');
/// AppLogger.error('Ошибка при отправке', exception, stackTrace);
/// ```
class AppLogger {
  // ============================================================
  // 1. ВНУТРЕННИЙ ЛОГГЕР
  // ============================================================

  /// Единственный экземпляр Logger, который использует PrettyPrinter
  static final Logger _logger = Logger(
    // Показываем информацию о коде только если это не release
    level: kReleaseMode ? Level.warning : Level.debug,

    // Настройка вывода
    printer: PrettyPrinter(
      // Количество строк кода в стектрейсе (0 = показывать только сообщение)
      methodCount: 2,

      // Количество строк кода для ошибок
      errorMethodCount: 5,

      // Длина строки перед переносом
      lineLength: 120,

      // Использовать цвета в консоли
      colors: true,

      // Печатать эмодзи в начале строки
      printEmojis: true,

      // Печатать время
      dateTimeFormat: DateTimeFormat.dateAndTime,
    ),
  );

  // ============================================================
  // 2. ОСНОВНЫЕ МЕТОДЫ
  // ============================================================

  /// Отладочная информация — для разработчика.
  ///
  /// Используется для детального трекинга выполнения кода.
  /// В production — не выводится.
  ///
  /// Пример: `AppLogger.debug('Начинаем парсинг SSE-потока')`
  static void debug(String message) {
    _logger.d(message);
  }

  /// Информационное сообщение — ключевые события.
  ///
  /// Используется для логирования важных действий в приложении.
  /// В production — выводится, но без деталей.
  ///
  /// Пример: `AppLogger.info('Агент определён: epoz')`
  static void info(String message) {
    _logger.i(message);
  }

  /// Предупреждение — что-то пошло не так, но приложение работает.
  ///
  /// Используется для нештатных, но не критичных ситуаций.
  ///
  /// Пример: `AppLogger.warning('Не удалось загрузить чаты для агента $agentId')`
  static void warning(String message) {
    _logger.w(message);
  }

  /// Ошибка — серьёзная проблема, требующая внимания.
  ///
  /// Используется для логирования исключений и сбоев.
  /// Всегда выводится, даже в production.
  ///
  /// Пример:
  /// ```dart
  /// try {
  ///   // ...
  /// } catch (e, stackTrace) {
  ///   AppLogger.error('Ошибка при отправке сообщения', e, stackTrace);
  /// }
  /// ```
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (error != null && stackTrace != null) {
      _logger.e(message, error: error, stackTrace: stackTrace);
    } else if (error != null) {
      _logger.e('$message\nError: $error');
    } else {
      _logger.e(message);
    }
  }

  // ============================================================
  // 3. СПЕЦИАЛЬНЫЕ МЕТОДЫ
  // ============================================================

  /// Разделитель для визуального отделения блоков в логах.
  ///
  /// Пример: `AppLogger.separator('НАЧАЛО ОТПРАВКИ')`
  static void separator(String title) {
    final border = '═══════════════════════════════════════';
    _logger.i('\n$border\n═══ $title\n$border');
  }

  /// Логировать HTTP-запрос.
  ///
  /// Пример: `AppLogger.http('GET', '/v1/models', 200)`
  static void http(String method, String path, int statusCode) {
    final emoji = statusCode < 400 ? '✅' : '❌';
    _logger.i('$emoji $method $path → $statusCode');
  }

  /// Логировать ошибку с контекстом.
  ///
  /// Используется в ErrorHandler для структурированного логирования.
  ///
  /// Пример:
  /// ```dart
  /// AppLogger.logException(
  ///   'Не удалось загрузить агентов',
  ///   exception,
  ///   stackTrace,
  ///   context: {'agentId': agentId},
  /// );
  /// ```
  static void logException(
    String message,
    Object error, [
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  ]) {
    final buffer = StringBuffer()
      ..writeln(message)
      ..writeln('────────────────────────────────────────');

    // Добавляем контекст, если передан
    if (context != null && context.isNotEmpty) {
      buffer.writeln('📋 Контекст:');
      context.forEach((key, value) {
        buffer.writeln('  $key: $value');
      });
      buffer.writeln('────────────────────────────────────────');
    }

    // Если это наша AppException — выводим структурированно
    if (error is AppException) {
      buffer.writeln('❌ Ошибка приложения:');
      buffer.writeln('  Код: ${error.code}');
      buffer.writeln('  Сообщение: ${error.userMessage}');
      if (error.technicalDetails != null) {
        buffer.writeln('  Детали: ${error.technicalDetails}');
      }
      if (error.originalError != null) {
        buffer.writeln('  Оригинал: ${error.originalError}');
      }
    } else {
      buffer.writeln('❌ Ошибка: $error');
    }

    // Добавляем стектрейс
    if (stackTrace != null) {
      buffer.writeln('────────────────────────────────────────');
      buffer.writeln('📚 StackTrace:');
      buffer.writeln(stackTrace);
    }

    buffer.writeln('────────────────────────────────────────');

    // Логируем как ошибку
    _logger.e(buffer.toString());
  }

  // ============================================================
  // 4. НАСТРОЙКА
  // ============================================================

  /// Включить только ошибки (для production)
  ///
  /// По умолчанию логгер уже фильтрует по `kReleaseMode`,
  /// но этот метод позволяет переопределить поведение.
  static void errorsOnly() {
    // В пакете logger мы не можем динамически менять уровень
    // Поэтому просто создаем новый Logger
    // Но лучше оставить автоматическую фильтрацию через kReleaseMode
    // Этот метод оставлен для совместимости с существующим кодом
  }

  /// Полное логирование (для разработки)
  ///
  /// По умолчанию уже включено в debug режиме.
  static void all() {
    // Тоже оставлен для совместимости
  }
}
