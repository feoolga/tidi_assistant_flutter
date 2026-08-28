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
}
