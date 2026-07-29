// lib/services/chat_history_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/chat_session.dart';
import '../models/message.dart';

/// Сервис для работы с историей чатов и сообщениями агентов
class ChatHistoryService {
  final String _baseUrl;
  final String _userId;

  ChatHistoryService({
    required String baseUrl,
    String userId =
        '11111111-1111-1111-1111-111111111111', // 👈 ЗНАЧЕНИЕ ПО УМОЛЧАНИЮ
  }) : _baseUrl = baseUrl,
       _userId = userId;

  /// Получить все чаты агента
  Future<List<ChatSession>> getChats(String agentId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/agents/$agentId/sessions'),
        headers: {
          'Content-Type': 'application/json',
          'X-User-Id': _userId, // 👈 ДОБАВЛЯЕМ
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => ChatSession.fromJson(json, agentId)).toList();
      } else {
        throw Exception('Ошибка загрузки чатов: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Не удалось загрузить чаты: $e');
    }
  }

  /// Получить сообщения чата
  Future<List<Message>> getMessages(String agentId, String chatId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/agents/$agentId/sessions/$chatId/messages'),
        headers: {'Content-Type': 'application/json', 'X-User-Id': _userId},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        print('📦 Получены сообщения: ${data.length} шт.');
        print('📦 Первое сообщение: ${data.isNotEmpty ? data.first : 'нет'}');

        return data
            .map((json) {
              // 👇 ДОБАВЛЯЕМ ПРОВЕРКУ
              try {
                return Message.fromJson(json as Map<String, dynamic>);
              } catch (e) {
                print('❌ Ошибка парсинга сообщения: $e');
                print('❌ JSON: $json');
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

  /// Создать новый чат для агента
  Future<ChatSession> createChat(String agentId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/agents/$agentId/sessions'),
        headers: {
          'Content-Type': 'application/json',
          'X-User-Id': _userId, // 👈 ДОБАВЛЯЕМ
        },
        body: jsonEncode({}),
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

  /// Удалить чат
  Future<void> deleteChat(String agentId, String chatId) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/agents/$agentId/sessions/$chatId'),
        headers: {
          'Content-Type': 'application/json',
          'X-User-Id': _userId, // 👈 ДОБАВЛЯЕМ
        },
      );

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('Ошибка удаления чата: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Не удалось удалить чат: $e');
    }
  }

  /// Переименовать чат
  Future<ChatSession> renameChat(
    String agentId,
    String chatId,
    String newTitle,
  ) async {
    try {
      final response = await http.patch(
        Uri.parse('$_baseUrl/agents/$agentId/sessions/$chatId'),
        headers: {
          'Content-Type': 'application/json',
          'X-User-Id': _userId, // 👈 ДОБАВЛЯЕМ
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
}
