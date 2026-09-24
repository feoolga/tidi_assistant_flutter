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

  /// POST /route — определить, какого агента выберет роутер.
  ///
  /// НЕ вызывает агента и ничего не генерирует — только прогоняет текст
  /// через роутер мастера и возвращает решение `{"agent": "<agent_id>"}`.
  ///
  /// Используется при открытии нового чата, чтобы заранее узнать
  /// `agent_id`: с ним создаётся чат (`POST /agents/{id}/.../conversations`)
  /// и дальше все сообщения идут в `POST /v1/responses` с явным `model`.
  ///
  /// Вызывается один раз на чат — на первом сообщении пользователя.
  /// Дальше `agent_id` фиксирован и известен из `sessionProvider`.
  Future<http.Response> route({required String message}) async {
    return await _httpClient.post('/route', body: {'message': message});
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

  /// PATCH /agents/{agentId}/v1/platform/conversations/{conversationId}
  ///
  /// Переименовать чат.
  ///
  /// **Тело:** `{ "title": "<новое название>" }`.
  /// **Успех:** `200` с обновлённым объектом чата
  /// (`id`, `title`, `created_at`, `updated_at`).
  /// **Ошибки:** `404`, если чат не найден или чужой; `400`,
  /// если `title` невалидный (например, пустая строка — на стороне
  /// бэкенда это может быть отдельное правило).
  ///
  /// **Разбор ответа и статусов — задача `ChatRepository`,
  /// не этого метода.**
  Future<http.Response> renameConversation({
    required String agentId,
    required String conversationId,
    required String title,
  }) async {
    return await _httpClient.patch(
      '/agents/$agentId/v1/platform/conversations/$conversationId',
      body: {'title': title},
    );
  }

  /// DELETE /agents/{agentId}/v1/platform/conversations/{conversationId}
  ///
  /// Удалить чат со всей его историей.
  ///
  /// Каскадно удаляются сообщения чата и их фидбэк
  /// (см. README `document_chat`, раздел «Чаты»).
  ///
  /// **Успех:** `204 No Content` — тело пустое.
  /// **Ошибки:** `404`, если чат не найден или чужой.
  ///
  /// **Разбор ответа и статусов — задача `ChatRepository`.**
  Future<http.Response> deleteConversation({
    required String agentId,
    required String conversationId,
  }) async {
    return await _httpClient.delete(
      '/agents/$agentId/v1/platform/conversations/$conversationId',
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
