// lib/services/master_chat_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/message.dart';
import '../models/agent.dart';

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

class MasterChatService {
  final String _baseUrl;
  final String _userId;

  // Сохраняем текущего агента и сессию для продолжения диалога
  String? _currentAgentId;
  String? _currentSessionId;

  MasterChatService({
    required String baseUrl,
    String userId = '11111111-1111-1111-1111-111111111111',
  }) : _baseUrl = baseUrl,
       _userId = userId;

  /// Отправить сообщение и получить результат
  Future<ChatResult> sendMessage(String text) async {
    try {
      print('🔵 Отправляем сообщение: "$text"');
      
      // Строим URL и тело запроса
      final uri = Uri.parse('$_baseUrl/chat');
      
      // 👇 ФОРМИРУЕМ ТЕЛО ЗАПРОСА
      final Map<String, dynamic> body = {
        'message': text,
      };
      
      // 👇 ЕСЛИ У НАС УЖЕ ЕСТЬ АГЕНТ И СЕССИЯ - ПЕРЕДАЕМ ИХ
      if (_currentAgentId != null && _currentSessionId != null) {
        body['agent_id'] = _currentAgentId;
        body['session_id'] = _currentSessionId;
        print('🔵 Продолжаем диалог с агентом: $_currentAgentId, сессия: $_currentSessionId');
      } else {
        print('🔵 Новый диалог (агент будет определен сервером)');
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
        print('🔴 Ошибка сервера: ${response.statusCode}');
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }

      // 👇 ПОЛУЧАЕМ AGENT_ID И SESSION_ID ИЗ ЗАГОЛОВКОВ
      String? agentId = response.headers['x-agent-id'];
      String? sessionId = response.headers['x-session-id'];
      
      print('🔵 Заголовки ответа:');
      print('   X-Agent-Id: $agentId');
      print('   X-Session-Id: $sessionId');

      // --- Парсим SSE поток ---
      final stream = response.stream;
      String buffer = '';
      String fullText = '';
      String? messageId;

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

              // 👇 ПОЛУЧАЕМ AGENT_ID И SESSION_ID ИЗ METADATA (если нет в заголовках)
              if (json.containsKey('type') && json['type'] == 'metadata') {
                final metaAgentId = json['agent_id'] as String?;
                final metaSessionId = json['session_id'] as String?;
                
                // Если в заголовках не было, берем из metadata
                if (agentId == null && metaAgentId != null) {
                  agentId = metaAgentId;
                  print('🔵 Agent ID из metadata: $agentId');
                }
                if (sessionId == null && metaSessionId != null) {
                  sessionId = metaSessionId;
                  print('🔵 Session ID из metadata: $sessionId');
                }
                continue;
              }

              // Собираем токены
              if (json.containsKey('token')) {
                fullText += json['token'] as String;
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

      // 👇 СОХРАНЯЕМ АГЕНТА И СЕССИЮ ДЛЯ СЛЕДУЮЩИХ ЗАПРОСОВ
      if (agentId != null && sessionId != null) {
        _currentAgentId = agentId;
        _currentSessionId = sessionId;
        print('✅ Сохранен агент: $agentId, сессия: $sessionId');
      } else {
        print('⚠️ Не удалось получить agent_id или session_id');
      }

      return ChatResult(
        text: fullText.trim(),
        messageId: messageId,
        agentId: agentId,
        sessionId: sessionId,
      );
    } catch (e) {
      throw Exception('Ошибка при отправке сообщения: $e');
    }
  }

  /// Очистить текущие данные (для новой сессии)
  void resetSession() {
    _currentAgentId = null;
    _currentSessionId = null;
    print('🔄 Сессия сброшена');
  }

  /// Получить текущий ID агента
  String? get currentAgentId => _currentAgentId;
  
  /// Получить текущий ID сессии
  String? get currentSessionId => _currentSessionId;

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
    resetSession();
    return;
  }
}