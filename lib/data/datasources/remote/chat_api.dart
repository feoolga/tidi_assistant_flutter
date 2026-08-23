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

  /// Создать новый чат.
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

  /// Получить список чатов.
  /// GET /agents/{agentId}/v1/platform/conversations
  Future<http.Response> getConversations({required String agentId}) async {
    return await _httpClient.get('/agents/$agentId/v1/platform/conversations');
  }

  /// Получить сообщения чата.
  /// GET /agents/{agentId}/v1/platform/conversations/{conversationId}/messages
  Future<http.Response> getMessages({
    required String agentId,
    required String conversationId,
  }) async {
    return await _httpClient.get(
      '/agents/$agentId/v1/platform/conversations/$conversationId/messages',
    );
  }

  /// Отправить сообщение (стрим).
  /// POST /v1/chat/completions
  Future<http.StreamedResponse> sendMessage({
    required Map<String, dynamic> body,
  }) async {
    return await _httpClient.postStream('/v1/chat/completions', body: body);
  }
}
