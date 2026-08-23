// lib/services/chat_session_service.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_provider.dart';
import '../providers/session_provider.dart';
import '../providers/agent_provider.dart';
import '../data/repositories/chat_repository.dart';
import '../domain/models/chat_session.dart';

/// Сервис для управления сессией чата.
///
/// Это единственное место, где:
/// 1. Создаются новые чаты
/// 2. Загружаются существующие чаты
/// 3. Управляется текущая сессия (agentId + sessionId)
///
/// ВНИМАНИЕ! Этот сервис УСТАРЕВАЕТ.
/// В будущем его логика будет перенесена в ChatNotifier.
///
/// @deprecated Используйте ChatNotifier напрямую
class ChatSessionService {
  // ============================================================
  // 1. ЗАВИСИМОСТИ
  // ============================================================

  final Ref _ref;
  final ChatRepository _repository;

  // ============================================================
  // 2. КОНСТРУКТОР
  // ============================================================

  ChatSessionService(this._ref, this._repository);

  // ============================================================
  // 3. МЕТОДЫ
  // ============================================================

  /// Начинает новый диалог (без создания чата на сервере).
  void startNewDialog() {
    print('🆕 ChatSessionService: начинаем новый диалог');

    // 1. Сбрасываем сессию
    _ref.read(sessionProvider.notifier).clearSession();

    // 2. Создаем новый пустой чат в UI
    _ref.read(chatProvider.notifier).createNewChat();
  }

  /// Загружает существующий чат.
  Future<void> loadChat(String agentId, String chatId) async {
    print('📂 ChatSessionService: загружаем чат $chatId');

    // 1. Устанавливаем сессию
    _ref.read(sessionProvider.notifier).setSession(agentId, chatId);

    // 2. Загружаем сообщения
    await _ref.read(chatProvider.notifier).loadChat(agentId, chatId);
  }

  /// Создает новый чат на сервере и загружает его.
  Future<ChatSession> createNewChat(String agentId) async {
    print('🆕 ChatSessionService: создаем новый чат для агента $agentId');

    try {
      // 1. Создаем чат через Repository
      final chat = await _repository.createConversation(
        agentId: agentId,
        title: null, // Пустой title, сервер создаст с дефолтным названием
      );

      // 2. Устанавливаем сессию
      _ref.read(sessionProvider.notifier).setSession(agentId, chat.id);

      // 3. Загружаем сообщения (пока пустые)
      await _ref.read(chatProvider.notifier).loadChat(agentId, chat.id);

      print('✅ ChatSessionService: чат создан, ID=${chat.id}');
      return chat;
    } catch (e) {
      print('❌ ChatSessionService: ошибка создания чата: $e');
      rethrow;
    }
  }

  // ============================================================
  // 4. ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ
  // ============================================================

  /// Проверяет, есть ли активная сессия.
  bool get hasSession {
    final session = _ref.read(sessionProvider);
    return session.hasSession;
  }

  /// Возвращает текущий agentId или null.
  String? get currentAgentId {
    return _ref.read(sessionProvider).agentId;
  }

  /// Возвращает текущий sessionId или null.
  String? get currentSessionId {
    return _ref.read(sessionProvider).sessionId;
  }
}
// ============================================================
// 5. ПРОВАЙДЕР
// ============================================================

/// Провайдер для ChatSessionService.
///
/// @deprecated Используйте chatProvider и sessionProvider напрямую
@Deprecated('Используйте chatProvider и sessionProvider напрямую')
final chatSessionServiceProvider = Provider<ChatSessionService>((ref) {
  final repository = ref.read(chatRepositoryProvider);
  return ChatSessionService(ref, repository);
});
