// lib/data/datasources/remote/chat_api.dart

import 'package:http/http.dart' as http;
import '../../../core/network/http_client.dart';

/// API слой для работы с чатом.
class ChatApi {
  final AppHttpClient _httpClient;

  ChatApi({AppHttpClient? httpClient})
    : _httpClient = httpClient ?? AppHttpClient();

  // ============================================================
  // 1. АГЕНТЫ
  // ============================================================

  /// GET /v1/models
  Future<http.Response> getModels() async {
    return await _httpClient.get('/v1/models');
  }

  // ============================================================
  // 2. ЧАТЫ (CONVERSATIONS)
  // ============================================================

  /// POST /agents/{agentId}/v1/platform/conversations
  Future<http.Response> createConversation({
    required String agentId,
    String? title,
  }) async {
    final Map<String, dynamic> body = title != null ? {'title': title} : {};
    return await _httpClient.post(
      '/agents/$agentId/v1/platform/conversations',
      body: body,
    );
  }

  /// GET /agents/{agentId}/v1/platform/conversations
  Future<http.Response> getConversations({required String agentId}) async {
    return await _httpClient.get('/agents/$agentId/v1/platform/conversations');
  }

  /// GET /agents/{agentId}/v1/platform/conversations/{conversationId}/messages
  Future<http.Response> getMessages({
    required String agentId,
    required String conversationId,
  }) async {
    return await _httpClient.get(
      '/agents/$agentId/v1/platform/conversations/$conversationId/messages',
    );
  }

  // ============================================================
  // 3. ОТПРАВКА СООБЩЕНИЙ (RESPONSES API)
  // ============================================================

  /// POST /v1/responses
  Future<http.StreamedResponse> sendMessage({
    required Map<String, dynamic> body,
  }) async {
    return await _httpClient.postStream('/v1/responses', body: body);
  }

  // ============================================================
  // 4. ФИДБЭК
  // ============================================================

  /// POST /agents/{agentId}/v1/chat/completions/{completionId}/feedback
  Future<http.Response> setFeedback({
    required String agentId,
    required String completionId,
    required Map<String, dynamic> body,
  }) async {
    return await _httpClient.post(
      '/agents/$agentId/v1/chat/completions/$completionId/feedback',
      body: body,
    );
  }

  /// GET /agents/{agentId}/v1/chat/completions/{completionId}/feedback
  Future<http.Response> getFeedback({
    required String agentId,
    required String completionId,
  }) async {
    return await _httpClient.get(
      '/agents/$agentId/v1/chat/completions/$completionId/feedback',
    );
  }

  /// DELETE /agents/{agentId}/v1/chat/completions/{completionId}/feedback
  Future<http.Response> deleteFeedback({
    required String agentId,
    required String completionId,
  }) async {
    return await _httpClient.delete(
      '/agents/$agentId/v1/chat/completions/$completionId/feedback',
    );
  }

  // ============================================================
  // 5. ИСТОЧНИКИ
  // ============================================================

  /// GET /agents/{agentId}/v1/chat/completions/{completionId}/sources
  Future<http.Response> getSources({
    required String agentId,
    required String completionId,
  }) async {
    return await _httpClient.get(
      '/agents/$agentId/v1/chat/completions/$completionId/sources',
    );
  }
}
