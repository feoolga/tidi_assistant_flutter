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
  final String? conversationId;  // 👈 ДОБАВЛЯЕМ

  const ChatResult({
    required this.text,
    this.messageId,
    this.agentId,
    this.sessionId,
    this.conversationId,  // 👈 ДОБАВЛЯЕМ
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

  /// Отправить сообщение с историей
  /// 
  /// [messages] - ВСЯ история диалога (список сообщений)
  /// [conversationId] - ID чата (если есть)
  Future<ChatResult> sendMessage({
    required List<Message> messages,  // 👈 МЕНЯЕМ: теперь принимаем список
    String? conversationId,           // 👈 ДОБАВЛЯЕМ
    String? forceAgentId,             // 👈 если нужно принудительно указать агента
  }) async {
    try {
      print('🔵 Отправляем сообщение с историей (${messages.length} сообщений)');
      
      // ---- 1. Строим список messages для API ----
      final List<Map<String, dynamic>> apiMessages = messages.map((msg) {
        return {
          'role': msg.isFromUser ? 'user' : 'assistant',
          'content': msg.text,
        };
      }).toList();

      // ---- 2. Формируем тело запроса ----
      final Map<String, dynamic> body = {
        'messages': apiMessages,
        'stream': true,
      };

      // ---- 3. Определяем модель ----
      if (conversationId != null && forceAgentId != null) {
        // Продолжаем существующий чат
        body['model'] = forceAgentId;
        body['conversation_id'] = conversationId;
        print('🔵 Продолжаем диалог: агент=$forceAgentId, чат=$conversationId');
      } else {
        // Новый диалог — авто-роутинг
        body['model'] = 'auto';
        print('🔵 Новый диалог (авто-роутинг)');
      }

      // ---- 4. Отправляем запрос ----
      final request = http.Request('POST', Uri.parse('$_baseUrl/v1/chat/completions'))
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

      // ---- 5. Парсим SSE-поток ----
      final stream = response.stream;
      String buffer = '';
      String fullText = '';
      String? messageId;
      String? responseAgentId;
      String? responseConversationId;

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

              // ---- Извлекаем agentId из поля model ----
              if (json.containsKey('model')) {
                final model = json['model'] as String?;
                if (model != null && model != 'auto' && responseAgentId == null) {
                  responseAgentId = model;
                  print('🔵 Агент: $responseAgentId');
                }
              }

              // ---- Извлекаем conversationId ----
              if (json.containsKey('conversation_id')) {
                final convId = json['conversation_id'] as String?;
                if (convId != null && responseConversationId == null) {
                  responseConversationId = convId;
                  print('🔵 conversation_id: $responseConversationId');
                }
              }

              // ---- Собираем токены ----
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

      // ---- 6. Возвращаем результат ----
      String displayText = fullText.trim();

      // Заменяем "Источники:" на "Проанализированные источники:"
      const String oldText = '\n\nИсточники:\n';
      const String newText = '\n\nПроанализированные источники:\n';
      if (displayText.contains(oldText)) {
        displayText = displayText.replaceAll(oldText, newText);
      }

      print('✅ Ответ получен, длина: ${displayText.length} символов');

      return ChatResult(
        text: displayText,
        messageId: messageId,
        agentId: responseAgentId,
        sessionId: responseConversationId,  // 👈 conversation_id — это sessionId
        conversationId: responseConversationId,
      );
    } catch (e) {
      throw Exception('Ошибка при отправке сообщения: $e');
    }
  }

  // ============================================================
  // ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ (оставляем как есть)
  // ============================================================

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