// test/providers/chat_provider_test.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:tidi_assistant_flutter/core/errors/business_exceptions.dart';
import 'package:tidi_assistant_flutter/core/errors/network_exceptions.dart';
import 'package:tidi_assistant_flutter/data/repositories/chat_repository.dart';
import 'package:tidi_assistant_flutter/domain/models/agent.dart';
import 'package:tidi_assistant_flutter/domain/models/attachment.dart';
import 'package:tidi_assistant_flutter/domain/models/chat_session.dart';
import 'package:tidi_assistant_flutter/domain/models/message.dart';
import 'package:tidi_assistant_flutter/domain/models/message_source.dart';
import 'package:tidi_assistant_flutter/domain/models/message_status.dart';
import 'package:tidi_assistant_flutter/domain/services/chat_message_sender.dart';
import 'package:tidi_assistant_flutter/domain/services/chat_stream_event.dart';
import 'package:tidi_assistant_flutter/providers/agent_provider.dart';
import 'package:tidi_assistant_flutter/providers/chat_provider.dart';
import 'package:tidi_assistant_flutter/providers/session_provider.dart';

/// Тесты на `ChatNotifier` — **страховка** перед/после рефакторинга.
///
/// **Фаза 1**: «золотые» тесты (createNewChat, clearChat, clearError,
/// loadChat, sendMessage — ошибка getRoute, retryLastMessage — нет user).
///
/// **Фаза 4.1**: happy path (`sendMessage`, `retryLastMessage`),
/// догрузка sources (после стрима, из истории).
///
/// **Принцип**: проверяем **поведение** (state), а не реализацию.
/// Рефакторинг `ChatNotifier` не должен их сломать.

// ============================================================
// ФЕЙКИ
// ============================================================

class FakeChatRepository implements ChatRepository {
  String Function(String message)? onGetRoute;
  ChatSession Function(String agentId, String? title, String? ragId)?
  onCreateConversation;
  List<Message> Function(String agentId, String conversationId)? onGetMessages;
  List<MessageSource> Function(String agentId, String messageId)? onGetSources;

  int getRouteCalls = 0;
  int createConversationCalls = 0;
  int getMessagesCalls = 0;
  int getSourcesCalls = 0;
  int sendMessageStreamCalls = 0;

  @override
  Future<List<Agent>> getAgents() async => const [];

  @override
  Future<String> getRoute(String message) async {
    getRouteCalls++;
    if (onGetRoute == null) {
      throw StateError('FakeChatRepository.onGetRoute не задан');
    }
    return onGetRoute!(message);
  }

  @override
  Future<ChatSession> createConversation({
    required String agentId,
    String? title,
    String? ragId,
  }) async {
    createConversationCalls++;
    if (onCreateConversation == null) {
      throw StateError('FakeChatRepository.onCreateConversation не задан');
    }
    return onCreateConversation!(agentId, title, ragId);
  }

  @override
  Future<List<ChatSession>> getConversations({required String agentId}) async {
    return const [];
  }

  @override
  Future<List<Message>> getMessages({
    required String agentId,
    required String conversationId,
  }) async {
    getMessagesCalls++;
    if (onGetMessages == null) {
      throw StateError('FakeChatRepository.onGetMessages не задан');
    }
    return onGetMessages!(agentId, conversationId);
  }

  @override
  Future<List<MessageSource>> getSources({
    required String agentId,
    required String messageId,
  }) async {
    getSourcesCalls++;
    if (onGetSources == null) return const [];
    return onGetSources!(agentId, messageId);
  }

  @override
  Future<void> renameConversation({
    required String agentId,
    required String conversationId,
    required String title,
  }) async {}

  @override
  Future<void> deleteConversation({
    required String agentId,
    required String conversationId,
  }) async {}

  @override
  Future<http.StreamedResponse> sendMessageStream({
    required String text,
    String? conversationId,
    String? agentId,
    String? ragId,
    List<Attachment> attachments = const [],
  }) async {
    sendMessageStreamCalls++;
    throw UnimplementedError(
      'sendMessageStream для тестов не нужен — '
      'используй FakeChatMessageSender.',
    );
  }
}

/// Фейковый `ChatMessageSender`.
///
/// **Зачем**: `ChatNotifier.sendMessage` **вызывает** `_messageSender.send`
/// **и** **обрабатывает** **события**. **В** **тестах** — **подменяем**
/// **сервис** **фейком** **с** **заранее** **заготовленным** **потоком**.
class FakeChatMessageSender implements ChatMessageSender {
  Stream<ChatStreamEvent> Function({
    required String text,
    required String agentId,
    required String? sessionId,
    required String? ragId,
    required List<Attachment> attachments,
  })?
  onSend;

  int sendCalls = 0;

  @override
  Stream<ChatStreamEvent> send({
    required String text,
    required String agentId,
    required String? sessionId,
    required String? ragId,
    required List<Attachment> attachments,
  }) {
    sendCalls++;
    if (onSend == null) {
      throw StateError('FakeChatMessageSender.onSend не задан');
    }
    return onSend!(
      text: text,
      agentId: agentId,
      sessionId: sessionId,
      ragId: ragId,
      attachments: attachments,
    );
  }
}

void main() {
  // ============================================================
  // ИНФРАСТРУКТУРА
  // ============================================================

  /// Создать `ProviderContainer` с подменёнными провайдерами.
  ///
  /// **Что подменяем:**
  /// - `chatRepositoryProvider` → `FakeChatRepository`;
  /// - `agentsProvider` → пустой список (для `loadChat`);
  /// - `chatMessageSenderProvider` → `FakeChatMessageSender`
  ///   (**если** **передан** — **для** **тестов** `sendMessage` **с** **потоком**).
  ProviderContainer makeContainer({
    required FakeChatRepository fakeRepository,
    FakeChatMessageSender? fakeSender,
  }) {
    return ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(fakeRepository),
        agentsProvider.overrideWith((ref) async => <Agent>[]),
        if (fakeSender != null)
          chatMessageSenderProvider.overrideWithValue(fakeSender),
      ],
    );
  }

  // ============================================================
  // ТЕСТ 1: createNewChat
  // ============================================================

  group('ChatNotifier.createNewChat', () {
    test('очищает messages, добавляет welcome, сбрасывает сессию', () {
      final fakeRepository = FakeChatRepository();
      final container = makeContainer(fakeRepository: fakeRepository);
      addTearDown(container.dispose);

      final chatNotifier = container.read(chatProvider.notifier);
      final sessionNotifier = container.read(sessionProvider.notifier);

      sessionNotifier.setSession(
        'document_chat',
        'some-session-id',
        agentDisplayName: 'Документы',
      );

      chatNotifier.createNewChat();

      final state = container.read(chatProvider);
      final session = container.read(sessionProvider);

      expect(state.messages.length, 1);
      expect(state.messages.first.isFromUser, false);
      expect(state.messages.first.text, contains('Здравствуйте'));

      expect(session.agentId, isNull);
      expect(session.sessionId, isNull);
      expect(session.ragId, isNull);
      expect(session.agentDisplayName, isNull);
    });
  });

  // ============================================================
  // ТЕСТ 2: clearChat
  // ============================================================

  group('ChatNotifier.clearChat', () {
    test('очищает messages, добавляет welcome, НЕ трогает сессию', () {
      final fakeRepository = FakeChatRepository();
      final container = makeContainer(fakeRepository: fakeRepository);
      addTearDown(container.dispose);

      final chatNotifier = container.read(chatProvider.notifier);
      final sessionNotifier = container.read(sessionProvider.notifier);

      sessionNotifier.setSession(
        'epoz',
        'epoz-session-1',
        agentDisplayName: 'ЕПоЗ',
      );

      chatNotifier.clearChat();

      final state = container.read(chatProvider);
      final session = container.read(sessionProvider);

      expect(state.messages.length, 1);
      expect(state.messages.first.isFromUser, false);

      expect(session.agentId, 'epoz');
      expect(session.sessionId, 'epoz-session-1');
      expect(session.agentDisplayName, 'ЕПоЗ');
    });
  });

  // ============================================================
  // ТЕСТ 3: clearError
  // ============================================================

  group('ChatNotifier.clearError', () {
    test('сбрасывает error в state', () {
      final fakeRepository = FakeChatRepository();
      final container = makeContainer(fakeRepository: fakeRepository);
      addTearDown(container.dispose);

      final notifier = container.read(chatProvider.notifier);

      notifier.clearError();

      final state = container.read(chatProvider);
      expect(state.error, isNull);
    });
  });

  // ============================================================
  // ТЕСТ 4: loadChat — успех / 404
  // ============================================================

  group('ChatNotifier.loadChat', () {
    test('успех: загружает messages и устанавливает сессию', () async {
      final fakeRepository = FakeChatRepository();
      fakeRepository.onGetMessages = (agentId, conversationId) {
        return [
          Message(
            id: 'msg-1',
            text: 'Привет',
            isFromUser: true,
            timestamp: DateTime(2026, 1, 1),
          ),
          Message(
            id: 'msg-2',
            text: 'Здравствуйте',
            isFromUser: false,
            timestamp: DateTime(2026, 1, 1, 0, 0, 1),
          ),
        ];
      };

      final container = makeContainer(fakeRepository: fakeRepository);
      addTearDown(container.dispose);

      final notifier = container.read(chatProvider.notifier);

      await notifier.loadChat('epoz', 'chat-42', null);

      final state = container.read(chatProvider);
      final session = container.read(sessionProvider);

      expect(state.messages.length, 2);
      expect(state.messages.first.text, 'Привет');
      expect(state.messages.last.text, 'Здравствуйте');

      expect(session.agentId, 'epoz');
      expect(session.sessionId, 'chat-42');
      expect(session.ragId, isNull);

      expect(fakeRepository.getMessagesCalls, 1);
    });

    test('404: устанавливает error', () async {
      final fakeRepository = FakeChatRepository();
      fakeRepository.onGetMessages = (agentId, conversationId) {
        throw BusinessException.chatNotFound(conversationId);
      };

      final container = makeContainer(fakeRepository: fakeRepository);
      addTearDown(container.dispose);

      final notifier = container.read(chatProvider.notifier);

      await notifier.loadChat('epoz', 'chat-42', null);

      final state = container.read(chatProvider);
      expect(state.error, isNotNull);
      expect(state.error, contains('найден'));
    });
  });

  // ============================================================
  // ТЕСТ 5: sendMessage — ошибка getRoute
  // ============================================================

  group('ChatNotifier.sendMessage', () {
    // ============================================================
    // ТЕСТ 11: sendMessage в RAG — догружает sources после стрима
    // ============================================================
    //
    // **Зачем**: закрывает «дырку», найденную мутационным тестом.
    // Если сломать `_fetchAndApplySourcesForMessage` (сделать пустым) —
    // **этот** тест упадёт, потому что `getSourcesCalls` **не** станет 1.
    //
    // **Особенность**: загрузка sources — **fire-and-forget**
    // (`unawaited`). Значит, **после** `sendMessage` она может **ещё**
    // не выполниться. Ждём через `pumpEventQueue` (стандарт
    // `flutter_test` для «дождаться microtask'ов»).
    test('RAG: догружает sources после стрима', () async {
      // 1. Готовим fakeRepository.
      final fakeRepository = FakeChatRepository();
      fakeRepository.onCreateConversation = (agentId, title, ragId) {
        return ChatSession(
          id: 'chat-1',
          agentId: agentId,
          title: title,
          ragId: ragId, // ← важно: сохраняем ragId в сессии
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );
      };
      fakeRepository.onGetSources = (agentId, messageId) {
        if (messageId == 'resp_rag_1') {
          return [const MessageSource(filename: 'rag-source.pdf', order: 1)];
        }
        return const [];
      };

      // 2. Готовим fakeSender.
      final fakeSender = FakeChatMessageSender();
      fakeSender.onSend =
          ({
            required String text,
            required String agentId,
            required String? sessionId,
            required String? ragId,
            required List<Attachment> attachments,
          }) {
            return Stream.fromIterable([
              const ChatStreamStarted(),
              const ChatStreamCompleted(
                fullText: 'Ответ',
                messageId: 'resp_rag_1',
                agentId: 'agentic_rag',
                conversationId: 'chat-1',
              ),
            ]);
          };

      // 3. Создаём контейнер.
      final container = makeContainer(
        fakeRepository: fakeRepository,
        fakeSender: fakeSender,
      );
      addTearDown(container.dispose);

      // 4. Устанавливаем сессию с ragId — **иначе** `sendMessage`
      //    пойдёт по ветке «новый чат» (без ragId), и sources
      //    не будут загружаться.
      container
          .read(sessionProvider.notifier)
          .setSession('agentic_rag', 'chat-1', ragId: 'rag-1');

      // 5. Вызываем.
      final notifier = container.read(chatProvider.notifier);
      await notifier.sendMessage(text: 'вопрос');

      // 6. Ждём завершения fire-and-forget (`unawaited`) —
      //    `getSources` в `_fetchAndApplySourcesForMessage`.
      await pumpEventQueue();

      // 7. Проверки.
      expect(fakeRepository.getSourcesCalls, 1);

      final state = container.read(chatProvider);
      final lastMessage = state.messages.last;
      expect(lastMessage.sources, isNotNull);
      expect(lastMessage.sources!.length, 1);
      expect(lastMessage.sources!.first.filename, 'rag-source.pdf');
    });
    test('ошибка /route: удаляет пустой AI-пузырь, ставит error', () async {
      final fakeRepository = FakeChatRepository();
      fakeRepository.onGetRoute = (message) {
        throw NetworkException.connectionError();
      };

      final container = makeContainer(fakeRepository: fakeRepository);
      addTearDown(container.dispose);

      final notifier = container.read(chatProvider.notifier);

      await notifier.sendMessage(text: 'привет');

      final state = container.read(chatProvider);

      expect(state.error, isNotNull);

      // welcome + user = 2 (пустой AI-пузырь удалён).
      expect(state.messages.length, 2);
      expect(state.messages.last.isFromUser, true);
      expect(state.messages.last.text, 'привет');

      expect(fakeRepository.getRouteCalls, 1);
    });

    // ============================================================
    // ТЕСТ 7: sendMessage — happy path (новый тест, Фаза 4.1)
    // ============================================================

    test('успех: пользователь → AI, обновляет state', () async {
      final fakeRepository = FakeChatRepository();
      fakeRepository.onGetRoute = (_) => 'epoz';
      fakeRepository.onCreateConversation = (agentId, title, ragId) {
        return ChatSession(
          id: 'chat-1',
          agentId: agentId,
          title: title,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );
      };

      final fakeSender = FakeChatMessageSender();
      fakeSender.onSend =
          ({
            required String text,
            required String agentId,
            required String? sessionId,
            required String? ragId,
            required List<Attachment> attachments,
          }) {
            return Stream.fromIterable([
              const ChatStreamStarted(),
              const ChatStreamDelta(fullText: 'Привет'),
              const ChatStreamCompleted(
                fullText: 'Привет',
                messageId: 'resp_1',
                agentId: 'epoz',
                conversationId: 'chat-1',
              ),
            ]);
          };

      final container = makeContainer(
        fakeRepository: fakeRepository,
        fakeSender: fakeSender,
      );
      addTearDown(container.dispose);

      final notifier = container.read(chatProvider.notifier);

      await notifier.sendMessage(text: 'привет');

      final state = container.read(chatProvider);
      final session = container.read(sessionProvider);

      // welcome + user + AI = 3
      expect(state.messages.length, 3);
      expect(state.messages[1].text, 'привет');
      expect(state.messages[1].isFromUser, true);
      expect(state.messages[2].text, 'Привет');
      expect(state.messages[2].isFromUser, false);
      expect(state.messages[2].id, 'resp_1');

      expect(session.agentId, 'epoz');
      expect(session.sessionId, 'chat-1');

      expect(fakeSender.sendCalls, 1);
    });
  });

  // ============================================================
  // ТЕСТ 6: retryLastMessage — нет user
  // ============================================================

  group('ChatNotifier.retryLastMessage', () {
    test('нет user-сообщения: ничего не делает', () async {
      final fakeRepository = FakeChatRepository();
      final container = makeContainer(fakeRepository: fakeRepository);
      addTearDown(container.dispose);

      final notifier = container.read(chatProvider.notifier);

      await notifier.retryLastMessage();

      final state = container.read(chatProvider);

      expect(state.messages.length, 1);
      expect(state.messages.first.isFromUser, false);

      expect(fakeRepository.sendMessageStreamCalls, 0);
    });

    // ============================================================
    // ТЕСТ 8: retryLastMessage — happy path (новый тест, Фаза 4.1)
    // ============================================================

    test('успех: заменяет failed на AI-ответ', () async {
      final fakeRepository = FakeChatRepository();
      final fakeSender = FakeChatMessageSender();

      // Готовим state: user + failed AI.
      // welcome + user + failed AI = 3.
      //
      // **`copyWith`** — единственный способ **изменить** state
      // (он immutable). Но проще — **через** **публичный** API.
      //
      // Используем sendMessage с ошибкой getRoute — state получит
      // welcome + user, потом надо добавить failed AI. Но это
      // **сложно** (надо **имитировать** **failed**).
      //
      // Проще: сначала **установить** сессию, потом `retryLastMessage`.
      // Но `retryLastMessage` **ищет** `failed` AI — если его нет,
      // **выйдет** **рано**.
      //
      // **Решение**: сначала **провалить** sendMessage через
      // `fakeSender.onSend` (поток с ChatStreamFailed), потом
      // **повторить**.
      fakeRepository.onGetRoute = (_) => 'epoz';
      fakeRepository.onCreateConversation = (agentId, title, ragId) {
        return ChatSession(
          id: 'chat-1',
          agentId: agentId,
          title: title,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );
      };

      // 1. Первый send — «падает» с ChatStreamFailed.
      fakeSender.onSend =
          ({
            required String text,
            required String agentId,
            required String? sessionId,
            required String? ragId,
            required List<Attachment> attachments,
          }) {
            return Stream.fromIterable([
              const ChatStreamStarted(),
              ChatStreamFailed(error: NetworkException.connectionError()),
            ]);
          };

      final container = makeContainer(
        fakeRepository: fakeRepository,
        fakeSender: fakeSender,
      );
      addTearDown(container.dispose);

      final notifier = container.read(chatProvider.notifier);

      await notifier.sendMessage(text: 'привет');

      // Проверили, что AI-сообщение помечено failed.
      var state = container.read(chatProvider);
      expect(state.messages.last.status, MessageStatus.failed);

      // 2. Готовим второй send — «успех».
      fakeSender.onSend =
          ({
            required String text,
            required String agentId,
            required String? sessionId,
            required String? ragId,
            required List<Attachment> attachments,
          }) {
            return Stream.fromIterable([
              const ChatStreamStarted(),
              const ChatStreamDelta(fullText: 'Привет'),
              const ChatStreamCompleted(
                fullText: 'Привет',
                messageId: 'resp_2',
                agentId: 'epoz',
                conversationId: 'chat-1',
              ),
            ]);
          };

      // 3. Повтор.
      await notifier.retryLastMessage();

      state = container.read(chatProvider);

      // welcome + user + AI = 3.
      expect(state.messages.length, 3);
      expect(state.messages.last.text, 'Привет');
      expect(state.messages.last.status, MessageStatus.ok);
      expect(state.messages.last.id, 'resp_2');

      // Сервис вызван дважды (первый send + retry).
      expect(fakeSender.sendCalls, 2);
    });
  });

  // ============================================================
  // ТЕСТ 9: loadChat для RAG — догрузка sources (Фаза 4.1)
  // ============================================================

  group('ChatNotifier.loadChat (RAG sources)', () {
    test('догружает sources для assistant-сообщений', () async {
      final fakeRepository = FakeChatRepository();
      fakeRepository.onGetMessages = (agentId, conversationId) {
        return [
          Message(
            id: 'msg-1',
            text: 'Вопрос',
            isFromUser: true,
            timestamp: DateTime(2026, 1, 1),
          ),
          Message(
            id: 'resp_1',
            text: 'Ответ',
            isFromUser: false,
            timestamp: DateTime(2026, 1, 1, 0, 0, 1),
          ),
        ];
      };
      fakeRepository.onGetSources = (agentId, messageId) {
        if (messageId == 'resp_1') {
          return [const MessageSource(filename: 'a.pdf', order: 1)];
        }
        return const [];
      };

      final container = makeContainer(fakeRepository: fakeRepository);
      addTearDown(container.dispose);

      final notifier = container.read(chatProvider.notifier);

      await notifier.loadChat('agentic_rag', 'chat-42', 'rag-1');

      final state = container.read(chatProvider);

      // У assistant-сообщения — sources.
      final assistant = state.messages.firstWhere((m) => !m.isFromUser);
      expect(assistant.sources, isNotNull);
      expect(assistant.sources!.length, 1);
      expect(assistant.sources!.first.filename, 'a.pdf');

      // Сервис вызван (для одного assistant).
      expect(fakeRepository.getSourcesCalls, 1);
    });
  });
}
