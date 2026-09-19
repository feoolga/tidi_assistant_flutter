// lib/data/repositories/chat_repository.dart

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/errors/business_exceptions.dart';
import '../../core/errors/error_handler.dart';
import '../../core/errors/server_exceptions.dart';
import '../../core/logger/app_logger.dart';
import '../../domain/models/agent.dart';
import '../../domain/models/attachment.dart';
import '../../domain/models/chat_session.dart';
import '../../domain/models/message.dart';
import '../datasources/remote/chat_api.dart';
import '../mappers/agent_mapper.dart';
import '../mappers/chat_session_mapper.dart';
import '../mappers/message_mapper.dart';
import '../models/agent_dto.dart';
import '../models/chat_session_dto.dart';
import '../models/message_dto.dart';

/// Репозиторий для работы с чатом.
///
/// Этот слой отвечает за:
/// 1. Получение данных из API (через [ChatApi]).
/// 2. Преобразование данных из формата сервера в формат приложения.
/// 3. Подготовку данных для use-case-ов.
///
/// **Политика ошибок:**
/// - Репозиторий **никогда** не возвращает пустое вместо ошибки.
/// - Все ошибки — либо валидные данные (включая `[]` там, где это
///   семантически правильно, например `404 → []` для `getConversations`),
///   либо `AppException` наверх.
/// - Логирование — с `stackTrace` и контекстом (operation, ids).
///
/// **Что репозиторий НЕ делает:**
/// - Не проверяет `statusCode != 200` — этим занимается [AppHttpClient],
///   который бросает `ServerException` на `>= 400`.
/// - Не решает, что показать пользователю — это работа UI.
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
  ///
  /// `GET /v1/models` — клиент уже бросит `ServerException` на `>= 400`.
  /// Нам остаётся только распарсить и замапить.
  ///
  /// **Важно:** фильтруем `auto` — это **не** агент, а **специальное**
  /// значение для роутинга.
  Future<List<Agent>> getAgents() async {
    try {
      final response = await _api.getModels();

      final Map<String, dynamic> data = jsonDecode(response.body);
      final List<dynamic> models = data['data'] ?? [];

      final agents = models
          .where((item) => item['id'] != 'auto')
          .map((json) => AgentDto.fromJson(json as Map<String, dynamic>))
          .map((dto) => AgentMapper.toDomain(dto))
          .toList();

      AppLogger.info('Загружено агентов: ${agents.length}');
      return agents;
    } catch (e, stackTrace) {
      AppLogger.logException('Не удалось загрузить агентов', e, stackTrace);
      throw ErrorHandler.handle(e, stackTrace);
    }
  }

  /// Определить, какого агента выберет роутер, без реального вызова.
  ///
  /// `POST /route` — тело `{"message": "..."}`, ответ `{"agent": "<id>"}`.
  ///
  /// **Семантическая проверка:** ответ **должен** содержать поле `agent`
  /// (тип `String`, непустое). Если нет — это **не** валидный ответ,
  /// и мы бросаем `ServerException.parseError`.
  ///
  /// **Почему это в репозитории, а не в клиенте:** клиент не знает,
  /// что ответ `/route` **должен** содержать `agent`. Это **доменное**
  /// требование к конкретному эндпоинту.
  Future<String> getRoute(String message) async {
    try {
      final response = await _api.route(message: message);

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
    } catch (e, stackTrace) {
      AppLogger.logException('Не удалось определить агента', e, stackTrace, {
        'message_length': message.length,
      });
      throw ErrorHandler.handle(e, stackTrace);
    }
  }

  // ============================================================
  // 4. РАБОТА С ЧАТАМИ (CONVERSATIONS)
  // ============================================================

  /// Создать новый чат для агента.
  ///
  /// `POST /agents/{agentId}/v1/platform/conversations` — успех **только** `201`.
  ///
  /// **Почему явная проверка `== 201`:** клиент **не** бросает на `200`/`202`/`204`
  /// (это `< 400`). Но по контракту успех — **только** `201`. Если сервер
  /// вернёт `200` с **непонятным** телом — мы **хотим** это заметить,
  /// а не пытаться распарсить неизвестное.
  Future<ChatSession> createConversation({
    required String agentId,
    String? title,
  }) async {
    try {
      final response = await _api.createConversation(
        agentId: agentId,
        title: title,
      );

      if (response.statusCode != 201) {
        AppLogger.error(
          'Неожиданный статус при создании чата: ${response.statusCode} '
          '(ожидался 201)',
        );
        throw ServerException.clientError(
          statusCode: response.statusCode,
          body: response.body.isNotEmpty
              ? jsonDecode(response.body) as Map<String, dynamic>
              : null,
        );
      }

      final Map<String, dynamic> data = jsonDecode(response.body);
      final sessionDto = ChatSessionDto.fromJson(data);
      final session = ChatSessionMapper.toDomain(sessionDto, agentId);

      AppLogger.info('Чат создан: ${session.id}');
      return session;
    } catch (e, stackTrace) {
      AppLogger.logException(
        'Не удалось создать чат для агента $agentId',
        e,
        stackTrace,
        {'agentId': agentId, 'title': title},
      );
      throw ErrorHandler.handle(e, stackTrace);
    }
  }

  /// Получить список чатов агента.
  ///
  /// `GET /agents/{agentId}/v1/platform/conversations` — успех `200`.
  ///
  /// **Семантический случай `404`:** у агента **нет** чатов. Это **не**
  /// ошибка — возвращаем **пустой** список. Все остальные статусы
  /// (`>= 400`) — **ошибка**, пробрасываем.
  ///
  /// **Что НЕ делаем:** не глотаем **все** ошибки. Если сеть упала —
  /// пробросим `NetworkException`, пользователь увидит ошибку,
  /// а не **пустой** список.
  Future<List<ChatSession>> getConversations({required String agentId}) async {
    try {
      final response = await _api.getConversations(agentId: agentId);

      final List<dynamic> data = jsonDecode(response.body) as List;
      final chats = data
          .map((json) => ChatSessionDto.fromJson(json as Map<String, dynamic>))
          .map((dto) => ChatSessionMapper.toDomain(dto, agentId))
          .toList();

      AppLogger.debug('Загружено чатов для агента $agentId: ${chats.length}');
      return chats;
    } on ServerException catch (e, stackTrace) {
      // 404 — семантически "у агента нет чатов". Не ошибка.
      if (e.statusCode == 404) {
        AppLogger.info('У агента $agentId нет чатов (404)');
        return [];
      }

      // Все остальные серверные ошибки — пробрасываем.
      AppLogger.logException(
        'Не удалось загрузить чаты агента $agentId',
        e,
        stackTrace,
        {'agentId': agentId},
      );
      throw ErrorHandler.handle(e, stackTrace);
    } catch (e, stackTrace) {
      // Транспортные ошибки, невалидный JSON — сюда.
      AppLogger.logException(
        'Не удалось загрузить чаты агента $agentId',
        e,
        stackTrace,
        {'agentId': agentId},
      );
      throw ErrorHandler.handle(e, stackTrace);
    }
  }

  /// Получить сообщения чата.
  ///
  /// `GET /agents/{agentId}/v1/platform/conversations/{conversationId}/messages`
  ///
  /// **Семантический случай `404`:** чат **удалён** или **чужой**.
  /// По README: обращение к **чужому** чату возвращает `404`
  /// (сервис **не** подтверждает существование **чужих** ресурсов).
  /// Пользователю — **явное** сообщение «Этот чат был удалён».
  ///
  /// Все остальные ошибки — пробрасываем.
  Future<List<Message>> getMessages({
    required String agentId,
    required String conversationId,
  }) async {
    try {
      final response = await _api.getMessages(
        agentId: agentId,
        conversationId: conversationId,
      );

      final List<dynamic> data = jsonDecode(response.body) as List;
      final messages = data
          .map((json) => MessageDto.fromJson(json as Map<String, dynamic>))
          .map((dto) => MessageMapper.toDomain(dto))
          .toList();

      AppLogger.info(
        'Загружено сообщений чата $conversationId: ${messages.length}',
      );
      return messages;
    } on ServerException catch (e, stackTrace) {
      // 404 — чат удалён или чужой. Это **доменное** событие, не транспорт.
      if (e.statusCode == 404) {
        AppLogger.info('Чат $conversationId не найден (404)');
        throw BusinessException.chatNotFound(conversationId);
      }

      AppLogger.logException(
        'Не удалось загрузить сообщения чата $conversationId',
        e,
        stackTrace,
        {'agentId': agentId, 'conversationId': conversationId},
      );
      throw ErrorHandler.handle(e, stackTrace);
    } catch (e, stackTrace) {
      AppLogger.logException(
        'Не удалось загрузить сообщения чата $conversationId',
        e,
        stackTrace,
        {'agentId': agentId, 'conversationId': conversationId},
      );
      throw ErrorHandler.handle(e, stackTrace);
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
  ///
  /// **Обработка ошибок:** `postStream` **сам** бросает `ServerException`
  /// на `>= 400`, читая **тело** ошибки. Нам **не** надо проверять
  /// статус — только пробросить.
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

    try {
      final response = await _api.sendMessage(body: body);
      AppLogger.debug('📥 Получен ответ: ${response.statusCode}');
      return response;
    } catch (e, stackTrace) {
      AppLogger.logException(
        'Ошибка при отправке стрим-запроса',
        e,
        stackTrace,
        {
          'agentId': agentId,
          'conversationId': conversationId,
          'attachments_count': attachments.length,
        },
      );
      throw ErrorHandler.handle(e, stackTrace);
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
