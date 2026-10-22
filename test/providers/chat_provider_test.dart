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
import 'package:tidi_assistant_flutter/providers/agent_provider.dart';
import 'package:tidi_assistant_flutter/providers/chat_provider.dart';
import 'package:tidi_assistant_flutter/providers/session_provider.dart';

/// Тесты на `ChatNotifier` — **страховка** перед рефакторингом.
///
/// **Зачем.** `ChatNotifier` — God-object (~700 строк). Перед разделением
/// на сервисы надо **зафиксировать** текущее поведение тестами. После
/// рефакторинга те же тесты **должны** быть зелёными — значит,
/// поведение **не** изменилось.
///
/// **Что тестируем** (пошагово, от простого к сложному):
/// 1. `createNewChat` — очищает messages, добавляет welcome, сбрасывает
///    сессию.
/// 2. `clearChat` — очищает messages, добавляет welcome, **НЕ** трогает
///    сессию.
/// 3. `clearError` — сбрасывает error.
/// 4. `loadChat` — успех/404.
/// 5. `sendMessage` — ошибка `/route`.
/// 6. `retryLastMessage` — нет user (ничего не делает).
///
/// **Что НЕ тестируем (в этой фазе):**
/// - `sendMessage` happy path — требует `FakeSendMessageUseCase`
///   (сделаем в Фазе 1.2 — когда будем тестировать стрим).
/// - `retryLastMessage` happy path — то же.
/// - Догрузку sources для RAG — то же (нужен фейк с `getSources`).
/// - Приватные методы — покрываются **через** публичные.
///
/// **Принцип:** тесты проверяют **поведение** (state), а не
/// реализацию. Рефакторинг `ChatNotifier` не должен их сломать,
/// потому что **публичный API** и **state** остаются теми же.

// ============================================================
// ФЕЙКИ (заменяют реальные зависимости в тестах)
// ============================================================

/// Фейковый `ChatRepository` для тестов.
///
/// **Зачем.** Реальный `ChatRepository` **ходит** **по** **HTTP**.
/// В **тестах** **нельзя** **ходить** **в** **сеть** (**нет** **сервера**,
/// **медленно**, **нестабильно**).
///
/// **Что делаем.** **Наследуемся** **от** **реального** `ChatRepository`
/// (**Dart** **позволяет** **наследование** **с** **final** **полями** —
/// **просто** **переопределяем** **все** **публичные** **методы**).
///
/// **Что** **настраиваем** **в** **каждом** **тесте** — **через** **функции**
/// (`onGetRoute`, `onGetMessages` и т.д.), **чтобы** **гибко** **задавать**
/// **поведение**.
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
      'используй onSendMessageStream через SendMessageUseCase.',
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
  /// - `agentsProvider` → пустой список (для `loadChat`).
  ///
  /// **Что оставляем настоящим:**
  /// - `sessionProvider` — обычный `StateNotifier`, без HTTP;
  /// - `attachmentDraftProvider` — обычный `StateNotifier`
  ///   (пока не создаёт реальный `ChatRepository` — создаёт, но
  ///   **не** **использует**, так как тесты не вызывают
  ///   `addAttachment`);
  /// - `chatStreamHandlerProvider` — чистый Dart.
  ProviderContainer makeContainer(FakeChatRepository fakeRepository) {
    return ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(fakeRepository),
        agentsProvider.overrideWith((ref) async => <Agent>[]),
      ],
    );
  }

  // ============================================================
  // ТЕСТ 1: createNewChat
  // ============================================================

  group('ChatNotifier.createNewChat', () {
    test('очищает messages, добавляет welcome, сбрасывает сессию', () {
      final fakeRepository = FakeChatRepository();
      final container = makeContainer(fakeRepository);
      addTearDown(container.dispose);

      final chatNotifier = container.read(chatProvider.notifier);
      final sessionNotifier = container.read(sessionProvider.notifier);

      // Подготовка: "загрязняем" сессию.
      sessionNotifier.setSession(
        'document_chat',
        'some-session-id',
        agentDisplayName: 'Документы',
      );

      // Действие.
      chatNotifier.createNewChat();

      // Проверки.
      final state = container.read(chatProvider);
      final session = container.read(sessionProvider);

      // messages — ровно 1 сообщение (welcome).
      expect(state.messages.length, 1);
      expect(state.messages.first.isFromUser, false);
      expect(state.messages.first.text, contains('Здравствуйте'));

      // Сессия — сброшена.
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
      final container = makeContainer(fakeRepository);
      addTearDown(container.dispose);

      final chatNotifier = container.read(chatProvider.notifier);
      final sessionNotifier = container.read(sessionProvider.notifier);

      sessionNotifier.setSession(
        'epoz',
        'epoz-session-1',
        agentDisplayName: 'ЕПоЗ',
      );

      // Действие.
      chatNotifier.clearChat();

      // Проверки.
      final state = container.read(chatProvider);
      final session = container.read(sessionProvider);

      expect(state.messages.length, 1);
      expect(state.messages.first.isFromUser, false);

      // Сессия — **не** сброшена (отличие от createNewChat).
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
      final container = makeContainer(fakeRepository);
      addTearDown(container.dispose);

      final notifier = container.read(chatProvider.notifier);

      // Вызываем — не падает, state остаётся валидным.
      // Полноценная проверка "сбросил реальную ошибку" —
      // в следующей фазе (когда сможем выставить error через sendMessage).
      notifier.clearError();

      final state = container.read(chatProvider);
      expect(state.error, isNull);
    });
  });

  // ============================================================
  // ТЕСТ 4: loadChat — успех
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

      final container = makeContainer(fakeRepository);
      addTearDown(container.dispose);

      final notifier = container.read(chatProvider.notifier);

      await notifier.loadChat('epoz', 'chat-42', null);

      final state = container.read(chatProvider);
      final session = container.read(sessionProvider);

      // messages — загружены.
      expect(state.messages.length, 2);
      expect(state.messages.first.text, 'Привет');
      expect(state.messages.last.text, 'Здравствуйте');

      // Сессия — установлена.
      expect(session.agentId, 'epoz');
      expect(session.sessionId, 'chat-42');
      expect(session.ragId, isNull);

      // Репозиторий — вызван.
      expect(fakeRepository.getMessagesCalls, 1);
    });

    test('404: устанавливает error', () async {
      final fakeRepository = FakeChatRepository();
      fakeRepository.onGetMessages = (agentId, conversationId) {
        throw BusinessException.chatNotFound(conversationId);
      };

      final container = makeContainer(fakeRepository);
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
    test('ошибка /route: удаляет пустой AI-пузырь, ставит error', () async {
      final fakeRepository = FakeChatRepository();
      fakeRepository.onGetRoute = (message) {
        throw NetworkException.connectionError();
      };

      final container = makeContainer(fakeRepository);
      addTearDown(container.dispose);

      final notifier = container.read(chatProvider.notifier);

      await notifier.sendMessage(text: 'привет');

      final state = container.read(chatProvider);

      // error — установлена.
      expect(state.error, isNotNull);

      // messages — welcome + user (пустой AI-пузырь удалён).
      expect(state.messages.length, 2);
      expect(state.messages.last.isFromUser, true);
      expect(state.messages.last.text, 'привет');

      // getRoute — вызван.
      expect(fakeRepository.getRouteCalls, 1);
    });
  });

  // ============================================================
  // ТЕСТ 6: retryLastMessage — нет user
  // ============================================================

  group('ChatNotifier.retryLastMessage', () {
    test('нет user-сообщения: ничего не делает', () async {
      final fakeRepository = FakeChatRepository();
      final container = makeContainer(fakeRepository);
      addTearDown(container.dispose);

      final notifier = container.read(chatProvider.notifier);

      // В state — только welcome (AI). Нет user.
      await notifier.retryLastMessage();

      final state = container.read(chatProvider);

      expect(state.messages.length, 1);
      expect(state.messages.first.isFromUser, false);

      // Репозиторий — не вызван.
      expect(fakeRepository.sendMessageStreamCalls, 0);
    });
  });
}
