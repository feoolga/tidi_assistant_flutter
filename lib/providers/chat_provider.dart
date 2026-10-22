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
import '../domain/services/chat_history_loader.dart';
import '../domain/services/chat_message_sender.dart';
import '../domain/services/chat_sources_fetcher.dart';

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
/// - отправлять сообщения через `ChatMessageSender`;
/// - обрабатывать события стрима (Started / Delta / Completed / Failed);
/// - загружать чат из истории (`loadChat` через `ChatHistoryLoader`);
/// - догружать sources (`ChatSourcesFetcher`);
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
  final Ref _ref;

  final ChatRepository _repository;

  /// Сервис **загрузки** **истории** **чата** (**Фаза** **2**).
  ///
  /// **Что** **делает**: **загружает** `messages`. **Возвращает**
  /// `ChatHistoryLoadResult`.
  ///
  /// **Почему** **не** **трогает** **state**: **сервис** **stateless**.
  /// **State** — **здесь**, **в** `ChatNotifier`. **Разделение**
  /// **ответственности**.
  final ChatHistoryLoader _historyLoader;

  /// Сервис **отправки** **сообщений** (**Фаза** **2**).
  ///
  /// **Что** **делает**: **создаёт** `SendMessageParams`, **вызывает**
  /// `SendMessageUseCase.execute`, **оборачивает** **поток** **через**
  /// `ChatStreamHandler.handle`. **Возвращает** `Stream<ChatStreamEvent>`.
  ///
  /// **Почему** **не** **трогает** **state**: **сервис** **stateless**.
  /// **State** — **здесь**, **в** `ChatNotifier`.
  final ChatMessageSender _messageSender;

  /// Сервис **загрузки** **sources** (**Фаза** **2**).
  ///
  /// **Что** **делает**: **загружает** `sources` **для** **одного**
  /// **сообщения** (**после** **стрима**) **или** **для** **многих**
  /// (**история** **RAG-чата**). **Возвращает** `List<SourcesBatch>`
  /// **или** `List<MessageSource>`.
  ///
  /// **Почему** **не** **трогает** **state**: **сервис** **stateless**.
  /// **State** — **здесь**, **в** `ChatNotifier`.
  final ChatSourcesFetcher _sourcesFetcher;

  ChatNotifier({
    required Ref ref,
    required ChatRepository repository,
    required ChatHistoryLoader historyLoader,
    required ChatMessageSender messageSender,
    required ChatSourcesFetcher sourcesFetcher,
  }) : _ref = ref,
       _repository = repository,
       _historyLoader = historyLoader,
       _messageSender = messageSender,
       _sourcesFetcher = sourcesFetcher,
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
  ///
  /// **Фаза 3.2 рефакторинга**: отправка делегирует
  /// `ChatMessageSender.send` (HTTP + SSE). Здесь — только state
  /// и обработка событий (`switch`).
  Future<void> sendMessage({required String text}) async {
    if (state.isLoading) {
      AppLogger.warning('Отправка уже в процессе — пропускаем повторный вызов');
      return;
    }

    // Берём текущий черновик вложений.
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

        AppLogger.info('Новый чат — определяем агента через /route');
        currentAgentId = await _repository.getRoute(text);

        AppLogger.info('Создаём чат у агента $currentAgentId');
        final session = await _repository.createConversation(
          agentId: currentAgentId,
          title: text,
        );
        currentSessionId = session.id;

        final displayName = _ref.read(agentsByIdProvider)[currentAgentId]?.name;

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

      // 4. Запускаем стрим через сервис.
      //
      // `_messageSender.send` возвращает `Stream<ChatStreamEvent>` —
      // семантические события (Started/Delta/Completed/Failed).
      // **Обрабатываем** их **здесь** (**state** **трогаем** **только** **мы**).
      final ragId = _ref.read(sessionProvider).ragId;

      final events = _messageSender.send(
        text: text,
        agentId: currentAgentId!,
        sessionId: currentSessionId,
        ragId: ragId,
        attachments: attachments,
      );

      // 5. Обработка событий стрима.
      await _processStreamEvents(
        events: events,
        agentId: currentAgentId,
        sessionId: currentSessionId,
        ragId: ragId,
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

  /// Обработать **поток** **семантических** **событий** **стрима**.
  ///
  /// **Что** **делает**: **`switch`** **по** **событиям** **с** **обновлением**
  /// **state**:
  /// - `ChatStreamStarted` — **лог**;
  /// - `ChatStreamDelta` — **обновление** **текста** **в** **последнем**
  ///   **AI-сообщении**;
  /// - `ChatStreamCompleted` — **финализация** (**текст**, `messageId`,
  ///   **сессия**, **догрузка** **sources** **для** **RAG**, **очистка**
  ///   **вложений**);
  /// - `ChatStreamFailed` — **пометка** **пустого** **AI-пузыря**
  ///   **как** `failed`.
  ///
  /// **Почему** **отдельный** **метод**: **та** **же** **логика**
  /// **используется** **в** `sendMessage` **и** `retryLastMessage`.
  /// **Дубль** `switch` **был** **бы** **~30** **строк** **в** **двух**
  /// **местах** — **риск** **разъехаться**. **Один** **метод** — **один**
  /// **источник** **правды**.
  ///
  /// **Почему** **не** **в** `ChatMessageSender`: **обновляет** **state**
  /// (**это** **работа** `ChatNotifier`, **не** **сервиса**).
  Future<void> _processStreamEvents({
    required Stream<ChatStreamEvent> events,
    required String agentId,
    required String sessionId,
    required String? ragId,
  }) async {
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
          // `modelFromResponse`.
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

          // Догрузка sources — для RAG, если messageId пришёл.
          //
          // **Фаза 3.3 рефакторинга**: вызов сервиса
          // `ChatSourcesFetcher.fetchForMessage` — вместо локального
          // `_loadSourcesForMessage`.
          if (ragId != null && messageId != null && messageId.isNotEmpty) {
            unawaited(
              _fetchAndApplySourcesForMessage(
                agentId: agentId,
                messageId: messageId,
              ),
            );
          }

          _ref.read(attachmentDraftProvider.notifier).clear();
          break;

        case ChatStreamFailed(:final error):
          _markLastAiMessageAsFailed(error.userMessage);
          break;
      }
    }
  }

  // ============================================================
  // ПОВТОР ОТПРАВКИ (для failed-сообщений)
  // ============================================================

  /// Повторить последнее user-сообщение, если после него — failed-AI.
  ///
  /// **Фаза 3.2 рефакторинга**: отправка делегирует
  /// `ChatMessageSender.send` (как и в `sendMessage`).
  /// Обработка событий — общий `_processStreamEvents`.
  ///
  /// **Логика:**
  /// 1. Найти индекс последнего **user**-сообщения (с конца).
  /// 2. Найти индекс последнего **assistant**-сообщения (после user).
  /// 3. Проверить, что assistant — **failed**. Иначе — тихо выходим.
  /// 4. Заменить failed-пузырь на **пустой** `ok`-пузырь.
  /// 5. Запустить `_messageSender.send` с **тем же** текстом
  ///    user-сообщения и обработать события через `_processStreamEvents`.
  Future<void> retryLastMessage() async {
    if (state.isLoading) {
      AppLogger.warning('retryLastMessage: уже идёт отправка — пропускаем');
      return;
    }

    // 1. Найти последнее user-сообщение.
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

    // 2. Индекс assistant — следующий после user.
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
        _setError('Не удалось повторить: сессия потеряна.');
        return;
      }

      // Запускаем стрим через сервис (как в `sendMessage`).
      //
      // **Вложения** для retry **не** передаём: если они были —
      // пользователь уже отправил их, и повтор без файлов —
      // корректное поведение (файлы уже на сервере).
      final events = _messageSender.send(
        text: userText,
        agentId: currentAgentId,
        sessionId: currentSessionId,
        ragId: ragId,
        attachments: const [],
      );

      await _processStreamEvents(
        events: events,
        agentId: currentAgentId,
        sessionId: currentSessionId,
        ragId: ragId,
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

  // ============================================================
  // ДОГРУЗКА SOURCES (для одного сообщения — после стрима)
  // ============================================================

  /// Загрузить sources **для** **одного** **сообщения** **и** **применить**
  /// **к** **state**.
  ///
  /// **Когда** **вызывается**: **после** **стрима**
  /// (`ChatStreamCompleted`), **если** **это** **RAG-чат**.
  ///
  /// **Что** **делает**:
  /// 1. **Вызывает** `_sourcesFetcher.fetchForMessage` (**сервис**
  ///    **загрузки**). **Ошибки** **логируются** **внутри** **сервиса**,
  ///    **не** **пробрасываются** (**sources** **вторичны**).
  /// 2. **Применяет** **через** `_updateSourcesForMessage` (**для**
  ///    **одного** **сообщения**).
  ///
  /// **Fire-and-forget**: **не** **блокируем** **пользователя**.
  /// **Ответ** **уже** **получен**, sources — **вторичны**.
  Future<void> _fetchAndApplySourcesForMessage({
    required String agentId,
    required String messageId,
  }) async {
    final sources = await _sourcesFetcher.fetchForMessage(
      agentId: agentId,
      messageId: messageId,
    );

    if (sources.isEmpty) {
      AppLogger.debug(
        'Sources пусто для сообщения $messageId — оставляем как есть',
      );
      return;
    }

    // **Применяем** **через** **отдельный** **метод** —
    // **потому** **что** **у** **этого** **сценария** **своя** **логика**
    // (**один** **messageId**, **поиск** **по** **индексу**).
    //
    // **Почему** **не** **объединяем** **с** `_applySourcesToMessages`:
    // см. комментарий **к** `_updateSourcesForMessage`.
    _updateSourcesForMessage(messageId: messageId, sources: sources);
  }

  /// Обновить sources у **одного** сообщения с указанным id.
  ///
  /// **Когда** **используется**: **после** **стрима** (**один**
  /// `messageId`) — через `_fetchAndApplySourcesForMessage`.
  ///
  /// **Что** **делает**:
  /// - **ищет** **индекс** **по** `id` **в** `state.messages`;
  /// - **если** **не** **нашёл** — **тихо** **выходит** (**пользователь**
  ///   **мог** **уже** **начать** **новый** **чат**, **или** **сообщение**
  ///   **удалено**);
  /// - **заменяет** **сообщение** **на** **копию** **с** `sources`;
  /// - **обновляет** `state` **один** **раз** (**атомарно**).
  ///
  /// **Почему** **не** **объединяем** **с** `_applySourcesToMessages`:
  ///
  /// **Это** **два** **разных** **сценария**:
  /// - **`_updateSourcesForMessage`** — **один** **messageId**, **известен**
  ///   **заранее** (**после** **стрима**). **Логика**: **найти** **по**
  ///   **индексу** **→** **заменить**.
  /// - **`_applySourcesToMessages`** — **много** **messageId** (**история**).
  ///   **Логика**: **пройти** **по** **всем** → **применить** **из** `Map`.
  ///
  /// **Почему** **не** **объединять** (**с** **учётом** **будущих** **фич**):
  /// - **Кеширование**: **для** **истории** **sources** **могут** **прийти**
  ///   **из** **кеша** (**устаревшие**), **понадобится** **валидация**
  ///   (**например**, **скрыть**, **если** **документ** **удалён**).
  ///   **Для** **стрима** — **sources** **всегда** **свежие** (**валидация**
  ///   **не** **нужна**).
  /// - **Авторизация**: **оба** **сценария** **работают** **с** **уже**
  ///   **загруженными** **sources**, **но** **логика** **применения**
  ///   **может** **разойтись** (**например**, **для** **истории** —
  ///   **доп** **проверка** **доступа**).
  /// - **Настройки** **UI**: **могут** **влиять** **на** **отображение**
  ///   (**но** **это** **в** **UI**, **не** **в** `ChatNotifier`).
  ///
  /// **Дубль** **финальной** **строки** (`state = state.copyWith(...)`) —
  /// **2** **строки** **на** **два** **метода**. **Это** **не** **дубль**
  /// **логики**, **а** **неизбежная** **атомарная** **запись** **в** **state**.
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

  /// Применить **батчи** sources к сообщениям в state.
  ///
  /// **Когда** **используется**: **при** **загрузке** **истории**
  /// **RAG-чата** (`loadChat`) — **для** **многих** **messageId**.
  ///
  /// **Откуда** **батчи**: `ChatSourcesFetcher.fetchForHistory` вернул
  /// `Map<messageId, List<MessageSource>>` — **только** для тех
  /// сообщений, у которых **есть** sources. **Порядок** **не** **важен**.
  ///
  /// **Что делает**:
  /// 1. Проходит по **актуальному** `state.messages` (за время загрузки
  ///    пользователь мог отправить новое сообщение — не потеряем).
  /// 2. Для каждого сообщения — **если** `messageId` есть в батче —
  ///    **ставит** sources.
  /// 3. **Если** у сообщения **уже** есть sources — **не** перезаписывает
  ///    (например, пользователь **успел** получить **новый** ответ
  ///    через `sendMessage`, пока шла загрузка — там sources уже есть).
  /// 4. **Один** `state = ...` — без мерцания.
  ///
  /// **Почему** **именно** **так**:
  /// - **актуальный** state — пользователь мог отправить новое сообщение
  ///   пока шла загрузка (200 мс);
  /// - **не** перезаписывать существующие sources — «не трогай то,
  ///   что уже работает»;
  /// - **один** state — атомарное обновление.
  ///
  /// **Почему** **не** **объединяем** **с** `_updateSourcesForMessage`:
  /// **два** **разных** **сценария** (**один** **vs** **много**),
  /// **разная** **логика** (**поиск** **по** **индексу** **vs** **проход**
  /// **по** **всем**), **разная** **расширяемость** (**см.** **комментарий**
  /// **к** `_updateSourcesForMessage`).
  void _applySourcesToMessages(
    Map<String, List<MessageSource>> sourcesByMessageId,
  ) {
    final currentMessages = state.messages;
    var anyUpdated = false;
    final newMessages = <Message>[];

    for (final message in currentMessages) {
      final sources = sourcesByMessageId[message.id];

      // Нет sources в батче — оставляем сообщение как есть.
      if (sources == null || sources.isEmpty) {
        newMessages.add(message);
        continue;
      }

      // У сообщения уже есть sources — не перезаписываем.
      if (message.sources != null && message.sources!.isNotEmpty) {
        newMessages.add(message);
        continue;
      }

      newMessages.add(message.copyWith(sources: sources));
      anyUpdated = true;
    }

    if (anyUpdated) {
      state = state.copyWith(messages: newMessages);
      AppLogger.info(
        'Применены sources к ${sourcesByMessageId.length} сообщениям',
      );
    } else {
      AppLogger.debug('Нечего применять — sources уже есть или пусты');
    }
  }

  // ============================================================
  // ЗАГРУЗКА И УПРАВЛЕНИЕ ЧАТОМ
  // ============================================================

  /// Загрузить чат из истории.
  ///
  /// Загружает сообщения чата (и sources для RAG) и обновляет SSOT-сессию.
  ///
  /// **Фаза 3.1 рефакторинга**: логика загрузки messages вынесена в
  /// [ChatHistoryLoader]. **Фаза 3.3**: sources — через
  /// [ChatSourcesFetcher].
  ///
  /// **Что делает:**
  /// 1. Загружает messages через `_historyLoader.load`.
  /// 2. Применяет messages к state (`_setMessages`).
  /// 3. Получает displayName из `agentsByIdProvider` (Riverpod — не в сервисе).
  /// 4. Устанавливает сессию (`setSession`).
  /// 5. Для RAG: загружает sources через `_sourcesFetcher.fetchForHistory`
  ///    и применяет к state.
  ///
  /// **Что НЕ делает:**
  /// - не ходит по HTTP напрямую — это в сервисах;
  /// - не парсит ответы — это в сервисах;
  /// - не полагается на порядок sources — применяет по `messageId`.
  Future<void> loadChat(String agentId, String chatId, String? ragId) async {
    AppLogger.info('Загрузка чата: агент=$agentId, чат=$chatId, ragId=$ragId');

    _setLoading(true);
    _clearError();

    try {
      // 1. Загружаем messages через сервис.
      final result = await _historyLoader.load(
        agentId: agentId,
        chatId: chatId,
        ragId: ragId,
      );

      // 2. Применяем messages к state.
      _setMessages(result.messages);

      // 3. displayName — из провайдера (сервис про Riverpod не знает).
      final displayName = _ref.read(agentsByIdProvider)[agentId]?.name;

      // 4. Устанавливаем сессию.
      //
      // `ragId` передаём явно (может быть null) — чтобы перезаписать
      // старое значение (если в предыдущей сессии остался ragId,
      // а сейчас открыли обычный чат).
      _ref
          .read(sessionProvider.notifier)
          .setSession(
            agentId,
            chatId,
            ragId: ragId,
            agentDisplayName: displayName,
          );

      AppLogger.info('Загружено сообщений: ${result.messages.length}');

      // 5. Для RAG — загружаем sources через сервис и применяем к state.
      //
      // **`await`** — ждём загрузки, потом применяем. Это **небольшая**
      // задержка (~200 мс) — приемлемо (пользователь **видит** сообщения
      // **уже**, sources — **догружаются** фоном).
      //
      // **Альтернатива** — `unawaited` (не ждать). Но тогда тесты
      // сложнее (надо ждать «до применения sources»). С `await` —
      // тест проще: после `loadChat` state уже с sources.
      if (ragId != null) {
        // **Собираем** `messageIds` **всех** **assistant-сообщений**
        // **с** **непустым** **id** — **только** **у** **них** **есть**
        // sources **на** **сервере**.
        final messageIds = result.messages
            .where((m) => !m.isFromUser && m.id.isNotEmpty)
            .map((m) => m.id)
            .toList();

        if (messageIds.isNotEmpty) {
          // **Параллельно** **загружаем** **sources** **для** **всех**
          // **assistant-сообщений** (**через** **сервис**).
          final batches = await _sourcesFetcher.fetchForHistory(
            agentId: agentId,
            messageIds: messageIds,
          );

          // **Превращаем** `List<SourcesBatch>` в
          // `Map<messageId, List<MessageSource>>` — **единый** **формат**
          // **для** `_applySourcesToMessages`.
          final sourcesByMessageId = <String, List<MessageSource>>{
            for (final batch in batches) batch.messageId: batch.sources,
          };

          if (sourcesByMessageId.isNotEmpty) {
            _applySourcesToMessages(sourcesByMessageId);
          }
        }
      }
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

/// Провайдер для `ChatHistoryLoader`.
///
/// **Зависимости**: `ChatRepository` (для HTTP).
///
/// **Кто** **читает**: `chatProvider` (**через** `ChatNotifier`).
///
/// **Фаза** **3.1** **рефакторинга**: сервис вынесен из `ChatNotifier`,
/// провайдер — новый.
final chatHistoryLoaderProvider = Provider<ChatHistoryLoader>((ref) {
  final repository = ref.read(chatRepositoryProvider);
  return ChatHistoryLoader(repository: repository);
});

/// Провайдер для `ChatMessageSender`.
///
/// **Зависимости**:
/// - `SendMessageUseCase` (HTTP + SSE);
/// - `ChatStreamHandler` (парсинг событий).
///
/// **Кто** **читает**: `chatProvider` (**через** `ChatNotifier`).
///
/// **Фаза** **3.2** **рефакторинга**: сервис вынесен из `ChatNotifier`,
/// провайдер — новый.
final chatMessageSenderProvider = Provider<ChatMessageSender>((ref) {
  final sendMessageUseCase = ref.read(sendMessageUseCaseProvider);
  final streamHandler = ref.read(chatStreamHandlerProvider);
  return ChatMessageSender(
    sendMessageUseCase: sendMessageUseCase,
    streamHandler: streamHandler,
  );
});

/// Провайдер для `ChatSourcesFetcher`.
///
/// **Зависимости**: `ChatRepository` (для HTTP).
///
/// **Кто** **читает**: `chatProvider` (**через** `ChatNotifier`).
///
/// **Фаза** **3.3** **рефакторинга**: сервис вынесен из `ChatNotifier`,
/// провайдер — новый.
final chatSourcesFetcherProvider = Provider<ChatSourcesFetcher>((ref) {
  final repository = ref.read(chatRepositoryProvider);
  return ChatSourcesFetcher(repository: repository);
});

/// Основной провайдер чата.
///
/// **Зависимости:**
/// - `chatRepositoryProvider` — репозиторий (для сервисов);
/// - `chatHistoryLoaderProvider` — загрузка истории;
/// - `chatMessageSenderProvider` — отправка сообщений;
/// - `chatSourcesFetcherProvider` — загрузка sources.
///
/// **Фаза** **3.3** **рефакторинга**: `ChatNotifier` **теперь** **тонкий**
/// (~500 **строк** **вместо** ~700) — **логика** **в** **сервисах**.
/// **State** — **здесь**, **в** `ChatNotifier`.
final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  final repository = ref.read(chatRepositoryProvider);
  final historyLoader = ref.read(chatHistoryLoaderProvider);
  final messageSender = ref.read(chatMessageSenderProvider);
  final sourcesFetcher = ref.read(chatSourcesFetcherProvider);

  return ChatNotifier(
    ref: ref,
    repository: repository,
    historyLoader: historyLoader,
    messageSender: messageSender,
    sourcesFetcher: sourcesFetcher,
  );
});
