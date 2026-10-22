// lib/domain/services/chat_history_loader.dart

import '../../core/logger/app_logger.dart';
import '../../data/repositories/chat_repository.dart';
import '../models/message.dart';

/// Результат загрузки истории чата.
///
/// **Что** **содержит**:
/// - `messages` — **загруженные** **сообщения**;
/// - `displayName` — **человекочитаемое** **имя** **агента** (**задел**
///   **на** **будущее**; **сейчас** **не** **заполняется** — **`ChatNotifier`**
///   **берёт** **из** **`agentsByIdProvider`**).
///
/// **Про** **sources** — **их** **здесь** **НЕТ**.
///
/// **История** **этого** **решения**: **изначально** `ChatHistoryLoader`
/// **загружал** **sources** **для** **RAG** **сам**. **Потом** **вынесли**
/// **в** `ChatSourcesFetcher` (**Фаза** **3.3**). **Дубль** **убрали**
/// **здесь** — **теперь** **sources** **загружает** **только**
/// `ChatSourcesFetcher`.
///
/// **Почему** **так** **правильнее**:
/// - **Один** **сервис** — **одна** **ответственность**
///   (**`ChatHistoryLoader`** — **messages**, **`ChatSourcesFetcher`** — **sources**);
/// - **Нет** **двойной** **загрузки** (**`getSources`** **вызывался**
///   **дважды** — **из** **этого** **сервиса** **и** **из** `ChatNotifier`);
/// - **Тесты** **проще** (**каждый** **сервис** **тестируется** **отдельно**).
class ChatHistoryLoadResult {
  /// Загруженные сообщения чата.
  final List<Message> messages;

  /// Человекочитаемое имя агента (для AppBar).
  ///
  /// `null`, **если** **агент** **не** **найден** **в** `agentsByIdProvider`
  /// (**например**, **агенты** **ещё** **не** **загружены** **или** **не** **пришли**
  /// **с** **сервера**). **UI** **покажет** **fallback** («AI** **Ассистент»**).
  ///
  /// **Сейчас** **не** **заполняется** — **`ChatNotifier`** **сам** **берёт**
  /// `displayName` **из** **провайдера**. **Поле** — **задел** **на** **будущее**
  /// (**если** **понадобится** **передавать** **из** **сервиса**).
  final String? displayName;

  const ChatHistoryLoadResult({required this.messages, this.displayName});
}

/// Загрузчик истории чата.
///
/// **Ответственность** — **только** **загрузка** `messages`
/// **из** `ChatRepository.getMessages`.
///
/// **Что** **НЕ** **делает**:
/// - **не** **управляет** **state** (**это** `ChatNotifier`);
/// - **не** **устанавливает** **сессию** (**это** `ChatNotifier`);
/// - **не** **загружает** **sources** (**это** `ChatSourcesFetcher`);
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

  /// Загрузить историю чата (**только** **messages**).
  ///
  /// **Параметры**:
  /// - [agentId] — **id** **агента** (**для** **путей** `/agents/{agentId}/...`);
  /// - [chatId] — **id** **чата** (`conversation_id`);
  /// - [ragId] — **id** **RAG-набора** (**только** **для** **RAG-чатов**,
  ///   **иначе** `null`). **НЕ** **используется** **здесь** — **оставлен**
  ///   **для** **сигнатуры** **на** **случай**, **если** **в** **будущем**
  ///   **понадобится** **разная** **логика** **для** **RAG** **и** **не-RAG**.
  ///
  /// **Что** **делает**:
  /// - **вызывает** `_repository.getMessages`;
  /// - **возвращает** [ChatHistoryLoadResult] **с** **messages**.
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

    final messages = await _repository.getMessages(
      agentId: agentId,
      conversationId: chatId,
    );

    AppLogger.info('ChatHistoryLoader: загружено ${messages.length} сообщений');

    return ChatHistoryLoadResult(messages: messages);
  }
}
