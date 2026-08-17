// lib/providers/chat_list_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/chat_session.dart';
import '../models/agent.dart';
import '../services/chat_history_service.dart';  // 👈 ДОБАВЛЯЕМ
import 'chat_provider.dart';  // 👈 ДЛЯ chatHistoryServiceProvider

// ============================================================
// ЧАСТЬ 1: СОСТОЯНИЕ СПИСКА ЧАТОВ
// ============================================================

class ChatListState {
  /// Список чатов
  final List<ChatSession> chats;
  
  /// Флаг загрузки
  final bool isLoading;
  
  /// Ошибка (если есть)
  final String? error;
  
  /// Версия данных (увеличивается при каждом обновлении)
  final int version;

  const ChatListState({
    this.chats = const [],
    this.isLoading = false,
    this.error,
    this.version = 0,
  });

  factory ChatListState.initial() {
    return const ChatListState();
  }

  ChatListState copyWith({
    List<ChatSession>? chats,
    bool? isLoading,
    String? error,
    int? version,
  }) {
    return ChatListState(
      chats: chats ?? this.chats,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      version: version ?? this.version,
    );
  }

  bool get hasChats => chats.isNotEmpty;
  bool get hasError => error != null && error!.isNotEmpty;
}

// ============================================================
// ЧАСТЬ 2: NOTIFIER ДЛЯ УПРАВЛЕНИЯ СПИСКОМ ЧАТОВ
// ============================================================

class ChatListNotifier extends StateNotifier<ChatListState> {
  final ChatHistoryService _chatHistoryService;
  
  /// Кэш агентов (чтобы не запрашивать каждый раз)
  List<Agent>? _cachedAgents;

  ChatListNotifier({
    required ChatHistoryService chatHistoryService,
  }) : _chatHistoryService = chatHistoryService,
       super(ChatListState.initial());

  // ============================================================
  // ПРИВАТНЫЕ МЕТОДЫ
  // ============================================================

  void _setLoading(bool isLoading) {
    state = state.copyWith(isLoading: isLoading);
  }

  void _setError(String? error) {
    state = state.copyWith(error: error);
  }

  void _clearError() {
    state = state.copyWith(error: null);
  }

  void _setChats(List<ChatSession> chats) {
    state = state.copyWith(
      chats: chats,
      version: state.version + 1,
    );
  }

  // ============================================================
  // ПУБЛИЧНЫЕ МЕТОДЫ
  // ============================================================

  /// Загрузить чаты для всех агентов
  Future<void> loadAllChats(List<Agent> agents) async {
    if (agents.isEmpty) {
      _setChats([]);
      return;
    }

    print('📦 ChatListNotifier: загружаем чаты для ${agents.length} агентов...');
    
    _setLoading(true);
    _clearError();

    try {
      List<ChatSession> allChats = [];

      for (final agent in agents) {
        try {
          final chats = await _chatHistoryService.getChats(agent.id);
          allChats.addAll(chats);
        } catch (e) {
          print('⚠️ Не удалось загрузить чаты для агента ${agent.id}: $e');
        }
      }

      allChats.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      _setChats(allChats);
      print('✅ ChatListNotifier: загружено ${allChats.length} чатов');
    } catch (e) {
      print('❌ ChatListNotifier: ошибка загрузки: $e');
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  /// Принудительно обновить список чатов
  Future<void> refresh({List<Agent>? agents}) async {
    print('🔄 ChatListNotifier: принудительное обновление...');
    
    List<Agent>? agentsToUse = agents ?? _cachedAgents;
    
    if (agentsToUse == null || agentsToUse.isEmpty) {
      print('⚠️ ChatListNotifier: нет агентов для загрузки');
      return;
    }

    await loadAllChats(agentsToUse);
  }

  /// Обновить кэш агентов
  void updateAgents(List<Agent> agents) {
    _cachedAgents = agents;
  }

  /// Очистить список чатов
  void clear() {
    _setChats([]);
    _cachedAgents = null;
  }

  /// Получить количество чатов
  int get chatCount => state.chats.length;
}

// ============================================================
// ЧАСТЬ 3: ПРОВАЙДЕРЫ
// ============================================================

/// 👇 ИСПОЛЬЗУЕМ ПРОВАЙДЕР ИЗ chat_provider.dart
final chatListNotifierProvider = StateNotifierProvider<ChatListNotifier, ChatListState>((ref) {
  final chatHistoryService = ref.read(chatHistoryServiceProvider);
  return ChatListNotifier(
    chatHistoryService: chatHistoryService,
  );
});

/// Провайдер для получения списка всех чатов
final allChatsProvider = Provider<List<ChatSession>>((ref) {
  final state = ref.watch(chatListNotifierProvider);
  return state.chats;
});

/// Провайдер для получения состояния загрузки чатов
final chatListLoadingProvider = Provider<bool>((ref) {
  return ref.watch(chatListNotifierProvider).isLoading;
});

/// Провайдер для получения ошибки загрузки чатов
final chatListErrorProvider = Provider<String?>((ref) {
  return ref.watch(chatListNotifierProvider).error;
});