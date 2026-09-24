// lib/providers/chat_list_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logger/app_logger.dart';
import '../domain/models/chat_session.dart';
import 'agent_provider.dart';

/// Провайдер списка всех чатов.
///
/// **Как работает:**
/// 1. `ref.watch(agentsProvider.future)` — ждёт загрузки агентов.
///    Если агенты ещё грузятся — чаты тоже будут в состоянии `AsyncLoading`.
///    Если агенты упали — чаты будут в состоянии `AsyncError`.
/// 2. Для каждого агента запрашивает чаты через `ChatRepository`.
/// 3. Объединяет результаты в один список и сортирует по `updatedAt`.
///
/// **Почему `FutureProvider`, а не `StateNotifier`:**
/// - Нет императивного `loadAllChats()` — данные грузятся автоматически
///   при первом `ref.watch` и пересчитываются при изменении агентов.
/// - Нет `_isLoaded`, `_cachedAgents`, `updateAgents` — всё ушло.
/// - `AsyncValue` сам даёт UI три состояния: loading, error, data.
/// - `ref.watch(agentsProvider.future)` — рекомендованный Riverpod-паттерн
///   для комбинирования асинхронных провайдеров[citation:1][citation:12].
///
/// **Что будет, если один агент упал:**
/// Сейчас — весь провайдер перейдёт в `AsyncError`. Это отличие от старого
/// поведения (когда падение одного агента не ломало остальные). Если
/// понадобится «частичная загрузка» — обработаем в отдельном шаге
/// (см. план: Шаг 4.6 — баннер «часть чатов не загружена»).
final chatsProvider = FutureProvider<List<ChatSession>>((ref) async {
  // 1. Ждём агентов. Если они ещё грузятся — чаты тоже будут loading.
  final agents = await ref.watch(agentsProvider.future);

  if (agents.isEmpty) {
    AppLogger.debug('Нет агентов — чаты не загружаем');
    return const [];
  }

  AppLogger.info('Загружаем чаты для ${agents.length} агентов...');

  // 2. Грузим чаты для каждого агента.
  //    `ref.read` — потому что репозиторий не меняется.
  final repository = ref.read(chatRepositoryProvider);

  final allChats = <ChatSession>[];
  for (final agent in agents) {
    try {
      final chats = await repository.getConversations(agentId: agent.id);
      allChats.addAll(chats);
    } catch (e, stackTrace) {
      // Логируем, но не падаем — как в старом `loadAllChats`.
      AppLogger.logException(
        'Не удалось загрузить чаты агента ${agent.id}',
        e,
        stackTrace,
        {'agentId': agent.id},
      );
      // TODO(Шаг 4.6): передать информацию о частичной загрузке в UI.
    }
  }

  // 3. Сортируем по дате обновления (новые сверху).
  //
  // Чаты с `null` `updatedAt` уходят **в конец** списка:
  // у них дата неизвестна, поэтому мы не можем судить,
  // «свежие» они или «старые». Ставить их наверх (как было бы
  // с `DateTime.now()` в fallback) — неправильно: старый чат
  // выглядел бы как только что созданный.
  //
  // Используем `DateTime(0)` (эпоха) как «самая старая дата» —
  // тогда `null`-чаты естественно оказываются в конце.
  // Компаратор: сначала сравниваем по `updatedAt`, но `null`
  // превращаем в «эпоху».
  allChats.sort((a, b) {
    final aDate = a.updatedAt ?? DateTime(0);
    final bDate = b.updatedAt ?? DateTime(0);
    return bDate.compareTo(aDate);
  });

  AppLogger.info('Загружено чатов: ${allChats.length}');
  return allChats;
});
