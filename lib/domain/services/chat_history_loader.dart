// lib/domain/services/chat_history_loader.dart

import '../../core/logger/app_logger.dart';
import '../../data/repositories/chat_repository.dart';
import '../models/message.dart';
import '../models/message_source.dart';

/// Результат загрузки истории чата.
///
/// **Зачем** **отдельный** **класс** **вместо** `List<Message>`:
/// **сервис** **загружает** **три** **вещи** **одним** **вызовом**:
/// - **messages** (**история** **чата**);
/// - **displayName** (**имя** **агента** **для** **AppBar**);
/// - **sources** (**Map** `messageId → sources` — **для** **RAG**).
///
/// **Возвращать** **всё** **вместе** — **удобнее**, **чем** **три**
/// **отдельных** **вызова** (**и** **быстрее**).
class ChatHistoryLoadResult {
  /// Загруженные сообщения чата.
  final List<Message> messages;

  /// Человекочитаемое имя агента (для AppBar).
  ///
  /// `null`, **если** **агент** **не** **найден** **в** `agentsByIdProvider`
  /// (**например**, **агенты** **ещё** **не** **загружены** **или** **не** **пришли**
  /// **с** **сервера**). **UI** **покажет** **fallback** («AI** **Ассистент»**).
  final String? displayName;

  /// Sources **для** **каждого** **assistant-сообщения** (**только** **для** **RAG**).
  ///
  /// **Пустая** **Map** — **если**:
  /// - **это** **не** **RAG-чат** (`ragId == null`);
  /// - **или** **sources** **не** **загружены** (**ошибка**, **пусто**).
  ///
  /// **Ключ** — `messageId` (тот **же**, **что** **в** `Message.id`).
  /// **Значение** — **список** **sources** (**может** **быть** **пустым**).
  final Map<String, List<MessageSource>> sourcesByMessageId;

  const ChatHistoryLoadResult({
    required this.messages,
    this.displayName,
    this.sourcesByMessageId = const {},
  });
}

/// Загрузчик истории чата.
///
/// **Ответственность** — **только** **загрузка**:
/// - `messages` **из** `ChatRepository.getMessages`;
/// - `displayName` **агента** — **передаётся** **снаружи** (**знает**
///   `ChatNotifier`, **через** `agentsByIdProvider`);
/// - `sources` **для** **RAG** — **через** `ChatRepository.getSources`.
///
/// **Что** **НЕ** **делает**:
/// - **не** **управляет** **state** (**это** `ChatNotifier`);
/// - **не** **устанавливает** **сессию** (**это** `ChatNotifier`);
/// - **не** **логирует** **ошибки** **сам** (**пробрасывает** **наверх**).
///
/// **Почему** **stateless**: **каждый** **вызов** `load` — **независимый**.
/// **State** **живёт** **в** `ChatNotifier`. **Сервис** **только** **загружает**.
///
/// **Почему** **не** **принимает** `Ref`: **сервис** **не** **должен** **знать**
/// **про** **Riverpod**. **Зависимости** — **через** **конструктор**
/// (`ChatRepository`), **всё** **остальное** — **снаружи**.
class ChatHistoryLoader {
  final ChatRepository _repository;

  ChatHistoryLoader({required ChatRepository repository})
    : _repository = repository;

  /// Загрузить историю чата.
  ///
  /// **Параметры**:
  /// - [agentId] — **id** **агента** (**для** **путей** `/agents/{agentId}/...`);
  /// - [chatId] — **id** **чата** (`conversation_id`);
  /// - [ragId] — **id** **RAG-набора** (**только** **для** **RAG-чатов**,
  ///   **иначе** `null`).
  ///
  /// **Что** **делает**:
  /// 1. **Загружает** `messages` **через** `_repository.getMessages`.
  /// 2. **Если** `ragId != null` — **параллельно** **загружает** **sources**
  ///    **для** **всех** **assistant-сообщений** **с** **непустым** **id**.
  /// 3. **Возвращает** [ChatHistoryLoadResult].
  ///
  /// **`displayName`** **здесь** **не** **заполняется** — **это** **забота**
  /// **вызывающего** **кода** (**`ChatNotifier`**), **потому** **что**
  /// `agentsByIdProvider` — **Riverpod-провайдер**, **а** **сервис**
  /// **не** **должен** **знать** **про** **Riverpod**.
  ///
  /// **Ошибки** **не** **логируются** **здесь** — **пробрасываются**
  /// **наверх**. `ChatNotifier` **сам** **решит**, **как** **их**
  /// **обработать** (**через** `ErrorHandler`).
  Future<ChatHistoryLoadResult> load({
    required String agentId,
    required String chatId,
    String? ragId,
  }) async {
    AppLogger.info(
      'ChatHistoryLoader.load: agentId=$agentId, chatId=$chatId, '
      'ragId=$ragId',
    );

    // 1. Загружаем messages.
    final messages = await _repository.getMessages(
      agentId: agentId,
      conversationId: chatId,
    );

    AppLogger.info('ChatHistoryLoader: загружено ${messages.length} сообщений');

    // 2. Если это RAG-чат — параллельно грузим sources.
    //
    // **`ragId != null`** — единственный признак RAG-чата. **Для**
    // **`document_chat`** и **обычных** **агентов** — sources **приходят**
    // **в** **самих** **messages** (**через** `MessageDto.sources`),
    // **отдельная** **ручка** **не** **нужна**.
    if (ragId == null) {
      return ChatHistoryLoadResult(messages: messages);
    }

    // **Найти** **assistant-сообщения** **с** **непустым** **id** — **только**
    // **у** **них** **есть** **sources** **на** **сервере**.
    final assistants = messages
        .where((m) => !m.isFromUser && m.id.isNotEmpty)
        .toList();

    if (assistants.isEmpty) {
      AppLogger.debug('ChatHistoryLoader: нет assistant-сообщений для sources');
      return ChatHistoryLoadResult(messages: messages);
    }

    // **Параллельно** **загружаем** **sources** **для** **всех**
    // **assistant-сообщений**. Ошибки **одного** **не** **должны**
    // **ронять** **остальные** — **`catchError`** **внутри**.
    final sourcesByMessageId = <String, List<MessageSource>>{};

    await Future.wait(
      assistants.map((m) async {
        try {
          final sources = await _repository.getSources(
            agentId: agentId,
            messageId: m.id,
          );
          if (sources.isNotEmpty) {
            sourcesByMessageId[m.id] = sources;
          }
        } catch (e, stackTrace) {
          // Ошибку **логируем**, **но** **не** **роняем** `Future.wait` —
          // остальные **sources** **всё** **равно** **нужны**.
          AppLogger.logException(
            'ChatHistoryLoader: ошибка загрузки sources для ${m.id}',
            e,
            stackTrace,
            {'agentId': agentId, 'messageId': m.id},
          );
        }
      }),
    );

    AppLogger.info(
      'ChatHistoryLoader: загружено sources для '
      '${sourcesByMessageId.length} из ${assistants.length}',
    );

    return ChatHistoryLoadResult(
      messages: messages,
      sourcesByMessageId: sourcesByMessageId,
    );
  }
}
