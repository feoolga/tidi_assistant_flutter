// lib/data/repositories/chat_repository.dart

import 'dart:convert';
import '../datasources/remote/chat_api.dart';
import '../models/chat_response_dto.dart';
import '../../domain/models/agent.dart';
import '../../domain/models/chat_session.dart';
import '../../domain/models/message.dart';

/// Репозиторий для работы с чатом.
///
/// Этот слой отвечает за:
/// 1. Получение данных из API (через ChatApi)
/// 2. Преобразование данных из формата сервера в формат приложения
/// 3. Подготовку данных для UseCase-ов
///
/// Repository НЕ ЗНАЕТ про UI и про бизнес-логику.
/// Он только отвечает на вопрос: "Где взять данные и как их преобразовать?"
class ChatRepository {
  // ============================================================
  // 1. ЗАВИСИМОСТИ
  // ============================================================

  final ChatApi _api;

  // ============================================================
  // 2. КОНСТРУКТОР
  // ============================================================

  ChatRepository({ChatApi? api}) : _api = api ?? ChatApi();

  // ============================================================
  // 3. РАБОТА С АГЕНТАМИ
  // ============================================================

  /// Получить список агентов.
  /// GET /v1/models
  Future<List<Agent>> getAgents() async {
    try {
      // 1. Запрашиваем данные через API
      final response = await _api.getModels();

      // 2. Проверяем статус
      if (response.statusCode != 200) {
        throw Exception('Ошибка загрузки агентов: ${response.statusCode}');
      }

      // 3. Парсим JSON
      final Map<String, dynamic> data = jsonDecode(response.body);
      final List<dynamic> models = data['data'] ?? [];

      // 4. Преобразуем в модели Agent
      // Фильтруем "auto" — это не агент, а специальное значение для роутинга
      return models
          .where((item) => item['id'] != 'auto')
          .map((json) => Agent.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Не удалось загрузить агентов: $e');
    }
  }

  // ============================================================
  // 4. РАБОТА С ЧАТАМИ (CONVERSATIONS)
  // ============================================================

  /// Создать новый чат для агента.
  /// POST /agents/{agentId}/v1/platform/conversations
  Future<ChatSession> createConversation({
    required String agentId,
    String? title,
  }) async {
    try {
      // 1. Отправляем запрос через API
      final response = await _api.createConversation(
        agentId: agentId,
        title: title,
      );

      // 2. Проверяем статус
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Ошибка создания чата: ${response.statusCode}');
      }

      // 3. Парсим ответ
      final Map<String, dynamic> data = jsonDecode(response.body);

      // 4. Преобразуем в модель ChatSession
      return ChatSession.fromJson(data, agentId);
    } catch (e) {
      throw Exception('Не удалось создать чат: $e');
    }
  }

  /// Получить список чатов агента.
  /// GET /agents/{agentId}/v1/platform/conversations
  Future<List<ChatSession>> getConversations({required String agentId}) async {
    try {
      // 1. Отправляем запрос через API
      final response = await _api.getConversations(agentId: agentId);

      // 2. Проверяем статус
      if (response.statusCode == 404) {
        // Агент не поддерживает чаты (например, OCR)
        return [];
      }

      if (response.statusCode != 200) {
        throw Exception('Ошибка загрузки чатов: ${response.statusCode}');
      }

      // 3. Парсим ответ
      final List<dynamic> data = jsonDecode(response.body);

      // 4. Преобразуем в модели ChatSession
      return data.map((json) => ChatSession.fromJson(json, agentId)).toList();
    } catch (e) {
      // Возвращаем пустой список, чтобы не ломать UI
      print('⚠️ ChatRepository: ошибка загрузки чатов: $e');
      return [];
    }
  }

  /// Получить сообщения чата.
  /// GET /agents/{agentId}/v1/platform/conversations/{conversationId}/messages
  Future<List<Message>> getMessages({
    required String agentId,
    required String conversationId,
  }) async {
    try {
      // 1. Отправляем запрос через API
      final response = await _api.getMessages(
        agentId: agentId,
        conversationId: conversationId,
      );

      // 2. Проверяем статус
      if (response.statusCode != 200) {
        throw Exception('Ошибка загрузки сообщений: ${response.statusCode}');
      }

      // 3. Парсим ответ
      final List<dynamic> data = jsonDecode(response.body);

      // 4. Преобразуем в модели Message
      return data
          .map((json) => Message.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Не удалось загрузить сообщения: $e');
    }
  }

  // ============================================================
  // 5. РАБОТА С СООБЩЕНИЯМИ (ПОКА ЗАГЛУШКА)
  // ============================================================

  /// Отправить сообщение и получить ответ.
  ///
  /// ВНИМАНИЕ! Этот метод пока НЕ РАБОТАЕТ,
  /// потому что бэкенд возвращает 500 на /v1/chat/completions.
  ///
  /// Как только бэкенд починят — мы допишем реализацию.
  Future<ChatResponseDto> sendMessage({
    required List<Message> messages,
    String? conversationId,
    String? forceAgentId,
  }) async {
    // TODO: Реализовать, когда заработает /v1/chat/completions
    throw UnimplementedError(
      'sendMessage пока не реализован, ждем починки бэкенда',
    );
  }
}
