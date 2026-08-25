// lib/data/repositories/chat_repository.dart

import 'dart:convert';
import '../datasources/remote/chat_api.dart';
import '../models/chat_response_dto.dart';
import '../../domain/models/agent.dart';
import '../../domain/models/chat_session.dart';
import '../../domain/models/message.dart';
import '../../core/logger/app_logger.dart';

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
        AppLogger.error('Ошибка загрузки агентов: ${response.statusCode}');
        throw Exception('Ошибка загрузки агентов: ${response.statusCode}');
      }

      // 3. Парсим JSON
      final Map<String, dynamic> data = jsonDecode(response.body);
      final List<dynamic> models = data['data'] ?? [];

      // 4. Преобразуем в модели Agent
      // Фильтруем "auto" — это не агент, а специальное значение для роутинга
      final agents = models
          .where((item) => item['id'] != 'auto')
          .map((json) => Agent.fromJson(json))
          .toList();

      AppLogger.info('Загружено агентов: ${agents.length}');
      return agents;
    } catch (e) {
      AppLogger.error('Не удалось загрузить агентов', e);
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
        AppLogger.error('Ошибка создания чата: ${response.statusCode}');
        throw Exception('Ошибка создания чата: ${response.statusCode}');
      }

      // 3. Парсим ответ
      final Map<String, dynamic> data = jsonDecode(response.body);

      // 4. Преобразуем в модель ChatSession
      final session = ChatSession.fromJson(data, agentId);
      AppLogger.info('Чат создан: ${session.id}');
      return session;
    } catch (e) {
      AppLogger.error('Не удалось создать чат для агента $agentId', e);
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
        // Агент не поддерживает чаты
        return [];
      }

      if (response.statusCode != 200) {
        AppLogger.error('Ошибка загрузки чатов: ${response.statusCode}');
        throw Exception('Ошибка загрузки чатов: ${response.statusCode}');
      }

      // 3. Парсим ответ
      final List<dynamic> data = jsonDecode(response.body);

      // 4. Преобразуем в модели ChatSession
      final chats = data
          .map((json) => ChatSession.fromJson(json, agentId))
          .toList();
      AppLogger.debug('Загружено чатов для агента $agentId: ${chats.length}');
      return chats;
    } catch (e) {
      // Возвращаем пустой список, чтобы не ломать UI
      AppLogger.warning('Не удалось загрузить чаты для агента $agentId: $e');
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
        AppLogger.error('Ошибка загрузки сообщений: ${response.statusCode}');
        throw Exception('Ошибка загрузки сообщений: ${response.statusCode}');
      }

      // 3. Парсим ответ
      final List<dynamic> data = jsonDecode(response.body);

      // 4. Преобразуем в модели Message
      final messages = data
          .map((json) => Message.fromJson(json as Map<String, dynamic>))
          .toList();

      AppLogger.info(
        'Загружено сообщений чата $conversationId: ${messages.length}',
      );
      return messages;
    } catch (e) {
      AppLogger.error('Не удалось загрузить сообщения чата $conversationId', e);
      throw Exception('Не удалось загрузить сообщения: $e');
    }
  }

  // ============================================================
  // 5. РАБОТА С СООБЩЕНИЯМИ
  // ============================================================

  /// Отправить сообщение и получить ответ.
  Future<ChatResponseDto> sendMessage({
    required List<Message> messages,
    String? conversationId,
    String? forceAgentId,
  }) async {
    try {
      AppLogger.info('Отправка сообщения (${messages.length} сообщений)');

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
        AppLogger.info(
          'Продолжаем диалог (агент=$forceAgentId, чат=$conversationId)',
        );
      } else {
        // Новый диалог — авто-роутинг
        body['model'] = 'auto';
        AppLogger.info('Новый диалог (авто-роутинг)');
      }

      // ---- 4. Отправляем запрос через API ----
      final response = await _api.sendMessage(body: body);

      // ---- 5. Проверяем статус ----
      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        AppLogger.error('Ошибка сервера: ${response.statusCode} - $errorBody');
        throw Exception('Ошибка сервера: ${response.statusCode} - $errorBody');
      }

      // ---- 6. Парсим SSE-поток ----
      return await _parseSseStream(response.stream);
    } catch (e) {
      AppLogger.error('Ошибка при отправке сообщения', e);
      throw Exception('Ошибка при отправке сообщения: $e');
    }
  }

  /// Парсит SSE-поток и собирает ответ.
  ///
  /// Возвращает ChatResponseDto с полным текстом и метаданными.
  Future<ChatResponseDto> _parseSseStream(Stream<List<int>> stream) async {
    String buffer = '';
    String fullText = '';
    String id = '';
    String model = 'auto';
    String? conversationId;

    AppLogger.debug('Начинаем парсинг SSE-потока');

    // Читаем поток по частям
    await for (final chunk in stream) {
      // Декодируем байты в строку
      buffer += utf8.decode(chunk, allowMalformed: true);

      // Разбиваем на строки
      final lines = buffer.split('\n');
      buffer = lines.last;

      // Обрабатываем все полные строки
      for (int i = 0; i < lines.length - 1; i++) {
        final line = lines[i];

        // Ищем строки с data:
        if (line.startsWith('data: ')) {
          final data = line.substring(6).trim();

          // Проверяем на завершение потока
          if (data == '[DONE]') {
            AppLogger.debug('Поток завершен [DONE]');
            break;
          }

          // Пропускаем пустые строки
          if (data.isEmpty) continue;

          try {
            // Парсим JSON
            final json = jsonDecode(data) as Map<String, dynamic>;

            // ---- Извлекаем model (агента) ----
            if (json.containsKey('model')) {
              final modelValue = json['model'] as String?;
              if (modelValue != null && modelValue.isNotEmpty) {
                if (model != modelValue) {
                  // Логируем только при ИЗМЕНЕНИИ
                  model = modelValue;
                  AppLogger.info('Агент определён: $model');
                }
              }
            }

            // ---- Извлекаем conversationId ----
            if (json.containsKey('conversation_id')) {
              final convId = json['conversation_id'] as String?;
              if (convId != null && conversationId == null) {
                conversationId = convId;
                AppLogger.info('conversation_id: $conversationId');
              }
            }

            // ---- Извлекаем id сообщения ----
            if (json.containsKey('id')) {
              final idValue = json['id'] as String?;
              if (idValue != null && id.isEmpty) {
                id = idValue;
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
            AppLogger.warning('Ошибка парсинга JSON: $e');
            AppLogger.debug('Строка: $data');
            continue;
          }
        }
      }
    }

    // ---- Формируем результат ----
    String displayText = fullText.trim();

    // Заменяем "Источники:" на "Проанализированные источники:"
    const String oldText = '\n\nИсточники:\n';
    const String newText = '\n\nПроанализированные источники:\n';
    if (displayText.contains(oldText)) {
      displayText = displayText.replaceAll(oldText, newText);
    }

    AppLogger.info(
      'Ответ получен (${displayText.length} символов, агент=$model, чат=$conversationId)',
    );

    return ChatResponseDto(
      id: id,
      model: model,
      conversationId: conversationId,
      content: displayText,
    );
  }
}
