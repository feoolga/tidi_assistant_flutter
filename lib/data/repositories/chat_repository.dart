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
      final response = await _api.createConversation(
        agentId: agentId,
        title: title,
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        AppLogger.error('Ошибка создания чата: ${response.statusCode}');
        throw Exception('Ошибка создания чата: ${response.statusCode}');
      }

      final Map<String, dynamic> data = jsonDecode(response.body);
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
      final response = await _api.getConversations(agentId: agentId);

      if (response.statusCode == 404) {
        return [];
      }

      if (response.statusCode != 200) {
        AppLogger.error('Ошибка загрузки чатов: ${response.statusCode}');
        throw Exception('Ошибка загрузки чатов: ${response.statusCode}');
      }

      final List<dynamic> data = jsonDecode(response.body);
      final chats = data
          .map((json) => ChatSession.fromJson(json, agentId))
          .toList();
      AppLogger.debug('Загружено чатов для агента $agentId: ${chats.length}');
      return chats;
    } catch (e) {
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
      final response = await _api.getMessages(
        agentId: agentId,
        conversationId: conversationId,
      );

      if (response.statusCode != 200) {
        AppLogger.error('Ошибка загрузки сообщений: ${response.statusCode}');
        throw Exception('Ошибка загрузки сообщений: ${response.statusCode}');
      }

      final List<dynamic> data = jsonDecode(response.body);
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
    required String text,
    String? conversationId,
    String? agentId,
  }) async {
    try {
      AppLogger.info('Отправка сообщения: "$text"');

      final Map<String, dynamic> body = {
        'model': agentId ?? 'auto',
        'input': text, // ← только строка, НЕ массив!
        'stream': true,
      };

      if (conversationId != null && conversationId.isNotEmpty) {
        body['conversation_id'] = conversationId;
        AppLogger.info('Продолжаем чат: $conversationId');
      }

      final response = await _api.sendMessage(body: body);

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        AppLogger.error('Ошибка сервера: ${response.statusCode} - $errorBody');
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }

      return await _parseSseStream(response.stream);
    } catch (e) {
      AppLogger.error('Ошибка при отправке сообщения', e);
      throw Exception('Ошибка при отправке сообщения: $e');
    }
  }

  /// Парсит SSE-поток в формате Responses API.
  ///
  /// Responses API присылает события в виде:
  ///   event: response.created
  ///   data: {"id": "...", "model": "...", "conversation_id": "..."}
  ///
  ///   event: response.output_text.delta
  ///   data: {"delta": "текст"}
  ///
  ///   event: response.completed
  ///   data: {"status": "completed", "usage": {...}}
  ///
  /// Возвращает ChatResponseDto с полным текстом и метаданными.
  Future<ChatResponseDto> _parseSseStream(Stream<List<int>> stream) async {
    // ---- 1. Начинаем с пустого DTO ----
    var dto = ChatResponseDto.empty();

    // ---- 2. Буфер для накопления строк ----
    String buffer = '';
    String? currentEventType;

    AppLogger.debug('Начинаем парсинг SSE-потока (Responses API)');

    // ---- 3. Читаем поток по частям ----
    await for (final chunk in stream) {
      // Декодируем байты в строку
      buffer += utf8.decode(chunk, allowMalformed: true);

      // Разбиваем на строки
      final lines = buffer.split('\n');
      buffer = lines.last;

      // Обрабатываем все полные строки
      for (int i = 0; i < lines.length - 1; i++) {
        final line = lines[i].trim();

        // ---- 4. Пропускаем пустые строки ----
        if (line.isEmpty) continue;

        // ---- 5. Определяем тип события ----
        if (line.startsWith('event: ')) {
          currentEventType = line.substring(7).trim();
          AppLogger.debug('Событие: $currentEventType');
          continue;
        }

        // ---- 6. Обрабатываем данные события ----
        if (line.startsWith('data: ')) {
          final data = line.substring(6).trim();

          // Пропускаем пустые данные
          if (data.isEmpty) continue;

          // ---- 7. Парсим JSON ----
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;

            // ---- 8. Обрабатываем в зависимости от типа события ----
            if (currentEventType == 'response.created') {
              // ---- Событие: response.created ----
              // Содержит id, model, conversation_id
              final id = json['id'] as String? ?? '';
              final model = json['model'] as String? ?? 'auto';
              final conversationId = json['conversation_id'] as String?;

              dto = dto.copyWith(
                id: id,
                model: model,
                conversationId: conversationId,
              );

              AppLogger.info(
                'Ответ создан: id=$id, model=$model, conversationId=$conversationId',
              );
            } else if (currentEventType == 'response.output_text.delta') {
              // ---- Событие: response.output_text.delta ----
              // Содержит очередной кусок текста в поле "delta"
              final delta = json['delta'] as String? ?? '';
              if (delta.isNotEmpty) {
                dto = dto.copyWith(content: dto.content + delta);
              }
            } else if (currentEventType == 'response.completed') {
              // ---- Событие: response.completed ----
              // Завершение потока
              AppLogger.info('Поток завершён (response.completed)');

              // ---- Заменяем "Источники:" на "Проанализированные источники:" ----
              String finalText = dto.content.trim();
              const String oldText = '\n\nИсточники:\n';
              const String newText = '\n\nПроанализированные источники:\n';
              if (finalText.contains(oldText)) {
                finalText = finalText.replaceAll(oldText, newText);
              }

              // ---- Возвращаем финальный DTO ----
              return ChatResponseDto(
                id: dto.id,
                model: dto.model,
                conversationId: dto.conversationId,
                content: finalText,
              );
            } else {
              // ---- Неизвестное событие — логируем, но не падаем ----
              AppLogger.warning('Неизвестное событие: $currentEventType');
              AppLogger.debug('Данные: $data');
            }
          } catch (e) {
            // ---- Ошибка парсинга JSON ----
            AppLogger.warning('Ошибка парсинга JSON: $e');
            AppLogger.debug('Строка: $data');
            continue;
          }
        }
      }
    }

    // ---- 9. Если поток завершился без response.completed ----
    AppLogger.warning('Поток завершился без события response.completed');

    // Возвращаем то, что успели собрать
    String finalText = dto.content.trim();
    const String oldText = '\n\nИсточники:\n';
    const String newText = '\n\nПроанализированные источники:\n';
    if (finalText.contains(oldText)) {
      finalText = finalText.replaceAll(oldText, newText);
    }

    return ChatResponseDto(
      id: dto.id,
      model: dto.model,
      conversationId: dto.conversationId,
      content: finalText,
    );
  }
}
