/// Простой логгер для приложения.
///
/// Позволяет:
/// 1. Разделять логи по уровням (debug, info, warning, error)
/// 2. Включать/выключать отдельные уровни
/// 3. Полностью отключить логирование в production
/// 4. Иметь единый формат вывода
class AppLogger {
  // ============================================================
  // 1. НАСТРОЙКИ
  // ============================================================

  /// Глобальный переключатель: включен ли логгер вообще
  static bool isEnabled = true;

  /// Показывать отладочную информацию (самый подробный уровень)
  static bool showDebug = true;

  /// Показывать информационные сообщения
  static bool showInfo = true;

  /// Показывать предупреждения
  static bool showWarnings = true;

  /// Показывать ошибки (обычно всегда включено)
  static bool showErrors = true;

  // ============================================================
  // 2. МЕТОДЫ ЛОГИРОВАНИЯ
  // ============================================================

  /// Отладочная информация — для разработчика.
  ///
  /// Пример: AppLogger.debug('Начинаем парсинг SSE-потока');
  static void debug(String message) {
    if (isEnabled && showDebug) {
      print('🔍 DEBUG: $message');
    }
  }

  /// Информационное сообщение — ключевые события.
  ///
  /// Пример: AppLogger.info('Агент определён: $model');
  static void info(String message) {
    if (isEnabled && showInfo) {
      print('ℹ️ INFO: $message');
    }
  }

  /// Предупреждение — что-то пошло не так, но приложение работает.
  ///
  /// Пример: AppLogger.warning('Не удалось загрузить чаты для агента $agentId');
  static void warning(String message) {
    if (isEnabled && showWarnings) {
      print('⚠️ WARNING: $message');
    }
  }

  /// Ошибка — серьёзная проблема.
  ///
  /// Пример: AppLogger.error('Ошибка при отправке сообщения', e);
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (isEnabled && showErrors) {
      print('❌ ERROR: $message');
      if (error != null) {
        print('   Details: $error');
      }
      if (stackTrace != null) {
        print('   Stack: $stackTrace');
      }
    }
  }

  // ============================================================
  // 3. СПЕЦИАЛЬНЫЕ МЕТОДЫ
  // ============================================================

  /// Разделитель для визуального отделения блоков
  ///
  /// Пример: AppLogger.separator('НАЧАЛО ОТПРАВКИ');
  static void separator(String title) {
    if (isEnabled) {
      print('');
      print('═══════════════════════════════════════');
      print('═══ $title');
      print('═══════════════════════════════════════');
    }
  }

  /// Логировать HTTP-запрос
  ///
  /// Пример: AppLogger.http('GET', '/v1/models', 200);
  static void http(String method, String path, int statusCode) {
    if (isEnabled && showInfo) {
      final emoji = statusCode < 400 ? '✅' : '❌';
      print('$emoji $method $path → $statusCode');
    }
  }

  // ============================================================
  // 4. НАСТРОЙКА ДЛЯ PRODUCTION
  // ============================================================

  /// Выключить всё логирование (для production-сборки)
  static void disableAll() {
    isEnabled = false;
  }

  /// Включить только ошибки (для production с отладкой)
  static void errorsOnly() {
    isEnabled = true;
    showDebug = false;
    showInfo = false;
    showWarnings = false;
    showErrors = true;
  }

  /// Полное логирование (для разработки)
  static void all() {
    isEnabled = true;
    showDebug = true;
    showInfo = true;
    showWarnings = true;
    showErrors = true;
  }
}
