// lib/services/chat_history_service.dart

import 'dart:convert';
import '../models/chat_session.dart';
import '../models/message.dart';
import '../core/network/http_client.dart';
import '../core/config/app_config.dart';

/// Сервис для работы с историей чатов и сообщениями агентов.
/// 
/// Использует новый OpenAI-совместимый API (контракт v2).
/// Все запросы идут через единый HTTP клиент.
class ChatHistoryService {
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
  ChatHistoryService({
    String? baseUrl,
    AppHttpClient? httpClient,
  })  : _baseUrl = baseUrl ?? AppConfig.baseUrl,
        _httpClient = httpClient ?? AppHttpClient();
  
  // ============================================================
  // 3. ПОЛУЧЕНИЕ ЧАТОВ (CONVERSATIONS)
  // ============================================================
  
  /// Получить все чаты агента.
  /// 
  /// GET /agents/{agentId}/v1/platform/conversations
  Future<List<ChatSession>> getChats(String agentId) async {
    print('🔵 ChatHistoryService: getChats для агента $agentId');
    
    try {
      // ---- 1. Отправляем GET-запрос через наш клиент ----
      final response = await _httpClient.get(
        '/agents/$agentId/v1/platform/conversations',
      );
      
      print('🔵 ChatHistoryService: статус ${response.statusCode}');
      
      // ---- 2. Обрабатываем ответ ----
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        print('✅ ChatHistoryService: получено ${data.length} чатов');
        return data
            .map((json) => ChatSession.fromJson(json, agentId))
            .toList();
      } else if (response.statusCode == 404) {
        // Агент не поддерживает чаты (например, OCR)
        print('⚠️ ChatHistoryService: агент $agentId не поддерживает чаты (404)');
        return [];
      } else {
        throw Exception('Ошибка загрузки чатов: ${response.statusCode}');
      }
    } catch (e) {
      print('⚠️ ChatHistoryService: ошибка для агента $agentId: $e');
      return []; // Возвращаем пустой список, чтобы не ломать UI
    }
  }
  
  // ============================================================
  // 4. СОЗДАНИЕ ЧАТА
  // ============================================================
  
  /// Создать новый чат для агента.
  /// 
  /// POST /agents/{agentId}/v1/platform/conversations
  Future<ChatSession> createChat(String agentId) async {
    print('🔵 ChatHistoryService: createChat для агента $agentId');
    
    try {
      // ---- 1. Отправляем POST-запрос через наш клиент ----
      final response = await _httpClient.post(
        '/agents/$agentId/v1/platform/conversations',
        body: {}, // Тело может быть пустым или с title
      );
      
      print('🔵 ChatHistoryService: статус ${response.statusCode}');
      
      // ---- 2. Обрабатываем ответ ----
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        print('✅ ChatHistoryService: чат создан');
        return ChatSession.fromJson(data, agentId);
      } else {
        throw Exception('Ошибка создания чата: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Не удалось создать чат: $e');
    }
  }
  
  // ============================================================
  // 5. ПОЛУЧЕНИЕ СООБЩЕНИЙ
  // ============================================================
  
  /// Получить сообщения чата.
  /// 
  /// GET /agents/{agentId}/v1/platform/conversations/{conversationId}/messages
  Future<List<Message>> getMessages(
    String agentId,
    String conversationId,
  ) async {
    print('🔵 ChatHistoryService: getMessages для чата $conversationId');
    
    try {
      // ---- 1. Отправляем GET-запрос через наш клиент ----
      final response = await _httpClient.get(
        '/agents/$agentId/v1/platform/conversations/$conversationId/messages',
      );
      
      print('🔵 ChatHistoryService: статус ${response.statusCode}');
      
      // ---- 2. Обрабатываем ответ ----
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        print('✅ ChatHistoryService: получено ${data.length} сообщений');
        
        // Парсим каждое сообщение, пропуская ошибочные
        return data
            .map((json) {
              try {
                return Message.fromJson(json as Map<String, dynamic>);
              } catch (e) {
                print('❌ ChatHistoryService: ошибка парсинга сообщения: $e');
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
  
  // ============================================================
  // 6. ПЕРЕИМЕНОВАНИЕ ЧАТА
  // ============================================================
  
  /// Переименовать чат.
  /// 
  /// PATCH /agents/{agentId}/v1/platform/conversations/{conversationId}
  Future<ChatSession> renameChat(
    String agentId,
    String conversationId,
    String newTitle,
  ) async {
    print('🔵 ChatHistoryService: renameChat $conversationId -> "$newTitle"');
    
    try {
      // ---- 1. Отправляем PATCH-запрос через наш клиент ----
      final response = await _httpClient.patch(
        '/agents/$agentId/v1/platform/conversations/$conversationId',
        body: {'title': newTitle},
      );
      
      print('🔵 ChatHistoryService: статус ${response.statusCode}');
      
      // ---- 2. Обрабатываем ответ ----
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ ChatHistoryService: чат переименован');
        return ChatSession.fromJson(data, agentId);
      } else {
        throw Exception('Ошибка переименования: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Не удалось переименовать чат: $e');
    }
  }
  
  // ============================================================
  // 7. УДАЛЕНИЕ ЧАТА
  // ============================================================
  
  /// Удалить чат.
  /// 
  /// DELETE /agents/{agentId}/v1/platform/conversations/{conversationId}
  Future<void> deleteChat(
    String agentId,
    String conversationId,
  ) async {
    print('🔵 ChatHistoryService: deleteChat $conversationId');
    
    try {
      // ---- 1. Отправляем DELETE-запрос через наш клиент ----
      final response = await _httpClient.delete(
        '/agents/$agentId/v1/platform/conversations/$conversationId',
      );
      
      print('🔵 ChatHistoryService: статус ${response.statusCode}');
      
      // ---- 2. Обрабатываем ответ ----
      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('Ошибка удаления чата: ${response.statusCode}');
      }
      
      print('✅ ChatHistoryService: чат удален');
    } catch (e) {
      throw Exception('Не удалось удалить чат: $e');
    }
  }
}