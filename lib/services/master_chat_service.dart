// lib/services/master_chat_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/message.dart';

/// Результат отправки сообщения
class ChatResult {
  /// Текст ответа от AI
  final String text;

  /// ID сообщения (для будущего фидбэка)
  final String? messageId;

  /// ID агента, который обработал запрос
  final String? agentId;

  /// ID сессии (чата) на сервере
  final String? sessionId;

  const ChatResult({
    required this.text,
    this.messageId,
    this.agentId,
    this.sessionId,
  });

  /// Проверяет, есть ли информация об агенте
  bool get hasAgentInfo => agentId != null && sessionId != null;
}

/// Сервис для работы с мастер-роутингом
///
/// Stateless-сервис: вся информация о сессии передается через параметры.
/// Это делает сервис тестируемым и предсказуемым.
class MasterChatService {
  final String _baseUrl;
  final String _userId;

  MasterChatService({
    required String baseUrl,
    String userId = '11111111-1111-1111-1111-111111111111',
  }) : _baseUrl = baseUrl,
       _userId = userId;

  /// Отправить сообщение и получить результат
  ///
  /// [text] — текст сообщения пользователя
  /// [agentId] — ID агента (если null — используется авто-роутинг)
  /// [sessionId] — ID сессии (conversation_id) для продолжения диалога
  ///
  /// Возвращает [ChatResult] с текстом ответа и информацией о сессии
  Future<ChatResult> sendMessage({
    required String text,
    String? agentId,
    String? sessionId,
  }) async {
    try {
      print('🔵 Отправляем сообщение: "$text"');
      print('🔵 agentId: $agentId, sessionId: $sessionId');

      // 👇 ПРАВИЛЬНЫЙ URL для OpenAI-совместимого API
      final uri = Uri.parse('$_baseUrl/v1/chat/completions');
      print('🔵 URL: $uri');

      // 👇 ФОРМИРУЕМ ТЕЛО ЗАПРОСА В ФОРМАТЕ OPENAI
      final Map<String, dynamic> body = {
        'messages': [
          {'role': 'user', 'content': text}
        ],
        'stream': true,
      };

      // Если у нас есть агент и сессия - передаем их
      if (agentId != null && sessionId != null) {
        body['model'] = agentId;
        body['conversation_id'] = sessionId;
        print('🔵 Продолжаем диалог с агентом: $agentId, сессия: $sessionId');
      } else {
        body['model'] = 'auto'; // 👈 АВТО-РОУТИНГ
        print('🔵 Новый диалог (авто-роутинг)');
      }

      final request = http.Request('POST', uri)
        ..headers.addAll({
          'Content-Type': 'application/json',
          'X-User-Id': _userId,
          'Accept': 'text/event-stream',
        })
        ..body = jsonEncode(body);

      print('🔵 Заголовки: ${request.headers}');
      print('🔵 Тело: ${request.body}');

      final response = await request.send();
      print('🔵 Статус ответа: ${response.statusCode}');

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        print('🔴 Ошибка: $errorBody');
        throw Exception('Ошибка сервера: ${response.statusCode} - $errorBody');
      }

      // 👇 ПОЛУЧАЕМ AGENT_ID И SESSION_ID ИЗ ЗАГОЛОВКОВ
      String? responseAgentId = response.headers['x-agent-id'];
      String? responseSessionId = response.headers['x-session-id'];

      print('🔵 Заголовки ответа:');
      print('   X-Agent-Id: $responseAgentId');
      print('   X-Session-Id: $responseSessionId');

      // --- Парсим SSE поток ---
      final stream = response.stream;
      String buffer = '';
      String fullText = '';
      String? messageId;

      bool hasMetadata = false;

      await for (final chunk in stream) {
        buffer += utf8.decode(chunk, allowMalformed: true);
        final lines = buffer.split('\n');
        buffer = lines.last;

        for (int i = 0; i < lines.length - 1; i++) {
          final line = lines[i];
          // print('🔵 Строка SSE: $line'); // Раскомментировать для отладки
          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();

            if (data == '[DONE]') {
              break;
            }

            if (data.isEmpty) continue;

            try {
              final json = jsonDecode(data) as Map<String, dynamic>;

              // 👇 ПОЛУЧАЕМ AGENT_ID И SESSION_ID ИЗ METADATA (если нет в заголовках)
              if (json.containsKey('type') && json['type'] == 'metadata') {
                hasMetadata = true;

                final metaAgentId = json['agent_id'] as String?;
                final metaSessionId = json['session_id'] as String?;

                // Если в заголовках не было, берем из metadata
                if (responseAgentId == null && metaAgentId != null) {
                  responseAgentId = metaAgentId;
                  print('🔵 Agent ID из metadata: $responseAgentId');
                }
                if (responseSessionId == null && metaSessionId != null) {
                  responseSessionId = metaSessionId;
                  print('🔵 Session ID из metadata: $responseSessionId');
                }
                continue;
              }

              // Собираем токены из OpenAI-формата
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

              // Получаем message_id
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
      print('🔵 hasMetadata: $hasMetadata');
      print('🔵 Итоговый agentId: $responseAgentId');
      print('🔵 Итоговый sessionId: $responseSessionId');
      print(
        '🔵 Итоговый текст: ${fullText.substring(0, fullText.length > 50 ? 50 : fullText.length)}...',
      );

      // 👇 ЗАМЕНА ТЕКСТА ПОСЛЕ СБОРКИ ВСЕГО ОТВЕТА
      String displayText = fullText.trim();

      // Заменяем точную подстроку с переносами
      const String oldText = '\n\nИсточники:\n';
      const String newText = '\n\nПроанализированные источники:\n';

      if (displayText.contains(oldText)) {
        displayText = displayText.replaceAll(oldText, newText);
        print('🔵 Заменен текст источников на: "Проанализированные источники"');
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

  // ============================================================
  // ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ (для совместимости с существующим кодом)
  // ============================================================

  /// Получить список сообщений (заглушка для совместимости)
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

  /// Очистить историю (заглушка для совместимости)
  Future<void> clearMessages() async {
    // Ничего не делаем, так как сервис stateless
    return;
  }
}