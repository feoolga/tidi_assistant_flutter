// lib/services/master_chat_service.dart

import 'dart:convert';
import '../models/message.dart';
import '../core/network/http_client.dart';
import '../core/config/app_config.dart';

/// Результат отправки сообщения
class ChatResult {
  final String text;
  final String? messageId;
  final String? agentId;
  final String? sessionId;
  final String? conversationId;

  const ChatResult({
    required this.text,
    this.messageId,
    this.agentId,
    this.sessionId,
    this.conversationId,
  });

  bool get hasAgentInfo => agentId != null && sessionId != null;
}

/// Сервис для работы с мастер-роутером.
/// 
/// Отправляет сообщения через /v1/chat/completions,
/// парсит SSE-поток и возвращает готовый ответ.
class MasterChatService {
  // ============================================================
  // 1. ЗАВИСИМОСТИ
  // ============================================================
  
  /// HTTP клиент для отправки запросов
  final AppHttpClient _httpClient;
  
  /// Базовый URL (оставляем для обратной совместимости)
  final String _baseUrl;
  
  // ============================================================
  // 2. КОНСТРУКТОР
  // ============================================================
  
  /// Создает сервис с HTTP клиентом.
  MasterChatService({
    String? baseUrl,
    AppHttpClient? httpClient,
  })  : _baseUrl = baseUrl ?? AppConfig.baseUrl,
        _httpClient = httpClient ?? AppHttpClient();
  
  // ============================================================
  // 3. ОТПРАВКА СООБЩЕНИЯ
  // ============================================================
  
  /// Отправить сообщение с историей.
  /// 
  /// [messages] - ВСЯ история диалога (список сообщений)
  /// [conversationId] - ID чата (если есть)
  /// [forceAgentId] - если нужно принудительно указать агента
  Future<ChatResult> sendMessage({
    required List<Message> messages,
    String? conversationId,
    String? forceAgentId,
  }) async {
    try {
      print('🔵 MasterChatService: отправка сообщения (${messages.length} сообщений)');
      
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
        print('🔵 MasterChatService: продолжаем диалог (агент=$forceAgentId, чат=$conversationId)');
      } else {
        // Новый диалог — авто-роутинг
        body['model'] = 'auto';
        print('🔵 MasterChatService: новый диалог (авто-роутинг)');
      }

      // ---- 4. Отправляем запрос через наш клиент ----
      final response = await _httpClient.postStream(
        '/v1/chat/completions',
        body: body,
      );

      // Проверяем статус ответа
      if (response.statusCode != 200) {
        // Если ошибка - читаем тело ошибки
        final errorBody = await response.stream.bytesToString();
        throw Exception('Ошибка сервера: ${response.statusCode} - $errorBody');
      }

      // ---- 5. Парсим SSE-поток ----
      return await _parseSseStream(response.stream);
      
    } catch (e) {
      print('❌ MasterChatService: ошибка: $e');
      throw Exception('Ошибка при отправке сообщения: $e');
    }
  }
  
  // ============================================================
  // 4. ПАРСИНГ SSE-ПОТОКА
  // ============================================================
  
  /// Парсит SSE-поток и собирает ответ.
  /// 
  /// Возвращает ChatResult с полным текстом и метаданными.
  Future<ChatResult> _parseSseStream(Stream<List<int>> stream) async {
    String buffer = '';
    String fullText = '';
    String? messageId;
    String? responseAgentId;
    String? responseConversationId;

    // Читаем поток по частям
    await for (final chunk in stream) {
      // Декодируем байты в строку
      buffer += utf8.decode(chunk, allowMalformed: true);
      
      // Разбиваем на строки
      final lines = buffer.split('\n');
      buffer = lines.last; // Последняя строка может быть неполной

      // Обрабатываем все полные строки
      for (int i = 0; i < lines.length - 1; i++) {
        final line = lines[i];
        
        // Ищем строки с data:
        if (line.startsWith('data: ')) {
          final data = line.substring(6).trim();

          // Проверяем на завершение потока
          if (data == '[DONE]') {
            print('🔵 MasterChatService: поток завершен [DONE]');
            break;
          }

          // Пропускаем пустые строки
          if (data.isEmpty) continue;

          try {
            // Парсим JSON
            final json = jsonDecode(data) as Map<String, dynamic>;

            // ---- Извлекаем agentId из поля model ----
            if (json.containsKey('model')) {
              final model = json['model'] as String?;
              if (model != null && model != 'auto' && responseAgentId == null) {
                responseAgentId = model;
                print('🔵 MasterChatService: агент определен: $responseAgentId');
              }
            }

            // ---- Извлекаем conversationId ----
            if (json.containsKey('conversation_id')) {
              final convId = json['conversation_id'] as String?;
              if (convId != null && responseConversationId == null) {
                responseConversationId = convId;
                print('🔵 MasterChatService: conversation_id: $responseConversationId');
              }
            }

            // ---- Извлекаем id сообщения ----
            if (json.containsKey('id')) {
              final id = json['id'] as String?;
              if (id != null && messageId == null) {
                messageId = id;
              }
            }

            // ---- Собираем токены из choices ----
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
            }
            
          } catch (e) {
            print('⚠️ MasterChatService: ошибка парсинга JSON: $e');
            print('📄 Строка: $data');
            continue;
          }
        }
      }
    }

    // ---- 6. Формируем результат ----
    String displayText = fullText.trim();

    // Заменяем "Источники:" на "Проанализированные источники:"
    const String oldText = '\n\nИсточники:\n';
    const String newText = '\n\nПроанализированные источники:\n';
    if (displayText.contains(oldText)) {
      displayText = displayText.replaceAll(oldText, newText);
    }

    print('✅ MasterChatService: ответ получен (${displayText.length} символов)');
    print('🔵 MasterChatService: агент=$responseAgentId, чат=$responseConversationId');

    return ChatResult(
      text: displayText,
      messageId: messageId,
      agentId: responseAgentId,
      sessionId: responseConversationId,
      conversationId: responseConversationId,
    );
  }

  // ============================================================
  // 5. ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ (для обратной совместимости)
  // ============================================================
  
  /// Заглушка для получения сообщений.
  /// 
  /// Пока возвращает приветственное сообщение.
  /// Позже можно будет загружать реальную историю.
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

  /// Заглушка для очистки сообщений.
  Future<void> clearMessages() async {
    return;
  }
}