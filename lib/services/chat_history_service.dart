// lib/services/chat_history_service.dart

import '../models/chat_session.dart';
import '../models/message.dart';
import '../data/repositories/chat_repository.dart';

/// Сервис для работы с историей чатов и сообщениями.
///
/// ВНИМАНИЕ! Этот сервис УСТАРЕЛ и скоро будет удален.
/// Используйте ChatRepository напрямую.
///
/// @deprecated Используйте ChatRepository вместо этого сервиса
@Deprecated('Используйте ChatRepository вместо ChatHistoryService')
class ChatHistoryService {
  // ============================================================
  // 1. ЗАВИСИМОСТИ
  // ============================================================

  final ChatRepository _repository;

  // ============================================================
  // 2. КОНСТРУКТОР
  // ============================================================

  ChatHistoryService({required ChatRepository repository})
    : _repository = repository;

  // ============================================================
  // 3. МЕТОДЫ (ПРОКСИРУЮТ ВЫЗОВЫ К REPOSITORY)
  // ============================================================

  /// Получить все чаты агента.
  @Deprecated('Используйте repository.getConversations()')
  Future<List<ChatSession>> getChats(String agentId) async {
    return await _repository.getConversations(agentId: agentId);
  }

  /// Создать новый чат для агента.
  @Deprecated('Используйте repository.createConversation()')
  Future<ChatSession> createChat(String agentId) async {
    return await _repository.createConversation(agentId: agentId);
  }

  /// Получить сообщения чата.
  @Deprecated('Используйте repository.getMessages()')
  Future<List<Message>> getMessages(
    String agentId,
    String conversationId,
  ) async {
    return await _repository.getMessages(
      agentId: agentId,
      conversationId: conversationId,
    );
  }

  /// Переименовать чат.
  @Deprecated('Этот метод будет перенесен в Repository позже')
  Future<ChatSession> renameChat(
    String agentId,
    String conversationId,
    String newTitle,
  ) async {
    // TODO: Перенести в Repository
    throw UnimplementedError('renameChat будет реализован в Repository позже');
  }

  /// Удалить чат.
  @Deprecated('Этот метод будет перенесен в Repository позже')
  Future<void> deleteChat(String agentId, String conversationId) async {
    // TODO: Перенести в Repository
    throw UnimplementedError('deleteChat будет реализован в Repository позже');
  }
}
