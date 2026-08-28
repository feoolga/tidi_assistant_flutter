// lib/data/datasources/remote/chat_api.dart

import 'package:http/http.dart' as http;
import '../../../core/network/http_client.dart';

/// API слой для работы с чатом.
///
/// Отвечает ТОЛЬКО за HTTP-запросы.
/// Не содержит бизнес-логики.
///
/// Использует AppHttpClient для отправки запросов.
class ChatApi {
  // ============================================================
  // 1. ЗАВИСИМОСТИ
  // ============================================================

  final AppHttpClient _httpClient;

  // ============================================================
  // 2. КОНСТРУКТОР
  // ============================================================

  ChatApi({AppHttpClient? httpClient})
    : _httpClient = httpClient ?? AppHttpClient();

  // ============================================================
  // 3. МЕТОДЫ
  // ============================================================

  /// Получить список агентов.
  /// GET /v1/models
  Future<http.Response> getModels() async {
    return await _httpClient.get('/v1/models');
  }

  // ============================================================
  // 4. РАБОТА С ЧАТАМИ (CONVERSATIONS)
  // ============================================================

  /// Создать новый чат.
  /// POST /v1/platform/conversations
  Future<http.Response> createConversation({String? title}) async {
    final Map<String, dynamic> body = title != null ? {'title': title} : {};
    return await _httpClient.post('/v1/platform/conversations', body: body);
  }

  /// Получить список чатов пользователя.
  /// GET /v1/platform/conversations
  Future<http.Response> getConversations() async {
    return await _httpClient.get('/v1/platform/conversations');
  }

  /// Получить сообщения чата.
  /// GET /v1/platform/conversations/{conversationId}/messages
  Future<http.Response> getMessages({required String conversationId}) async {
    return await _httpClient.get(
      '/v1/platform/conversations/$conversationId/messages',
    );
  }

  // ============================================================
  // 5. ОТПРАВКА СООБЩЕНИЙ
  // ============================================================

  /// Отправить сообщение (стрим) через Responses API.
  /// POST /v1/responses
  Future<http.StreamedResponse> sendMessage({
    required Map<String, dynamic> body,
  }) async {
    return await _httpClient.postStream('/v1/responses', body: body);
  }

  // ============================================================
  // 6. ФИДБЭК И ИСТОЧНИКИ
  // ============================================================

  /// Поставить/обновить оценку ответа.
  /// POST /v1/chat/completions/{completionId}/feedback
  Future<http.Response> setFeedback({
    required String completionId,
    required Map<String, dynamic> body,
  }) async {
    return await _httpClient.post(
      '/v1/chat/completions/$completionId/feedback',
      body: body,
    );
  }

  /// Получить оценку ответа.
  /// GET /v1/chat/completions/{completionId}/feedback
  Future<http.Response> getFeedback({required String completionId}) async {
    return await _httpClient.get('/v1/chat/completions/$completionId/feedback');
  }

  /// Удалить оценку ответа.
  /// DELETE /v1/chat/completions/{completionId}/feedback
  Future<http.Response> deleteFeedback({required String completionId}) async {
    return await _httpClient.delete(
      '/v1/chat/completions/$completionId/feedback',
    );
  }

  /// Получить источники ответа.
  /// GET /v1/chat/completions/{completionId}/sources
  Future<http.Response> getSources({required String completionId}) async {
    return await _httpClient.get('/v1/chat/completions/$completionId/sources');
  }
}
