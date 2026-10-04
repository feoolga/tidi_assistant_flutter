// lib/providers/rag_list_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logger/app_logger.dart';
import '../domain/models/rag_set.dart';
import 'agent_provider.dart';

/// Провайдер списка **всех** RAG-наборов пользователя.
///
/// **Что делает.** Загружает список через `RagRepository.list()`.
/// Данные приходят **уже отсортированными** (сервер отдаёт
/// `updated_at DESC` — новые сверху), поэтому **сортируем** не мы.
///
/// **Зачем `FutureProvider`.**
/// - Данные грузятся **автоматически** при первом `ref.watch`.
/// - `AsyncValue` даёт UI **три** состояния: `loading`, `error`, `data` —
///   не надо **вручную** городить флаги.
/// - `ref.invalidate(ragListProvider)` — перезагрузка **одной** строкой
///   (используется в UI после создания нового набора — D8).
///
/// **Что НЕ делает.**
/// - Не управляет состоянием **создания** — это `RagCreationNotifier` (D6).
/// - Не сортирует — приходит **уже** отсортированным с сервера.
/// - Не кеширует **на диск** — только **в памяти** (Riverpod).
///
/// **Пример использования:**
/// ```dart
/// final ragListAsync = ref.watch(ragListProvider);
/// return ragListAsync.when(
///   loading: () => CircularProgressIndicator(),
///   error: (e, st) => Text('Ошибка: $e'),
///   data: (sets) => ListView(...),
/// );
/// ```
final ragListProvider = FutureProvider<List<RagSet>>((ref) async {
  AppLogger.debug('Загрузка списка RAG-наборов');

  final repository = ref.read(ragRepositoryProvider);
  final sets = await repository.list();

  AppLogger.debug('Загружено RAG-наборов: ${sets.length}');
  return sets;
});

/// Быстрый доступ к RAG-набору по `id` через `Map`.
///
/// **Почему `Map`, а не `family`:**
/// - один провайдер на всё приложение, а не отдельный на каждый `id`;
/// - поиск **O(1)** вместо `list.firstWhere(...)` — **O(n)**;
/// - не нужен `try/catch` вокруг `firstWhere` (он бросает `StateError`);
/// - `null` при поиске означает **ровно одно**: «не найден или ещё
///   загружается».
///
/// `valueOrNull` возвращает `null`, пока `ragListProvider` в состоянии
/// `AsyncLoading` или `AsyncError`. В этом случае `Map` пустой — UI
/// покажет fallback.
///
/// **Пример использования:**
/// ```dart
/// final ragSet = ref.watch(ragByIdProvider)[ragId];
/// ```
final ragByIdProvider = Provider<Map<String, RagSet>>((ref) {
  final sets = ref.watch(ragListProvider).valueOrNull ?? const [];
  return {for (final set in sets) set.id: set};
});
