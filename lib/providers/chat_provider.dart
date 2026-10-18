// lib/providers/chat_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/error_handler.dart';
import '../core/logger/app_logger.dart';
import '../core/utils/copy_with_marker.dart';
import '../domain/models/attachment.dart';
import '../data/repositories/chat_repository.dart';
import '../domain/models/message.dart';
import '../domain/services/chat_stream_event.dart';
import '../domain/services/chat_stream_handler.dart';
import '../domain/usecases/send_message_usecase.dart';
import 'agent_provider.dart';
import 'attachment_draft_provider.dart';
import 'session_provider.dart';
import 'dart:async';
import '../domain/models/message_source.dart';
import '../domain/models/message_status.dart';

// ============================================================
// 1. СОСТОЯНИЕ ЧАТА
// ============================================================

/// Состояние чата — сообщения, статус загрузки, стриминг.
///
/// **ВАЖНО:** здесь **нет** ни `agentId` / `sessionId`, ни состояния
/// вложений. И то, и другое живёт отдельно:
/// - сессия — в `sessionProvider` (SSOT);
/// - черновик вложений — в `attachmentDraftProvider`.
///
/// Раньше `pendingAttachments` / `isAddingAttachment` / `infoMessage`
/// лежали здесь, что смешивало «состояние диалога» и «черновик ввода».
/// После разделения у каждого объекта — **свой** жизненный цикл:
/// - `ChatState.messages` — живёт долго, растёт, это **история**;
/// - `AttachmentDraftState.attachments` — живёт минуты, обнуляется.
class ChatState {
  /// История сообщений — то, что уже **отправлено**.
  ///
  /// Вложения, отправленные с сообщением, лежат в `Message.attachments`,
  /// не здесь. Здесь — только сам диалог.
  final List<Message> messages;

  /// Идёт ли отправка сообщения или загрузка истории.
  final bool isLoading;

  /// Ошибка **чата** — отправки, загрузки, стриминга.
  ///
  /// **НЕ** путать с `AttachmentDraftState.error` — там ошибки
  /// **прикрепления файла**.
  final String? error;

  /// Идёт ли сейчас стриминг ответа AI.
  final bool isStreaming;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
    this.isStreaming = false,
  });

  factory ChatState.initial() {
    return const ChatState();
  }

  ChatState copyWith({
    List<Message>? messages,
    bool? isLoading,
    Object? error = copyWithUnset,
    bool? isStreaming,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: isCopyWithUnset(error) ? this.error : error as String?,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }

  bool get hasMessages => messages.isNotEmpty;
  bool get hasError => error != null && error!.isNotEmpty;
}

// ============================================================
// 2. NOTIFIER
// ============================================================

/// Нотифаер **чата**.
///
/// **Ответственность:**
/// - хранить историю сообщений;
/// - отправлять сообщения через `SendMessageUseCase`;
/// - обрабатывать события стрима (Started / Delta / Completed / Failed);
/// - загружать чат из истории (`loadChat`);
/// - очищать/создавать новый чат.
///
/// **Что НЕ делает:**
/// - не управляет вложениями-черновиками (это `AttachmentDraftNotifier`);
/// - не знает про `document_chat`-специфику загрузки файлов;
/// - не показывает SnackBar (это работа UI).
///
/// **Про вложения.** Когда пользователь отправляет сообщение,
/// `ChatNotifier` **читает** текущий черновик из `attachmentDraftProvider`
/// и кладёт вложения в `Message.fromUser(attachments: ...)`. После
/// успешной отправки — **очищает** черновик (вызывает
/// `attachmentDraftProvider.notifier.clear()`).
class ChatNotifier extends StateNotifier<ChatState> {
  /// Ссылка на Riverpod — нужна, чтобы читать и писать в другие
  /// провайдеры: `sessionProvider` (SSOT сессии) и `attachmentDraftProvider`
  /// (черновик вложений).
  final Ref _ref;

  final ChatRepository _repository;
  final SendMessageUseCase _sendMessageUseCase;
  final ChatStreamHandler _streamHandler;

  ChatNotifier({
    required Ref ref,
    required ChatRepository repository,
    required SendMessageUseCase sendMessageUseCase,
    required ChatStreamHandler streamHandler,
  }) : _ref = ref,
       _repository = repository,
       _sendMessageUseCase = sendMessageUseCase,
       _streamHandler = streamHandler,
       super(ChatState.initial()) {
    _addWelcomeMessage();
  }

  // ============================================================
  // ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ СОСТОЯНИЯ
  // ============================================================

  void _addWelcomeMessage() {
    if (state.messages.isEmpty) {
      final welcomeMessage = Message(
        id: 'welcome_${DateTime.now().millisecondsSinceEpoch}',
        text: 'Здравствуйте! Я AI-ассистент. Задайте мне вопрос.',
        isFromUser: false,
        timestamp: DateTime.now(),
      );
      state = state.copyWith(messages: [welcomeMessage]);
    }
  }

  void _setLoading(bool isLoading) {
    state = state.copyWith(isLoading: isLoading);
  }

  void _setStreaming(bool isStreaming) {
    state = state.copyWith(isStreaming: isStreaming);
  }

  void _setError(String? error) {
    if (error != null) {
      AppLogger.debug('🔴 ChatNotifier._setError("$error")');
    }
    state = state.copyWith(error: error);
  }

  void _clearError() {
    state = state.copyWith(error: null);
  }

  void _addMessage(Message message) {
    state = state.copyWith(messages: [...state.messages, message]);
  }

  void _setMessages(List<Message> messages) {
    state = state.copyWith(messages: messages);
  }

  /// Обновляет текст последнего сообщения AI.
  void _updateMessageText(String text) {
    final currentMessages = state.messages;
    if (currentMessages.isEmpty) return;

    final lastIndex = currentMessages.length - 1;
    final lastMessage = currentMessages[lastIndex];

    if (!lastMessage.isFromUser) {
      final updatedMessage = lastMessage.copyWith(text: text);
      final newMessages = List<Message>.from(currentMessages);
      newMessages[lastIndex] = updatedMessage;
      state = state.copyWith(messages: newMessages);
    }
  }

  /// Завершает ответ — обновляет метаданные последнего сообщения AI.
  void _completeMessage({
    required String? agentId,
    required String? sessionId,
    required String? messageId,
  }) {
    final currentMessages = state.messages;
    if (currentMessages.isEmpty) return;

    final lastIndex = currentMessages.length - 1;
    final lastMessage = currentMessages[lastIndex];

    if (!lastMessage.isFromUser) {
      final updatedMessage = lastMessage.copyWith(
        id: messageId ?? lastMessage.id,
        agentId: agentId ?? lastMessage.agentId,
        sessionId: sessionId ?? lastMessage.sessionId,
      );

      final newMessages = List<Message>.from(currentMessages);
      newMessages[lastIndex] = updatedMessage;
      state = state.copyWith(messages: newMessages);
    }
  }

  /// Удаляет пустое AI-сообщение (если есть) — используется при ошибке.
  void _removeEmptyAiMessageIfAny() {
    final currentMessages = state.messages;
    if (currentMessages.isEmpty) return;

    final lastMessage = currentMessages.last;
    if (!lastMessage.isFromUser && lastMessage.text.isEmpty) {
      final newMessages = List<Message>.from(currentMessages)..removeLast();
      state = state.copyWith(messages: newMessages);
    }
  }

  /// Пометить последнее AI-сообщение как `failed`.
  ///
  /// **Зачем нужен.** Когда SSE-стрим падает **после** того, как
  /// сервер уже **принял** запрос (получен `200`, стрим открылся),
  /// пользователь **должен** видеть **пометку** «Не удалось получить
  /// ответ» **с кнопкой «Повторить»** — а **не** пустоту.
  ///
  /// **Почему `_removeEmptyAiMessageIfAny` не подходит.**
  /// Тот **удаляет** пузырь — хорошо, когда **сервер не знает**
  /// о запросе (валидация, сеть до `postStream`). Но если **стрим был
  /// открыт** — сервер **уже** создал ход, и «удалить» пузырь = скрыть
  /// от пользователя **факт** неудачной попытки. Пользователь
  /// запутается: «я отправил, а куда делось?».
  ///
  /// **Условия срабатывания:**
  /// - есть **последнее** сообщение (список не пуст);
  /// - оно **от AI** (`!isFromUser`);
  /// - у него **пустой текст** (значит, это именно «наш» пустой пузырь,
  ///   а не сообщение с частичным ответом — те **не** трогаем);
  /// - у него ещё **не** статус `failed` (не перезаписываем дважды —
  ///   иначе потеряем `errorMessage` от **первой** ошибки).
  ///
  /// **Что делает:**
  /// - копирует сообщение с `status: MessageStatus.failed`;
  /// - пробрасывает `errorMessage` (для логов/отладки);
  /// - заменяет в state (атомарно, без «мигания»).
  ///
  /// **Что НЕ делает:**
  /// - **не** удаляет пузырь (он должен **остаться** в UI);
  /// - **не** трогает `ChatState.error` (SnackBar **не** покажется);
  /// - **не** создаёт **новый** пузырь (переиспользует **тот же**).
  void _markLastAiMessageAsFailed(String errorMessage) {
    final currentMessages = state.messages;
    if (currentMessages.isEmpty) return;

    final lastIndex = currentMessages.length - 1;
    final lastMessage = currentMessages[lastIndex];

    // Условия: AI-сообщение, пустой текст, ещё не failed.
    // Если хоть одно не выполнено — **не** трогаем.
    if (lastMessage.isFromUser) return;
    if (lastMessage.text.isNotEmpty) return;
    if (lastMessage.status == MessageStatus.failed) return;

    final updatedMessage = lastMessage.copyWith(
      status: MessageStatus.failed,
      errorMessage: errorMessage,
    );

    final newMessages = List<Message>.from(currentMessages);
    newMessages[lastIndex] = updatedMessage;
    state = state.copyWith(messages: newMessages);

    AppLogger.info('AI-сообщение помечено как failed: "$errorMessage"');
  }

  // ============================================================
  // ОТПРАВКА СООБЩЕНИЯ
  // ============================================================

  /// Отправить сообщение в текущем чате.
  ///
  /// Логика:
  /// - Если сессия (agent_id + conversation_id) уже известна — используем её.
  /// - Если нет — определяем агента через `POST /route`, создаём чат,
  ///   сохраняем пару в `sessionProvider` и только потом отправляем.
  ///
  /// **Вложения** берём из `attachmentDraftProvider` — это текущий
  /// черновик ввода. После успешной отправки — **очищаем** черновик:
  /// вложения «переехали» в `Message.attachments` пользовательского
  /// сообщения и остаются в истории чата.
  Future<void> sendMessage({required String text}) async {
    if (state.isLoading) {
      AppLogger.warning('Отправка уже в процессе — пропускаем повторный вызов');
      return;
    }

    // Берём текущий черновик вложений.
    // **Копия** списка — потому что дальше мы можем очистить черновик,
    // и оригинальный список не должен измениться.
    final attachments = List<Attachment>.from(
      _ref.read(attachmentDraftProvider).attachments,
    );

    AppLogger.info(
      'Отправка сообщения: "$text" '
      '(вложений: ${attachments.length})',
    );

    _clearError();

    // 1. Сообщение пользователя — сразу с вложениями, чтобы UI показал превью.
    _addMessage(Message.fromUser(text: text, attachments: attachments));
    _setLoading(true);
    _setStreaming(true);

    // 2. Пустое AI-сообщение — заполнится по мере стрима.
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final aiMessage = Message(
      id: tempId,
      text: '',
      isFromUser: false,
      timestamp: DateTime.now(),
    );
    _addMessage(aiMessage);

    try {
      // 3. Определяем сессию: либо уже есть, либо создаём на лету.
      var currentAgentId = _ref.read(sessionProvider).agentId;
      var currentSessionId = _ref.read(sessionProvider).sessionId;

      if (currentSessionId == null) {
        if (attachments.isNotEmpty) {
          AppLogger.warning(
            'Есть вложения, но нет сессии — пропускаем отправку. '
            'Ожидалось, что чат создан в addAttachment.',
          );
          _removeEmptyAiMessageIfAny();
          return;
        }

        // Обычный новый чат: определяем агента и создаём чат.
        AppLogger.info('Новый чат — определяем агента через /route');
        currentAgentId = await _repository.getRoute(text);

        AppLogger.info('Создаём чат у агента $currentAgentId');
        final session = await _repository.createConversation(
          agentId: currentAgentId,
          title: text,
        );
        currentSessionId = session.id;

        // Ищем человекочитаемое имя для UI.
        // `agentsByIdProvider` — Map<String, Agent>, единый источник
        // правды об агентах (приходят с бэкенда через /v1/models).
        // Если агент ещё не загружен или не найден — `null`, UI покажет
        // fallback «AI Ассистент».
        final displayName = _ref.read(agentsByIdProvider)[currentAgentId]?.name;

        // Обновляем SSOT — sessionProvider.
        // UI читает agentId/sessionId/agentDisplayName напрямую оттуда,
        // поэтому agentId и sessionId здесь гарантированно non-null:
        // getRoute возвращает String, ChatSession.id — String.
        _ref
            .read(sessionProvider.notifier)
            .setSession(
              currentAgentId,
              currentSessionId,
              agentDisplayName: displayName,
            );

        AppLogger.info(
          'Чат создан: agent=$currentAgentId, session=$currentSessionId, '
          'displayName=$displayName',
        );
      }

      // 4–5. Отправка и обработка стрима — общий метод `_runStream`.
      //
      // См. `_runStream`: он создаёт `SendMessageParams`, запускает
      // `SendMessageUseCase.execute` + `ChatStreamHandler.handle`
      // и прогоняет `await for` по событиям. Логика **идентична**
      // той, что была здесь inline. Вынесена **только** для того,
      // чтобы `retryLastMessage` мог использовать её повторно.
      //
      // `currentAgentId` и `currentSessionId` — гарантированно
      // non-null к этому моменту (созданы на шагах 3).
      final ragId = _ref.read(sessionProvider).ragId;

      await _runStream(
        text: text,
        agentId: currentAgentId!,
        sessionId: currentSessionId,
        ragId: ragId,
        attachments: attachments,
      );
    } catch (e, stackTrace) {
      final appException = ErrorHandler.handle(
        e,
        stackTrace,
        'Ошибка в sendMessage',
        {'text_length': text.length, 'attachments_count': attachments.length},
      );
      _removeEmptyAiMessageIfAny();
      _setError(appException.userMessage);
    } finally {
      AppLogger.debug('🏁 Завершение обработки сообщения');
      _setLoading(false);
      _setStreaming(false);
    }
  }

  // ============================================================
  // ОБЩИЙ СТРИМ (sendMessage и retryLastMessage)
  // ============================================================

  /// Запустить отправку сообщения и обработать SSE-стрим.
  ///
  /// **Общий метод** для [sendMessage] и [retryLastMessage]. Логика
  /// **идентична** той, что раньше была inline в [sendMessage]:
  /// - создаёт [SendMessageParams];
  /// - вызывает [SendMessageUseCase.execute];
  /// - оборачивает в [ChatStreamHandler.handle];
  /// - `await for` по событиям;
  /// - на `ChatStreamCompleted` — обновляет последнее AI-сообщение,
  ///   догружает sources (для RAG), очищает черновик вложений;
  /// - на `ChatStreamFailed` — удаляет пустой AI-пузырь, ставит
  ///   ошибку в state.
  ///
  /// **Чего метод НЕ делает:**
  /// - не создаёт user-сообщение (это делает вызывающий код);
  /// - не создаёт пустой AI-пузырь (тоже вызывающий код);
  /// - не управляет `isLoading`/`isStreaming` — это тоже на вызывающем.
  ///
  /// **Зачем разнесли.** Раньше вся логика жила в [sendMessage].
  /// При добавлении [retryLastMessage] её пришлось бы **дублировать**
  /// — а это **риск** разъехаться. Один общий метод — один источник
  /// правды.
  ///
  /// **Почему `chatState.isStreaming` не трогаем внутри.** Флаг
  /// `isStreaming` в state управляет UI (`TypingIndicator`). Ставим
  /// его **вне** этого метода — вместе с `isLoading`, чтобы состояние
  /// было согласованным (оба включились / оба выключились в `finally`).
  Future<void> _runStream({
    required String text,
    required String agentId,
    required String? sessionId,
    required String? ragId,
    required List<Attachment> attachments,
  }) async {
    final params = SendMessageParams(
      text: text,
      agentId: agentId,
      sessionId: sessionId,
      ragId: ragId,
      attachments: attachments,
    );

    final source = _sendMessageUseCase.execute(params);
    final events = _streamHandler.handle(source);

    await for (final event in events) {
      switch (event) {
        case ChatStreamStarted():
          AppLogger.debug('🟢 Стрим начался');
          break;

        case ChatStreamDelta(:final fullText):
          _updateMessageText(fullText);
          break;

        case ChatStreamCompleted(
          :final fullText,
          :final messageId,
          // Поле называется `agentId` (историческое имя), но по факту
          // содержит `model` из ответа сервера (`rag/<uuid>` для RAG,
          // `epoz` для обычных). Переименовываем в локальную переменную
          // `modelFromResponse`, чтобы не путать с настоящим `agentId`
          // для путей `/agents/{agentId}/...`.
          agentId: final modelFromResponse,
          :final conversationId,
        ):
          _updateMessageText(fullText);
          _setStreaming(false);

          _completeMessage(
            agentId: agentId,
            sessionId: conversationId ?? sessionId,
            messageId: messageId,
          );

          if (conversationId != null) {
            _ref
                .read(sessionProvider.notifier)
                .setSession(agentId, conversationId);
          }

          AppLogger.info('✅ Ответ получен полностью');
          AppLogger.debug('   📌 Агент (для путей): $agentId');
          AppLogger.debug('   📌 model (эхо сервера): $modelFromResponse');
          AppLogger.debug('   📌 Чат: $conversationId');
          AppLogger.debug('   📌 ID сообщения: $messageId');
          AppLogger.debug('   📌 Длина текста: ${fullText.length} символов');

          if (ragId != null && messageId != null && messageId.isNotEmpty) {
            unawaited(
              _loadSourcesForMessage(agentId: agentId, messageId: messageId),
            );
          }

          _ref.read(attachmentDraftProvider.notifier).clear();
          break;

        case ChatStreamFailed(:final error):
          // Логирование **уже произошло** в `SendMessageUseCase`
          // (для `event: error`) или в `ErrorHandler.handle` внутри
          // `ChatStreamHandler` (для транспортных ошибок).
          // Здесь — только UI-реакция.
          //
          // **Что делаем:** помечаем пустой AI-пузырь как `failed`.
          // Пользователь видит «Не удалось получить ответ» **с**
          // кнопкой «Повторить» **прямо в чате** — без SnackBar.
          //
          // **Почему НЕ `_removeEmptyAiMessageIfAny`.** Раньше
          // удаляли пузырь — но тогда пользователь **терял**
          // факт неудачной попытки (только SnackBar, который
          // исчезает). Теперь пузырь **остаётся** — но с пометкой.
          //
          // **Почему НЕ `_setError`.** SnackBar **не** нужен:
          // пометка **уже** в чате, пользователь её видит.
          // Если поставить `_setError` — `ChatScreen` покажет
          // **ещё и** SnackBar, получится **двойная** ошибка.
          //
          // **Почему `_markLastAiMessageAsFailed` безопасен.**
          // Внутри есть **проверки**:
          // - `isFromUser` — не трогаем user-сообщения;
          // - `text.isNotEmpty` — не трогаем **частичные** ответы
          //   (если стрим упал **после** получения нескольких токенов,
          //   пользователь **уже** видит часть ответа — не надо
          //   портить);
          // - `status == failed` — не перезаписываем (иначе
          //   потеряем `errorMessage` от **первой** ошибки).
          _markLastAiMessageAsFailed(error.userMessage);
          // Черновик вложений НЕ очищаем — пользователь может
          // попробовать снова.
          break;
      }
    }
  }

  // ============================================================
  // ПОВТОР ОТПРАВКИ (для failed-сообщений)
  // ============================================================

  /// Повторить последнее user-сообщение, если после него — failed-AI.
  ///
  /// **Зачем нужен.** Если SSE-стрим оборвался (`client_disconnected`),
  /// сервер сохраняет assistant-сообщение с `status: failed`
  /// и **пустым** `text`. UI показывает пометку «Не удалось получить
  /// ответ». Пользователь хочет **повторить** — эта функция делает
  /// ровно это.
  ///
  /// **Логика:**
  /// 1. Найти индекс последнего **user**-сообщения (с конца).
  /// 2. Найти индекс последнего **assistant**-сообщения (после user).
  /// 3. Проверить, что assistant — **failed**. Иначе — это **не**
  ///    «повторить», а «странный вызов», тихо выходим.
  /// 4. Заменить failed-пузырь на **пустой** `ok`-пузырь
  ///    (text: '', status: ok) — так `MessageBubble` покажет
  ///    `TypingIndicator`, а не старую ошибку.
  /// 5. Запустить `_runStream` с **тем же** текстом user-сообщения.
  ///
  /// **Что **не** делает:**
  /// - **не** создаёт **новое** user-сообщение (старое уже есть);
  /// - **не** удаляет failed-пузырь (заменяет — чтобы не мигал UI);
  /// - **не** работает для `document_chat` — у него **свой** механизм
  ///   ретрая (`AttachmentDraftNotifier`), и там сообщения **не**
  ///   имеют `status: failed` в БД.
  ///
  /// **Защита от дурака.** Если `state.isLoading` уже `true` —
  /// выходим. Значит, пользователь нажал «Повторить» **во время**
  /// другого стрима — это бессмысленно.
  Future<void> retryLastMessage() async {
    if (state.isLoading) {
      AppLogger.warning('retryLastMessage: уже идёт отправка — пропускаем');
      return;
    }

    // 1. Найти последнее user-сообщение.
    //
    // Идём **с конца**, потому что `state.messages` растёт в конец.
    // Индекс последнего user — начало «последнего хода».
    final messages = state.messages;
    int? userIndex;
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].isFromUser) {
        userIndex = i;
        break;
      }
    }

    if (userIndex == null) {
      AppLogger.warning(
        'retryLastMessage: нет user-сообщений — повтор невозможен',
      );
      return;
    }

    // 2. Индекс assistant — следующий после user. У нас **один**
    //    ход = user + assistant, поэтому это `userIndex + 1`.
    //    На всякий случай проверяем, что assistant **есть**.
    final assistantIndex = userIndex + 1;
    if (assistantIndex >= messages.length) {
      AppLogger.warning(
        'retryLastMessage: после user-сообщения нет assistant — '
        'повтор невозможен',
      );
      return;
    }

    final failedMessage = messages[assistantIndex];

    // 3. Проверка: точно failed?
    if (failedMessage.status != MessageStatus.failed) {
      AppLogger.warning(
        'retryLastMessage: последнее assistant-сообщение '
        'не failed (status: ${failedMessage.status.name}) — '
        'повтор бессмысленен',
      );
      return;
    }

    // 4. Заменить failed-пузырь на пустой ok-пузырь.
    //
    // Почему **заменяем**, а не **удаляем** + создаём заново:
    // замена **атомарна** с точки зрения UI — не будет «мигания»
    // (удаление + создание = два rebuild'а).
    //
    // `text: ''` + `status: ok` → `MessageBubble` покажет
    // `TypingIndicator` (потому что `message.text.isEmpty`,
    // а `isStreaming` придёт из `ChatState`).
    final emptyAi = failedMessage.copyWith(
      text: '',
      status: MessageStatus.ok,
      errorMessage: null,
    );

    final newMessages = List<Message>.from(messages);
    newMessages[assistantIndex] = emptyAi;
    state = state.copyWith(messages: newMessages);

    // 5. Запустить стрим.
    final userText = messages[userIndex].text;

    _clearError();
    _setLoading(true);
    _setStreaming(true);

    try {
      final session = _ref.read(sessionProvider);
      final currentAgentId = session.agentId;
      final currentSessionId = session.sessionId;
      final ragId = session.ragId;

      if (currentAgentId == null || currentSessionId == null) {
        // Сессия потеряна — не можем повторить. Ставим ошибку.
        _setError('Не удалось повторить: сессия потеряна.');
        return;
      }

      await _runStream(
        text: userText,
        agentId: currentAgentId,
        sessionId: currentSessionId,
        ragId: ragId,
        // Вложения для retry **не** передаём: если они были —
        // пользователь уже отправил их, и повтор без файлов —
        // корректное поведение (файлы уже на сервере).
        attachments: const [],
      );
    } catch (e, stackTrace) {
      final appException = ErrorHandler.handle(
        e,
        stackTrace,
        'Ошибка в retryLastMessage',
        {'text_length': userText.length},
      );
      _removeEmptyAiMessageIfAny();
      _setError(appException.userMessage);
    } finally {
      _setLoading(false);
      _setStreaming(false);
    }
  }

  /// Догрузить sources для последнего AI-сообщения.
  ///
  /// Вызывается **после** `ChatStreamCompleted`, **только** для RAG.
  /// **Fire-and-forget**: не блокируем пользователя, ошибки логируем
  /// и **не** показываем — sources вторичны, ответ уже получен.
  Future<void> _loadSourcesForMessage({
    required String agentId,
    required String messageId,
  }) async {
    try {
      final sources = await _repository.getSources(
        agentId: agentId,
        messageId: messageId,
      );

      if (sources.isEmpty) {
        AppLogger.debug(
          'Sources пусто для сообщения $messageId — оставляем как есть',
        );
        return;
      }

      // Обновляем последнее AI-сообщение — то, у которого id == messageId.
      //
      // Ищем **по** id, а не по «последнее AI» — потому что за время
      // сетевого запроса пользователь мог отправить **новое** сообщение,
      // и «последнее AI» станет **другим**. Ищем надёжно.
      _updateSourcesForMessage(messageId: messageId, sources: sources);
    } catch (e, stackTrace) {
      // Sources — вторичные. Ошибку логируем, но **не** показываем
      // пользователю и **не** роняем ход.
      AppLogger.logException(
        'Ошибка догрузки sources для сообщения $messageId',
        e,
        stackTrace,
        {'agentId': agentId, 'messageId': messageId},
      );
    }
  }

  /// Обновить sources у сообщения с указанным id.
  ///
  /// Если сообщения с таким id **нет** (например, пользователь уже
  /// начал **новый** чат, или сообщение было удалено) — тихо выходим.
  void _updateSourcesForMessage({
    required String messageId,
    required List<MessageSource> sources,
  }) {
    final currentMessages = state.messages;
    final index = currentMessages.indexWhere((m) => m.id == messageId);
    if (index < 0) {
      AppLogger.debug(
        'Сообщение $messageId не найдено в state — пропускаем обновление sources',
      );
      return;
    }

    final updatedMessage = currentMessages[index].copyWith(sources: sources);
    final newMessages = List<Message>.from(currentMessages);
    newMessages[index] = updatedMessage;
    state = state.copyWith(messages: newMessages);
  }

  // ============================================================
  // ЗАГРУЗКА И УПРАВЛЕНИЕ ЧАТОМ
  // ============================================================

  /// Загрузить чат из истории.
  ///
  /// Загружает сообщения чата и обновляет SSOT-сессию.
  ///
  /// Обновление `sessionProvider` — критично: без него AppBar
  /// показывал бы старое имя агента при открытии чата из истории.
  /// Раньше сессия дублировалась в `ChatState` и могла рассинхронизироваться;
  /// теперь такого класса проблем нет — сессия живёт в одном месте.
  /// Загрузить чат из истории.
  ///
  /// [ragId] — id RAG-набора, если чат принадлежит RAG-агенту.
  /// Для обычных агентов (`document_chat`, `epoz`, `chat`) — `null`.
  ///
  /// **Почему `ragId` критичен.** `agentic_rag` в `POST /v1/responses`
  /// требует `model` в форме `rag/<uuid>` и **отвергает** просто
  /// `agentic_rag` (`response.error: "model='agentic_rag' — ожидается
  /// форма 'rag/<uuid>'"`). Значит, при открытии RAG-чата из истории
  /// мы **обязаны** проставить `ragId` в `sessionProvider` — иначе
  /// следующее сообщение уйдёт с неправильным `model`.
  Future<void> loadChat(String agentId, String chatId, String? ragId) async {
    AppLogger.info('Загрузка чата: агент=$agentId, чат=$chatId, ragId=$ragId');

    _setLoading(true);
    _clearError();

    try {
      final messages = await _repository.getMessages(
        agentId: agentId,
        conversationId: chatId,
      );
      _setMessages(messages);

      // Ищем человекочитаемое имя для UI.
      // См. комментарий в `sendMessage` — почему `agentsByIdProvider`.
      final displayName = _ref.read(agentsByIdProvider)[agentId]?.name;

      // Обновляем SSOT — AppBar сразу покажет нужного агента,
      // а следующий `sendMessage` возьмёт правильный `ragId`.
      //
      // `ragId` передаём **явно** (может быть `null` — для обычных
      // агентов). `setSession` через `copyWithUnset` **сохранит**
      // текущее значение, если мы **не** передали параметр. Но нам
      // нужно **перезаписать**: при открытии чата без RAG в предыдущей
      // сессии мог остаться `ragId` — и он бы **просочился** в
      // следующее сообщение.
      //
      // Поэтому передаём **явно** — чтобы `null` действительно
      // **сбросил** значение.
      _ref
          .read(sessionProvider.notifier)
          .setSession(
            agentId,
            chatId,
            ragId: ragId,
            agentDisplayName: displayName,
          );

      AppLogger.info('Загружено сообщений: ${messages.length}');
    } catch (e, stackTrace) {
      final appException = ErrorHandler.handle(
        e,
        stackTrace,
        'Ошибка в loadChat',
        {'agentId': agentId, 'chatId': chatId},
      );
      _setError(appException.userMessage);
    } finally {
      _setLoading(false);
    }
  }

  /// Создать новый чат (визуально очистить поле).
  ///
  /// Сессия сбрасывается в `sessionProvider` — значит, `AppBar`
  /// сразу покажет «AI Ассистент» (агент не выбран).
  ///
  /// Черновик вложений тоже очищается — при создании нового чата
  /// старые вложения не имеют смысла.
  Future<void> createNewChat() async {
    AppLogger.info('Создание нового чата');

    _setMessages([]);
    _addWelcomeMessage();
    _clearError();

    // Очищаем черновик вложений (живёт в отдельном провайдере).
    _ref.read(attachmentDraftProvider.notifier).clear();

    _ref.read(sessionProvider.notifier).clearSession();

    AppLogger.debug('Новый чат создан');
  }

  /// Очистить текущий чат.
  ///
  /// **Осознанное отличие от [createNewChat]:** `clearChat` НЕ сбрасывает
  /// сессию — пользователь остаётся в том же агенте и чате, но история
  /// сообщений на экране очищается. Если надо начать полностью новый чат —
  /// используйте [createNewChat].
  void clearChat() {
    AppLogger.info('Очистка чата');

    _setMessages([]);
    _addWelcomeMessage();
    _clearError();

    // Черновик вложений тоже чистим — на экране пусто, и вложений быть
    // не должно. Сессию при этом НЕ трогаем — см. комментарий выше.
    _ref.read(attachmentDraftProvider.notifier).clear();
  }

  /// Очистить ошибку **чата** (не вложений).
  ///
  /// Для ошибок вложений — `attachmentDraftProvider.notifier.clearError()`.
  void clearError() {
    _clearError();
  }
}

// ============================================================
// 3. ПРОВАЙДЕРЫ
// ============================================================

/// Провайдер для ChatStreamHandler.
final chatStreamHandlerProvider = Provider<ChatStreamHandler>((ref) {
  return ChatStreamHandler();
});

/// Провайдер для SendMessageUseCase.
final sendMessageUseCaseProvider = Provider<SendMessageUseCase>((ref) {
  final repository = ref.read(chatRepositoryProvider);
  return SendMessageUseCase(repository: repository);
});

/// Основной провайдер чата.
///
/// **Зависимости:**
/// - `chatRepositoryProvider` — репозиторий для отправки/загрузки;
/// - `sendMessageUseCaseProvider` — UseCase отправки;
/// - `chatStreamHandlerProvider` — обработчик событий стрима.
///
/// **Больше не зависит** от `uploadAttachmentUseCaseProvider` —
/// управление вложениями переехало в `AttachmentDraftNotifier`.
final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  final repository = ref.read(chatRepositoryProvider);
  final sendMessageUseCase = ref.read(sendMessageUseCaseProvider);
  final streamHandler = ref.read(chatStreamHandlerProvider);

  return ChatNotifier(
    ref: ref,
    repository: repository,
    sendMessageUseCase: sendMessageUseCase,
    streamHandler: streamHandler,
  );
});
