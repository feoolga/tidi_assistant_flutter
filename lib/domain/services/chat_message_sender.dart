// lib/domain/services/chat_message_sender.dart

import '../../core/logger/app_logger.dart';
import '../models/attachment.dart';
import '../usecases/send_message_usecase.dart';
import 'chat_stream_event.dart';
import 'chat_stream_handler.dart';

/// Сервис **отправки** **сообщений** **в** **чат**.
///
/// **Ответственность**:
/// - **создать** [SendMessageParams] **из** **высокоуровневых** **параметров**;
/// - **вызвать** [SendMessageUseCase.execute] (**HTTP** **+** **SSE**);
/// - **обернуть** **поток** **через** [ChatStreamHandler] —
///   **семантические** **события**;
/// - **вернуть** `Stream<ChatStreamEvent>` **вызывающему** **коду**.
///
/// **Что** **НЕ** **делает**:
/// - **не** **управляет** **state** (**это** `ChatNotifier`);
/// - **не** **создаёт** **user-сообщение** (**это** `ChatNotifier`);
/// - **не** **создаёт** **пустой** **AI-пузырь** (**это** `ChatNotifier`);
/// - **не** **устанавливает** **сессию** (**это** `ChatNotifier`);
/// - **не** **читает** **провайдеры** **напрямую** (**принимает**
///   **всё** **готовое** **через** **параметры**).
///
/// **Почему** **stateless**: **каждый** **вызов** `send` — **независимый**.
/// **State** — **снаружи**.
///
/// **Почему** **не** **принимает** `Ref`: **сервис** **не** **должен** **знать**
/// **про** **Riverpod**. **Зависимости** — **через** **конструктор**.
class ChatMessageSender {
  final SendMessageUseCase _sendMessageUseCase;
  final ChatStreamHandler _streamHandler;

  ChatMessageSender({
    required SendMessageUseCase sendMessageUseCase,
    required ChatStreamHandler streamHandler,
  }) : _sendMessageUseCase = sendMessageUseCase,
       _streamHandler = streamHandler;

  /// Отправить сообщение и получить **поток** **событий**.
  ///
  /// **Параметры**:
  /// - [text] — **текст** **сообщения**;
  /// - [agentId] — **id** **агента** (**для** **путей**
  ///   `/agents/{agentId}/v1/...` **и** **поля** `model`);
  /// - [sessionId] — **id** **чата** (`conversation_id`); `null` — **новый** **чат**;
  /// - [ragId] — **id** **RAG-набора** (**только** **для** **RAG-чатов**);
  /// - [attachments] — **уже** **загруженные** **вложения**
  ///   (`status: done`, **с** **remoteId**).
  ///
  /// **Возвращает** `Stream<ChatStreamEvent>`:
  /// - **сначала** — **ровно** **один** [ChatStreamStarted];
  /// - **потом** — **ноль** **или** **больше** [ChatStreamDelta];
  /// - **в** **конце** — **ровно** **один** [ChatStreamCompleted]
  ///   **ИЛИ** [ChatStreamFailed].
  ///
  /// **Ошибки** **HTTP** (**до** **открытия** **стрима** — `getRoute`,
  /// `createConversation`) **пробрасываются** **наверх** (**на** **уровне**
  /// **future**). **Ошибки** **во** **время** **стрима** — **внутри** **потока**
  /// (**через** `ChatStreamFailed`).
  ///
  /// **`displayName`** **здесь** **не** **участвует** — **это** **забота**
  /// **`ChatNotifier`**.
  Stream<ChatStreamEvent> send({
    required String text,
    required String agentId,
    required String? sessionId,
    required String? ragId,
    required List<Attachment> attachments,
  }) {
    AppLogger.info(
      'ChatMessageSender.send: textLength=${text.length}, '
      'agentId=$agentId, sessionId=$sessionId, ragId=$ragId, '
      'attachments=${attachments.length}',
    );

    // 1. Собираем параметры для UseCase.
    final params = SendMessageParams(
      text: text,
      agentId: agentId,
      sessionId: sessionId,
      ragId: ragId,
      attachments: attachments,
    );

    // 2. Запускаем UseCase — он вернёт поток «сырых» ChatResponseDto
    //    (или ошибку через addError).
    final source = _sendMessageUseCase.execute(params);

    // 3. Оборачиваем в ChatStreamHandler — он превратит
    //    ChatResponseDto в ChatStreamEvent (Started/Delta/Completed/Failed).
    return _streamHandler.handle(source);
  }
}
