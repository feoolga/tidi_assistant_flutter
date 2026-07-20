import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/message.dart';

class ChatService {
  final String _baseUrl;

  // !!! ЗДЕСЬ ЗАМЕНИ IP НА СВОЙ !!!
  ChatService({String baseUrl = 'http://192.168.1.88:5000'}) : _baseUrl = baseUrl;

  // Получить все сообщения
  Future<List<Message>> getMessages() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/messages'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> messagesJson = data['messages'];
        return messagesJson.map((json) => Message.fromJson(json)).toList();
      } else {
        throw Exception('Ошибка загрузки сообщений: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Не удалось загрузить сообщения: $e');
    }
  }

  // Отправить сообщение
  Future<Map<String, Message>> sendMessage(String text) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'user': Message.fromJson(data['user_message']),
          'ai': Message.fromJson(data['ai_message']),
        };
      } else {
        throw Exception('Ошибка отправки: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Не удалось отправить сообщение: $e');
    }
  }

  // Очистить историю
  Future<void> clearMessages() async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/clear'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode != 200) {
        throw Exception('Ошибка очистки: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Не удалось очистить историю: $e');
    }
  }
}