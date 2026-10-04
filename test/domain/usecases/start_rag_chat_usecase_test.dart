// test/domain/usecases/start_rag_chat_usecase_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:tidi_assistant_flutter/core/config/app_config.dart';
import 'package:tidi_assistant_flutter/core/errors/rag_exceptions.dart';
import 'package:tidi_assistant_flutter/data/repositories/chat_repository.dart';
import 'package:tidi_assistant_flutter/domain/models/chat_session.dart';
import 'package:tidi_assistant_flutter/domain/usecases/start_rag_chat_usecase.dart';

// ============================================================
// FAKE — ПОДМЕНА ChatRepository
// ============================================================

class FakeChatRepository extends ChatRepository {
  ChatSession? createResult;
  Object? createError;

  String? lastAgentId;
  String? lastRagId;
  String? lastTitle;

  FakeChatRepository() : super();

  @override
  Future<ChatSession> createConversation({
    required String agentId,
    String? title,
    String? ragId,
  }) async {
    lastAgentId = agentId;
    lastRagId = ragId;
    lastTitle = title;
    if (createError != null) throw createError!;
    return createResult!;
  }
}

// ============================================================
// ХЕЛПЕРЫ
// ============================================================

ChatSession buildChatSession({
  String id = 'chat-1',
  String agentId = 'agentic_rag',
  String? title = 'RAG-чат',
}) {
  return ChatSession(
    id: id,
    agentId: agentId,
    title: title,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

// ============================================================
// ТЕСТЫ
// ============================================================

void main() {
  group('StartRagChatUseCase', () {
    test('happy path: создаёт чат с agentId=agentic_rag и ragId', () async {
      final repo = FakeChatRepository()
        ..createResult = buildChatSession(id: 'chat-42', title: 'Мой RAG');
      final useCase = StartRagChatUseCase(chatRepository: repo);

      final session = await useCase.execute(ragId: 'rag-1', title: 'Мой RAG');

      expect(session.id, 'chat-42');
      expect(session.title, 'Мой RAG');

      expect(repo.lastAgentId, AppConfig.ragAgentId);
      expect(repo.lastAgentId, 'agentic_rag');
      expect(repo.lastRagId, 'rag-1');
      expect(repo.lastTitle, 'Мой RAG');
    });

    test('без title — передаётся null', () async {
      final repo = FakeChatRepository()
        ..createResult = buildChatSession(id: 'chat-1');
      final useCase = StartRagChatUseCase(chatRepository: repo);

      await useCase.execute(ragId: 'rag-1');

      expect(repo.lastTitle, isNull);
      expect(repo.lastRagId, 'rag-1');
    });

    test('ошибка репозитория пробрасывается', () async {
      final repo = FakeChatRepository()
        ..createError = RagException.notFound('rag-1');
      final useCase = StartRagChatUseCase(chatRepository: repo);

      expect(
        () => useCase.execute(ragId: 'rag-1'),
        throwsA(
          isA<RagException>().having((e) => e.code, 'code', 'RAG_NOT_FOUND'),
        ),
      );
    });
  });
}
