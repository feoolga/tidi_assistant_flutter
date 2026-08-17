// lib/core/network/http_client.dart

import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

/// Единый HTTP клиент для всех запросов к API.
/// 
/// Все сервисы используют этот клиент вместо прямых вызовов http.
/// Это позволяет:
/// 1. Не дублировать заголовки и URL в каждом сервисе
/// 2. Легко добавить логирование всех запросов
/// 3. Централизованно обрабатывать ошибки
/// 4. Легко заменить реализацию (например, на dio)
class AppHttpClient {
  // ============================================================
  // 1. ВНУТРЕННИЙ КЛИЕНТ
  // ============================================================
  
  /// Внутренний HTTP клиент.
  /// 
  /// Используем один экземпляр на всё приложение.
  /// Это позволяет переиспользовать соединения (keep-alive).
  final http.Client _client;
  
  // ============================================================
  // 2. КОНСТРУКТОР
  // ============================================================
  
  /// Создает клиент с настройками из AppConfig.
  AppHttpClient()
      : _client = http.Client();
  
  // ============================================================
  // 3. ОСНОВНЫЕ МЕТОДЫ
  // ============================================================
  
  /// GET-запрос.
  /// 
  /// Пример использования:
  /// ```dart
  /// final response = await client.get('/v1/models');
  /// ```
  Future<http.Response> get(
    String path, {
    Map<String, String>? headers,
  }) async {
    final uri = _buildUri(path);
    final allHeaders = _mergeHeaders(headers);
    
    print('🌐 GET $uri');
    
    try {
      final response = await _client
          .get(uri, headers: allHeaders)
          .timeout(AppConfig.timeout);
      
      print('✅ GET ${response.statusCode}');
      _logResponse(response);
      
      return response;
    } on TimeoutException {
      throw Exception('Превышено время ожидания ответа от сервера');
    } catch (e) {
      throw Exception('Ошибка при выполнении GET-запроса: $e');
    }
  }
  
  /// POST-запрос с JSON-телом.
  /// 
  /// Пример использования:
  /// ```dart
  /// final body = {'model': 'auto', 'messages': [...]};
  /// final response = await client.post('/v1/chat/completions', body: body);
  /// ```
  Future<http.Response> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final uri = _buildUri(path);
    final allHeaders = _mergeHeaders(headers);
    final jsonBody = body != null ? jsonEncode(body) : null;
    
    print('🌐 POST $uri');
    if (body != null) {
      print('📦 Тело: ${jsonBody?.length ?? 0} символов');
    }
    
    try {
      final response = await _client
          .post(
            uri,
            headers: allHeaders,
            body: jsonBody,
          )
          .timeout(AppConfig.timeout);
      
      print('✅ POST ${response.statusCode}');
      _logResponse(response);
      
      return response;
    } on TimeoutException {
      throw Exception('Превышено время ожидания ответа от сервера');
    } catch (e) {
      throw Exception('Ошибка при выполнении POST-запроса: $e');
    }
  }
  
  /// POST-запрос со стрим-ответом (для SSE).
  /// 
  /// Отличается от обычного POST тем, что возвращает StreamedResponse.
  /// Это позволяет читать ответ по частям (токен за токеном).
  /// 
  /// Пример использования:
  /// ```dart
  /// final body = {'model': 'auto', 'messages': [...]};
  /// final response = await client.postStream('/v1/chat/completions', body: body);
  /// ```
  Future<http.StreamedResponse> postStream(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final uri = _buildUri(path);
    final allHeaders = _mergeHeaders(headers, isStream: true);
    final jsonBody = body != null ? jsonEncode(body) : null;
    
    print('🌐 POST (stream) $uri');
    
    try {
      final request = http.Request('POST', uri)
        ..headers.addAll(allHeaders)
        ..body = jsonBody ?? '';
      
      final response = await _client
          .send(request)
          .timeout(AppConfig.streamTimeout);
      
      print('✅ POST (stream) ${response.statusCode}');
      
      return response;
    } on TimeoutException {
      throw Exception('Превышено время ожидания ответа от сервера');
    } catch (e) {
      throw Exception('Ошибка при выполнении POST-запроса (stream): $e');
    }
  }

  /// PATCH-запрос с JSON-телом.
  Future<http.Response> patch(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final uri = _buildUri(path);
    final allHeaders = _mergeHeaders(headers);
    final jsonBody = body != null ? jsonEncode(body) : null;
    
    print('🌐 PATCH $uri');
    
    try {
      final response = await _client
          .patch(
            uri,
            headers: allHeaders,
            body: jsonBody,
          )
          .timeout(AppConfig.timeout);
      
      print('✅ PATCH ${response.statusCode}');
      _logResponse(response);
      
      return response;
    } on TimeoutException {
      throw Exception('Превышено время ожидания ответа от сервера');
    } catch (e) {
      throw Exception('Ошибка при выполнении PATCH-запроса: $e');
    }
  }

  /// DELETE-запрос.
  Future<http.Response> delete(
    String path, {
    Map<String, String>? headers,
  }) async {
    final uri = _buildUri(path);
    final allHeaders = _mergeHeaders(headers);
    
    print('🌐 DELETE $uri');
    
    try {
      final response = await _client
          .delete(uri, headers: allHeaders)
          .timeout(AppConfig.timeout);
      
      print('✅ DELETE ${response.statusCode}');
      _logResponse(response);
      
      return response;
    } on TimeoutException {
      throw Exception('Превышено время ожидания ответа от сервера');
    } catch (e) {
      throw Exception('Ошибка при выполнении DELETE-запроса: $e');
    }
  }
  
  // ============================================================
  // 4. ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ
  // ============================================================
  
  /// Строит полный URI из базового URL и пути.
  Uri _buildUri(String path) {
    // Убираем лишние слэши
    final base = AppConfig.baseUrl.endsWith('/')
        ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
        : AppConfig.baseUrl;
    
    final cleanPath = path.startsWith('/') ? path : '/$path';
    
    return Uri.parse('$base$cleanPath');
  }
  
  /// Объединяет заголовки по умолчанию с переданными.
  Map<String, String> _mergeHeaders(
    Map<String, String>? customHeaders, {
    bool isStream = false,
  }) {
    // Берем заголовки по умолчанию
    final defaultHeaders = isStream
        ? AppConfig.streamHeaders
        : AppConfig.defaultHeaders;
    
    // Добавляем X-User-Id
    final headers = Map<String, String>.from(defaultHeaders)
      ..['X-User-Id'] = AppConfig.userId;
    
    // Добавляем кастомные заголовки (они переопределяют дефолтные)
    if (customHeaders != null) {
      headers.addAll(customHeaders);
    }
    
    return headers;
  }
  
  /// Логирует ответ (только для отладки).
  void _logResponse(http.Response response) {
    if (response.statusCode >= 400) {
      print('❌ Ошибка: ${response.statusCode}');
      print('📄 Тело: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}...');
    }
  }
  
  // ============================================================
  // 5. ЗАКРЫТИЕ КЛИЕНТА
  // ============================================================
  
  /// Закрывает HTTP клиент.
  /// 
  /// Нужно вызывать при завершении приложения.
  /// Но обычно Flutter сам управляет жизненным циклом.
  void close() {
    _client.close();
  }
}