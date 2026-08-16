// lib/services/chat_history_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/chat_session.dart';
import '../models/message.dart';

/// Сервис для работы с историей чатов и сообщениями агентов.
/// Использует новый OpenAI-совместимый API (контракт v2).
class ChatHistoryService {
  final String _baseUrl;
  final String _userId;

  ChatHistoryService({
    required String baseUrl,
    String userId = '11111111-1111-1111-1111-111111111111',
  }) : _baseUrl = baseUrl,
       _userId = userId;

  // ============================================================
  // ПОЛУЧЕНИЕ ЧАТОВ (CONVERSATIONS)
  // ============================================================

  /// Получить все чаты агента
  /// GET /agents/{agentId}/v1/platform/conversations
  Future<List<ChatSession>> getChats(String agentId) async {
    print('🔵 getChats: agentId=$agentId');
    print('🔵 URL: $_baseUrl/agents/$agentId/v1/platform/conversations');
    
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/agents/$agentId/v1/platform/conversations'),
        headers: {
          'Content-Type': 'application/json',
          'X-User-Id': _userId,
        },
      );

      print('🔵 Статус: ${response.statusCode}');
      print('🔵 Тело: ${response.body}');

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        print('✅ Получено ${data.length} чатов для агента $agentId');
        return data.map((json) => ChatSession.fromJson(json, agentId)).toList();
      } else if (response.statusCode == 404) {
        // Агент не поддерживает чаты (например, OCR)
        print('⚠️ Агент $agentId не поддерживает чаты (404)');
        return [];
      } else {
        throw Exception('Ошибка загрузки чатов: ${response.statusCode}');
      }
    } catch (e) {
      print('⚠️ Не удалось загрузить чаты для агента $agentId: $e');
      return [];
    }
  }

  // ============================================================
  // СОЗДАНИЕ ЧАТА
  // ============================================================

  /// Создать новый чат для агента
  /// POST /agents/{agentId}/v1/platform/conversations
  Future<ChatSession> createChat(String agentId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/agents/$agentId/v1/platform/conversations'),
        headers: {
          'Content-Type': 'application/json',
          'X-User-Id': _userId,
        },
        body: jsonEncode({}), // Тело может быть пустым или с title
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return ChatSession.fromJson(data, agentId);
      } else {
        throw Exception('Ошибка создания чата: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Не удалось создать чат: $e');
    }
  }

  // ============================================================
  // ПОЛУЧЕНИЕ СООБЩЕНИЙ
  // ============================================================

  /// Получить сообщения чата
  /// GET /agents/{agentId}/v1/platform/conversations/{conversationId}/messages
  Future<List<Message>> getMessages(String agentId, String conversationId) async {
    try {
      final response = await http.get(
        Uri.parse(
          '$_baseUrl/agents/$agentId/v1/platform/conversations/$conversationId/messages',
        ),
        headers: {
          'Content-Type': 'application/json',
          'X-User-Id': _userId,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        print('📦 Получены сообщения: ${data.length} шт.');

        return data
            .map((json) {
              try {
                return Message.fromJson(json as Map<String, dynamic>);
              } catch (e) {
                print('❌ Ошибка парсинга сообщения: $e');
                return null;
              }
            })
            .whereType<Message>()
            .toList();
      } else {
        throw Exception('Ошибка загрузки сообщений: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Не удалось загрузить сообщения: $e');
    }
  }

  // ============================================================
  // ПЕРЕИМЕНОВАНИЕ ЧАТА
  // ============================================================

  /// Переименовать чат
  /// PATCH /agents/{agentId}/v1/platform/conversations/{conversationId}
  Future<ChatSession> renameChat(
    String agentId,
    String conversationId,
    String newTitle,
  ) async {
    try {
      final response = await http.patch(
        Uri.parse(
          '$_baseUrl/agents/$agentId/v1/platform/conversations/$conversationId',
        ),
        headers: {
          'Content-Type': 'application/json',
          'X-User-Id': _userId,
        },
        body: jsonEncode({'title': newTitle}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return ChatSession.fromJson(data, agentId);
      } else {
        throw Exception('Ошибка переименования: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Не удалось переименовать чат: $e');
    }
  }

  // ============================================================
  // УДАЛЕНИЕ ЧАТА
  // ============================================================

  /// Удалить чат
  /// DELETE /agents/{agentId}/v1/platform/conversations/{conversationId}
  Future<void> deleteChat(String agentId, String conversationId) async {
    try {
      final response = await http.delete(
        Uri.parse(
          '$_baseUrl/agents/$agentId/v1/platform/conversations/$conversationId',
        ),
        headers: {
          'Content-Type': 'application/json',
          'X-User-Id': _userId,
        },
      );

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('Ошибка удаления чата: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Не удалось удалить чат: $e');
    }
  }
}