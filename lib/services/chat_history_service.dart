// lib/services/chat_history_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/chat_session.dart';
import '../models/message.dart';

/// Сервис для работы с историей чатов и сообщениями агентов
class ChatHistoryService {
  final String _baseUrl;

  ChatHistoryService({required String baseUrl}) : _baseUrl = baseUrl;

  /// Получить все чаты агента
  Future<List<ChatSession>> getChats(String agentId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/agents/$agentId/sessions'),
        headers: {'Content-Type': 'application/json'},
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
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => Message.fromJson(json)).toList();
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
        headers: {'Content-Type': 'application/json'},
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
        headers: {'Content-Type': 'application/json'},
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
        headers: {'Content-Type': 'application/json'},
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
