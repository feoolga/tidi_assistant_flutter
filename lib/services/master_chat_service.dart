import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/message.dart';

class MasterChatService {
  final String _baseUrl;
  final String _userId;

  MasterChatService({
    required String baseUrl,
    String userId = '11111111-1111-1111-1111-111111111111',
  }) : _baseUrl = baseUrl,
       _userId = userId;

  Future<Map<String, dynamic>> sendMessage(String text) async {
    try {
      final uri = Uri.parse('$_baseUrl/chat');
      final body = jsonEncode({'message': text});

      final request = http.Request('POST', uri)
        ..headers.addAll({
          'Content-Type': 'application/json',
          'X-User-Id': _userId,
          'Accept': 'text/event-stream',
        })
        ..body = body;

      final response = await request.send();

      if (response.statusCode != 200) {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }

      // --- СВОЙ ПАРСЕР SSE (без пакета sse) ---
      final stream = response.stream;
      String buffer = '';
      String fullText = '';
      String? messageId;
      String? agentId;
      String? sessionId;

      await for (final chunk in stream) {
        buffer += utf8.decode(chunk);
        final lines = buffer.split('\n');
        buffer = lines.last;

        for (int i = 0; i < lines.length - 1; i++) {
          final line = lines[i];
          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();

            if (data == '[DONE]') {
              break;
            }

            if (data.isEmpty) continue;

            try {
              final json = jsonDecode(data) as Map<String, dynamic>;

              if (json.containsKey('type') && json['type'] == 'metadata') {
                agentId = json['agent_id'] as String?;
                sessionId = json['session_id'] as String?;
                continue;
              }

              if (json.containsKey('token')) {
                fullText += json['token'] as String;
                continue;
              }

              if (json.containsKey('message_id')) {
                messageId = json['message_id'] as String?;
                continue;
              }
            } catch (e) {
              // Если JSON невалидный — пропускаем
              continue;
            }
          }
        }
      }

      return {
        'text': fullText.trim(),
        'messageId': messageId,
        'agentId': agentId,
        'sessionId': sessionId,
      };
    } catch (e) {
      throw Exception('Ошибка при отправке сообщения: $e');
    }
  }

  Future<List<Message>> getMessages() async {
    return [
      Message(
        id: '0',
        text: 'Здравствуйте! Я AI-ассистент. Задайте мне вопрос.',
        isFromUser: false,
        timestamp: DateTime.now(),
      ),
    ];
  }

  Future<void> clearMessages() async {
    return;
  }
}
