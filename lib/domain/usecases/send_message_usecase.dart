// lib/domain/usecases/send_message_usecase.dart

import 'dart:async';

import '../../core/errors/app_exception.dart';
import '../../core/errors/business_exceptions.dart';
import '../../core/errors/error_handler.dart';
import '../../core/logger/app_logger.dart';
import '../../core/network/sse_parser.dart';
import '../../data/models/chat_response_dto.dart';
import '../../data/repositories/chat_repository.dart';
import '../models/attachment.dart';

// ============================================================
// 1. ПАРАМЕТРЫ
// ============================================================

/// Параметры для отправки сообщения.
class SendMessageParams {
  /// Текст сообщения.
  final String text;

  /// ID агента — используется для путей `/agents/{agentId}/v1/...`
  /// и как значение поля `model` в теле запроса (для обычных агентов).
  ///
  /// Для RAG-сессии — всегда `"agentic_rag"`. Конкретный набор
  /// задаётся отдельно через [ragId], а `model` собирается как
  /// `"rag/<ragId>"` (см. [ragId] и `AppConfig.ragModelId`).
  ///
  /// `null` — сессия ещё не определена, роутинг сделает бэкенд
  /// (`model: "auto"`).
  final String? agentId;

  /// ID чата (`conversation_id`) — для продолжения диалога.
  ///
  /// `null` — новый чат, сессия ещё не создана.
  final String? sessionId;

  /// ID RAG-набора — **только** для RAG-сессии.
  ///
  /// `null` для обычных агентов (`document_chat`, `epoz`, `chat`, ...).
  /// Для RAG-сессии — UUID пользовательского набора документов.
  ///
  /// Когда [ragId] задан, `model` в теле запроса собирается как
  /// `"rag/<ragId>"` — через `AppConfig.ragModelId`. Отдельное поле
  /// нужно потому, что `agentId` для путей остаётся `"agentic_rag"`,
  /// а `model` — другое значение.
  final String? ragId;

  /// Вложения, приложенные пользователем к этому сообщению.
  ///
  /// Все вложения должны быть уже загружены на сервер (`status: done`)
  /// и иметь `remoteId` — иначе их нельзя передать в `input_file`.
  /// Пустой список означает, что сообщение текстовое.
  final List<Attachment> attachments;

  const SendMessageParams({
    required this.text,
    this.agentId,
    this.sessionId,
    this.ragId,
    this.attachments = const [],
  });

  /// Есть ли активная сессия (агент + чат).
  bool get hasSession => agentId != null && sessionId != null;

  /// Есть ли вложения у сообщения.
  bool get hasAttachments => attachments.isNotEmpty;

  /// Это RAG-сессия?
  ///
  /// `true`, если задан [ragId]. Используется в репозитории для
  /// решения, как собирать `model`.
  bool get isRag => ragId != null;
}

// ============================================================
// 2. USECASE
// ============================================================

/// UseCase для отправки сообщения.
///
/// Отвечает на вопрос: «Что делает приложение, когда пользователь
/// отправляет сообщение?»
///
/// Возвращает поток `ChatResponseDto` — чистых данных без UI-логики.
///
/// **Обработка ошибок:**
/// - HTTP-ошибки (404, 502, ...) бросает `ChatRepository` до возврата
///   стрима — они попадают в общий `catch`;
/// - ошибки в SSE-потоке (`event: error`) — обрабатываем **здесь**,
///   превращая в `controller.addError(...)` — чтобы `ChatStreamHandler`
///   получил `onError` и передал `ChatStreamFailed` в notifier.
class SendMessageUseCase {
  final ChatRepository _repository;

  SendMessageUseCase({required ChatRepository repository})
    : _repository = repository;

  /// Выполнить сценарий: отправить сообщение.
  ///
  /// Возвращает поток `ChatResponseDto`.
  Stream<ChatResponseDto> execute(SendMessageParams params) {
    final controller = StreamController<ChatResponseDto>();
    _sendAndProcess(params, controller);
    return controller.stream;
  }

  void _sendAndProcess(
    SendMessageParams params,
    StreamController<ChatResponseDto> controller,
  ) async {
    try {
      // 1. Отправляем запрос и получаем StreamedResponse.
      //    HTTP-ошибки (>= 400) бросает ChatRepository.
      final response = await _repository.sendMessageStream(
        text: params.text,
        conversationId: params.sessionId,
        agentId: params.agentId,
        ragId: params.ragId,
        attachments: params.attachments,
      );

      // 2. Парсим SSE-поток.
      final eventStream = SseParser.parse(response);

      // 3. Переменные для сборки ответа.
      String fullText = '';

      // 4. Обрабатываем каждое событие.
      await for (final event in eventStream) {
        final eventType = event['_event_type'] as String?;

        // --- Служебные события начала — игнорируем ---
        if (eventType == 'response.created' ||
            eventType == 'response.output_item.added' ||
            eventType == 'response.content_part.added') {
          continue;
        }

        // --- Дельта текста — эмитим промежуточный DTO ---
        if (eventType == 'response.output_text.delta') {
          final delta = event['delta'] as String? ?? '';
          fullText += delta;

          controller.add(
            ChatResponseDto(
              id: '',
              model: params.agentId ?? 'auto',
              conversationId: params.sessionId,
              content: fullText,
              isStreaming: true,
            ),
          );
          continue;
        }

        // --- Финал — эмитим финальный DTO и закрываем поток ---
        if (eventType == 'response.completed') {
          final responseData = event['response'] as Map<String, dynamic>?;
          if (responseData != null) {
            final messageId = responseData['id'] as String?;
            final agentId = responseData['model'] as String?;
            final conversationId = responseData['conversation_id'] as String?;

            controller.add(
              ChatResponseDto(
                id: messageId ?? '',
                model: agentId ?? params.agentId ?? 'auto',
                conversationId: conversationId ?? params.sessionId,
                content: fullText,
                isStreaming: false,
              ),
            );
          }

          controller.close();
          return;
        }

        // --- Ошибка в стриме ---
        //
        // Поддерживаем **оба** варианта имени события:
        // - `event: error` — обычные агенты (`document_chat`, `epoz`, ...);
        //   см. README document_chat: «Ошибка в процессе генерации —
        //   `event: error` с sequence_number: 9999».
        // - `event: response.error` — RAG-агент (`agentic_rag`);
        //   см. README Agentic RAG: при ошибке во время генерации
        //   приходит `event: response.error` с телом
        //   `{"error": {...}, "id": "resp_<uuid>"}`.
        //
        // Тело в обоих случаях одинаковое — `_parseErrorEvent` его
        // разбирает одинаково, потому что формат `error`-объекта
        // общий для обеих форм.
        if (eventType == 'error' || eventType == 'response.error') {
          final appException = _parseErrorEvent(event);

          // Логируем напрямую: ошибка уже AppException (создана в
          // `_parseErrorEvent`), ErrorHandler.handle здесь не нужен.
          // Логируем `eventType` — чтобы видеть в логах, какое именно
          // имя события пришло (полезно для отладки).
          AppLogger.logException(
            'Ошибка в SSE-потоке (event: $eventType)',
            appException,
          );
          controller.addError(appException);
          await controller.close();
          return;
        }

        // --- Всё остальное — логируем, но не ломаем стрим ---
        // Примеры: response.output_text.done, response.content_part.done,
        // response.output_item.done — служебные события конца.
        AppLogger.debug('Пропущено SSE-событие: $eventType');
      }

      // 5. Если поток завершился без response.completed — это нештатно.
      //    ChatStreamHandler отдельно обработает этот случай через onDone.
      AppLogger.warning('SSE-поток завершился без response.completed');
      await controller.close();
    } catch (error, stackTrace) {
      // Транспортные ошибки, HTTP-ошибки, ошибки парсинга — сюда.
      final appException =
          ErrorHandler.handle(error, stackTrace, 'Ошибка в SSE-потоке', {
            'agentId': params.agentId,
            'sessionId': params.sessionId,
            'attachments_count': params.attachments.length,
          });

      controller.addError(appException);
      await controller.close();
    }
  }

  // ============================================================
  // 3. РАЗБОР EVENT: ERROR
  // ============================================================

  /// Превращает `event: error` или `event: response.error` из SSE-потока
  /// в [AppException].
  ///
  /// **Формат (по README).** Обычные агенты (`document_chat`, `epoz`):
  /// ```json
  /// {
  ///   "type": "error",
  ///   "sequence_number": 9999,
  ///   "error": {
  ///     "message": "...",
  ///     "type": "server_error",
  ///     "param": null,
  ///     "code": null
  ///   }
  /// }
  /// ```
  ///
  /// RAG-агент (`agentic_rag`):
  /// ```json
  /// {
  ///   "error": {"message": "...", "type": "...", "code": null},
  ///   "id": "resp_<uuid>"
  /// }
  /// ```
  /// `id` присутствует **только** если pending message уже создан
  /// (после `response.created`). При ранней валидации — `id`
  /// отсутствует. На разбор `error` это не влияет: парсим
  /// **только поле `error`**, `id` игнорируем.
  ///
  /// **Почему один метод на оба события:** формат `error`-объекта
  /// **одинаковый** в обеих формах. Различается только имя события
  /// (`error` vs `response.error`) — его мы уже знаем в вызывающем
  /// коде (`eventType`) и используем в логе.
  ///
  /// **Защитный парсинг:** бэкенд может присылать упрощённую форму
  /// (`{"message": "..."}`), поэтому пробуем несколько вариантов.
  /// Если совсем ничего не нашли — общая ошибка «Сервер сообщил об ошибке».
  ///
  /// **Возвращаем [BusinessException.streamError]** — потому что это
  /// **семантическое** событие из **успешного** HTTP-ответа, а не
  /// транспортная или серверная ошибка уровня HTTP.
  AppException _parseErrorEvent(Map<String, dynamic> event) {
    // Вариант 1: `error` — вложенный объект с `message`.
    final errorObj = event['error'];
    if (errorObj is Map<String, dynamic>) {
      final message = errorObj['message'];
      if (message is String && message.isNotEmpty) {
        return BusinessException.streamError(message);
      }

      // `error` есть, но без `message` — возможно, есть `type`.
      final type = errorObj['type'];
      if (type is String && type.isNotEmpty) {
        return BusinessException.streamError('Тип ошибки: $type');
      }
    }

    // Вариант 2: `message` лежит прямо в корне события.
    final message = event['message'];
    if (message is String && message.isNotEmpty) {
      return BusinessException.streamError(message);
    }

    // Вариант 3: ничего не нашли — общее сообщение.
    // Не падаем, не показываем сырой JSON пользователю.
    return BusinessException.streamError(
      'Сервер сообщил об ошибке при генерации ответа',
    );
  }
}
