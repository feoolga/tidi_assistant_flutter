// lib/services/chat_session_service.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'chat_history_service.dart';
import '../providers/chat_provider.dart';
import '../providers/session_provider.dart';
import '../models/chat_session.dart';

/// Сервис для управления сессией чата.
/// 
/// Это единственное место, где:
/// 1. Создаются новые чаты
/// 2. Загружаются существующие чаты
/// 3. Управляется текущая сессия (agentId + sessionId)
/// 
/// ChatScreen и ChatNotifier используют этот сервис,
/// вместо того чтобы управлять сессией напрямую.
class ChatSessionService {
  final Ref _ref;
  
  ChatSessionService(this._ref);
  
  // ============================================================
  // 1. УПРАВЛЕНИЕ СЕССИЕЙ
  // ============================================================
  
  /// Начинает новый диалог (без создания чата на сервере).
  /// 
  /// Используется когда:
  /// - Пользователь нажал "Новый чат"
  /// - Нужно начать диалог с чистого листа
  void startNewDialog() {
    print('🆕 ChatSessionService: начинаем новый диалог');
    
    // 1. Сбрасываем сессию
    _ref.read(sessionProvider.notifier).clearSession();
    
    // 2. Создаем новый пустой чат в UI
    _ref.read(chatProvider.notifier).createNewChat();
  }
  
  /// Загружает существующий чат.
  /// 
  /// Используется когда:
  /// - Пользователь выбрал чат из истории
  /// - Нужно восстановить диалог
  Future<void> loadChat(String agentId, String chatId) async {
    print('📂 ChatSessionService: загружаем чат $chatId');
    
    // 1. Устанавливаем сессию
    _ref.read(sessionProvider.notifier).setSession(agentId, chatId);
    
    // 2. Загружаем сообщения
    await _ref.read(chatProvider.notifier).loadChat(agentId, chatId);
  }
  
  /// Создает новый чат на сервере и загружает его.
  /// 
  /// Используется когда:
  /// - Нужно создать чат с конкретным агентом
  /// - Например, при первом сообщении новому агенту
  Future<ChatSession> createNewChat(String agentId) async {
    print('🆕 ChatSessionService: создаем новый чат для агента $agentId');
    
    try {
      // 1. Создаем чат на сервере
      final chat = await _ref.read(chatHistoryServiceProvider).createChat(agentId);
      
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
  // 2. ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ
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
// ПРОВАЙДЕР
// ============================================================

/// Провайдер для ChatSessionService.
/// 
/// Используется везде, где нужно управлять сессией.
final chatSessionServiceProvider = Provider<ChatSessionService>((ref) {
  return ChatSessionService(ref);
});