// lib/services/openai_chat_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/message.dart';

/// Результат отправки сообщения через OpenAI-совместимый API
class OpenAIChatResult {
  /// Текст ответа от AI (собранный из токенов)
  final String text;

  /// ID завершения (completion_id) — нужен для фидбэка
  final String? completionId;

  /// ID агента, который ответил (поле "model" в ответе)
  final String? agentId;

  /// ID сессии/чата (conversation_id)
  final String? conversationId;

  const OpenAIChatResult({
    required this.text,
    this.completionId,
    this.agentId,
    this.conversationId,
  });

  /// Проверяет, есть ли информация об агенте
  bool get hasAgentInfo => agentId != null && conversationId != null;

  @override
  String toString() {
    return 'OpenAIChatResult(text: "${text.length > 30 ? text.substring(0, 30) + "..." : text}", '
        'completionId: $completionId, agentId: $agentId, conversationId: $conversationId)';
  }
}

/// Сервис для работы с OpenAI-совместимым API мастера
/// 
/// Пример запроса:
/// ```json
/// {
///   "model": "auto",  // или конкретный agent_id
///   "messages": [{"role": "user", "content": "вопрос"}],
///   "stream": true
/// }
/// ```
class OpenAIChatService {
  final String _baseUrl;
  final String _userId;

  // Текущая сессия для продолжения диалога
  String? _currentAgentId;
  String? _currentConversationId;

  OpenAIChatService({
    required String baseUrl,
    String userId = '11111111-1111-1111-1111-111111111111',
  }) : _baseUrl = baseUrl,
       _userId = userId;

  // ============================================================
  // ПУБЛИЧНЫЕ МЕТОДЫ
  // ============================================================

  /// Отправить сообщение и получить результат
  Future<OpenAIChatResult> sendMessage(String text) async {
    try {
      print('🔵 Отправляем сообщение (OpenAI API): "$text"');

      // Строим тело запроса в формате OpenAI
      final body = _buildRequestBody(text);

      // Отправляем запрос
      final response = await _sendRequest(body);

      // Парсим SSE-поток
      final result = await _parseSSEStream(response);

      // Сохраняем агента и сессию для следующих запросов
      _updateSession(result);

      return result;
    } catch (e) {
      throw Exception('Ошибка при отправке сообщения: $e');
    }
  }

  /// Очистить текущие данные (для новой сессии)
  void resetSession() {
    _currentAgentId = null;
    _currentConversationId = null;
    print('🔄 Сессия сброшена (OpenAI)');
  }

  /// Получить текущий ID агента
  String? get currentAgentId => _currentAgentId;

  /// Получить текущий ID сессии
  String? get currentConversationId => _currentConversationId;

  /// Установить текущую сессию (для продолжения диалога)
  void setSession(String agentId, String conversationId) {
    _currentAgentId = agentId;
    _currentConversationId = conversationId;
    print('🔵 Установлена сессия: агент=$agentId, сессия=$conversationId');
  }

  // ============================================================
  // ПРИВАТНЫЕ МЕТОДЫ
  // ============================================================

  /// Формирует тело запроса в формате OpenAI
  Map<String, dynamic> _buildRequestBody(String text) {
    final body = <String, dynamic>{
      'messages': [
        {'role': 'user', 'content': text}
      ],
      'stream': true,
    };

    // Если есть текущий агент — используем его, иначе авто-роутинг
    if (_currentAgentId != null && _currentConversationId != null) {
      body['model'] = _currentAgentId;
      body['conversation_id'] = _currentConversationId;
      print('🔵 Продолжаем диалог: агент=$_currentAgentId, сессия=$_currentConversationId');
    } else {
      body['model'] = 'auto';
      print('🔵 Новый диалог (авто-роутинг)');
    }

    return body;
  }

  /// Отправляет запрос и возвращает потоковый ответ
  Future<http.StreamedResponse> _sendRequest(Map<String, dynamic> body) async {
    final uri = Uri.parse('$_baseUrl/v1/chat/completions');
    print('🔵 URL: $uri');

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
      // Пытаемся прочитать тело ошибки
      final errorBody = await response.stream.bytesToString();
      print('🔴 Ошибка: $errorBody');
      throw Exception('Ошибка сервера: ${response.statusCode} - $errorBody');
    }

    return response;
  }

  /// Парсит SSE-поток в формате OpenAI
  Future<OpenAIChatResult> _parseSSEStream(http.StreamedResponse response) async {
    final stream = response.stream;
    String buffer = '';
    String fullText = '';
    String? completionId;
    String? agentId;
    String? conversationId;

    print('🔵 Начинаем парсинг SSE-потока...');

    await for (final chunk in stream) {
      buffer += utf8.decode(chunk, allowMalformed: true);
      final lines = buffer.split('\n');
      buffer = lines.last;

      for (int i = 0; i < lines.length - 1; i++) {
        final line = lines[i];
        if (line.startsWith('data: ')) {
          final data = line.substring(6).trim();

          if (data == '[DONE]') {
            print('🔵 Получен [DONE]');
            break;
          }

          if (data.isEmpty) continue;

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            print('🔵 RAW JSON: $json');

            // --- Извлекаем agent_id из поля "model" ---
            if (json.containsKey('model')) {
              final model = json['model'] as String?;
              if (model != null && model != 'auto') {
                agentId = model;
                print('🔵 Agent ID (из model): $agentId');
              }
            }

            // --- Извлекаем completion_id ---
            if (json.containsKey('id')) {
              final id = json['id'] as String?;
              if (id != null && id.startsWith('chatcmpl-')) {
                completionId = id;
                print('🔵 Completion ID: $completionId');
              }
            }

            // --- Извлекаем conversation_id (если есть) ---
            if (json.containsKey('conversation_id')) {
              conversationId = json['conversation_id'] as String?;
              print('🔵 Conversation ID: $conversationId');
            }

            // --- Собираем токены ---
            if (json.containsKey('choices')) {
              final choices = json['choices'] as List<dynamic>?;
              if (choices != null && choices.isNotEmpty) {
                final choice = choices.first as Map<String, dynamic>;
                final delta = choice['delta'] as Map<String, dynamic>?;
                if (delta != null) {
                  final content = delta['content'] as String?;
                  if (content != null) {
                    fullText += content;
                    // print('🔵 Токен: "$content"');
                  }
                }
              }
            }
          } catch (e) {
            print('🔴 Ошибка парсинга JSON: $e');
            continue;
          }
        }
      }
    }

    print('🔵 Парсинг SSE завершен');
    print('🔵 Итоговый текст: ${fullText.length > 50 ? fullText.substring(0, 50) + "..." : fullText}');
    print('🔵 agentId: $agentId');
    print('🔵 conversationId: $conversationId');
    print('🔵 completionId: $completionId');

    // Замена текста "Источники:" на "Проанализированные источники:"
    String displayText = fullText.trim();
    const String oldText = '\n\nИсточники:\n';
    const String newText = '\n\nПроанализированные источники:\n';
    if (displayText.contains(oldText)) {
      displayText = displayText.replaceAll(oldText, newText);
      print('🔵 Заменен текст источников');
    }

    return OpenAIChatResult(
      text: displayText,
      completionId: completionId,
      agentId: agentId,
      conversationId: conversationId,
    );
  }

  /// Сохраняет агента и сессию для следующих запросов
  void _updateSession(OpenAIChatResult result) {
    if (result.agentId != null && result.conversationId != null) {
      _currentAgentId = result.agentId;
      _currentConversationId = result.conversationId;
      print('✅ Сохранен агент: ${result.agentId}, сессия: ${result.conversationId}');
    } else {
      print('⚠️ Не удалось получить agent_id или conversation_id');
    }
  }

  // ============================================================
  // МЕТОДЫ ДЛЯ СОВМЕСТИМОСТИ СО СТАРЫМ КОДОМ
  // ============================================================

  /// Заглушка для getMessages (будет заменена на реальную)
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

  /// Заглушка для clearMessages
  Future<void> clearMessages() async {
    resetSession();
    return;
  }
}