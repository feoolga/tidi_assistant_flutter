// lib/providers/chat_list_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/errors/error_handler.dart';
import '../core/logger/app_logger.dart';
import '../domain/models/agent.dart';
import '../domain/models/chat_session.dart';
import '../data/repositories/chat_repository.dart';
import 'agent_provider.dart';

// ============================================================
// 1. СОСТОЯНИЕ СПИСКА ЧАТОВ
// ============================================================

class ChatListState {
  /// Список чатов.
  final List<ChatSession> chats;

  /// Флаг загрузки.
  final bool isLoading;

  /// Сообщение об ошибке для пользователя (userMessage).
  ///
  /// **Важно:** здесь — **только** userMessage, **не** технический текст.
  /// Если показать `e.toString()` — пользователь увидит
  /// `AppException(code: NETWORK_...)` вместо «Не удаётся подключиться».
  final String? error;

  /// Версия данных (увеличивается при каждом обновлении).
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
// 2. NOTIFIER
// ============================================================

class ChatListNotifier extends StateNotifier<ChatListState> {
  // ---- Зависимости ----
  final ChatRepository _repository;

  /// Кэш агентов (чтобы не запрашивать каждый раз).
  List<Agent>? _cachedAgents;

  // ---- Конструктор ----
  ChatListNotifier({required ChatRepository repository})
    : _repository = repository,
      super(ChatListState.initial());

  // ============================================================
  // ПРИВАТНЫЕ МЕТОДЫ СОСТОЯНИЯ
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
    state = state.copyWith(chats: chats, version: state.version + 1);
  }

  // ============================================================
  // ПУБЛИЧНЫЕ МЕТОДЫ
  // ============================================================

  /// Загрузить чаты для всех агентов.
  ///
  /// **Двухуровневая стратегия ошибок:**
  ///
  /// **Уровень агента** — если у одного агента не получилось, **не**
  /// останавливаем цикл. Логируем, продолжаем со следующим.
  ///
  /// **Уровень операции** — после цикла смотрим:
  /// - **что-то загрузилось** → показываем данные, ошибку **не** показываем
  ///   (даже если часть агентов упала — пользователь видит то, что есть);
  /// - **всё упало** (пусто + есть ошибки) → показываем ошибку,
  ///   чтобы пользователь не думал, что у него нет чатов;
  /// - **всё успешно** (включая пустые списки) → показываем данные,
  ///   ошибку **не** показываем.
  ///
  /// **Почему такая стратегия:** если 4 из 5 агентов ответили, а 1 упал —
  /// показать ошибку **хуже**, чем показать 4 набора чатов. Если упали
  /// **все** — показать пустой список **хуже**, чем показать ошибку:
  /// пользователь подумает, что чатов нет, хотя на самом деле
  /// не работает сеть.
  Future<void> loadAllChats(List<Agent> agents) async {
    if (agents.isEmpty) {
      _setChats([]);
      return;
    }

    AppLogger.info('Загружаем чаты для ${agents.length} агентов...');

    _setLoading(true);
    _clearError();

    // Аккумуляторы — живут в области видимости метода, потому что
    // нужны и внутри цикла, и после него.
    final List<ChatSession> allChats = [];
    int errorCount = 0;
    Object? firstError;

    try {
      // ---- УРОВЕНЬ АГЕНТА: не останавливаемся на первой ошибке ----
      for (final agent in agents) {
        try {
          final chats = await _repository.getConversations(agentId: agent.id);
          allChats.addAll(chats);
        } catch (e, stackTrace) {
          errorCount++;
          firstError ??= e;
          AppLogger.logException(
            'Не удалось загрузить чаты агента ${agent.id}',
            e,
            stackTrace,
            {'agentId': agent.id},
          );
          // 👈 продолжаем цикл
        }
      }

      // ---- УРОВЕНЬ ОПЕРАЦИИ: решаем, что показать ----
      if (allChats.isEmpty && errorCount > 0) {
        // Всё упало — не показываем пустой список, показываем ошибку.
        AppLogger.error(
          'Все ${agents.length} агентов упали при загрузке чатов',
        );
        _setError(ErrorHandler.getUserMessage(firstError));
        return;
      }

      // Что-то загрузилось (или всё ок) — сортируем и показываем.
      allChats.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _setChats(allChats);

      if (errorCount > 0) {
        AppLogger.warning(
          'Частичная загрузка: ${agents.length - errorCount} из '
          '${agents.length} агентов ответили, $errorCount упали',
        );
      } else {
        AppLogger.info('Загружено чатов: ${allChats.length}');
      }
    } catch (e, stackTrace) {
      // Сюда попадаем только если упало что-то вне цикла —
      // например, ошибка в _setChats (маловероятно, но возможно).
      AppLogger.logException(
        'Неожиданная ошибка в loadAllChats',
        e,
        stackTrace,
      );
      _setError(ErrorHandler.getUserMessage(e));
    } finally {
      _setLoading(false);
    }
  }

  /// Принудительно обновить список чатов.
  Future<void> refresh({List<Agent>? agents}) async {
    AppLogger.debug('Принудительное обновление списка чатов...');

    final agentsToUse = agents ?? _cachedAgents;

    if (agentsToUse == null || agentsToUse.isEmpty) {
      AppLogger.warning('Нет агентов для загрузки чатов');
      return;
    }

    await loadAllChats(agentsToUse);
  }

  /// Обновить кэш агентов.
  void updateAgents(List<Agent> agents) {
    _cachedAgents = agents;
  }

  /// Очистить список чатов.
  void clear() {
    AppLogger.debug('Очистка списка чатов');
    _setChats([]);
    _cachedAgents = null;
  }

  /// Получить количество чатов.
  int get chatCount => state.chats.length;
}

// ============================================================
// 3. ПРОВАЙДЕРЫ
// ============================================================

/// Провайдер для списка чатов.
final chatListNotifierProvider =
    StateNotifierProvider<ChatListNotifier, ChatListState>((ref) {
      final repository = ref.read(chatRepositoryProvider);
      return ChatListNotifier(repository: repository);
    });

/// Провайдер для получения списка всех чатов.
final allChatsProvider = Provider<List<ChatSession>>((ref) {
  final state = ref.watch(chatListNotifierProvider);
  return state.chats;
});

/// Провайдер для получения состояния загрузки чатов.
final chatListLoadingProvider = Provider<bool>((ref) {
  return ref.watch(chatListNotifierProvider).isLoading;
});

/// Провайдер для получения ошибки загрузки чатов.
final chatListErrorProvider = Provider<String?>((ref) {
  return ref.watch(chatListNotifierProvider).error;
});
