// lib/data/repositories/chat_repository.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../datasources/remote/chat_api.dart';
import '../../domain/models/agent.dart';
import '../../domain/models/chat_session.dart';
import '../../domain/models/message.dart';
import '../../core/logger/app_logger.dart';
import '../../core/errors/error_handler.dart';
import '../../core/errors/server_exceptions.dart';
import '../models/agent_dto.dart';
import '../models/chat_session_dto.dart';
import '../models/message_dto.dart';
import '../mappers/agent_mapper.dart';
import '../mappers/chat_session_mapper.dart';
import '../mappers/message_mapper.dart';
import '../../domain/models/attachment.dart';

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
        // 👇 Бросаем ServerException с правильным статусом
        throw ServerException.clientError(
          statusCode: response.statusCode,
          body: response.body.isNotEmpty ? jsonDecode(response.body) : null,
        );
      }

      // 3. Парсим JSON
      final Map<String, dynamic> data = jsonDecode(response.body);
      final List<dynamic> models = data['data'] ?? [];

      // 4. Преобразуем в модели Agent
      // Фильтруем "auto" — это не агент, а специальное значение для роутинга
      final agents = models
          .where((item) => item['id'] != 'auto')
          .map((json) => AgentDto.fromJson(json))
          .map((dto) => AgentMapper.toDomain(dto))
          .toList();

      AppLogger.info('Загружено агентов: ${agents.length}');
      return agents;
    } catch (e) {
      AppLogger.error('Не удалось загрузить агентов', e);
      // 👇 ErrorHandler превратит любую ошибку в AppException
      throw ErrorHandler.handle(e);
    }
  }

  /// Определить, какого агента выберет роутер, без реального вызова.
  ///
  /// POST /route — тело `{"message": "..."}`, ответ `{"agent": "<id>"}`.
  ///
  /// Используется при открытии нового чата: сначала узнаём `agent_id`,
  /// потом создаём чат у этого агента и дальше все сообщения идут
  /// в `POST /v1/responses` с явным `model: agent_id`.
  ///
  /// Возвращает `agent_id` (`"epoz"`, `"document_chat"`, ...).
  /// Бросает [ServerException], если сервер ответил ошибкой или
  /// прислал невалидный ответ.
  Future<String> getRoute(String message) async {
    try {
      final response = await _api.route(message: message);

      if (response.statusCode != 200) {
        AppLogger.error('Ошибка роутинга: ${response.statusCode}');
        throw ServerException.clientError(
          statusCode: response.statusCode,
          body: response.body.isNotEmpty ? jsonDecode(response.body) : null,
        );
      }

      final Map<String, dynamic> data = jsonDecode(response.body);
      final agentId = data['agent'];

      if (agentId is! String || agentId.isEmpty) {
        AppLogger.error('Невалидный ответ роутера: отсутствует поле "agent"');
        throw ServerException.parseError(
          'В ответе /route отсутствует поле "agent": ${response.body}',
        );
      }

      AppLogger.info('Роутер выбрал агента: $agentId');
      return agentId;
    } catch (e) {
      AppLogger.error('Не удалось определить агента', e);
      throw ErrorHandler.handle(e);
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
        // 👇 Бросаем ServerException
        throw ServerException.clientError(
          statusCode: response.statusCode,
          body: response.body.isNotEmpty ? jsonDecode(response.body) : null,
        );
      }

      final Map<String, dynamic> data = jsonDecode(response.body);
      final sessionDto = ChatSessionDto.fromJson(data);
      final session = ChatSessionMapper.toDomain(sessionDto, agentId);

      AppLogger.info('Чат создан: ${session.id}');
      return session;
    } catch (e) {
      AppLogger.error('Не удалось создать чат для агента $agentId', e);
      // 👇 Используем ErrorHandler
      throw ErrorHandler.handle(e);
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
        // 👇 Бросаем ServerException
        throw ServerException.clientError(
          statusCode: response.statusCode,
          body: response.body.isNotEmpty ? jsonDecode(response.body) : null,
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      final chats = data
          .map((json) => ChatSessionDto.fromJson(json))
          .map((dto) => ChatSessionMapper.toDomain(dto, agentId))
          .toList();
      AppLogger.debug('Загружено чатов для агента $agentId: ${chats.length}');
      return chats;
    } catch (e) {
      AppLogger.warning('Не удалось загрузить чаты для агента $agentId: $e');
      return []; // 👈 Оставляем — возвращаем пустой список
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
        // 👇 Бросаем ServerException
        throw ServerException.clientError(
          statusCode: response.statusCode,
          body: response.body.isNotEmpty ? jsonDecode(response.body) : null,
        );
      }

      final List<dynamic> data = jsonDecode(response.body);
      final messages = data
          .map((json) => MessageDto.fromJson(json as Map<String, dynamic>))
          .map((dto) => MessageMapper.toDomain(dto))
          .toList();

      AppLogger.info(
        'Загружено сообщений чата $conversationId: ${messages.length}',
      );
      return messages;
    } catch (e) {
      AppLogger.error('Не удалось загрузить сообщения чата $conversationId', e);
      // 👇 Используем ErrorHandler
      throw ErrorHandler.handle(e);
    }
  }

  // ============================================================
  // 5. РАБОТА С СООБЩЕНИЯМИ
  // ============================================================

  /// Отправить сообщение и получить сырой SSE-поток.
  ///
  /// [attachments] — уже загруженные вложения (`status: done`,
  /// `remoteId != null`). Формируют `input_file`-части в формате
  /// Responses API. Вложения без `remoteId` молча отбрасываются —
  /// см. [_buildInput].
  Future<http.StreamedResponse> sendMessageStream({
    required String text,
    String? conversationId,
    String? agentId,
    List<Attachment> attachments = const [],
  }) async {
    AppLogger.info('Отправка стрим-запроса: "$text"');

    final Map<String, dynamic> body = {
      'model': agentId ?? 'auto',
      'input': _buildInput(text: text, attachments: attachments),
      'stream': true,
    };

    if (conversationId != null && conversationId.isNotEmpty) {
      body['conversation_id'] = conversationId;
      AppLogger.debug('📎 Продолжаем чат: $conversationId');
    }

    // ✅ ЛОГ 3: перед отправкой
    AppLogger.debug('🚀 Отправка запроса на сервер...');

    // 👇 Оборачиваем в try-catch для преобразования ошибок
    try {
      final response = await _api.sendMessage(body: body);
      AppLogger.debug('📥 Получен ответ: ${response.statusCode}');

      // 👇 Проверяем статус ответа
      if (response.statusCode != 200) {
        throw ServerException.clientError(statusCode: response.statusCode);
      }

      return response;
    } catch (e) {
      AppLogger.error('Ошибка при отправке стрим-запроса', e);
      throw ErrorHandler.handle(e);
    }
  }

  /// Собирает значение `input` для тела запроса в формате Responses API.
  ///
  /// Без вложений — просто строка (совместимо со старым поведением).
  /// С вложениями — массив items, где `content` — массив частей:
  /// - `input_text` с текстом вопроса;
  /// - `input_file` для каждого вложения с плоским `file_id`
  ///   (именно такой формат ждёт Responses API, см. README `document_chat`).
  ///
  /// Вложения без `remoteId` (например, ещё не загруженные) молча
  /// отбрасываются с предупреждением в лог. Так отправка не падает
  /// из-за одного сломанного файла, и в запрос не уходит мусор.
  Object _buildInput({
    required String text,
    required List<Attachment> attachments,
  }) {
    final uploaded = attachments
        .where((a) => a.remoteId != null && a.remoteId!.isNotEmpty)
        .toList();

    if (uploaded.length < attachments.length) {
      AppLogger.warning(
        'Пропущено ${attachments.length - uploaded.length} '
        'незагруженных вложений при формировании input',
      );
    }

    if (uploaded.isEmpty) return text;

    return [
      {
        'role': 'user',
        'content': [
          {'type': 'input_text', 'text': text},
          for (final att in uploaded)
            {'type': 'input_file', 'file_id': att.remoteId},
        ],
      },
    ];
  }
}
