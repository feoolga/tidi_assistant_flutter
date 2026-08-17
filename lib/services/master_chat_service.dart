// lib/services/master_chat_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/message.dart';

/// Результат отправки сообщения
class ChatResult {
  final String text;
  final String? messageId;
  final String? agentId;
  final String? sessionId;

  const ChatResult({
    required this.text,
    this.messageId,
    this.agentId,
    this.sessionId,
  });

  bool get hasAgentInfo => agentId != null && sessionId != null;
}

class MasterChatService {
  final String _baseUrl;
  final String _userId;

  MasterChatService({
    required String baseUrl,
    String userId = '11111111-1111-1111-1111-111111111111',
  }) : _baseUrl = baseUrl,
       _userId = userId;

  Future<ChatResult> sendMessage({
    required String text,
    String? agentId,
    String? sessionId,
  }) async {
    try {
      print('🔵 Отправляем сообщение: "$text"');
      print('🔵 agentId: $agentId, sessionId: $sessionId');

      final uri = Uri.parse('$_baseUrl/v1/chat/completions');
      print('🔵 URL: $uri');

      final Map<String, dynamic> body = {
        'messages': [
          {'role': 'user', 'content': text}
        ],
        'stream': true,
      };

      if (agentId != null && sessionId != null) {
        body['model'] = agentId;
        body['conversation_id'] = sessionId;
        print('🔵 Продолжаем диалог с агентом: $agentId, сессия: $sessionId');
      } else {
        body['model'] = 'auto';
        print('🔵 Новый диалог (авто-роутинг)');
      }

      final request = http.Request('POST', uri)
        ..headers.addAll({
          'Content-Type': 'application/json',
          'X-User-Id': _userId,
          'Accept': 'text/event-stream',
        })
        ..body = jsonEncode(body);

      final response = await request.send();

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        throw Exception('Ошибка сервера: ${response.statusCode} - $errorBody');
      }

      final stream = response.stream;
      String buffer = '';
      String fullText = '';
      String? messageId;
      String? responseAgentId;
      String? responseSessionId;

      await for (final chunk in stream) {
        buffer += utf8.decode(chunk, allowMalformed: true);
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

              // 👇 ИЗВЛЕКАЕМ AGENT_ID ИЗ ПОЛЯ model
              if (json.containsKey('model')) {
                final model = json['model'] as String?;
                if (model != null && model != 'auto' && responseAgentId == null) {
                  responseAgentId = model;
                  print('🔵 Agent ID из model: $responseAgentId');
                }
              }

              // 👇 ИЗВЛЕКАЕМ SESSION_ID ИЗ ПОЛЯ id
              if (json.containsKey('id')) {
                final id = json['id'] as String?;
                if (id != null && responseSessionId == null) {
                  if (id.startsWith('chatcmpl-')) {
                    responseSessionId = id.substring(8);
                  } else if (id.startsWith('resp_')) {
                    responseSessionId = id.substring(5);
                  } else {
                    responseSessionId = id;
                  }
                  print('🔵 Session ID из id: $responseSessionId');
                }
              }

              // 👇 ИЗВЛЕКАЕМ SESSION_ID ИЗ conversation_id
              if (json.containsKey('conversation_id')) {
                final convId = json['conversation_id'] as String?;
                if (convId != null && responseSessionId == null) {
                  responseSessionId = convId;
                  print('🔵 Session ID из conversation_id: $responseSessionId');
                }
              }

              // Собираем токены
              if (json.containsKey('choices')) {
                final choices = json['choices'] as List<dynamic>?;
                if (choices != null && choices.isNotEmpty) {
                  final choice = choices.first as Map<String, dynamic>;
                  final delta = choice['delta'] as Map<String, dynamic>?;
                  if (delta != null) {
                    final content = delta['content'] as String?;
                    if (content != null && content.isNotEmpty) {
                      fullText += content;
                    }
                  }
                }
                continue;
              }

              if (json.containsKey('message_id')) {
                messageId = json['message_id'] as String?;
                continue;
              }
            } catch (e) {
              print('🔴 Ошибка парсинга JSON: $e');
              continue;
            }
          }
        }
      }

      print('🔵 Парсинг SSE завершен');
      print('🔵 Итоговый agentId: $responseAgentId');
      print('🔵 Итоговый sessionId: $responseSessionId');

      String displayText = fullText.trim();

      const String oldText = '\n\nИсточники:\n';
      const String newText = '\n\nПроанализированные источники:\n';

      if (displayText.contains(oldText)) {
        displayText = displayText.replaceAll(oldText, newText);
      }

      return ChatResult(
        text: displayText,
        messageId: messageId,
        agentId: responseAgentId,
        sessionId: responseSessionId,
      );
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